import 'dart:async';
import 'dart:collection';
import '../models/message.dart';
import '../protocol/bloom_filter.dart';

/// Implements the Rapid Alert Message Protocol (RAMP) store-and-forward router.
/// Uses epidemic (flooding) routing with duplicate suppression via a bloom filter.
class MeshRoutingService {
  static const int defaultTtl = 12;
  static const int maxQueueSize = 500;
  static const Duration forwardDelay = Duration(milliseconds: 150);

  final _seen = BloomFilter(10000, 5);           // dedup: message IDs seen via bloom filter
  final _queue = Queue<Message>();               // store-and-forward queue
  final _routingTable = <String, List<String>>{}; // nodeId → reachable via
  final _forwardController = StreamController<Message>.broadcast();

  Stream<Message> get outboundMessages => _forwardController.stream;

  /// Process an incoming message. Returns true if it's new and was enqueued.
  ///
  /// "TTL" in this router maps onto the `Message` model's `hopCount`/`maxHops`
  /// pair: a message that has already reached `maxHops` is considered TTL-
  /// exhausted and is dropped.
  bool receive(Message message) {
    if (_seen.contains(message.id)) return false;  // duplicate — drop
    if (!message.canForward) return false;          // hop budget exhausted — drop
    _seen.add(message.id);

    if (_queue.length >= maxQueueSize) _queue.removeFirst(); // evict oldest
    _queue.addLast(message);
    _scheduleForward(message);
    return true;
  }

  void _scheduleForward(Message message) {
    Future.delayed(forwardDelay, () {
      // The forwarded copy carries an incremented hop count; the receive()
      // check above uses canForward (hopCount < maxHops) to enforce the limit.
      final hopped = message.incrementHop(_thisNodeId);
      if (!_forwardController.isClosed) {
        _forwardController.add(hopped);
      }
    });
  }

  /// Identifier used to extend `routePath` when forwarding. Default constant so
  /// existing call sites that don't supply one keep working; set this from the
  /// mesh service if a stable per-node id is available.
  String _thisNodeId = 'this-node';
  set thisNodeId(String id) => _thisNodeId = id;

  /// Update routing table when a new peer is discovered.
  void onPeerDiscovered(String peerId, List<String> reachableNodes) {
    _routingTable[peerId] = reachableNodes;
  }

  /// Remove a peer from the routing table on disconnect.
  void onPeerLost(String peerId) {
    _routingTable.remove(peerId);
  }

  /// Return best next-hop for a destination node (Bellman-Ford minimum hops).
  String? bestNextHop(String destination) {
    if (_routingTable.containsKey(destination)) return destination;
    for (final entry in _routingTable.entries) {
      if (entry.value.contains(destination)) return entry.key;
    }
    return null; // flood to all peers if no route known
  }

  int get queueDepth => _queue.length;
  int get peersKnown => _routingTable.length;
  int get messagesDeduped => _seen.length;

  void dispose() {
    _forwardController.close();
    _queue.clear();
  }
}
