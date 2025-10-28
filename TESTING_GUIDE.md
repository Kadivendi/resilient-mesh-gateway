# Field Testing Guide

✅ **Completed**: Code pushed successfully, v0.1.0 released.
✅ **Completed**: Installed Flutter and dependencies.
✅ **Completed**: Ran unit tests and widget tests successfully via CI.
✅ **Completed**: Conducted latency benchmarks using `dart benchmark_runner.dart`.

## Running the Tests Locally

```bash
flutter test
```

## Running Benchmarks

```bash
dart benchmark_runner.dart
```

## Physical Device Testing
To test the Nearby Connections mesh network:
1. Deploy the app to at least 2 physical Android/iOS devices.
2. Ensure Bluetooth and WiFi are enabled.
3. Grant Nearby Devices permissions.
4. Verify peer discovery in the Network tab.
