# Floating Notes

A tiny standalone macOS app: one floating, always-on-top note editor toggled by a global hotkey — inspired by [Tinycast](https://github.com/abue-ammar/tinycast)'s Notes feature and Raycast's built-in Floating Notes. Unlike a Raycast extension, this is its own process with a Dock icon and native app menus, so it stays around independent of Raycast (or any launcher) being open and is easy to identify in Activity Monitor.

Each note is a plain `.md` file — no database or frontmatter. The default folder is `~/Documents/Floating Notes/`, and it can be changed in Settings. Filenames are generated automatically from the first non-empty line (up to 60 characters), while the editor always preserves the exact Markdown source on disk.

## Features

- **⌥.** toggles the panel from anywhere (registered via Carbon's `RegisterEventHotKey`, so no Accessibility permission prompt)
- Standard macOS app behavior: Dock/⌘Tab presence and Application, File, Edit, Format, and Window menus
- Independently hide the Dock icon and menu-bar icon; the app keeps running and remains available through **⌥.**
- CodeMirror 6 editor with Obsidian-style live preview: Markdown markers unfold around the cursor
- GFM support for headings, tables, strikethrough, links, fenced code, lists, and interactive task checkboxes
- Bullet lists use `*` in Markdown, preview as dots, and support Tab/Shift-Tab nesting with hanging indentation
- Autosaves ~300ms after you stop typing; always flushes immediately on hide or note switch
- Standard **⌘Z/⇧⌘Z**, **⌘X**, **⌘C**, **⌘V**, and **⌘A** editing shortcuts
- Selection-aware formatting shortcuts: **⌘B** bold, **⌘I** italic, **⌘U** underline, **⇧⌘X** strikethrough, **⌘L** link, **⌘E** inline code, **⌥⌘C** code block, and **⇧⌘B** block quote
- **⌘F** find, **⇧⌘F** find/replace, **⌘K** action panel, **⌘,** Settings, **⌘N** new note, **⌘P** search/switch notes, **⌘O** reveal notes folder, **⌘⌫** move to Trash
- **⌘Q** hides Floating Notes but leaves its background process and global hotkey active; **⇧⌘Q** confirms before quitting it completely
- Switcher searches both titles and note bodies
- Filename collisions append " 2", " 3", etc. (case- and accent-insensitive)
- Settings (**⌘,**) for menu-bar visibility and selecting, revealing, or resetting the notes folder
- Signed in-app updates with **Check for Updates…** in Settings, the app menu, and the menu-bar menu

## Build & run

Requires Xcode's command-line tools (for `swift build` and `codesign`) and Node.js/npm (to bundle CodeMirror).

```bash
./build.sh
open "build/Floating Notes.app"
```

`build.sh` bundles the web editor, compiles a universal Apple silicon/Intel release binary, assembles it into `build/Floating Notes.app`, and ad-hoc code-signs it.

## Publish an update

The app uses [Sparkle](https://sparkle-project.org/) and GitHub Releases. Update archives are signed with a dedicated Ed25519 key, and the matching public key is embedded in the app. The private key is stored in the local macOS Keychain and in the repository's encrypted `SPARKLE_PRIVATE_KEY` Actions secret.

Update behavior:

- Sparkle checks the public `appcast.xml` feed automatically, at most once per day.
- **Check for Updates…** starts an immediate user-initiated check.
- If a newer build is available, Sparkle verifies its signature before offering to install and relaunch.
- Automatic installation is disabled; the user always chooses when to install.

To publish, push a new semantic-version tag:

```bash
git switch main
git pull --ff-only
git tag v1.1.0
git push origin v1.1.0
```

The release workflow takes the display version from the tag, uses the GitHub Actions run number as Sparkle's monotonically increasing build number, builds the universal app, signs the update archive, generates `appcast.xml`, and publishes both files to a GitHub Release.

Version tags must use `vMAJOR.MINOR.PATCH`, must increase with every release, and should only point to commits already pushed to `main`. Do not replace the Sparkle key without following Sparkle's key-rotation procedure: existing installs trust the public key currently in `Info.plist`.

The first build containing Sparkle is a one-time manual install over older copies. All later releases can update in-app. For public distribution outside your own Macs, replace the workflow's ad-hoc app signature with a Developer ID signature and Apple notarization so Gatekeeper trusts fresh downloads.

See [Release and updater operations](docs/RELEASING.md) for the complete release checklist, signing-key recovery, verification commands, and troubleshooting.

## Run at login

Copy the built app to `/Applications`, then add it as a Login Item:

**System Settings → General → Login Items → +** → select `Floating Notes.app`

Or use a LaunchAgent if you'd rather not show it in Login Items:

```bash
mkdir -p ~/Library/LaunchAgents
cat > ~/Library/LaunchAgents/com.vishalbalaji.floatingnotes.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.vishalbalaji.floatingnotes</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/Floating Notes.app/Contents/MacOS/FloatingNotes</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF
launchctl load ~/Library/LaunchAgents/com.vishalbalaji.floatingnotes.plist
```

## Settings and hotkey

Open **Floating Notes → Settings…** or press **⌘,** to choose the notes folder and control the Dock and menu-bar icons independently. If both icons are hidden, use **⌥.** to reopen the window. Changing the folder does not move existing note files.

To change the global hotkey, edit the constants at the top of `Sources/FloatingNotes/HotKeyManager.swift` (`keyCode`, `modifiers`, `displayString`) and rebuild. Key codes are the `kVK_*` constants from `Carbon.HIToolbox`.

## Project structure

```
floating-notes/
├── Sources/FloatingNotes/
│   ├── main.swift                 # Entry point, sets normal foreground app policy
│   ├── AppDelegate.swift          # Status item, hotkey wiring, app lifecycle
│   ├── AppSettings.swift          # Persistent app preferences
│   ├── SettingsWindowController.swift # Native Settings window and storage controls
│   ├── HotKeyManager.swift        # Global hotkey via Carbon RegisterEventHotKey
│   ├── NotesRepository.swift      # Filesystem and content-derived filenames
│   ├── NotesStore.swift           # Observable state + autosave debounce
│   ├── NotesWindowController.swift# The floating NSPanel hosting the SwiftUI editor
│   ├── NoteEditorView.swift       # Single editor window and actions (SwiftUI)
│   ├── PlainTextEditor.swift      # WKWebView/CodeMirror bridge
│   ├── Resources/Editor/          # Editor HTML and generated JavaScript bundle
│   └── NoteSwitcherView.swift     # Search/select/trash list (SwiftUI)
├── editor-web/                    # CodeMirror live-preview source and build config
├── docs/RELEASING.md              # Release, signing-key, and updater runbook
├── .github/workflows/release.yml  # Tag-driven GitHub Release publisher
├── AGENTS.md                      # Repository guidance for coding agents
├── Info.plist
├── build.sh
└── Package.swift
```

## License

MIT — see [LICENSE](LICENSE).

The live-preview editor architecture is inspired by [MD Sticky Notes](https://github.com/jaesuny/markdown-sticky-notes), also MIT licensed.
