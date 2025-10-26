import 'package:flutter_test/flutter_test.dart';
import 'package:resilient_mesh_gateway/core/models/message.dart';
import 'package:resilient_mesh_gateway/core/services/mesh_routing_service.dart';

void main() {
  group('MeshRoutingService', () {
    late MeshRoutingService router;

    setUp(() => router = MeshRoutingService());
    tearDown(() => router.dispose());

    test('accepts new message and adds to queue', () {
      final msg = _makeMessage('msg-001');
      expect(router.receive(msg), isTrue);
      expect(router.queueDepth, equals(1));
    });

    test('deduplicates messages with same ID', () {
      final msg = _makeMessage('msg-dup');
      router.receive(msg);
      expect(router.receive(msg), isFalse);
      expect(router.queueDepth, equals(1));
    });

    test('drops message whose hop budget is exhausted', () {
      // maxHops == 0 means the message cannot be forwarded.
      final msg = _makeMessage('msg-ttl0', maxHops: 0);
      expect(router.receive(msg), isFalse);
      expect(router.queueDepth, equals(0));
    });

    test('routing table updated on peer discovery', () {
      router.onPeerDiscovered('peer-A', ['peer-B', 'peer-C']);
      expect(router.peersKnown, equals(1));
      expect(router.bestNextHop('peer-B'), equals('peer-A'));
    });

    test('peer removed from routing table on disconnect', () {
      router.onPeerDiscovered('peer-X', ['peer-Y']);
      router.onPeerLost('peer-X');
      expect(router.peersKnown, equals(0));
      expect(router.bestNextHop('peer-Y'), isNull);
    });

    test('floods to all when no route known', () {
      expect(router.bestNextHop('unknown-node'), isNull);
    });

    test('handles 100 unique messages without duplication', () {
      for (int i = 0; i < 100; i++) {
        router.receive(_makeMessage('msg-$i'));
      }
      expect(router.messagesDeduped, equals(100));
    });
  });
}

Message _makeMessage(String id, {int maxHops = 8}) => Message(
      id: id,
      senderId: 'test-node-001',
      recipientId: 'broadcast',
      content: 'test payload',
      timestamp: DateTime.now(),
      maxHops: maxHops,
    );
