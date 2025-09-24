/// Mesh network diagnostics and health reporting.
///
/// Collects real-time statistics about mesh network performance
/// including peer counts, message throughput, hop distribution,
/// and packet loss rates. Generates diagnostic reports for
/// debugging and performance monitoring.
library;

/// Tracks a single mesh performance metric over time.
class MetricTracker {
  final String name;
  final List<double> _values = [];
  final int maxSamples;

  MetricTracker({required this.name, this.maxSamples = 100});

  void record(double value) {
    _values.add(value);
    if (_values.length > maxSamples) {
      _values.removeAt(0);
    }
  }

  double get average {
    if (_values.isEmpty) return 0.0;
    return _values.reduce((a, b) => a + b) / _values.length;
  }

  double get max => _values.isEmpty ? 0.0 : _values.reduce((a, b) => a > b ? a : b);
  double get min => _values.isEmpty ? 0.0 : _values.reduce((a, b) => a < b ? a : b);
  int get sampleCount => _values.length;
}

/// Comprehensive mesh network diagnostics service.
class MeshDiagnostics {
  final MetricTracker _messageLatency = MetricTracker(name: 'message_latency_ms');
  final MetricTracker _hopCount = MetricTracker(name: 'hop_count');
  final MetricTracker _throughput = MetricTracker(name: 'messages_per_second');

  /// Surface for per-second throughput tracking; populated by the broadcast loop.
  MetricTracker get throughputMetric => _throughput;

  int _totalMessagesSent = 0;
  int _totalMessagesReceived = 0;
  int _totalMessagesDropped = 0;
  int _activePeerCount = 0;
  int _totalDuplicatesSuppressed = 0;
  DateTime _startTime = DateTime.now();

  /// Records a successfully delivered message with its hop count and latency.
  void recordDelivery({required int hops, required double latencyMs}) {
    _totalMessagesReceived++;
    _messageLatency.record(latencyMs);
    _hopCount.record(hops.toDouble());
  }

  /// Records a sent message.
  void recordSent() {
    _totalMessagesSent++;
  }

  /// Records a dropped message (TTL expired or routing failure).
  void recordDrop() {
    _totalMessagesDropped++;
  }

  /// Records a duplicate message that was suppressed.
  void recordDuplicate() {
    _totalDuplicatesSuppressed++;
  }

  /// Updates the current active peer count.
  void updatePeerCount(int count) {
    _activePeerCount = count;
  }

  /// Computes the current packet loss rate.
  double get packetLossRate {
    final total = _totalMessagesSent;
    if (total == 0) return 0.0;
    return _totalMessagesDropped / total;
  }

  /// Generates a comprehensive diagnostic report.
  Map<String, dynamic> generateReport() {
    final uptime = DateTime.now().difference(_startTime);
    return {
      'uptime_minutes': uptime.inMinutes,
      'active_peers': _activePeerCount,
      'messages': {
        'sent': _totalMessagesSent,
        'received': _totalMessagesReceived,
        'dropped': _totalMessagesDropped,
        'duplicates_suppressed': _totalDuplicatesSuppressed,
        'packet_loss_rate': packetLossRate,
      },
      'latency_ms': {
        'average': _messageLatency.average,
        'min': _messageLatency.min,
        'max': _messageLatency.max,
        'samples': _messageLatency.sampleCount,
      },
      'hops': {
        'average': _hopCount.average,
        'max': _hopCount.max,
      },
      'generated_at': DateTime.now().toIso8601String(),
    };
  }

  /// Resets all diagnostic counters.
  void reset() {
    _totalMessagesSent = 0;
    _totalMessagesReceived = 0;
    _totalMessagesDropped = 0;
    _totalDuplicatesSuppressed = 0;
    _startTime = DateTime.now();
  }
}
