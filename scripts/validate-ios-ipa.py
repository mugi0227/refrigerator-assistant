"""Validate the actual IPA metadata used by AltServer for App ID registration."""
import plistlib
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    bad = archive.testzip()
    if bad:
        raise SystemExit(f"Corrupt IPA entry: {bad}")
    app_infos = [name for name in archive.namelist()
                 if name.startswith("Payload/") and name.endswith(".app/Info.plist")
                 and name.count("/") == 2]
    if len(app_infos) != 1:
        raise SystemExit("IPA must contain one top-level Payload/*.app/Info.plist")
    info = plistlib.loads(archive.read(app_infos[0]))
    for key in ("CFBundleDisplayName", "CFBundleName"):
        value = info.get(key)
        if not isinstance(value, str) or not value.strip() or not value.isascii():
            raise SystemExit(f"{key} must be non-empty ASCII for AltServer App ID registration")
    app = app_infos[0].removesuffix("Info.plist")
    if app + info["CFBundleExecutable"] not in archive.namelist():
        raise SystemExit("IPA executable is missing")
    print(f'Validated AltStore IPA: {info["CFBundleDisplayName"]} '
          f'{info["CFBundleShortVersionString"]} ({info["CFBundleIdentifier"]})')
