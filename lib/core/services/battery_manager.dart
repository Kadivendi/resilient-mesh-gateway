/// Adaptive battery management with scan interval optimization.
///
/// Reduces BLE/WiFi scan frequency when battery is low to extend
/// mesh participation time during extended outages. Three modes:
/// - Aggressive (>60%): Full scan rate for maximum coverage
/// - Balanced (30-60%): Reduced scanning, prioritize relay
/// - Power Saver (<30%): Minimum scanning, critical alerts only
library;

/// Battery operating modes with associated scan parameters.
enum BatteryMode {
  aggressive(scanIntervalMs: 2000, scanDurationMs: 500, relayAll: true),
  balanced(scanIntervalMs: 5000, scanDurationMs: 300, relayAll: true),
  powerSaver(scanIntervalMs: 15000, scanDurationMs: 200, relayAll: false);

  const BatteryMode({
    required this.scanIntervalMs,
    required this.scanDurationMs,
    required this.relayAll,
  });

  final int scanIntervalMs;
  final int scanDurationMs;
  final bool relayAll;
}

/// Manages battery-aware mesh scanning behavior.
class BatteryManager {
  BatteryMode _currentMode = BatteryMode.aggressive;
  double _batteryLevel = 1.0;
  double _drainRatePerHour = 0.0;
  DateTime _lastUpdate = DateTime.now();
  final List<_BatteryReading> _readings = [];

  /// Current battery operating mode.
  BatteryMode get currentMode => _currentMode;

  /// Estimated remaining mesh time in minutes.
  double get estimatedRemainingMinutes {
    if (_drainRatePerHour <= 0) return double.infinity;
    return (_batteryLevel / _drainRatePerHour) * 60.0;
  }

  /// Updates battery level and recalculates mode.
  void updateBatteryLevel(double level) {
    final now = DateTime.now();
    _readings.add(_BatteryReading(level: level, timestamp: now));

    // Keep last 10 readings for drain rate calculation
    if (_readings.length > 10) {
      _readings.removeAt(0);
    }

    _batteryLevel = level;
    _drainRatePerHour = _calculateDrainRate();
    _currentMode = _selectMode(level);
    _lastUpdate = now;
  }

  /// Whether non-critical messages should be relayed in current mode.
  bool get shouldRelayNonCritical => _currentMode.relayAll;

  /// Current scan interval based on battery mode.
  int get scanIntervalMs => _currentMode.scanIntervalMs;

  /// Returns a diagnostic snapshot of battery state.
  Map<String, dynamic> getDiagnostics() {
    return {
      'batteryLevel': _batteryLevel,
      'mode': _currentMode.name,
      'scanIntervalMs': _currentMode.scanIntervalMs,
      'drainRatePerHour': _drainRatePerHour,
      'estimatedRemainingMinutes': estimatedRemainingMinutes,
      'relayNonCritical': shouldRelayNonCritical,
      'lastUpdate': _lastUpdate.toIso8601String(),
    };
  }

  BatteryMode _selectMode(double level) {
    if (level > 0.6) return BatteryMode.aggressive;
    if (level > 0.3) return BatteryMode.balanced;
    return BatteryMode.powerSaver;
  }

  double _calculateDrainRate() {
    if (_readings.length < 2) return 0.0;
    final first = _readings.first;
    final last = _readings.last;
    final hours = last.timestamp.difference(first.timestamp).inMinutes / 60.0;
    if (hours <= 0) return 0.0;
    return (first.level - last.level) / hours;
  }
}

class _BatteryReading {
  final double level;
  final DateTime timestamp;
  const _BatteryReading({required this.level, required this.timestamp});
}
