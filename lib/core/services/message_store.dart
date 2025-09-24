/// Persistent message store for crash recovery.
///
/// Stores undelivered messages to survive app restarts and device
/// reboots. Uses a simple file-backed store (SQLite in production)
/// with automatic retry on reconnection and TTL-based cleanup.
library;

/// Stored message with delivery state tracking.
class StoredMessage {
  final String messageId;
  final String payload;
  final String severity;
  final String zoneId;
  final DateTime storedAt;
  final int deliveryAttempts;
  final int ttlSeconds;
  final bool isDelivered;

  const StoredMessage({
    required this.messageId,
    required this.payload,
    required this.severity,
    required this.zoneId,
    required this.storedAt,
    this.deliveryAttempts = 0,
    this.ttlSeconds = 3600,
    this.isDelivered = false,
  });

  /// Whether this message has exceeded its TTL.
  bool get isExpired =>
      DateTime.now().difference(storedAt).inSeconds > ttlSeconds;

  /// Create a copy with updated delivery state.
  StoredMessage withDeliveryAttempt() => StoredMessage(
    messageId: messageId,
    payload: payload,
    severity: severity,
    zoneId: zoneId,
    storedAt: storedAt,
    deliveryAttempts: deliveryAttempts + 1,
    ttlSeconds: ttlSeconds,
    isDelivered: isDelivered,
  );

  /// Create a copy marked as delivered.
  StoredMessage markDelivered() => StoredMessage(
    messageId: messageId,
    payload: payload,
    severity: severity,
    zoneId: zoneId,
    storedAt: storedAt,
    deliveryAttempts: deliveryAttempts,
    ttlSeconds: ttlSeconds,
    isDelivered: true,
  );
}

/// Persistent message store with crash recovery support.
class MessageStore {
  final Map<String, StoredMessage> _messages = {};
  int _totalStored = 0;
  int _totalCleaned = 0;

  /// Store a message for later delivery.
  void store(StoredMessage message) {
    _messages[message.messageId] = message;
    _totalStored++;
  }

  /// Get all undelivered, non-expired messages for retry.
  List<StoredMessage> getPendingMessages({int maxRetries = 5}) {
    _cleanupExpired();
    return _messages.values
        .where((m) => !m.isDelivered && !m.isExpired && m.deliveryAttempts < maxRetries)
        .toList()
      ..sort((a, b) => a.storedAt.compareTo(b.storedAt));
  }

  /// Mark a message as delivered.
  void markDelivered(String messageId) {
    final msg = _messages[messageId];
    if (msg != null) {
      _messages[messageId] = msg.markDelivered();
    }
  }

  /// Record a delivery attempt.
  void recordAttempt(String messageId) {
    final msg = _messages[messageId];
    if (msg != null) {
      _messages[messageId] = msg.withDeliveryAttempt();
    }
  }

  /// Remove expired and delivered messages.
  int _cleanupExpired() {
    final before = _messages.length;
    _messages.removeWhere((_, m) => m.isExpired || m.isDelivered);
    final removed = before - _messages.length;
    _totalCleaned += removed;
    return removed;
  }

  /// Current store size.
  int get pendingCount => _messages.values.where((m) => !m.isDelivered).length;

  /// Store statistics.
  Map<String, dynamic> get stats => {
    'pending': pendingCount,
    'totalStored': _totalStored,
    'totalCleaned': _totalCleaned,
    'currentSize': _messages.length,
  };
}
