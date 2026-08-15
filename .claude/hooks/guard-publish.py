#!/usr/bin/env python3
"""Block `dart pub publish` unless the exact commit being published is reachable.

Why this exists: on 2026-08-15 flutter_gemma_litertlm 1.4.0 was published while
the local branch was 20+ commits ahead of origin. For ~25 minutes the package
existed on pub.dev with no corresponding source anywhere on GitHub — nobody
could have reproduced or reviewed what shipped.

The release skill already states the correct order (step 9 push, step 10
publish). It was read and the order was still inverted, which is the argument
for a guard rather than more prose: a checklist advises, a hook refuses.

The first version of this guard was itself reviewed and found to be a no-op on
the most likely command shape (a two-line `cd` + publish), so the matching and
every fail-open path below are deliberate and tested — see `_TESTS`.

Blocks a real publish (not --dry-run) when:
  * the working tree is dirty      -> the archive matches no commit
  * HEAD is not on origin          -> the published source is unreachable
  * git itself cannot be consulted -> we do not know, and not knowing is a block

Exit 0 allows, exit 2 blocks with the reason on stderr.
Run `python3 guard-publish.py --self-test` to check the matching rules.
"""
import json
import os
import re
import subprocess
import sys

# Must sit in *command position*: at the start of a line, or right after a
# separator, optionally behind an env assignment or a wrapper like `timeout`.
# re.MULTILINE is load-bearing — without it `^` anchors to the start of the
# whole string, and a newline is not a separator, so every multi-line shell
# block walked straight past this guard.
PUBLISH_RE = re.compile(
    r"(?:^|[;&|(]|&&|\|\|)\s*"
    r"(?:\w+=\S+\s+)*"  # FOO=bar dart pub publish
    r"(?:(?:timeout|nice|env|command|stdbuf)\s+\S+\s+)*"  # timeout 900 dart ...
    r"(?:dart|flutter)\s+pub\s+publish\b",
    re.MULTILINE,
)

# --dry-run must belong to the same command, not merely appear somewhere on the
# line. `dart pub publish --dry-run && dart pub publish` is the canonical
# verify-then-ship one-liner and must NOT be exempt.
DRY_RUN_RE = re.compile(r"(?<![\w-])--dry-run(?![\w-])")


class GitUnavailable(RuntimeError):
    """git could not be consulted — treated as a block, never as 'clean'."""


def git(*args):
    """Run git, or raise. Returning '' on failure would read as 'no problems'."""
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
        # the rest of this one command, up to the next separator
        tail = re.split(r"[;&|\n]", cmd[m.end() :], maxsplit=1)[0]
        if not DRY_RUN_RE.search(tail):
            return False
    return True


def _problems():
    """Return a list of reasons to block. Raises GitUnavailable if git fails."""
    out = []

    if git("status", "--porcelain"):
        out.append(
            "the working tree is dirty — the published archive would not "
            "correspond to any commit"
        )

    head = git("rev-parse", "HEAD")
    branch = git("rev-parse", "--abbrev-ref", "HEAD")

    if branch == "HEAD":
        out.append("detached HEAD — publish from a branch that exists on origin")
        return out

    # --exit-code + a full refname: `ls-remote --heads origin main` also matches
    # refs/heads/backup/main and can put the wrong SHA first.
    try:
        line = git("ls-remote", "--exit-code", "origin", f"refs/heads/{branch}")
    except GitUnavailable:
        out.append(f"branch '{branch}' does not exist on origin — push it first")
        return out

    remote = line.split("\t")[0].split()[0]
    if remote == head:
        return out

    # Distinguish ahead / behind / diverged: telling someone to push when they
    # need to pull is how a guard gets switched off.
    ahead = git("rev-list", "--count", f"{remote}..{head}")
    behind = git("rev-list", "--count", f"{head}..{remote}")
    if ahead != "0" and behind == "0":
        out.append(f"{ahead} unpushed commit(s) — `git push origin {branch}`")
    elif ahead == "0":
        out.append(
            f"HEAD is {behind} commit(s) behind origin/{branch} — `git pull` "
            "and publish the merged tree"
        )
    else:
        out.append(
            f"diverged from origin/{branch} ({ahead} ahead, {behind} behind) — "
            "reconcile before publishing"
        )
    return out


def main():
    try:
        payload = json.load(sys.stdin)
        cmd = (payload.get("tool_input") or {}).get("command") or ""
    except Exception as e:
        sys.stderr.write(
            f"BLOCKED: guard-publish could not read the hook payload ({e!r}).\n"
            "Refusing to allow an irreversible publish it could not inspect.\n"
        )
        return 2

    if not PUBLISH_RE.search(cmd):
        return 0
    if _publish_is_exempt(cmd):
        return 0

    try:
        problems = _problems()
    except GitUnavailable as e:
        sys.stderr.write(
            f"BLOCKED: cannot verify the commit is on origin — {e}\n"
            "A publish is irreversible; an unverifiable state is not a safe one.\n"
        )
        return 2

    if not problems:
        return 0

    sys.stderr.write(
        "BLOCKED: refusing to publish source that is not on the remote.\n"
        + "".join(f"  - {p}\n" for p in problems)
        + "(guard: .claude/hooks/guard-publish.py)\n"
    )
    return 2


# (command, should_block) — the cases that made earlier versions useless.
_TESTS = [
    ("dart pub publish --force", True),
    ("cd packages/x && dart pub publish", True),
    ("cd packages/x\ndart pub publish", True),  # was a bypass
    ("set -e\ncd packages/x\n  dart pub publish -f", True),  # was a bypass
    ("timeout 900 dart pub publish", True),  # was a bypass
    ("PUB_HOSTED_URL=x dart pub publish", True),  # was a bypass
    ("cd x; (dart pub publish)", True),  # was a bypass
    ("dart pub publish --dry-run && dart pub publish", True),  # was a bypass
    ("flutter pub publish", True),
    ("dart pub publish --dry-run", False),
    ("cd x && dart pub publish --dry-run", False),
    ('echo \'{"command":"dart pub publish"}\' | cat', False),
    ('grep -r "dart pub publish" docs/', False),
    ("git push origin main", False),
]


def _self_test():
    bad = 0
    for cmd, want in _TESTS:
        got = bool(PUBLISH_RE.search(cmd)) and not _publish_is_exempt(cmd)
        if got != want:
            bad += 1
            print(f"  FAIL want_block={want} got={got}  {cmd!r}")
    print(f"  {len(_TESTS) - bad}/{len(_TESTS)} pass")
    return 1 if bad else 0


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(_self_test())
    sys.exit(main())
