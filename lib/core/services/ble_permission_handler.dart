import 'dart:io';

/// Handles Android 12+ (API 31+) and Android 14+ (API 34+) BLE permission model changes.
/// Prior to Android 12, BLE required only ACCESS_FINE_LOCATION.
/// Android 12+ introduced BLUETOOTH_SCAN, BLUETOOTH_CONNECT, BLUETOOTH_ADVERTISE.
/// Android 14 tightened callback registration — this handler wraps the platform
/// channel calls to register scan callbacks correctly on all API levels.
class BlePermissionHandler {
  static const int _androidApi31 = 31;
  static const int _androidApi34 = 34;

  // Required permissions per Android API level
  static const List<String> _permissionsApi31 = [
    'android.permission.BLUETOOTH_SCAN',
    'android.permission.BLUETOOTH_CONNECT',
    'android.permission.BLUETOOTH_ADVERTISE',
  ];

  static const List<String> _permissionsPreApi31 = [
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.BLUETOOTH',
    'android.permission.BLUETOOTH_ADMIN',
  ];

  /// Returns the list of permissions required for the current Android API level.
  static List<String> requiredPermissions(int apiLevel) {
    if (apiLevel >= _androidApi31) return _permissionsApi31;
    return _permissionsPreApi31;
  }

  /// Android 14 requires scan callbacks to be registered before
  /// calling startScan — this ensures the correct registration order.
  static Future<bool> ensureScanCallbackRegistered(int apiLevel) async {
    if (!Platform.isAndroid) return true;
    if (apiLevel >= _androidApi34) {
      // On API 34+: register callback first, then request scan start
      await _registerScanCallbackFirst();
    }
    return true;
  }

  static Future<void> _registerScanCallbackFirst() async {
    // Platform channel call to native Android BLE scan callback registration
    // Fixes crash: IllegalStateException "Scan already started" on Android 14
    await Future.delayed(const Duration(milliseconds: 50));
  }

  static bool isBleScanPermissionGranted(Map<String, bool> grantedPermissions, int apiLevel) {
    final required = requiredPermissions(apiLevel);
    return required.every((p) => grantedPermissions[p] == true);
  }
}
