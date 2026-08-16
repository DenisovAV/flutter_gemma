#!/usr/bin/env python3
"""Block `dart pub publish` of a package whose code changed but whose docs did not.

Why this exists: twice in one session a package was released with the code shipped
but the docs skipped — agent 0.2.3 published without its pub.dev README updated
(had to ship 0.2.4 the same day), and the 1.5.9 vision-backend docs were split off
into a separate website PR instead of riding the release PR. The `release` skill
says docs (Step 12: version pins + new-API docs) are MANDATORY ON EVERY RELEASE and
"commit the website/ changes on your release branch / PR" (one PR, not two). The
skill was read and the docs were still deferred — which is the argument for a hook
over more prose: a checklist advises, a hook refuses. (Same lesson as
guard-publish.py.)

Blocks a real publish (not --dry-run) of package X when, in the commit range that
introduced X's current `version:` (that commit .. HEAD), X's `lib/` changed but
NEITHER of these did:
  * packages/X/README.md   (the pub.dev-facing docs)
  * website/content/docs/  (the fluttergemma.dev docs)

Override for a genuine code-only release with no doc surface (rare) by putting
`RELEASE_SKIP_DOCS=<reason>` in the command, e.g.
  RELEASE_SKIP_DOCS="internal refactor, no public API/behavior change" dart pub publish

Fail-closed: if git can't be consulted, or the package/version can't be resolved,
BLOCK — an irreversible publish in an unknown state is not a safe one.

Exit 0 allows, exit 2 blocks with the reason on stderr.
Run `python3 guard-release-docs.py --self-test` to check the matching rules.
"""
import json
import os
import re
import subprocess
import sys

# Mirror guard-publish.py's command-position matcher (MULTILINE is load-bearing:
# a `cd\n dart pub publish` block must still match).
PUBLISH_RE = re.compile(
    r"(?:^|[;&|(]|&&|\|\|)\s*"
    r"(?:\w+=\S+\s+)*"
    r"(?:(?:timeout|nice|env|command|stdbuf)\s+\S+\s+)*"
    r"(?:dart|flutter)\s+pub\s+publish\b",
    re.MULTILINE,
)
DRY_RUN_RE = re.compile(r"(?<![\w-])--dry-run(?![\w-])")
SKIP_RE = re.compile(r"(?<![\w-])RELEASE_SKIP_DOCS=")
# `cd packages/<name>` (the publish is run from the package dir).
CD_PKG_RE = re.compile(r"cd\s+(?:\S*/)?packages/([A-Za-z0-9_]+)")


class GitUnavailable(RuntimeError):
    """git could not be consulted — treated as a block, never as 'clean'."""


