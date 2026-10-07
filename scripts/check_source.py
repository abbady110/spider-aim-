#!/usr/bin/env python3
"""Offline structural checks. NOT a substitute for Dart/Flutter compilation."""

import pathlib
import plistlib
import re
import sqlite3
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
errors = []
checks = 0


def check(condition, message):
    global checks
    checks += 1
    if not condition:
        errors.append(message)


for path in [*ROOT.glob("android/**/*.xml"), *ROOT.glob("ios/**/*.storyboard")]:
    try:
        ET.parse(path)
        check(True, str(path))
    except ET.ParseError as error:
        check(False, f"Invalid XML {path}: {error}")

for path in ROOT.glob("ios/**/*.plist"):
    try:
        with path.open("rb") as source:
            plistlib.load(source)
        check(True, str(path))
    except (ValueError, plistlib.InvalidFileException) as error:
        check(False, f"Invalid plist {path}: {error}")

for path in [*ROOT.glob("lib/**/*.dart"), *ROOT.glob("test/**/*.dart")]:
    for uri in re.findall(r"(?:import|export)\s+['\"]([^'\"]+)['\"]", path.read_text()):
        if uri.startswith("package:spider_aim/"):
            target = ROOT / "lib" / uri.removeprefix("package:spider_aim/")
        elif uri.startswith(("dart:", "package:")):
            continue
        else:
            target = path.parent / uri
        check(target.is_file(), f"Missing import {uri} in {path}")

for unsupported in ["web", "windows", "linux", "macos"]:
    check(not (ROOT / unsupported).exists(), f"Unsupported platform scaffold: {unsupported}")

manifest = ET.parse(ROOT / "android/app/src/main/AndroidManifest.xml")
permissions = [node.attrib.get("{http://schemas.android.com/apk/res/android}name")
               for node in manifest.findall("uses-permission")]
check(not permissions, f"Unexpected Android runtime/network permissions: {permissions}")
check(not manifest.findall(".//service"), "Unexpected background/accessibility service")

store = (ROOT / "lib/storage/sqlite_coach_store.dart").read_text()
sql = re.findall(r"await db\.execute\((['\"])(.*?)\1\)", store, re.DOTALL)
database = sqlite3.connect(":memory:")
for _, statement in sql:
    database.execute(statement)
for table in ["devices", "profiles", "backups", "events"]:
    check(database.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?", (table,)).fetchone(),
          f"Missing SQLite table: {table}")
database.execute("INSERT INTO backups VALUES ('b1', 'd1', '{}')")
for statement in ["DELETE FROM backups", "UPDATE backups SET payload = 'changed'"]:
    try:
        database.execute(statement)
        check(False, "Backup SQL trigger did not reject mutation")
    except sqlite3.IntegrityError:
        check(True, "Backup SQL trigger rejects mutation")
database.close()

workflow = (ROOT / ".github/workflows/android.yml").read_text()
for command in ["flutter pub get", "flutter analyze", "flutter test", "flutter build apk",
                "actions/upload-artifact@", "android-arm,android-arm64"]:
    check(command in workflow, f"CI missing {command}")
check("contents: read" in workflow, "CI should have read-only repository permission")

for module in ["aim/aim_calibration_engine", "movement/movement_calibration_engine",
               "throwables/throwables_calibration_engine", "landing/landing_assistant",
               "death_analysis/death_analysis_engine", "hit_registration/hit_registration_diagnostics"]:
    source = (ROOT / "lib" / f"{module}.dart").read_text()
    check("guard.requireAllowed()" in source, f"Guard not present in {module}")

if errors:
    print("Offline structural checks FAILED:")
    print("\n".join(errors))
    sys.exit(1)
print(f"PASS: {checks} offline structural checks (imports, XML/plist, SQLite triggers, platforms, CI).")
print("Dart/Flutter analysis, tests, and APK build were NOT executed by this script.")
