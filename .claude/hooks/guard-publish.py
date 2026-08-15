#!/usr/bin/env python3
"""Block `dart pub publish` unless the exact commit being published is on the remote.

Why this exists: on 2026-08-15 flutter_gemma_litertlm 1.4.0 was published while
the branch still sat 20+ commits behind on origin. For ~25 minutes the package
existed on pub.dev with no corresponding source anywhere on GitHub — nobody
could have reproduced or reviewed what shipped.

The release skill already states the correct order (step 9 push, step 10
publish). It was read and the order was still inverted, which is the argument
for a guard rather than more prose: a checklist advises, a hook refuses.

Blocks when, for a real publish (not --dry-run):
  * the working tree is dirty  -> the tarball would not match any commit, or
  * HEAD is absent from origin -> the published source is unreachable.

Exit 0 allows, exit 2 blocks with the message on stderr.
"""
import json
import subprocess
import sys


def git(*args):
    return subprocess.run(
        ["git", *args], capture_output=True, text=True
    ).stdout.strip()


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0  # never block on a malformed payload

    cmd = payload.get("tool_input", {}).get("command", "")
    if "pub publish" not in cmd:
        return 0
    if "--dry-run" in cmd:
        return 0  # dry-run touches nothing

    problems = []

    if git("status", "--porcelain"):
        problems.append(
            "the working tree is dirty — the published archive would not "
            "correspond to any commit"
        )

    head = git("rev-parse", "HEAD")
    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    remote = ""
    if branch and branch != "HEAD":
        line = git("ls-remote", "--heads", "origin", branch)
        remote = line.split()[0] if line else ""

    if not remote:
        problems.append(f"branch '{branch}' does not exist on origin — push it first")
    elif remote != head:
        behind = git("rev-list", "--count", f"{remote}..{head}") or "?"
        problems.append(
            f"origin/{branch} is at {remote[:8]}, HEAD is at {head[:8]} "
            f"({behind} unpushed commit(s)) — push before publishing"
        )

    if not problems:
        return 0

    sys.stderr.write(
        "BLOCKED: refusing to publish source that is not on the remote.\n"
        + "".join(f"  - {p}\n" for p in problems)
        + "\nFix: git push origin "
        + (branch or "<branch>")
        + "  then publish again.\n"
        "(guard: .claude/hooks/guard-publish.py)\n"
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
