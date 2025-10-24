// End-to-end routing-algorithm tests over a simulated multi-node mesh.
//
// The plain `flutter test test/routing_algorithm_test.dart` suite covers
// the priority queue and battery manager in isolation. This file exercises
// the routing service across a multi-hop topology so we catch regressions in
// TTL handling, dedup propagation, and partition healing that wouldn't show
// up in single-instance unit tests.
//
// Runnable via either of:
//
//   flutter test test/simulation/routing_algorithm_test.dart
//   dart test    test/simulation/routing_algorithm_test.dart
//
// We import from `flutter_test` rather than `test` because that's what the
// rest of the suite uses; `flutter_test` re-exports the `test` package's
// `group` / `test` / `expect` API so plain `dart test` still resolves them
// once `flutter pub get` has run.
import 'package:flutter_test/flutter_test.dart';
import 'package:resilient_mesh_gateway/core/models/message.dart';
import 'package:resilient_mesh_gateway/core/services/mesh_routing_service.dart';

import 'mesh_simulator.dart';

Message _alert(
  String id, {
  required String origin,
  int ttl = 8,
}) =>
    Message(
      id: id,
      senderId: origin,
      recipientId: 'broadcast',
      content: 'payload',
      timestamp: DateTime.now(),
      maxHops: ttl,
    );

List<SimNode> _line(int count) {
  final nodes = List<SimNode>.generate(count, (i) => SimNode('node-$i'));
  for (var i = 0; i < count - 1; i++) {
    nodes[i].connect(nodes[i + 1]);
    nodes[i + 1].connect(nodes[i]);
  }
  return nodes;
}

void main() {
  group('multi-hop propagation', () {
    test('alert traverses a 4-node line within TTL', () async {
      final nodes = _line(4);
      addTearDown(() {
        for (final n in nodes) {
          n.dispose();
        }
      });

      final msg = _alert('hop-4', origin: nodes.first.id, ttl: 8);
      nodes.first.received.add(msg.id);
      nodes.first.router.receive(msg);

      await Future<void>.delayed(const Duration(seconds: 2));
      expect(
        nodes.every((n) => n.received.contains(msg.id)),
        isTrue,
        reason: 'every node along the line should hear the alert',
      );
    });

    test('TTL=1 limits propagation to immediate neighbours', () async {
      final nodes = _line(4);
      addTearDown(() {
        for (final n in nodes) {
          n.dispose();
        }
      });

      final msg = _alert('ttl-1', origin: nodes.first.id, ttl: 1);
      nodes.first.received.add(msg.id);
      nodes.first.router.receive(msg);

      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(nodes[0].received.contains(msg.id), isTrue);
      expect(nodes[1].received.contains(msg.id), isTrue);
      expect(nodes[2].received.contains(msg.id), isFalse,
          reason: 'node 2 must not receive the alert once the hop budget is spent');
    });
  });

  group('dedup', () {
    test('duplicate alerts are suppressed across the mesh', () async {
      final nodes = _line(3);
      addTearDown(() {
        for (final n in nodes) {
          n.dispose();
        }
      });

      final msg = _alert('dup-1', origin: nodes.first.id);
      nodes.first.received.add(msg.id);
      nodes.first.router.receive(msg);
      // Re-inject the same id from the far end of the line.
      nodes.last.deliver(msg);

      await Future<void>.delayed(const Duration(seconds: 1));
      for (final n in nodes) {
        expect(n.router.messagesDeduped, lessThanOrEqualTo(1),
            reason: 'a node should only ever count this message once');
      }
    });
  });

  group('partition healing', () {
    test('a fresh alert traverses a healed partition', () async {
      // Two disconnected 2-node segments. Healing means a new alert
      // originating on the A side reaches the B side via the new edge.
      final a0 = SimNode('a0');
      final a1 = SimNode('a1');
      final b0 = SimNode('b0');
      final b1 = SimNode('b1');
      addTearDown(() {
        for (final n in [a0, a1, b0, b1]) {
          n.dispose();
        }
      });
      a0.connect(a1);
      a1.connect(a0);
      b0.connect(b1);
      b1.connect(b0);

      final isolated = _alert('partition-isolated', origin: a0.id);
      a0.received.add(isolated.id);
      a0.router.receive(isolated);

      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(b0.received.contains(isolated.id), isFalse,
          reason: 'partition isolates B side');

      // Heal partition by linking a1 <-> b0.
      a1.connect(b0);
      b0.connect(a1);

      // Originate a NEW alert after healing — this is what reaches the B side.
      final healed = _alert('partition-healed', origin: a0.id);
      a0.received.add(healed.id);
      a0.router.receive(healed);

      await Future<void>.delayed(const Duration(seconds: 2));
      expect(b0.received.contains(healed.id), isTrue,
          reason: 'after healing, a new alert should reach the B side');
      expect(b1.received.contains(healed.id), isTrue,
          reason: 'b0 must in turn relay onward to b1');
    });
  });

  group('next-hop selection', () {
    test('bestNextHop returns destination when directly known, '
        'falls back to a neighbour that can reach it, '
        'else null for flooding', () {
      final router = MeshRoutingService();
      addTearDown(router.dispose);

      router.onPeerDiscovered('peer-A', const ['peer-X']);

      // Direct neighbour 'peer-A' is preferred for 'peer-A'.
      expect(router.bestNextHop('peer-A'), equals('peer-A'));
      // For a node only reachable via 'peer-A', fall back to 'peer-A'.
      expect(router.bestNextHop('peer-X'), equals('peer-A'));
      // Unknown destinations return null so the caller floods.
      expect(router.bestNextHop('peer-Z'), isNull);
    });
  });
}
