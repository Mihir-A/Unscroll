# Unscroll

Use Instagram on iOS without an infinite Reels feed.

Unscroll injects a small client-side limiter into a user-supplied, decrypted
Instagram IPA. It filters suggested Reels from Home and prevents endless Reel
chaining without intercepting or changing Instagram's network requests.

## Compatibility

| Instagram version | Status | Date |
| --- | --- | --- |
| `447.0.0` | ⚠️ Build verified | September 17, 2026 |

## What stays and what goes

| Instagram feature | Result |
| --- | --- |
| Home feed | ✅ Works normally |
| Explore and search | ✅ Works normally |
| Stories, profiles, and direct messages | ✅ Work normally |
| A Reel opened from a message or profile | ✅ Still opens |
| Share extension, widgets, and Live Activities | ✅ Retained for SideStore |
| Reels tab | ⚠️ Shows one Reel |
| Endless Reel chaining | ❌ Blocked |
| Suggested Reels carousel in Home | ❌ Hidden |

The Reels button remains visible and opens one Reel. Swiping or refreshing does
not expose more recommendations. A Reel opened from a message or profile gets its
own viewer and remains available.

Unscroll only hooks two Reels-specific data sources. It does not modify Story
requests or models, so viewing and posting Stories remain separate.

The same small runtime library keeps the signed app on its available keychain and
app-group containers so a force quit does not discard the login session. It also
prevents the sideloaded app from being mistaken for an expired TestFlight beta.

## Recommended: Build with GitHub Actions

1. Fork Unscroll on GitHub.
2. Host your decrypted Instagram IPA at an HTTPS direct-download URL.
3. Open **Actions → Build Unscroll IPA → Run workflow** in your fork.
4. Enter the URL in `ipa_url` and run the workflow.

The workflow builds `Unscroll.ipa` and creates a draft release.

## Build locally

You need:

- A Linux computer with internet access and Python 3.10 or newer
- A lawfully obtained, decrypted ARM64 Instagram IPA
- An iPhone running iOS 16.3 or newer

Clone Unscroll, then run the one-command builder:

```bash
git clone https://github.com/Mihir-A/Unscroll.git
cd Unscroll
chmod +x ./unscroll-build
./unscroll-build /path/to/Instagram.ipa
```

The first run installs Theos, its iOS toolchain, and SDK under
`.build-tools/theos` inside the clone. The official Theos bootstrapper may ask for
`sudo` to install required Linux system packages. Subsequent builds reuse the
clone-local tools.

The result is `Unscroll.ipa` in the current directory. Choose another destination
with:

```bash
./unscroll-build --output /path/to/Unscroll.ipa /path/to/Instagram.ipa
```

Run `./unscroll-build --help` for advanced options, including using an existing
Theos installation.

The builder:

1. Installs and reuses a clone-local iOS build toolchain.
2. Builds one small library containing the Reels limiter and sideload fixes.
3. Confirms that the app and retained extension executables are decrypted ARM64
   code.
4. Injects the library without changing Instagram's network routes.
5. Retains Share, widget, Live Activity, broadcast, and camera-control extensions
   that SideStore can rebase under its signed app identifier.
6. Removes the two APNs-only notification extensions, which cannot receive native
   push under free SideStore provisioning, and the standalone Lock Screen camera
   extension whose fixed bundle identifier SideStore cannot install.
7. Adds the `unscroll://` link entry point and validates the rebuilt IPA.

The client hooks target Instagram `447.0.0`. Instagram can rename its internal
classes at any time, so other versions may need updated hook names.

## Install

Sign and install `Unscroll.ipa` with your preferred iOS sideloading tool. For
[SideStore](https://sidestore.io/), open Apps, choose the `+` button, and select the
resulting IPA. When prompted, select **Keep App Extensions (Use Main Profile)**.
A free Apple signing profile still needs to be refreshed on its normal schedule.

When replacing an existing signed installation, use the same bundle identifier and
signing identity if you want the sideloading tool to preserve its data container.

## Closest drop-in setup

Free SideStore provisioning cannot receive Instagram's native APNs notifications.
For notifications, calls, and universal links, keep the App Store version of
Instagram installed as a companion:

1. Sign in to the same account in Unscroll and official Instagram.
2. Open official Instagram last and enable only the notifications you want.
3. Remove official Instagram from the Home Screen without deleting it.
4. Keep Unscroll in Instagram's usual Home Screen position for normal use.

Notification taps and incoming calls open official Instagram at the correct
destination. Unscroll remains the client used for intentional browsing.

To send an Instagram web link to Unscroll, create a Share Sheet shortcut that
receives URLs, URL-encodes the input, builds
`unscroll://open?url=<encoded URL>`, and opens that URL. Unscroll validates the
Instagram host and passes the web link to Instagram's existing link router.

## Troubleshooting

**The builder says the executable is encrypted.**

Unscroll cannot decrypt apps. Use a legitimately obtained decrypted IPA.

**The workflow cannot create its draft release.**

In the fork, open **Settings → Actions → General → Workflow permissions**, select
**Read and write permissions**, save, and run the workflow again.

**Reels continue chaining.**

Confirm that the source IPA is Instagram `447.0.0` and rebuild it with the latest
Unscroll version. For another Instagram version, open an issue with its exact
version; do not attach the IPA.

**The app will not sign or install.**

Use a current SideStore release and choose **Keep App Extensions (Use Main
Profile)** instead of registering an App ID for each extension.

**The account appears logged out after a force quit.**

Reinstall the new IPA over the existing sideloaded app where possible, then log in
once. The standard builder always injects `UnscrollRuntimeFix.dylib` and reports
that injection in its output.

**Instagram asks for a TestFlight beta update.**

Confirm that the build output reports `Injected Reels limiter and sideload
compatibility` for the app and its retained extensions.

## Legal and privacy

This repository does not contain, download, or distribute Instagram. Do not commit
or publish an IPA made with this tool. You are responsible for obtaining and using
the source app in accordance with applicable law and service terms.

Unscroll is not affiliated with, endorsed by, or sponsored by Instagram or Meta.
Instagram, Reels, TestFlight, and related names are trademarks of their respective
owners.

The project is distributed under the [Apache License 2.0](LICENSE.md).
