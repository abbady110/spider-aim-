#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd -- "$script_directory/.."
bash scripts/bootstrap_flutter.sh
flutter pub get
flutter analyze --fatal-infos
flutter test --coverage
flutter build apk --release --target-platform android-arm,android-arm64
