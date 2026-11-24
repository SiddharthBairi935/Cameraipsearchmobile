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

import android.content.Context
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import java.net.NetworkInterface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private val permissionRequestCode = 9107
    private val localNetworkPermission = "android.permission.ACCESS_LOCAL_NETWORK"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.oxita.camera_ip_search_mobile/local_network"
        ).setMethodCallHandler { call, result ->
            if (call.method == "getNetworkInterfaceDetails") {
                val requested = call.argument<String>("interfaceName").orEmpty()
                try {
                    val networkInterface = NetworkInterface.getByName(requested)
                    if (networkInterface == null) {
                        result.success(mapOf("available" to false, "name" to requested))
                    } else {
                        result.success(mapOf(
                            "available" to true,
                            "name" to networkInterface.name,
                            "mtu" to runCatching { networkInterface.mtu }.getOrNull(),
                            "isUp" to runCatching { networkInterface.isUp }.getOrDefault(false),
                            "isLoopback" to runCatching { networkInterface.isLoopback }.getOrDefault(false)
                        ))
                    }
                } catch (error: Exception) {
                    result.error("interface_diagnostics_failed", error.message ?: "Unable to inspect interface.", null)
                }
                return@setMethodCallHandler
            }
            if (call.method == "probeIpv4Conflict") {
                val targetText = call.argument<String>("address").orEmpty()
                val interfaceName = call.argument<String>("interfaceName").orEmpty()
                try {
                    val octets = targetText.split(".").map { it.toIntOrNull() }
                    if (octets.size != 4 || octets.any { it == null || it < 0 || it > 255 }) {
                        result.success(mapOf("state" to "unknown", "evidence" to "A valid IPv4 address is required."))
                        return@setMethodCallHandler
                    }
                    val targetBytes = octets.map { it!!.toByte() }.toByteArray()
                    val target = java.net.InetAddress.getByAddress(targetBytes) as java.net.Inet4Address
                    val networkInterface = NetworkInterface.getByName(interfaceName)
                    if (networkInterface == null || !networkInterface.isUp) {
                        result.success(mapOf("state" to "unknown", "evidence" to "The selected interface is unavailable or not running."))
                        return@setMethodCallHandler
                    }
                    var attachedSubnet = false
                    for (entry in networkInterface.interfaceAddresses) {
                        val local = entry.address as? java.net.Inet4Address ?: continue
                        val prefix = entry.networkPrefixLength.toInt()
                        if (prefix !in 1..32) continue
                        if (target.address.contentEquals(local.address)) {
                            result.success(mapOf("state" to "conflict", "evidence" to "The proposed address belongs to this phone's selected interface."))
                            return@setMethodCallHandler
                        }
                        val mask = if (prefix == 32) -1 else (-1 shl (32 - prefix))
                        val targetValue = java.nio.ByteBuffer.wrap(target.address).int
                        val localValue = java.nio.ByteBuffer.wrap(local.address).int
                        if ((targetValue and mask) != (localValue and mask)) continue
                        attachedSubnet = true
                        if (prefix in 1..30) {
                            val network = localValue and mask
                            val broadcast = network or mask.inv()
                            if (targetValue == network || targetValue == broadcast) {
                                result.success(mapOf("state" to "unknown", "evidence" to "The target is the subnet network or broadcast address; no probe was sent."))
                                return@setMethodCallHandler
                            }
                        }
                    }
                    if (!attachedSubnet) {
                        result.success(mapOf("state" to "unknown", "evidence" to "Target is not on a subnet attached to the selected interface."))
                        return@setMethodCallHandler
                    }
                    val responsive = target.isReachable(networkInterface, 1, 1200)
                    if (responsive) {
                        result.success(mapOf("state" to "conflict", "evidence" to "The target responded to an interface-scoped reachability probe; treat the address as occupied."))
                    } else {
                        result.success(mapOf("state" to "unknown", "evidence" to "No response was received. This is not proof that the address is free; assignment remains blocked."))
                    }
                } catch (error: Exception) {
                    result.success(mapOf("state" to "unknown", "evidence" to "Android conflict probe failed: ${error.message ?: "unknown error"}"))
                }
                return@setMethodCallHandler
            }
            if (call.method == "acquireMulticastLock") {
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                if (multicastLock == null) {
                    multicastLock = wifiManager.createMulticastLock("camera_ip_search_mobile_discovery").apply {
                        setReferenceCounted(false)
                    }
                }
                if (multicastLock?.isHeld != true) multicastLock?.acquire()
                result.success(true)
                return@setMethodCallHandler
            }
            if (call.method == "releaseMulticastLock") {
                if (multicastLock?.isHeld == true) multicastLock?.release()
                result.success(true)
                return@setMethodCallHandler
            }
            if (call.method != "requestLocalNetworkPermission") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (Build.VERSION.SDK_INT < 37 || applicationInfo.targetSdkVersion < 37 ||
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

    override fun onDestroy() {
        if (multicastLock?.isHeld == true) multicastLock?.release()
        super.onDestroy()
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

# file_picker's Android lifecycle dependency requires compileSdk 36+.
# Flutter templates vary between Groovy/Kotlin DSL and SDK releases, so
# normalize the generated compileSdk declaration rather than matching one
# template spelling. Fail loudly if the template changes unexpectedly.
import re
import os

compile_sdk_updated = False
for gradle_file in [Path("android/app/build.gradle.kts"), Path("android/app/build.gradle")]:
    if gradle_file.exists():
        gradle_content = gradle_file.read_text()
        gradle_content, replacements = re.subn(
            r"(?m)^(\s*)compileSdk(?:Version)?\s*(?:=\s*)?(?:flutter\.compileSdkVersion|\d+)(\s*(?://.*)?)$",
            r"\g<1>compileSdk = 36\g<2>",
            gradle_content,
        )
        if replacements:
            compile_sdk_updated = True
            gradle_file.write_text(gradle_content)
            print(f"Set {gradle_file} compileSdk to 36.")
if not compile_sdk_updated:
    raise SystemExit("Could not find a generated Android compileSdk declaration to raise to 36.")

# Some Flutter plugins ship Android library modules pinned to API 34.
# The app-level compileSdk alone does not override those library modules.
pub_cache = Path(os.environ.get("PUB_CACHE", str(Path.home() / ".pub-cache")))
for gradle_file in pub_cache.glob("hosted/pub.dev/*/android/build.gradle*"):
    content = gradle_file.read_text()
    updated = re.sub(
        r"(?m)^(\\s*)compileSdkVersion\\s+\\d+",
        r"\\g<1>compileSdkVersion 36",
        content,
    )
    updated = re.sub(
        r"(?m)^(\\s*)compileSdk\\s*=\\s*\\d+",
        r"\\g<1>compileSdk = 36",
        updated,
    )
    if updated != content:
        gradle_file.write_text(updated)
        print(f"Raised Android plugin compileSdk to 36: {gradle_file.parent.parent.name}")

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

app_delegate = Path("ios/Runner/AppDelegate.swift")
if app_delegate.exists():
    content = app_delegate.read_text()
    if "getNetworkInterfaceDetails" not in content:
        content = content.replace("import UIKit", "import UIKit\nimport Darwin")
        marker = "    GeneratedPluginRegistrant.register(with: self)"
        handler = '''
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.oxita.camera_ip_search_mobile/local_network",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        guard call.method == "getNetworkInterfaceDetails" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard let arguments = call.arguments as? [String: Any],
              let requestedName = arguments["interfaceName"] as? String else {
          result(FlutterError(code: "invalid_arguments", message: "interfaceName is required.", details: nil))
          return
        }
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else {
          result(FlutterError(code: "interface_diagnostics_failed", message: "getifaddrs failed.", details: nil))
          return
        }
        defer { freeifaddrs(addresses) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        var found = false
        var isUp = false
        var isLoopback = false
        while let current = cursor {
          let item = current.pointee
          if let interfaceName = item.ifa_name,
             String(cString: interfaceName) == requestedName {
            found = true
            isUp = (item.ifa_flags & UInt32(IFF_UP)) != 0
            isLoopback = (item.ifa_flags & UInt32(IFF_LOOPBACK)) != 0
            break
          }
          cursor = item.ifa_next
        }
        result([
          "available": found,
          "name": requestedName,
          "isUp": isUp,
          "isLoopback": isLoopback,
          "mtu": NSNull(),
          "mtuAvailable": false
        ])
      }
    }
'''
        if marker in content:
            content = content.replace(marker, handler, 1)
            app_delegate.write_text(content)

PY

echo "Generated Android and iOS platform runners and local-network permission bridge."
echo "Android API 37+ requests ACCESS_LOCAL_NETWORK at runtime."
echo "iOS UDP multicast/broadcast still requires Apple's approved multicast entitlement and provisioning profile."
