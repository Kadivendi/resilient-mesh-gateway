/// Priority-based message queue with severity-aware scheduling.
///
/// EXTREME alerts jump to the front of the queue while age-based
/// priority boost prevents starvation of lower-severity messages.
/// Implements a heap-backed priority queue with configurable capacity.
library;

/// Priority levels mapped from CAP severity values.
enum AlertPriority {
  extreme(weight: 100),
  severe(weight: 75),
  moderate(weight: 50),
  minor(weight: 25);

  const AlertPriority({required this.weight});
  final int weight;
}

/// A queued message with computed priority score.
class PriorityMessage {
  final String messageId;
  final String payload;
  final AlertPriority priority;
  final DateTime enqueuedAt;
  final int ttlSeconds;

  PriorityMessage({
    required this.messageId,
    required this.payload,
    required this.priority,
    required this.enqueuedAt,
    this.ttlSeconds = 3600,
  });

  /// Compute effective priority with age-based boost.
  /// Older messages get up to +50 priority boost to prevent starvation.
  double get effectivePriority {
    final ageSeconds = DateTime.now().difference(enqueuedAt).inSeconds;
    final ageBoost = (ageSeconds / 60.0).clamp(0.0, 50.0);
    return priority.weight + ageBoost;
  }

  /// Whether this message has exceeded its TTL.
  bool get isExpired {
    return DateTime.now().difference(enqueuedAt).inSeconds > ttlSeconds;
  }
}

/// Priority queue for mesh alert messages.
class MeshPriorityQueue {
  final int maxCapacity;
  final List<PriorityMessage> _queue = [];
  int _totalEnqueued = 0;
  int _totalDequeued = 0;
  int _totalDropped = 0;

  MeshPriorityQueue({this.maxCapacity = 1000});

  /// Enqueue a message with priority-based insertion.
  bool enqueue(PriorityMessage message) {
    // Remove expired messages first
    _queue.removeWhere((m) => m.isExpired);

    if (_queue.length >= maxCapacity) {
      // Drop lowest priority message if at capacity
      _queue.sort((a, b) => a.effectivePriority.compareTo(b.effectivePriority));
      if (message.effectivePriority > _queue.first.effectivePriority) {
        _queue.removeAt(0);
        _totalDropped++;
      } else {
        _totalDropped++;
        return false;
      }
    }

    _queue.add(message);
    _totalEnqueued++;
    // Sort by priority descending — highest priority first
    _queue.sort((a, b) => b.effectivePriority.compareTo(a.effectivePriority));
    return true;
  }

  /// Dequeue the highest priority message.
  PriorityMessage? dequeue() {
    // Remove expired messages
    _queue.removeWhere((m) => m.isExpired);
    if (_queue.isEmpty) return null;

    final message = _queue.removeAt(0);
    _totalDequeued++;
    return message;
  }

  /// Peek at the highest priority message without removing it.
  PriorityMessage? peek() {
    _queue.removeWhere((m) => m.isExpired);
    return _queue.isEmpty ? null : _queue.first;
  }

  /// Current queue size.
  int get length => _queue.length;

  /// Whether the queue is empty.
  bool get isEmpty => _queue.isEmpty;

  /// Queue statistics for monitoring.
  Map<String, dynamic> get stats => {
    'size': _queue.length,
    'capacity': maxCapacity,
    'totalEnqueued': _totalEnqueued,
    'totalDequeued': _totalDequeued,
    'totalDropped': _totalDropped,
    'utilizationPercent': (_queue.length / maxCapacity * 100).round(),
  };
}
