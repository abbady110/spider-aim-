#!/usr/bin/env bash
set -euo pipefail

# Flutter distributes the Gradle wrapper and version-matched Xcode project as
# generated tooling. Fill missing scaffolding without replacing app sources.
script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_directory="$(cd -- "$script_directory/.." && pwd)"
cd -- "$repository_directory"

required_sources=(pubspec.yaml android/settings.gradle.kts android/app/build.gradle.kts)
for source in "${required_sources[@]}"; do
  if [[ ! -f "$source" ]]; then
    printf 'Required application source is missing: %s\n' "$source" >&2
    exit 1
  fi
done

wrapper_files=(
  android/gradlew
  android/gradlew.bat
  android/gradle/wrapper/gradle-wrapper.jar
  android/gradle/wrapper/gradle-wrapper.properties
)

missing_wrapper=false
for relative_path in "${wrapper_files[@]}"; do
  if [[ ! -f "$relative_path" ]]; then
    missing_wrapper=true
  fi
done

missing_ios_scaffold=false
if [[ ! -f ios/Runner.xcodeproj/project.pbxproj ]]; then
  missing_ios_scaffold=true
fi

if [[ "$missing_wrapper" == false && "$missing_ios_scaffold" == false ]]; then
  chmod +x android/gradlew
  exit 0
fi

scaffold_directory="$(mktemp -d /tmp/spider-aim-scaffold.XXXXXXXX)"
# Temporary scaffolding is intentionally confined to this newly created path.
trap '[[ "$scaffold_directory" == /tmp/spider-aim-scaffold.* ]] && rm -rf -- "$scaffold_directory"' EXIT
flutter create --no-pub --platforms=android,ios \
  --org org.spideraim --project-name spider_aim "$scaffold_directory"

for relative_path in "${wrapper_files[@]}"; do
  if [[ ! -f "$relative_path" ]]; then
    if [[ ! -f "$scaffold_directory/$relative_path" ]]; then
      printf 'Flutter did not generate required wrapper file: %s\n' "$relative_path" >&2
      exit 1
    fi
    mkdir -p -- "$(dirname -- "$relative_path")"
    cp -- "$scaffold_directory/$relative_path" "$relative_path"
    printf 'Generated missing build tooling: %s\n' "$relative_path"
  fi
done

# Use Flutter's exact Xcode project template and bundled assets. The custom
# AppDelegate, Info.plist, Podfile and platform configuration always win.
if [[ "$missing_ios_scaffold" == true ]]; then
  while IFS= read -r -d '' scaffold_path; do
    relative_path="${scaffold_path#"$scaffold_directory/"}"
    if [[ ! -e "$relative_path" ]]; then
      mkdir -p -- "$(dirname -- "$relative_path")"
      cp -- "$scaffold_path" "$relative_path"
    fi
  done < <(find "$scaffold_directory/ios" -type f -print0)
  printf 'Generated missing iOS scaffold without replacing native sources.\n'
fi
chmod +x android/gradlew
