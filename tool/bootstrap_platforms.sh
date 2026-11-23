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

# Native Android permission bridge for Android 17+ (API 37).
kotlin_dir="android/app/src/main/kotlin/com/oxita/camera_ip_search_mobile"
mkdir -p "$kotlin_dir"
cat > "$kotlin_dir/MainActivity.kt" <<'KOTLIN'
package com.oxita.camera_ip_search_mobile

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null
    private val permissionRequestCode = 9107
    private val localNetworkPermission = "android.permission.ACCESS_LOCAL_NETWORK"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.oxita.camera_ip_search_mobile/local_network"
        ).setMethodCallHandler { call, result ->
            if (call.method != "requestLocalNetworkPermission") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (Build.VERSION.SDK_INT < 37 ||
                checkSelfPermission(localNetworkPermission) == PackageManager.PERMISSION_GRANTED
            ) {
                result.success(true)
                return@setMethodCallHandler
            }
            if (permissionResult != null) {
                result.error("permission_in_progress", "A local-network permission request is already active.", null)
                return@setMethodCallHandler
            }
            permissionResult = result
            requestPermissions(arrayOf(localNetworkPermission), permissionRequestCode)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequestCode) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        permissionResult?.success(granted)
        permissionResult = null
    }
}
KOTLIN

python3 - <<'PY'
from pathlib import Path

manifest = Path("android/app/src/main/AndroidManifest.xml")
if manifest.exists():
    content = manifest.read_text()
    permissions = [
        "android.permission.INTERNET",
        "android.permission.ACCESS_NETWORK_STATE",
        "android.permission.ACCESS_WIFI_STATE",
        "android.permission.CHANGE_WIFI_MULTICAST_STATE",
        "android.permission.ACCESS_LOCAL_NETWORK",
    ]
    additions = "".join(
        f'    <uses-permission android:name="{permission}" />\n'
        for permission in permissions
        if f'android:name="{permission}"' not in content
    )
    if additions:
        content = content.replace("<application", additions + "    <application", 1)
        manifest.write_text(content)

plist = Path("ios/Runner/Info.plist")
if plist.exists():
    content = plist.read_text()
    key = "<key>NSLocalNetworkUsageDescription</key>"
    if key not in content:
        entry = key + "\n    <string>Discover and configure compatible cameras on your local network.</string>\n"
        content = content.replace("</dict>", entry + "</dict>", 1)
        plist.write_text(content)
PY

echo "Generated Android and iOS platform runners and local-network permission bridge."
echo "Android API 37+ requests ACCESS_LOCAL_NETWORK at runtime."
echo "iOS UDP multicast/broadcast still requires Apple's approved multicast entitlement and provisioning profile."
