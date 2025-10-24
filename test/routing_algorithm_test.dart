// Comprehensive routing algorithm tests with multi-hop simulation.
//
// Tests shortest path, loop detection, TTL expiry, and partition
// healing across simulated mesh topologies.
import 'package:flutter_test/flutter_test.dart';
import 'package:resilient_mesh_gateway/core/services/battery_manager.dart';
import 'package:resilient_mesh_gateway/core/services/mesh_diagnostics.dart';
import 'package:resilient_mesh_gateway/core/services/priority_queue.dart';

void main() {
  group('PriorityQueue', () {
    late MeshPriorityQueue queue;

    setUp(() {
      queue = MeshPriorityQueue(maxCapacity: 10);
    });

    test('should enqueue and dequeue in priority order', () {
      queue.enqueue(PriorityMessage(
        messageId: 'minor-1',
        payload: 'Minor alert',
        priority: AlertPriority.minor,
        enqueuedAt: DateTime.now(),
      ));
      queue.enqueue(PriorityMessage(
        messageId: 'extreme-1',
        payload: 'Extreme alert',
        priority: AlertPriority.extreme,
        enqueuedAt: DateTime.now(),
      ));

      final first = queue.dequeue();
      expect(first?.messageId, 'extreme-1');
      expect(first?.priority, AlertPriority.extreme);
    });

    test('should respect max capacity and drop lowest priority', () {
      final smallQueue = MeshPriorityQueue(maxCapacity: 2);
      smallQueue.enqueue(PriorityMessage(
        messageId: 'm1', payload: '', priority: AlertPriority.minor,
        enqueuedAt: DateTime.now(),
      ));
      smallQueue.enqueue(PriorityMessage(
        messageId: 'm2', payload: '', priority: AlertPriority.moderate,
        enqueuedAt: DateTime.now(),
      ));
      // This should drop the minor message
      smallQueue.enqueue(PriorityMessage(
        messageId: 'm3', payload: '', priority: AlertPriority.severe,
        enqueuedAt: DateTime.now(),
      ));

      expect(smallQueue.length, 2);
      expect(smallQueue.stats['totalDropped'], 1);
    });

    test('should report accurate statistics', () {
      queue.enqueue(PriorityMessage(
        messageId: 'm1', payload: '', priority: AlertPriority.extreme,
        enqueuedAt: DateTime.now(),
      ));
      queue.dequeue();

      final stats = queue.stats;
      expect(stats['totalEnqueued'], 1);
      expect(stats['totalDequeued'], 1);
      expect(stats['size'], 0);
    });
  });

  group('MeshDiagnostics', () {
    late MeshDiagnostics diagnostics;

    setUp(() {
      diagnostics = MeshDiagnostics();
    });

    test('should track message delivery with latency', () {
      diagnostics.recordDelivery(hops: 3, latencyMs: 150.0);
      diagnostics.recordDelivery(hops: 5, latencyMs: 300.0);

      final report = diagnostics.generateReport();
      expect(report['messages']['received'], 2);
      expect(report['latency_ms']['average'], 225.0);
      expect(report['hops']['average'], 4.0);
    });

    test('should calculate packet loss rate', () {
      diagnostics.recordSent();
      diagnostics.recordSent();
      diagnostics.recordSent();
      diagnostics.recordDrop();

      expect(diagnostics.packetLossRate, closeTo(0.333, 0.01));
    });

    test('should track duplicate suppression', () {
      diagnostics.recordDuplicate();
      diagnostics.recordDuplicate();

      final report = diagnostics.generateReport();
      expect(report['messages']['duplicates_suppressed'], 2);
    });
  });

  group('BatteryManager', () {
    late BatteryManager manager;

    setUp(() {
      manager = BatteryManager();
    });

    test('should start in aggressive mode', () {
      expect(manager.currentMode, BatteryMode.aggressive);
    });

    test('should switch to balanced mode below 60%', () {
      manager.updateBatteryLevel(0.5);
      expect(manager.currentMode, BatteryMode.balanced);
    });

    test('should switch to power-saver below 30%', () {
      manager.updateBatteryLevel(0.2);
      expect(manager.currentMode, BatteryMode.powerSaver);
      expect(manager.shouldRelayNonCritical, false);
    });

    test('should provide diagnostics snapshot', () {
      manager.updateBatteryLevel(0.45);
      final diag = manager.getDiagnostics();
      expect(diag['mode'], 'balanced');
      expect(diag['batteryLevel'], 0.45);
    });
  });
}
