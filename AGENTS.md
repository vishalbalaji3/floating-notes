# Repository guidance

These instructions apply to the entire repository.

## What this project is

Floating Notes is a standalone, unsandboxed macOS 13+ app. The native shell is Swift/AppKit/SwiftUI. The Markdown editor is CodeMirror 6 running in a `WKWebView`. Notes are plain Markdown files and user data must remain readable without the app.

The application intentionally behaves like a background utility:

- `⌥.` toggles its floating panel through a Carbon global hotkey.
- The Dock icon and menu-bar icon can both be hidden.
- `⌘Q` hides the UI but keeps the process and hotkey alive.
- `⇧⌘Q` is the explicit full-termination path.

Preserve those lifecycle semantics unless the task explicitly changes them.

## Source boundaries

- `Sources/FloatingNotes/`: native app source.
- `editor-web/src/editor.js`: editable CodeMirror implementation.
- `Sources/FloatingNotes/Resources/Editor/editor.bundle.js`: generated and gitignored; do not hand-edit it.
- `NotesRepository.swift`: filesystem naming, moves, and persistence rules. Treat changes here as data-safety changes.
- `NotesStore.swift`: in-memory state and autosave coordination.
- `PlainTextEditor.swift`: native/WebKit message bridge.
- `AppDelegate.swift`: menus, updater ownership, status item, activation policy, and application lifecycle.
- `Info.plist`: bundle identity, versions, minimum OS, and Sparkle trust configuration.
- `build.sh`: definitive distributable-app assembly path.
- `.github/workflows/release.yml`: tag-driven remote release path.
- `docs/RELEASING.md`: updater operations and troubleshooting.

## Build and verification

Use the smallest relevant check while iterating:

```bash
swift build
npm --prefix editor-web run build
```

Before handing off changes that affect packaging, resources, dependencies, Info.plist, or the updater, run:

```bash
./build.sh
codesign --verify --deep --strict --verbose=2 "build/Floating Notes.app"
file "build/Floating Notes.app/Contents/MacOS/FloatingNotes"
plutil -lint Info.plist
git diff --check
```

`./build.sh` runs `npm ci`, rebuilds the web editor, creates a universal `arm64`/`x86_64` app, embeds Sparkle, and signs the completed bundle. Do not treat a successful `swift build` alone as proof that the packaged app works.

There is currently no automated XCTest suite. For behavior changes, exercise the relevant window, keyboard command, persistence path, or updater flow manually when possible.

## Updater invariants

The updater is a security boundary. Read `docs/RELEASING.md` before changing it.

- Sparkle is the updater; GitHub Releases is the public update host.
- The feed URL is `https://github.com/vishalbalaji3/floating-notes/releases/latest/download/appcast.xml`.
- Release tags must match `vMAJOR.MINOR.PATCH`.
- `CFBundleShortVersionString` comes from the release tag; `CFBundleVersion` comes from the monotonically increasing GitHub Actions run number.
- The repository must remain public unless update hosting is migrated first.
- Keep `SUPublicEDKey` stable. Never invent, rotate, expose, print, or commit the private key.
- The private key belongs only in the macOS Keychain account `com.vishalbalaji.floatingnotes` and the `SPARKLE_PRIVATE_KEY` GitHub Actions secret.
- Never hand-edit a generated appcast or change its archive URL after signing.
- Preserve the `Sparkle.framework` symlinks and executable permissions when packaging; use `ditto`, not a flattening copy mechanism.
- Do not rename release assets or change `SUFeedURL`, the bundle identifier, or the Sparkle key without a migration plan for installed copies.
- Keep manual user approval for installation unless a task explicitly requests automatic installation.

Do not trigger a release, push a version tag, replace repository secrets, change repository visibility, or rotate signing keys unless the user explicitly authorizes that external action.

## Data and UI safety

- Never delete or migrate note files implicitly.
- Flush pending edits before hiding, switching notes, moving a note to Trash, or terminating.
- Preserve exact Markdown source; previews and derived filenames must not rewrite note content.
- Keep Cocoa responder-chain actions working for standard editing shortcuts.
- AppKit and observable UI state should remain main-actor isolated.
- Account for accessory-app activation behavior when opening or closing Settings and auxiliary windows.

## Working practices

- Preserve unrelated worktree changes; this repository is often edited with an app instance running from `build/`.
- Do not kill or replace a running installed copy unless the user asks. Rebuilding `build/Floating Notes.app` is expected.
- Update README.md and `docs/RELEASING.md` when commands, release assets, versioning, update hosting, key handling, or minimum system requirements change.
- Keep third-party dependency changes pinned in `Package.resolved` and `editor-web/package-lock.json`.
- Prefer focused edits over broad rewrites, especially in `editor-web/src/editor.js` and filesystem persistence code.
