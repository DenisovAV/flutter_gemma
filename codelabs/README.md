# Codelabs

The runnable code for the codelabs published at
[fluttergemma.dev/codelabs](https://fluttergemma.dev/codelabs).

## Layout

```
codelabs/<codelab-id>/step_NN_<name>/   a complete, runnable app
codelabs/<codelab-id>/complete/         the finished app
website/codelabs/<codelab-id>/index.md  the codelab text (claat source)
```

`<codelab-id>` is the same on both sides, and it is the URL the codelab is
published at.

**Steps are directories, not branches.** A learner opens a folder instead of
running `git checkout` in the middle of their own work, the diff between two
steps is a plain `diff -r`, and a fix is one sweep rather than a port across N
branches. It is also how [flutter/codelabs](https://github.com/flutter/codelabs)
is organised.

**A step exists where code changes hands**, not once per heading in the text.
Skipping numbers is fine: the point of a step directory is to give someone a
working app to resume from.

## Dependencies

Step apps are **not** members of the repo's pub workspace. They depend on the
*published* packages from pub.dev, exactly like a learner's checkout — so a
release that breaks the teaching material breaks this directory too, which is
the point.

They also do not commit a `pubspec.lock`, for the same reason: the codelab
tells the learner to `flutter pub add`, so the apps must resolve to whatever
that resolves to today.

That also means `flutter analyze packages/` never sees them. They have their
own gate:

```bash
tool/check_codelabs.sh     # pub get + analyze + format + test, every step
```

CI runs it on push, on pull requests, and **nightly** — a step app can rot
without anyone touching this repo, and the nightly run is what notices.

## Adding a codelab

1. `codelabs/<id>/step_01_.../` … — apps discovered automatically, no list to
   update.
2. `website/codelabs/<id>/index.md` — the text; `id:` in its front matter must
   match the directory.
3. Add the card to `website/lib/codelabs/codelabs_page.dart` and give it an
   `href` once the text is written. Cards without an `href` render as
   "Coming soon" and are deliberately not links.

## Integration tests

Some codelabs carry an `integration_test/` suite that downloads a real model
and runs inference. Those need a device and several hundred MB, so they are
**not** part of the CI gate. Run one by hand:

```bash
cd codelabs/getting-started-flutter-gemma/complete
flutter test integration_test/quickstart_test.dart -d <device-id>
```
