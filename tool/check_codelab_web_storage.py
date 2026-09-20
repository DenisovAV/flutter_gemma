#!/usr/bin/env python3
"""Assert every codelab app is set up to install a model in a browser.

Core binds with `@JS` to globals that only exist once the page has loaded
flutter_gemma's `cache_api.js` (Cache API storage) and `opfs_helper.js` (OPFS
streaming), which an app has to copy out of the package's own `web/`. Without
them a web install downloads the whole model and then dies on
`window.cachePut`. `flutter build web` cannot see that — it never opens a
browser — so every codelab app shipped broken on web until this check existed.

What is asserted per app, and why each oracle is the one it is:

- Does the app use flutter_gemma at all? Read `pubspec.yaml`, not the Dart
  source: a starter step whose only mention of the plugin is a TODO comment
  must not be treated as using it, and an app that calls `initialize` without
  `await`, or across a line break, must not escape the check.
- Are the two JS files the ones the app actually resolves? Compare against the
  RESOLVED package (`.dart_tool/package_config.json` → pub cache), not this
  repo's copy. The apps depend on the published release; the repo copy is the
  next one. `web/opfs_helper.js` existed here for three releases before
  `.pubignore` let it into the package (#505), so the two really do diverge.
- Are the scripts loaded? Parse with the comment blocks removed: a tag commented
  out "while debugging" loads nothing, and a plain grep cannot tell.
- Does the app ask for OPFS streaming? Require it in the SAME file as the
  `FlutterGemma.initialize(` call, with comments stripped, so a mention in a
  neighbouring file's prose cannot satisfy it.

Fail closed everywhere: anything this cannot read is an error, never a pass.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import url2pathname

STORAGE_JS = ("cache_api.js", "opfs_helper.js")
# `litert_embeddings.js` is an ES module that imports the other three by
# relative path, so all four have to sit next to each other in the app's web/.
# The CDN one-liner the embeddings README prescribes cannot work: two of the
# imports 404 there (measured 2026-09-20), and the module then never executes.
EMBEDDINGS_JS = {
    "flutter_gemma_embeddings": ("litert_embeddings.js", "sentencepiece.js"),
    "flutter_gemma_litertlm": ("litert.js", "tensorflow.js"),
}
EMBEDDING_BACKEND = re.compile(r"LiteRtEmbeddingBackend\s*\(")

HTML_COMMENT = re.compile(r"<!--.*?-->", re.DOTALL)
# Whitespace-tolerant: `dart format` wraps both of these across lines, and a
# call it wrapped must not read as "this app never initializes".
INITIALIZE_CALL = re.compile(r"FlutterGemma\s*\.\s*initialize\s*\(")
STREAMING_ARG = re.compile(r"webStorageMode:\s*WebStorageMode\s*\.\s*streaming")
DART_BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)
DART_LINE_COMMENT = re.compile(r"//[^\n]*")

errors: list[str] = []


def fail(message: str) -> None:
    errors.append(message)
    print(f"::error::{message}")


def resolved_package_dir(app: Path, package: str) -> Path | None:
    """Where `package` resolves for `app`, or None if it cannot be read.

    `flutter pub get` has already run for every app by the time this is called
    (the analyze/test loop does it), so package_config.json is on disk.
    """
    config = app / ".dart_tool" / "package_config.json"
    try:
        entries = json.loads(config.read_text())["packages"]
    except (OSError, ValueError, KeyError):
        return None
    for entry in entries:
        if entry.get("name") == package:
            root = entry.get("rootUri", "")
            if root.startswith("file://"):
                return Path(url2pathname(urlparse(root).path))
            return (config.parent / root).resolve()
    return None


def declares(app: Path, package: str) -> bool:
    """True when pubspec.yaml declares `package` as a real dependency.

    Matches the two-space indent of a dependency entry, so a commented-out line
    or a transitive mention in prose does not count.
    """
    try:
        pubspec = (app / "pubspec.yaml").read_text()
    except OSError:
        fail(f"{app}/pubspec.yaml is unreadable — the web storage check cannot run")
        return False
    return re.search(rf"^  {re.escape(package)}:", pubspec, re.MULTILINE) is not None


def loads_script(html: str, src: str) -> bool:
    """True when the page loads `src`, ignoring commented-out tags."""
    live = HTML_COMMENT.sub("", html)
    pattern = re.compile(
        rf"""<script\b[^>]*\bsrc\s*=\s*["']\.?/?{re.escape(src)}["']""",
        re.IGNORECASE,
    )
    return pattern.search(live) is not None


