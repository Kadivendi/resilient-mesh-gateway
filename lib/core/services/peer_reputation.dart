/// Peer reputation scoring based on relay reliability.
///
/// Tracks message forwarding success rate, acknowledgment reception,
/// and response latency for each peer node. Higher-reputation peers
/// are preferred for routing decisions.
library;

/// Reputation record for a single peer node.
class PeerReputation {
  final String peerId;
  int messagesForwarded;
  int acknowledgementsReceived;
  int failures;
  double totalLatencyMs;
  DateTime lastSeen;
  DateTime firstSeen;

  PeerReputation({
    required this.peerId,
    this.messagesForwarded = 0,
    this.acknowledgementsReceived = 0,
    this.failures = 0,
    this.totalLatencyMs = 0.0,
    DateTime? lastSeen,
    DateTime? firstSeen,
  })  : lastSeen = lastSeen ?? DateTime.now(),
        firstSeen = firstSeen ?? DateTime.now();

  /// Reputation score from 0 to 100.
  double get score {
    final total = messagesForwarded + failures;
    if (total == 0) return 50.0; // neutral for unknown peers

    final successRate = messagesForwarded / total;
    final ackRate = messagesForwarded > 0
        ? acknowledgementsReceived / messagesForwarded
        : 0.0;

    // Weighted score: 60% success rate + 40% ack rate
    final rawScore = (successRate * 60.0 + ackRate * 40.0);

    // Apply freshness decay: peers not seen recently lose reputation
    final hoursSinceLastSeen =
        DateTime.now().difference(lastSeen).inMinutes / 60.0;
    final decayFactor = hoursSinceLastSeen > 1.0
        ? (1.0 / (1.0 + (hoursSinceLastSeen - 1.0) * 0.1))
        : 1.0;

    return (rawScore * decayFactor).clamp(0.0, 100.0);
  }

  /// Average response latency in milliseconds.
  double get averageLatencyMs {
    if (acknowledgementsReceived == 0) return double.infinity;
    return totalLatencyMs / acknowledgementsReceived;
  }
}

/// Service for tracking and querying peer reputation scores.
class PeerReputationService {
  final Map<String, PeerReputation> _peers = {};
  final double _minScoreForRouting;

  PeerReputationService({double minScoreForRouting = 20.0})
      : _minScoreForRouting = minScoreForRouting;

  /// Record a successful message forward to a peer.
  void recordForward(String peerId) {
    final peer = _getOrCreate(peerId);
    peer.messagesForwarded++;
    peer.lastSeen = DateTime.now();
  }

  /// Record an acknowledgment received from a peer.
  void recordAcknowledgment(String peerId, double latencyMs) {
    final peer = _getOrCreate(peerId);
    peer.acknowledgementsReceived++;
    peer.totalLatencyMs += latencyMs;
    peer.lastSeen = DateTime.now();
  }

  /// Record a delivery failure for a peer.
  void recordFailure(String peerId) {
    final peer = _getOrCreate(peerId);
    peer.failures++;
  }

  /// Get the reputation score for a peer.
  double getScore(String peerId) {
    return _peers[peerId]?.score ?? 50.0;
  }

  /// Get peers sorted by reputation score (highest first).
  List<PeerReputation> getRankedPeers() {
    return _peers.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
  }

  /// Get peers that meet the minimum routing threshold.
  List<String> getRoutablePeers() {
    return _peers.entries
        .where((e) => e.value.score >= _minScoreForRouting)
        .map((e) => e.key)
        .toList();
  }

  PeerReputation _getOrCreate(String peerId) {
    return _peers.putIfAbsent(peerId, () => PeerReputation(peerId: peerId));
  }
}
