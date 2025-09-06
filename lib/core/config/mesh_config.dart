/// Central configuration for RAMP mesh network parameters.
class MeshConfig {
  final int defaultMessageTtl;
  final int bleScanDurationMs;
  final int minAcceptableRssiDbm;
  final int maxQueueSize;
  final int loraSyncWord;
  final int topologySyncIntervalSeconds;
  final int fastSyncIntervalSeconds;

  const MeshConfig({
    this.defaultMessageTtl = 12,
    this.bleScanDurationMs = 4000,
    this.minAcceptableRssiDbm = -85,
    this.maxQueueSize = 500,
    this.loraSyncWord = 0xAB,
    this.topologySyncIntervalSeconds = 30,
    this.fastSyncIntervalSeconds = 5,
  });

  /// High-density urban scenario — more nodes, shorter range per hop.
  static const MeshConfig urban = MeshConfig(
    defaultMessageTtl: 8,
    bleScanDurationMs: 2000,
    minAcceptableRssiDbm: -75,
  );

  /// Sparse rural/wildfire scenario — fewer nodes, longer LoRa range.
  static const MeshConfig rural = MeshConfig(
    defaultMessageTtl: 16,
    bleScanDurationMs: 6000,
    minAcceptableRssiDbm: -90,
  );

  void validate() {
    assert(defaultMessageTtl > 0 && defaultMessageTtl <= 32, 'TTL must be 1-32');
    assert(bleScanDurationMs >= 1000, 'BLE scan must be >= 1000ms');
    assert(minAcceptableRssiDbm < 0, 'RSSI threshold must be negative dBm');
    assert(maxQueueSize > 0, 'Queue size must be positive');
  }
}
