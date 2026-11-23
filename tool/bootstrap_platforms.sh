#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK is required. Install Flutter and retry." >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
flutter create --platforms=android,ios --project-name camera_ip_search_mobile --org com.oxita "$tmp_dir/camera_ip_search_mobile"
cp -R "$tmp_dir/camera_ip_search_mobile/android" .
cp -R "$tmp_dir/camera_ip_search_mobile/ios" .

echo "Generated Android and iOS platform runners."
echo "Next: add ACCESS_LOCAL_NETWORK runtime handling for Android API 37+."
echo "Next: add NSLocalNetworkUsageDescription to iOS Runner/Info.plist."
echo "iOS UDP multicast/broadcast also requires Apple's approved multicast entitlement."
