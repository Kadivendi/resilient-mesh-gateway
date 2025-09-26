import 'dart:async';

/// Manages periodic routing table exchange between mesh nodes.
/// Nodes broadcast their known peer list; recipients merge into local table.
class TopologySyncService {
  static const Duration syncInterval = Duration(seconds: 30);
  static const Duration fastSyncInterval = Duration(seconds: 5);

  Timer? _syncTimer;
  bool _fastMode = false;
  final _topologyController = StreamController<TopologySnapshot>.broadcast();
  final Map<String, PeerEntry> _peers = {};

  Stream<TopologySnapshot> get topologyUpdates => _topologyController.stream;

  void start() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(
      _fastMode ? fastSyncInterval : syncInterval,
      (_) => _broadcastTopology(),
    );
  }

  /// Switch to fast sync mode when topology changes are detected.
  void enableFastSync() {
    _fastMode = true;
    start(); // restart with new interval
    Future.delayed(const Duration(minutes: 2), () {
      _fastMode = false;
      start();
    });
  }

  void updatePeer(String peerId, double rssi, String transport) {
    final wasNew = !_peers.containsKey(peerId);
    _peers[peerId] = PeerEntry(
      id: peerId, rssi: rssi,
      transport: transport,
      lastSeen: DateTime.now(),
    );
    if (wasNew) enableFastSync(); // topology changed — sync faster
  }

  void removePeer(String peerId) {
    if (_peers.remove(peerId) != null) enableFastSync();
  }

  void _broadcastTopology() {
    final snapshot = TopologySnapshot(
      peers: Map.unmodifiable(_peers),
      timestamp: DateTime.now(),
    );
    if (!_topologyController.isClosed) {
      _topologyController.add(snapshot);
    }
  }

  int get activePeerCount => _peers.length;

  void dispose() {
    _syncTimer?.cancel();
    _topologyController.close();
  }
}

class PeerEntry {
  final String id;
  final double rssi;
  final String transport; // 'ble', 'wifi_direct', 'lora'
  final DateTime lastSeen;
  const PeerEntry({required this.id, required this.rssi,
      required this.transport, required this.lastSeen});
  bool get isStale => DateTime.now().difference(lastSeen) > const Duration(minutes: 2);
}

class TopologySnapshot {
  final Map<String, PeerEntry> peers;
  final DateTime timestamp;
  const TopologySnapshot({required this.peers, required this.timestamp});
}