def dart_code(text: str) -> str:
    """The file with comments removed, so prose cannot satisfy a check."""
    return DART_LINE_COMMENT.sub("", DART_BLOCK_COMMENT.sub("", text))


def check_app(app: Path, reference_web: Path) -> None:
    uses_gemma = declares(app, "flutter_gemma")

    index = app / "web" / "index.html"
    try:
        html = index.read_text()
    except OSError:
        fail(f"{index} is missing or unreadable — the web storage check cannot run")
        return

    for js in STORAGE_JS:
        source = reference_web / js
        copy = app / "web" / js
        if not copy.exists():
            if uses_gemma:
                fail(f"{copy} is missing — copy it from {source}")
            continue
        if copy.read_bytes() != source.read_bytes():
            fail(f"{copy} differs from the resolved package's {source}")
        if not loads_script(html, js):
            fail(f"{index} does not load {js}")

    # The engine bootstrap is the third leg of the same tripod: without the
    # `@litert-lm/core` handshake the browser fails at engine creation, and the
    # storage scripts alone would report a clean bill of health.
    if declares(app, "flutter_gemma_litertlm"):
        if "litertLmReady" not in HTML_COMMENT.sub("", html):
            fail(f"{index} does not publish window.litertLmReady (@litert-lm/core handshake)")

    # The embeddings loader, for the apps that register the backend.
    lib = app / "lib"
    registers_embeddings = lib.is_dir() and any(
        EMBEDDING_BACKEND.search(dart_code(path.read_text()))
        for path in lib.rglob("*.dart")
    )
    if registers_embeddings:
        for package, names in EMBEDDINGS_JS.items():
            source_dir = resolved_package_dir(app, package)
            if source_dir is None:
                fail(
                    f"{app} registers LiteRtEmbeddingBackend but {package} does not "
                    "resolve — the web storage check cannot run"
                )
                continue
            for js in names:
                source = source_dir / "web" / js
                copy = app / "web" / js
                if not source.is_file():
                    fail(f"{source} is missing — the web storage check cannot run")
                    continue
                if not copy.exists():
                    fail(f"{copy} is missing — copy it from {source}")
                    continue
                if copy.read_bytes() != source.read_bytes():
                    fail(f"{copy} differs from the resolved package's {source}")
        if not loads_script(html, "litert_embeddings.js"):
            fail(f"{index} does not load litert_embeddings.js")

    if not uses_gemma:
        return

    if not lib.is_dir():
        fail(f"{lib} is missing — the web storage check cannot run")
        return

    initializers = [
        path
        for path in sorted(lib.rglob("*.dart"))
        if INITIALIZE_CALL.search(dart_code(path.read_text()))
    ]
    for path in initializers:
        if not STREAMING_ARG.search(dart_code(path.read_text())):
            fail(
                f"{path} calls FlutterGemma.initialize without "
                "webStorageMode: WebStorageMode.streaming"
            )


def main(argv: list[str]) -> int:
    root = Path(argv[1]) if len(argv) > 1 else Path.cwd()
    apps = sorted(p.parent for p in root.glob("codelabs/*/*/pubspec.yaml"))

    # Fail closed, the way discovery does in check_codelabs.sh. A glob that
    # finds nothing must not read as "every app is fine".
    if not apps:
        print("::error::no codelab apps found — the web storage check cannot run")
        return 1

    reference_web = None
    for app in apps:
        if declares(app, "flutter_gemma"):
            package = resolved_package_dir(app, "flutter_gemma")
            if package is not None:
                reference_web = package / "web"
                print(f"Comparing against the resolved package: {reference_web}")
                break
    if reference_web is None:
        print(
            "::error::could not resolve flutter_gemma from any codelab app "
            "(run flutter pub get first) — the web storage check cannot run"
        )
        return 1
    for js in STORAGE_JS:
        if not (reference_web / js).is_file():
            print(
                f"::error::{reference_web / js} does not exist in the resolved "
                "package — the web storage check cannot run"
            )
            return 1

    for app in apps:
        check_app(app, reference_web)

    print(f"Checked web model storage in {len(apps)} app(s); {len(errors)} problem(s).")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
