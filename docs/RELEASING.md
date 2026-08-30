# Release and updater operations

Floating Notes uses Sparkle 2 to install updates from public GitHub Releases. This document is the operational runbook for publishing and diagnosing those updates.

## Update channel

- Feed: `https://github.com/vishalbalaji3/floating-notes/releases/latest/download/appcast.xml`
- Release workflow: `.github/workflows/release.yml`
- Release trigger: a pushed tag matching `vMAJOR.MINOR.PATCH`
- Update archive: `Floating-Notes-MAJOR.MINOR.PATCH.zip`
- Architectures: Apple silicon and Intel
- Minimum system: macOS 13

Sparkle compares `CFBundleVersion`, not only the display version. The workflow sets `CFBundleShortVersionString` from the tag and `CFBundleVersion` from `github.run_number`, which increases across release workflow runs.

## Prerequisites

Before publishing, verify that:

- The repository is public. Sparkle cannot anonymously download release assets from a private repository.
- GitHub Actions is enabled and the workflow has `contents: write` permission.
- The repository secret `SPARKLE_PRIVATE_KEY` exists.
- `Info.plist` still contains the matching `SUPublicEDKey`.
- The release commit is pushed and the worktree has no unintended changes.

Check the non-secret repository configuration with:

```bash
gh repo view vishalbalaji3/floating-notes --json visibility,url
gh secret list --repo vishalbalaji3/floating-notes
plutil -extract SUPublicEDKey raw Info.plist
```

Never print, log, commit, or paste the private Sparkle key into source files, issues, or release notes.

## Publish a release

Choose the next semantic version, then run:

```bash
git switch main
git pull --ff-only
git status --short
git tag v1.1.0
git push origin v1.1.0
```

Watch the workflow and inspect the resulting release:

```bash
gh run list --workflow Release --limit 5
gh run watch
gh release view v1.1.0
```

Verify that the public feed and archive are reachable without authentication:

```bash
curl --fail --location --head \
  https://github.com/vishalbalaji3/floating-notes/releases/latest/download/appcast.xml
curl --fail --location \
  https://github.com/vishalbalaji3/floating-notes/releases/latest/download/appcast.xml
```

Then use an older installed copy of Floating Notes and choose **Check for Updates…**. Confirm that the new version is offered, installs, relaunches, and preserves the notes folder and preferences.

Do not move an existing version tag. Publish a new, higher version if a release needs to be corrected.

## Bootstrap installation

Versions built before Sparkle was added cannot discover the update feed. Replace one of those copies manually with the first updater-enabled build. Once that build is installed in a writable location such as `/Applications`, subsequent releases can update in-app.

Running directly from a downloaded ZIP, a disk image, or another read-only/translocated location can prevent installation. Move the app to `/Applications` before testing updates.

## Sparkle signing key

The public key in `Info.plist` is safe to commit. The corresponding private key is stored:

- In the local macOS login Keychain under the account `com.vishalbalaji.floatingnotes`.
- In GitHub Actions as the encrypted secret `SPARKLE_PRIVATE_KEY`.

Sparkle's tools are available after package resolution under `.build/artifacts/sparkle/Sparkle/bin/`.

To export a backup to a temporary secure path:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account com.vishalbalaji.floatingnotes \
  -x /secure/temporary/path/sparkle-private-key
```

To restore that key on another Mac:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys \
  --account com.vishalbalaji.floatingnotes \
  -f /secure/temporary/path/sparkle-private-key
```

After restoring, delete the unencrypted export securely. Do not generate a replacement key casually: installed copies trust the existing public key, so changing it requires Sparkle's documented key-rotation process.

## Local verification

Run the definitive packaging check before changing release infrastructure:

```bash
./build.sh
codesign --verify --deep --strict --verbose=2 "build/Floating Notes.app"
file "build/Floating Notes.app/Contents/MacOS/FloatingNotes"
plutil -lint "build/Floating Notes.app/Contents/Info.plist"
```

The `file` output must list both `arm64` and `x86_64`. The build is ad-hoc signed by default. Set `CODE_SIGN_IDENTITY` to use another identity locally.

## Production distribution

Sparkle's Ed25519 signature authenticates update archives, but ad-hoc signing does not establish a public Gatekeeper identity. Before broadly distributing fresh downloads, update the release workflow to use a Developer ID Application certificate, the hardened runtime, and Apple notarization. Keep the Sparkle signature as an independent verification layer.

## Troubleshooting

### “Unable to check for updates”

- Confirm the latest GitHub Release is published rather than draft or prerelease.
- Confirm it contains both `appcast.xml` and the ZIP named in the appcast enclosure.
- Open the feed URL in a private browser session to ensure it requires no GitHub login.
- Inspect Console.app logs for the `com.vishalbalaji.floatingnotes` process and Sparkle subsystem.

### Update is not offered

- Confirm the release workflow's `CFBundleVersion` is greater than the installed build.
- Confirm the tag is a higher semantic version.
- Confirm the app is reading the expected `SUFeedURL` from its bundled `Info.plist`.
- Use **Check for Updates…** instead of waiting for the daily automatic check.

### Signature validation fails

- Confirm the `SPARKLE_PRIVATE_KEY` secret matches `SUPublicEDKey` in `Info.plist`.
- Do not hand-edit `appcast.xml`; regenerate it with Sparkle's `generate_appcast` tool.
- Confirm the published ZIP is exactly the archive that `generate_appcast` signed.
