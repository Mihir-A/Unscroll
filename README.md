# Unscroll

Use Instagram on iOS without an infinite Reels feed.

Unscroll is a source-only patcher for a user-supplied, decrypted Instagram IPA.
It disables the network routes used by algorithmic Reels discovery, recommendations,
and chaining while leaving the rest of Instagram intact.

## What stays and what goes

| Instagram feature | Result |
| --- | --- |
| Home feed | Works normally |
| Explore and search | Works normally |
| Stories, profiles, and direct messages | Work normally |
| A Reel opened from a message or profile | Still opens |
| Reels discovery and recommendation feeds | Blocked |
| Endless Reel chaining | Blocked |
| Reels injected into other feeds | Blocked |

The Reels button may remain visible because Unscroll changes requests, not Instagram's
interface. Opening it should not produce a working algorithmic feed.

Unscroll also includes an optional sideload runtime fix. It keeps the signed app on
its available keychain and app-group containers so a force quit does not discard the
login session, and it prevents the sideloaded build from being mistaken for an
expired TestFlight beta.

## Requirements

- A Linux host with Python 3.10 or newer
- [Theos](https://theos.dev/docs/installation-linux)
- A decrypted ARM64 Instagram IPA that you obtained lawfully
- An iPhone running iOS 16.3 or newer
- An IPA signer or sideloading tool such as [SideStore](https://sidestore.io/)

The automated route set is currently verified against Instagram `439.0.0`. Instagram
can change its binary and endpoints at any time, so other versions may find different
route counts or need updates.

## Build

Clone the repository:

```bash
git clone https://github.com/Mihir-A/Unscroll.git
cd Unscroll
```

Install Theos by following its
[official Linux setup guide](https://theos.dev/docs/installation-linux). With Theos
at `~/theos`, build the runtime fix:

```bash
THEOS=~/theos make -C runtime_fix clean all FINALPACKAGE=1
```

Build an Unscroll IPA from your decrypted source IPA:

```bash
python3 build_unscroll.py \
  --runtime-fix runtime_fix/.theos/obj/UnscrollRuntimeFix.dylib \
  Instagram.ipa \
  Unscroll.ipa
```

The builder:

1. Validates that the IPA contains a decrypted ARM64 Mach-O executable.
2. Patches every known algorithmic Reels route without changing string lengths.
3. Injects the optional session and TestFlight runtime fix.
4. Removes bundled app extensions by default for easier sideload signing.
5. Rebuilds the IPA and verifies every ZIP entry with a CRC check.

If your signing setup supports all of Instagram's bundled extensions, retain them
with `--keep-extensions`.

To patch Reels without injecting the runtime fix, omit `--runtime-fix`:

```bash
python3 build_unscroll.py Instagram.ipa Unscroll.ipa
```

## Install

Sign and install `Unscroll.ipa` with your preferred iOS sideloading tool. For
SideStore, open the Apps screen, choose the `+` button, and select the resulting IPA.
The free Apple signing profile still needs to be refreshed on its normal schedule.

When replacing an existing signed installation, use the same bundle identifier and
signing identity if you want the sideloading tool to preserve its data container.

## Troubleshooting

**The builder says the executable is encrypted.**

Unscroll cannot decrypt apps. Use a legitimately obtained decrypted IPA.

**No routes were found.**

The Instagram version likely changed. Open an issue with the exact app version and
the builder's route-count output; do not attach the IPA.

**The app will not sign or install.**

Build without bundled extensions (the default), then let your sideloading tool sign
the rebuilt IPA.

**The account appears logged out after a force quit.**

Confirm that you built and injected `UnscrollRuntimeFix.dylib`. Reinstall the new IPA
over the existing sideloaded app where possible, then log in once.

**Instagram asks for a TestFlight beta update.**

Confirm that the runtime fix is present in the build output. The builder prints
`Injected runtime fix: UnscrollRuntimeFix.dylib` when injection succeeds.

## Legal and privacy

This repository does not contain, download, or distribute Instagram. Do not commit
or publish an IPA made with this tool. You are responsible for obtaining and using
the source app in accordance with applicable law and service terms.

Unscroll is not affiliated with, endorsed by, or sponsored by Instagram or Meta.
Instagram, Reels, TestFlight, and related names are trademarks of their respective
owners.

## Credits

Unscroll grew from the iOS route research in
[HealthyIG](https://github.com/AlessandroBonomo28/HealthyIG). The runtime compatibility
approach is based on
[IGSideloadFix](https://github.com/opa334/IGSideloadFix) by Lars Fröder and retains
its MIT license in [`runtime_fix/LICENSE`](runtime_fix/LICENSE).

The project is distributed under the [Apache License 2.0](LICENSE.md).
