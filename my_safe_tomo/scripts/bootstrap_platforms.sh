#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ -d android || -d ios ]]; then
  echo "Android or iOS folder already exists; not overwriting it."
  exit 0
fi
flutter create --empty --platforms=android,ios --org com.mysafetomo --project-name my_safe_tomo _platform_seed
cp -R _platform_seed/android ./android
cp -R _platform_seed/ios ./ios
rm -rf _platform_seed
echo "Created Android and iOS runner folders. Follow README.md for platform permissions and FlutterFire setup."
