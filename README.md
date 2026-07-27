# Unscroll

Use Instagram on iOS without an infinite Reels feed.

Unscroll patches a user-supplied, decrypted Instagram IPA. It blocks the network
routes used by algorithmic Reels discovery, recommendations, and endless chaining
while keeping normal Instagram features available.

## Compatibility

| Instagram version | Status | Date |
| --- | --- | --- |
| `439.0.0` | ✅ Success | July 26, 2026 |

## What stays and what goes

| Instagram feature | Result |
| --- | --- |
| Home feed | ✅ Works normally |
| Explore and search | ✅ Works normally |
| Stories, profiles, and direct messages | ✅ Work normally |
| A Reel opened from a message or profile | ✅ Still opens |
| Reels discovery and recommendation feeds | ❌ Blocked |
| Endless Reel chaining | ❌ Blocked |
| Reels injected into other feeds | ❌ Blocked |

The Reels button may remain visible because Unscroll changes requests rather than
Instagram's interface. Opening it should not produce a working algorithmic feed.

Instagram internally uses the older “reels media” name for Story endpoints.
Unscroll deliberately preserves those routes so viewing and posting Stories keeps
working.

Every standard build also injects a small sideload compatibility fix. It keeps the
signed app on its available keychain and app-group containers so a force quit does
not discard the login session, and it prevents the sideloaded app from being
mistaken for an expired TestFlight beta.

## Recomended: Build with GitHub Actions

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

Clone your fork, then run the one-command builder:

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

Run `./unscroll-build --help` for advanced options, including retaining app
extensions or using an existing Theos installation.

The builder:

1. Installs and reuses a clone-local iOS build toolchain.
2. Builds and injects the session and TestFlight compatibility fix.
3. Confirms that the app executable is decrypted ARM64 code.
4. Patches the known algorithmic Reels routes without changing string lengths.
5. Removes bundled app extensions by default for easier sideload signing.
6. Rebuilds the IPA and checks every ZIP entry.

The route set is currently verified against Instagram `439.0.0`. Instagram can
change its binary and endpoints at any time, so other versions may find different
route counts or need updates.

## Install

Sign and install `Unscroll.ipa` with your preferred iOS sideloading tool. For
[SideStore](https://sidestore.io/), open Apps, choose the `+` button, and select the
resulting IPA. A free Apple signing profile still needs to be refreshed on its
normal schedule.

When replacing an existing signed installation, use the same bundle identifier and
signing identity if you want the sideloading tool to preserve its data container.

## Troubleshooting

**The builder says the executable is encrypted.**

Unscroll cannot decrypt apps. Use a legitimately obtained decrypted IPA.

**The workflow cannot create its draft release.**

In the fork, open **Settings → Actions → General → Workflow permissions**, select
**Read and write permissions**, save, and run the workflow again.

**No routes were found.**

The Instagram version likely changed. Open an issue with the exact app version and
the builder's route-count output; do not attach the IPA.

**The app will not sign or install.**

Build without bundled extensions, which is the default, then let your sideloading
tool sign the rebuilt IPA.

**The account appears logged out after a force quit.**

Reinstall the new IPA over the existing sideloaded app where possible, then log in
once. The standard builder always injects `UnscrollRuntimeFix.dylib` and reports
that injection in its output.

**Instagram asks for a TestFlight beta update.**

Confirm that the build output reports `Injected runtime fix:
UnscrollRuntimeFix.dylib`.

## Legal and privacy

This repository does not contain, download, or distribute Instagram. Do not commit
or publish an IPA made with this tool. You are responsible for obtaining and using
the source app in accordance with applicable law and service terms.

Unscroll is not affiliated with, endorsed by, or sponsored by Instagram or Meta.
Instagram, Reels, TestFlight, and related names are trademarks of their respective
owners.

## Credits

Unscroll grew from the iOS route research in
[HealthyIG](https://github.com/AlessandroBonomo28/HealthyIG). The runtime
compatibility approach is based on
[IGSideloadFix](https://github.com/opa334/IGSideloadFix) by Lars Fröder and retains
its MIT license in [`runtime_fix/LICENSE`](runtime_fix/LICENSE).

The project is distributed under the [Apache License 2.0](LICENSE.md).
