#!/usr/bin/env python3
"""Build an iOS Unscroll IPA with a minimal client-side Reels limiter."""

from __future__ import annotations

import argparse
import plistlib
import shutil
import struct
import tempfile
from pathlib import Path
from zipfile import ZIP_DEFLATED, BadZipFile, ZipFile, ZipInfo


EXECUTABLE = "Payload/Instagram.app/Instagram"
INFO_PLIST = "Payload/Instagram.app/Info.plist"
RUNTIME_FIX_NAME = "UnscrollRuntimeFix.dylib"
RUNTIME_FIX_ARCHIVE_PATH = f"Payload/Instagram.app/Frameworks/{RUNTIME_FIX_NAME}"
RUNTIME_FIX_INSTALL_NAME = f"@executable_path/Frameworks/{RUNTIME_FIX_NAME}"
EXTENSION_RUNTIME_FIX_INSTALL_NAME = (
    f"@executable_path/../../Frameworks/{RUNTIME_FIX_NAME}"
)
EXTENSION_PREFIXES = (
    "Payload/Instagram.app/Extensions/",
    "Payload/Instagram.app/PlugIns/",
)
UNSUPPORTED_EXTENSION_POINTS = {
    "com.apple.usernotifications.content-extension",
    "com.apple.usernotifications.service",
}
UNSUPPORTED_EXTENSION_BUNDLE_IDS = {
    "com.burbn.instagram.lockscreencamera",
}
UNSCROLL_URL_SCHEME = "unscroll"
LC_LOAD_DYLIB = 0xC
LC_SEGMENT_64 = 0x19
LC_ENCRYPTION_INFO = 0x21
LC_ENCRYPTION_INFO_64 = 0x2C


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build an iOS Instagram IPA with a single-item Reels viewer."
    )
    parser.add_argument("input", type=Path, help="decrypted Instagram IPA")
    parser.add_argument("output", type=Path, help="output Unscroll IPA")
    parser.add_argument(
        "--runtime-fix",
        type=Path,
        required=True,
        help="inject UnscrollRuntimeFix.dylib for sideload compatibility",
    )
    return parser.parse_args()


def encryption_id(binary: Path) -> int:
    with binary.open("rb") as stream:
        header = stream.read(32)
        if len(header) != 32:
            raise ValueError("Instagram executable is too small to be a Mach-O file")
        magic, _, _, _, command_count, _, _, _ = struct.unpack("<IiiIIIII", header)
        if magic != 0xFEEDFACF:
            raise ValueError(f"unsupported Mach-O magic 0x{magic:08x}; expected ARM64")

        for _ in range(command_count):
            command_header = stream.read(8)
            if len(command_header) != 8:
                raise ValueError("truncated Mach-O load commands")
            command, command_size = struct.unpack("<II", command_header)
            if command_size < 8:
                raise ValueError("invalid Mach-O load command size")
            payload = stream.read(command_size - 8)
            if len(payload) != command_size - 8:
                raise ValueError("truncated Mach-O load command")
            if command in (LC_ENCRYPTION_INFO, LC_ENCRYPTION_INFO_64):
                _, _, crypt_id = struct.unpack("<III", payload[:12])
                return crypt_id
    raise ValueError("Mach-O has no encryption information load command")


def inject_dylib(binary_path: Path, install_name: str) -> None:
    encoded_name = install_name.encode() + b"\0"
    command_size = (24 + len(encoded_name) + 7) & ~7
    dylib_command = (
        struct.pack("<IIIIII", LC_LOAD_DYLIB, command_size, 24, 0, 0, 0)
        + encoded_name
    ).ljust(command_size, b"\0")

    with binary_path.open("r+b") as stream:
        header = stream.read(32)
        if len(header) != 32:
            raise ValueError("Instagram executable has a truncated Mach-O header")
        (
            magic,
            cpu_type,
            _,
            _,
            command_count,
            commands_size,
            _,
            _,
        ) = struct.unpack("<IiiIIIII", header)
        if magic != 0xFEEDFACF or cpu_type != 0x0100000C:
            raise ValueError("dylib injection requires a 64-bit ARM Mach-O")

        command_area = stream.read(commands_size)
        if len(command_area) != commands_size:
            raise ValueError("Instagram executable has truncated load commands")
        if encoded_name[:-1] in command_area:
            raise ValueError(f"dylib is already injected: {install_name}")

        minimum_section_offset = binary_path.stat().st_size
        cursor = 0
        for _ in range(command_count):
            command, size = struct.unpack_from("<II", command_area, cursor)
            if size < 8 or cursor + size > len(command_area):
                raise ValueError("invalid Mach-O load command while injecting dylib")
            if command == LC_SEGMENT_64:
                if size < 72:
                    raise ValueError("invalid 64-bit Mach-O segment command")
                section_count = struct.unpack_from("<I", command_area, cursor + 64)[0]
                if 72 + section_count * 80 > size:
                    raise ValueError("invalid Mach-O section table")
                for section_index in range(section_count):
                    section = cursor + 72 + section_index * 80
                    section_offset = struct.unpack_from(
                        "<I", command_area, section + 48
                    )[0]
                    if section_offset:
                        minimum_section_offset = min(
                            minimum_section_offset, section_offset
                        )
            cursor += size

        command_end = 32 + commands_size
        new_command_end = command_end + command_size
        if new_command_end > minimum_section_offset:
            raise ValueError("Mach-O has insufficient header padding for dylib injection")
        stream.seek(command_end)
        if any(stream.read(command_size)):
            raise ValueError("Mach-O load command padding is not empty")

        stream.seek(command_end)
        stream.write(dylib_command)
        stream.seek(16)
        stream.write(struct.pack("<II", command_count + 1, commands_size + command_size))


