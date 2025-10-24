// Mesh simulator — invoked from the README's quick-start as:
//
//   cd test/simulation
//   dart run mesh_simulator.dart --nodes 5 --ttl 8 --zone US-CA-LA
//
// Builds an in-process mesh of [n] nodes, links them in a ring/random
// topology, originates a CAP-style alert at node 0, and reports how many
// nodes receive it within the TTL budget. This deliberately uses the same
// MeshRoutingService that runs on-device so the propagation behaviour we
// see in tests / CI matches what we'd see in the wild.
//
// Run without arguments for a 5-node sanity check.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:resilient_mesh_gateway/core/models/message.dart';
import 'package:resilient_mesh_gateway/core/services/mesh_routing_service.dart';

/// A single simulated mesh participant.
class SimNode {
  final String id;
  final MeshRoutingService router;
  final Set<String> received = <String>{};
  final List<SimNode> neighbours = [];

  SimNode(this.id) : router = MeshRoutingService() {
    router.thisNodeId = id;
    router.outboundMessages.listen(_relay);
  }

  void connect(SimNode other) {
    if (other == this || neighbours.contains(other)) return;
    neighbours.add(other);
    router.onPeerDiscovered(other.id, other.neighbours.map((n) => n.id).toList());
  }

  void _relay(Message msg) {
    for (final n in neighbours) {
      n.deliver(msg);
    }
  }

  void deliver(Message msg) {
    if (received.contains(msg.id)) return;
    received.add(msg.id);
    router.receive(msg);
  }

  void dispose() => router.dispose();
}

class _Args {
  final int nodes;
  final int ttl;
  final String zone;
  final int seed;
  final Duration timeout;

  const _Args({
    required this.nodes,
    required this.ttl,
    required this.zone,
    required this.seed,
    required this.timeout,
  });

  static _Args parse(List<String> args) {
    int nodes = 5;
    int ttl = 8;
    String zone = 'US-CA-LA';
    int seed = 1;
    Duration timeout = const Duration(seconds: 3);
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      String? next() => (i + 1 < args.length) ? args[++i] : null;
      switch (a) {
        case '--nodes':
          nodes = int.parse(next() ?? '$nodes');
          break;
        case '--ttl':
          ttl = int.parse(next() ?? '$ttl');
          break;
        case '--zone':
          zone = next() ?? zone;
          break;
        case '--seed':
          seed = int.parse(next() ?? '$seed');
          break;
        case '--timeout-ms':
          timeout = Duration(milliseconds: int.parse(next() ?? '${timeout.inMilliseconds}'));
          break;
        case '--help':
        case '-h':
          stdout.writeln(_helpText);
          exit(0);
      }
    }
    if (nodes < 2) {
      stderr.writeln('--nodes must be >= 2');
      exit(2);
    }
    return _Args(nodes: nodes, ttl: ttl, zone: zone, seed: seed, timeout: timeout);
  }
}

const _helpText = '''
Usage: dart run mesh_simulator.dart [options]

Options:
  --nodes <n>        Number of mesh participants (default: 5).
  --ttl <n>          Hop budget for the originated alert (default: 8).
  --zone <id>        Logical zone tag attached to the alert (default: US-CA-LA).
  --seed <n>         RNG seed for topology generation (default: 1).
  --timeout-ms <n>   How long to wait for propagation (default: 3000 ms).
  -h, --help         Show this help.
''';

/// Wire up a topology: ring + a few random shortcuts so we get multi-hop
/// without trivially having everyone-talks-to-everyone.
List<SimNode> _buildTopology(_Args args) {
  final rng = Random(args.seed);
  final nodes = List<SimNode>.generate(args.nodes, (i) => SimNode('node-$i'));
  for (var i = 0; i < nodes.length; i++) {
    nodes[i].connect(nodes[(i + 1) % nodes.length]);
    nodes[(i + 1) % nodes.length].connect(nodes[i]);
  }
  // ~30% random extra edges.
  final extras = (nodes.length * 0.3).ceil();
  for (var k = 0; k < extras; k++) {
    final a = nodes[rng.nextInt(nodes.length)];
    final b = nodes[rng.nextInt(nodes.length)];
    a.connect(b);
    b.connect(a);
  }
  return nodes;
}

// Returns 0 if every node received the alert, 1 otherwise. Made public via
// the [runSimulation] wrapper so tests / external callers can drive the
// simulator without touching the CLI argument-parsing surface.
Future<int> _simulate(_Args args) async {
  final nodes = _buildTopology(args);
  final originator = nodes.first;
  final alert = Message(
    id: 'sim-${DateTime.now().millisecondsSinceEpoch}',
    senderId: originator.id,
    recipientId: 'broadcast',
    content: '{"zone":"${args.zone}","severity":"EXTREME","note":"simulator"}',
    timestamp: DateTime.now(),
    maxHops: args.ttl,
  );

  stdout.writeln(
    'topology: ${nodes.length} nodes, ttl=${args.ttl}, zone=${args.zone}, seed=${args.seed}',
  );
  originator.received.add(alert.id);
  originator.router.receive(alert);

  await Future<void>.delayed(args.timeout);

  final reached = nodes.where((n) => n.received.contains(alert.id)).length;
  final coverage = (reached / nodes.length) * 100.0;
  final maxQueue =
      nodes.map((n) => n.router.queueDepth).fold<int>(0, (a, b) => a > b ? a : b);
  final totalDedups = nodes.fold<int>(0, (a, n) => a + n.router.messagesDeduped);

  stdout.writeln('---');
  stdout.writeln('reached:           $reached/${nodes.length} (${coverage.toStringAsFixed(1)}%)');
  stdout.writeln('max queue depth:   $maxQueue');
  stdout.writeln('total dedup hits:  $totalDedups');

  for (final n in nodes) {
    n.dispose();
  }
  return reached == nodes.length ? 0 : 1;
}

Future<void> main(List<String> args) async {
  final parsed = _Args.parse(args);
  final code = await _simulate(parsed);
  exit(code);
}
