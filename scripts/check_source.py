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

android_attribute = "{http://schemas.android.com/apk/res/android}"
tools_attribute = "{http://schemas.android.com/tools}"
manifest = ET.parse(ROOT / "android/app/src/main/AndroidManifest.xml")
allowed_permissions = {
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.PACKAGE_USAGE_STATS",
    "android.permission.SYSTEM_ALERT_WINDOW",
}
required_network_removals = {
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
}
permission_nodes = [node for node in manifest.getroot()
                    if node.tag.startswith("uses-permission")]
removal_nodes = [node for node in permission_nodes
                 if node.attrib.get(f"{tools_attribute}node") == "remove"]
removed_permissions = [node.attrib.get(f"{android_attribute}name") for node in removal_nodes]
check(set(removed_permissions) == required_network_removals,
      f"Both dependency network permissions must be removed explicitly: {removed_permissions}")
check(len(removed_permissions) == 2, "Exactly two distinct network permission removals are required")
for node in removal_nodes:
    check(node.tag == "uses-permission" and set(node.attrib) == {
        f"{android_attribute}name", f"{tools_attribute}node",
    }, "Network permission removals must be unconditional, with no SDK or library selectors")
permissions = [node.attrib.get(f"{android_attribute}name") for node in permission_nodes
               if node.attrib.get(f"{tools_attribute}node") != "remove"]
check(set(permissions) == allowed_permissions,
      f"Capture permission declarations differ from the official allowlist: {permissions}")
check(len(permissions) == len(set(permissions)), "Duplicate Android permission declaration")
for other_manifest in ROOT.glob("android/app/src/*/AndroidManifest.xml"):
    declared = ET.parse(other_manifest)
    for node in declared.getroot():
        if node.tag.startswith("uses-permission"):
            permission = node.attrib.get(f"{android_attribute}name")
            operation = node.attrib.get(f"{tools_attribute}node")
            if operation == "remove":
                check(permission in required_network_removals,
                      f"Unexpected permission removal in {other_manifest}: {permission}")
            else:
                check(operation is None and permission in allowed_permissions,
                      f"Unexpected permission or merger operation in {other_manifest}: {permission}")

services = manifest.findall(".//service")
check(len(services) == 1, "Only the official capture foreground service may be declared")
for service in services:
    check(service.attrib.get(f"{android_attribute}name") == ".capture.PubgCaptureService",
          "Unexpected Android service; input/accessibility/control services are forbidden")
    check(service.attrib.get(f"{android_attribute}exported") == "false",
          "Capture service must not be externally exported")
    check(service.attrib.get(f"{android_attribute}foregroundServiceType") == "mediaProjection",
          "Capture service must use only the official mediaProjection type")
    check(service.attrib.get(f"{android_attribute}stopWithTask") == "true",
          "Capture service must stop with its owning task")
    check(not service.findall("intent-filter"), "Capture service must have no external intent filter")
    check(not service.findall("meta-data"), "Unexpected service metadata or accessibility configuration")
    check(f"{android_attribute}permission" not in service.attrib,
          "Unexpected binding/control permission on capture service")

for node in manifest.iter():
    check("android.accessibilityservice.AccessibilityService" not in node.attrib.values(),
          "Accessibility control service declaration is forbidden")

for path in [*ROOT.glob("android/app/src/main/**/*.kt"),
             *ROOT.glob("android/app/src/main/**/*.java"), *ROOT.glob("lib/**/*.dart")]:
    source = path.read_text()
    forbidden_control = re.search(
        r"\b(?:AccessibilityService|BIND_ACCESSIBILITY_SERVICE)\b|"
        r"\b(?:dispatchGesture|injectInputEvent|sendPointerSync|sendKeySync)\s*\(",
        source,
    )
    check(forbidden_control is None, f"Forbidden input/accessibility control API in {path}")

guard = (ROOT / "lib/game_mode_guard/game_mode_guard.dart").read_text()
check(re.search(r"void\s+declareOfflineMode\(GameMode\s+\w+\)\s*\{\s*\}", guard),
      "Legacy manual mode declaration must remain a no-op")
check("AutomaticModeRecognizer" in guard, "Guard must delegate to automatic recognition")
mode_source = (ROOT / "lib/game_mode_guard/game_mode.dart").read_text()
mode_codes = set(re.findall(r"=>\s*'([A-Z_]+)'", mode_source))
check(mode_codes == {"TRAINING_SAFE", "WAREHOUSE_SAFE", "ARENA_SAFE", "SAFE_UNRANKED",
                     "COMPETITIVE_BLOCKED", "UNKNOWN_BLOCKED"},
      "Automatic guard must expose exactly the six specified mode codes")
native_build = (ROOT / "android/app/build.gradle.kts").read_text()
check('com.google.mlkit:text-recognition:' in native_build,
      "Capture must use the bundled on-device ML Kit text recognition dependency")
capture_source = (ROOT / "android/app/src/main/kotlin/org/spideraim/coach/capture/PubgCaptureService.kt").read_text()
check("MediaProjection" in capture_source and "startForeground(" in capture_source,
      "Capture must use official MediaProjection and foreground-service lifecycle")
check(not re.search(r"\b(?:FileOutputStream|MediaRecorder|MediaMuxer|OkHttpClient)\b", capture_source),
      "Unexpected raw capture persistence, recording, or network client")

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
                "./gradlew :app:testReleaseUnitTest", "bash scripts/check_apk_permissions.sh",
                ":app:testReleaseUnitTest",
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
print(f"PASS: {checks} offline structural checks (imports, XML/plist, capture permissions/services, automatic guard, SQLite triggers, platforms, CI).")
print("Dart/Flutter analysis, tests, and APK build were NOT executed by this script.")