def validate_runtime_fix(dylib_path: Path) -> None:
    with dylib_path.open("rb") as stream:
        header = stream.read(32)
    if len(header) != 32:
        raise ValueError("runtime fix dylib is truncated")
    magic, cpu_type, _, file_type, _, _, _, _ = struct.unpack(
        "<IiiIIIII", header
    )
    if magic != 0xFEEDFACF or cpu_type != 0x0100000C or file_type != 6:
        raise ValueError("runtime fix must be an ARM64 Mach-O dylib")


def validate_binary(binary_path: Path) -> None:
    crypt_id = encryption_id(binary_path)
    if crypt_id != 0:
        raise ValueError(
            f"Instagram executable is encrypted (cryptid={crypt_id}); "
            "use a decrypted IPA"
        )


def copy_zip_entry(source: ZipFile, target: ZipFile, info) -> None:
    if info.is_dir():
        target.writestr(info, b"")
        return
    with source.open(info, "r") as reader, target.open(info, "w") as writer:
        shutil.copyfileobj(reader, writer, length=1024 * 1024)


def add_runtime_fix(target: ZipFile, dylib_path: Path) -> None:
    info = ZipInfo(RUNTIME_FIX_ARCHIVE_PATH)
    info.create_system = 3
    info.compress_type = ZIP_DEFLATED
    info.external_attr = 0o100755 << 16
    with dylib_path.open("rb") as reader, target.open(info, "w") as writer:
        shutil.copyfileobj(reader, writer)


def extension_bundles(source: ZipFile) -> list[dict[str, str]]:
    bundles = []
    for name in source.namelist():
        if not name.endswith(".appex/Info.plist"):
            continue
        if not name.startswith(EXTENSION_PREFIXES):
            continue

        try:
            info = plistlib.loads(source.read(name))
        except plistlib.InvalidFileException as error:
            raise ValueError(f"invalid extension Info.plist: {name}") from error

        executable = info.get("CFBundleExecutable")
        if not isinstance(executable, str) or not executable:
            raise ValueError(f"extension has no executable: {name}")
        root = name.removesuffix("Info.plist")
        bundles.append(
            {
                "root": root,
                "bundle_id": info.get("CFBundleIdentifier", ""),
                "executable": root + executable,
                "point": info.get("NSExtension", {}).get(
                    "NSExtensionPointIdentifier", ""
                ),
            }
        )
    return bundles


def add_unscroll_url_scheme(raw_plist: bytes) -> bytes:
    try:
        info = plistlib.loads(raw_plist)
    except plistlib.InvalidFileException as error:
        raise ValueError("invalid Instagram Info.plist") from error

    url_types = info.setdefault("CFBundleURLTypes", [])
    if not isinstance(url_types, list):
        raise ValueError("Instagram CFBundleURLTypes is not an array")
    has_scheme = any(
        UNSCROLL_URL_SCHEME in url_type.get("CFBundleURLSchemes", [])
        for url_type in url_types
        if isinstance(url_type, dict)
    )
    if not has_scheme:
        url_types.append(
            {
                "CFBundleTypeRole": "Viewer",
                "CFBundleURLName": "Unscroll Link",
                "CFBundleURLSchemes": [UNSCROLL_URL_SCHEME],
            }
        )

    plist_format = (
        plistlib.FMT_BINARY if raw_plist.startswith(b"bplist") else plistlib.FMT_XML
    )
    return plistlib.dumps(info, fmt=plist_format, sort_keys=False)