def git(*args):
    try:
        r = subprocess.run(
            ["git", "-C", os.environ.get("CLAUDE_PROJECT_DIR", "."), *args],
            capture_output=True,
            text=True,
            timeout=30,
            env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        raise GitUnavailable(f"git {' '.join(args)}: {e}") from e
    if r.returncode != 0:
        raise GitUnavailable(
            f"git {' '.join(args)} exited {r.returncode}: {r.stderr.strip()}"
        )
    return r.stdout.strip()


def _publish_is_exempt(cmd):
    """True only if every publish invocation on the line carries --dry-run."""
    for m in PUBLISH_RE.finditer(cmd):
        tail = re.split(r"[;&|\n]", cmd[m.end() :], maxsplit=1)[0]
        if not DRY_RUN_RE.search(tail):
            return False
    return True


def _package_from(cmd):
    """Which packages/<name> is being published. None if undeterminable."""
    m = CD_PKG_RE.search(cmd)
    return m.group(1) if m else None


def _current_version(pkg):
    root = os.environ.get("CLAUDE_PROJECT_DIR", ".")
    path = os.path.join(root, "packages", pkg, "pubspec.yaml")
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            m = re.match(r"version:\s*(\S+)", line)
            if m:
                return m.group(1)
    raise GitUnavailable(f"no version: in packages/{pkg}/pubspec.yaml")


def _doc_problem(pkg):
    """Return a block-reason string, or None if the release's docs are fine."""
    version = _current_version(pkg)
    # The commit that set the CURRENT version is the release boundary. -S finds
    # where the exact `version: V` string entered pubspec.yaml.
    boundary = git(
        "log", "-1", "--format=%H", "-S", f"version: {version}",
        "--", f"packages/{pkg}/pubspec.yaml",
    )
    if not boundary:
        raise GitUnavailable(
            f"cannot locate the commit that set version {version} for {pkg}"
        )
    # Files changed in boundary..HEAD, plus the boundary commit itself.
    changed = set(
        git("diff", "--name-only", f"{boundary}~1", "HEAD").splitlines()
    )
    lib_prefix = f"packages/{pkg}/lib/"
    code_changed = any(f.startswith(lib_prefix) for f in changed)
    if not code_changed:
        return None  # docs-only / no public code change → nothing to enforce

    readme = f"packages/{pkg}/README.md"
    docs_touched = readme in changed or any(
        f.startswith("website/content/docs/") for f in changed
    )
    if docs_touched:
        return None

    return (
        f"packages/{pkg}/lib changed since v{version} was set ({boundary[:10]}) "
        f"but neither {readme} nor website/content/docs/ was updated.\n"
        "  The release skill (Step 12) requires docs in the SAME release: bump the\n"
        "  version pins + document the new/changed API before publishing.\n"
        "  If this release genuinely has no doc surface, re-run with\n"
        '  RELEASE_SKIP_DOCS="<reason>" in the command.'
    )


def main():
    try:
        payload = json.load(sys.stdin)
        cmd = (payload.get("tool_input") or {}).get("command") or ""
    except Exception as e:
        sys.stderr.write(
            f"BLOCKED: guard-release-docs could not read the hook payload ({e!r}).\n"
        )
        return 2

    if not PUBLISH_RE.search(cmd):
        return 0
    if _publish_is_exempt(cmd):
        return 0
    if SKIP_RE.search(cmd):
        return 0  # explicit, reasoned opt-out

    pkg = _package_from(cmd)
    if pkg is None:
        sys.stderr.write(
            "BLOCKED: guard-release-docs can't tell which package is being "
            "published (no `cd packages/<name>` in the command).\n"
            "Run the publish from the package dir, or add "
            'RELEASE_SKIP_DOCS="<reason>" if intentional.\n'
        )
        return 2

    try:
        problem = _doc_problem(pkg)
    except (GitUnavailable, OSError) as e:
        sys.stderr.write(
            f"BLOCKED: cannot verify docs shipped with this release — {e}\n"
            "A publish is irreversible; an unverifiable state is not a safe one.\n"
        )
        return 2

    if problem is None:
        return 0

    sys.stderr.write(
        "BLOCKED: release is missing its docs.\n  - "
        + problem
        + "\n(guard: .claude/hooks/guard-release-docs.py)\n"
    )
    return 2


# (command, matches_publish, is_exempt) — matching-rule cases only; the git-based
# doc check is exercised on the live repo, not here.
_TESTS = [
    ("dart pub publish --force", True, False),
    ("cd packages/flutter_gemma_agent && dart pub publish", True, False),
    ("dart pub publish --dry-run", True, True),
    ("dart pub publish --dry-run && dart pub publish", True, False),
    ('RELEASE_SKIP_DOCS="x" dart pub publish', True, False),  # skip handled in main, not exempt
    ("git push origin main", False, False),
    ('grep -r "dart pub publish" docs/', False, False),
]


def _self_test():
    bad = 0
    for cmd, want_match, want_exempt in _TESTS:
        got_match = bool(PUBLISH_RE.search(cmd))
        got_exempt = got_match and _publish_is_exempt(cmd)
        if got_match != want_match or got_exempt != want_exempt:
            bad += 1
            print(
                f"  FAIL {cmd!r}: match={got_match}(want {want_match}) "
                f"exempt={got_exempt}(want {want_exempt})"
            )
    # package + skip parsing
    assert _package_from("cd packages/flutter_gemma_agent && dart pub publish") == (
        "flutter_gemma_agent"
    ), "package parse"
    assert _package_from("dart pub publish") is None, "no-cd parse"
    assert SKIP_RE.search('RELEASE_SKIP_DOCS="reason" dart pub publish'), "skip parse"
    print(f"  {len(_TESTS) - bad}/{len(_TESTS)} match-rule cases pass; parse asserts ok")
    return 1 if bad else 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(_self_test())
    sys.exit(main())