def build_ipa(
    source_path: Path,
    output_path: Path,
    runtime_fix: Path,
) -> None:
    source_path = source_path.resolve()
    output_path = output_path.resolve()
    runtime_fix = runtime_fix.resolve()
    validate_runtime_fix(runtime_fix)
    if source_path == output_path:
        raise ValueError("input and output IPA paths must differ")
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(
        prefix=".unscroll-", dir=output_path.parent
    ) as temporary_dir:
        temporary = Path(temporary_dir)
        binary_path = temporary / "Instagram"
        staged_output = temporary / output_path.name
        patched_extensions: dict[str, Path] = {}

        try:
            with ZipFile(source_path, "r") as source:
                names = set(source.namelist())
                if EXECUTABLE not in names:
                    raise ValueError(f"IPA does not contain {EXECUTABLE}")
                if INFO_PLIST not in names:
                    raise ValueError(f"IPA does not contain {INFO_PLIST}")
                with source.open(EXECUTABLE) as reader, binary_path.open("wb") as writer:
                    shutil.copyfileobj(reader, writer, length=1024 * 1024)

                validate_binary(binary_path)
                inject_dylib(binary_path, RUNTIME_FIX_INSTALL_NAME)

                bundles = extension_bundles(source)
                removed_roots = {
                    bundle["root"]
                    for bundle in bundles
                    if bundle["point"] in UNSUPPORTED_EXTENSION_POINTS
                    or bundle["bundle_id"] in UNSUPPORTED_EXTENSION_BUNDLE_IDS
                }
                kept_bundles = [
                    bundle for bundle in bundles if bundle["root"] not in removed_roots
                ]
                empty_extension_directories = {
                    prefix
                    for prefix in EXTENSION_PREFIXES
                    if not any(
                        bundle["root"].startswith(prefix) for bundle in kept_bundles
                    )
                }
                for index, bundle in enumerate(kept_bundles):
                    executable = bundle["executable"]
                    if executable not in names:
                        raise ValueError(
                            f"extension executable is missing from IPA: {executable}"
                        )
                    staged_binary = temporary / f"extension-{index}"
                    with source.open(executable) as reader, staged_binary.open(
                        "wb"
                    ) as writer:
                        shutil.copyfileobj(reader, writer, length=1024 * 1024)
                    validate_binary(staged_binary)
                    inject_dylib(
                        staged_binary,
                        EXTENSION_RUNTIME_FIX_INSTALL_NAME,
                    )
                    patched_extensions[executable] = staged_binary

                patched_info_plist = add_unscroll_url_scheme(source.read(INFO_PLIST))

                removed_entries = 0
                with ZipFile(staged_output, "w", allowZip64=True) as target:
                    for info in source.infolist():
                        if info.filename == RUNTIME_FIX_ARCHIVE_PATH:
                            continue
                        if info.filename in empty_extension_directories:
                            removed_entries += 1
                            continue
                        if any(
                            info.filename.startswith(root) for root in removed_roots
                        ):
                            removed_entries += 1
                            continue
                        if info.filename == EXECUTABLE:
                            with binary_path.open("rb") as reader, target.open(
                                info, "w"
                            ) as writer:
                                shutil.copyfileobj(reader, writer, length=1024 * 1024)
                        elif info.filename == INFO_PLIST:
                            target.writestr(info, patched_info_plist)
                        elif info.filename in patched_extensions:
                            with (
                                patched_extensions[info.filename].open("rb") as reader,
                                target.open(info, "w") as writer,
                            ):
                                shutil.copyfileobj(
                                    reader, writer, length=1024 * 1024
                                )
                        else:
                            copy_zip_entry(source, target, info)
                    add_runtime_fix(target, runtime_fix)
        except BadZipFile as error:
            raise ValueError(f"invalid IPA/ZIP archive: {error}") from error

        with ZipFile(staged_output, "r") as verification:
            bad_entry = verification.testzip()
            if bad_entry:
                raise ValueError(f"rebuilt IPA failed CRC validation at {bad_entry}")
            output_names = set(verification.namelist())
            if any(
                name.startswith(root)
                for root in removed_roots
                for name in output_names
            ):
                raise ValueError("an unsupported app extension remains")
            if not set(patched_extensions).issubset(output_names):
                raise ValueError("a retained app extension is missing")
            if RUNTIME_FIX_ARCHIVE_PATH not in verification.namelist():
                raise ValueError("runtime fix is missing from the rebuilt IPA")

        staged_output.replace(output_path)

    print(f"Retained SideStore-compatible app extensions: {len(patched_extensions)}")
    print(f"Removed unsupported extension entries: {removed_entries}")
    print(
        "Injected Reels limiter and sideload compatibility into "
        f"the app and {len(patched_extensions)} extensions: {RUNTIME_FIX_NAME}"
    )
    print(f"Registered link scheme: {UNSCROLL_URL_SCHEME}://")
    print(f"Created: {output_path}")


def main() -> None:
    args = parse_args()
    try:
        build_ipa(
            args.input,
            args.output,
            args.runtime_fix,
        )
    except (OSError, ValueError) as error:
        raise SystemExit(f"error: {error}") from error


if __name__ == "__main__":
    main()
