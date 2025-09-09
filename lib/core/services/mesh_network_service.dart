import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:nearby_connections/nearby_connections.dart';

import '../models/message.dart';
import '../models/peer.dart';
import 'mesh_routing_service.dart';

/// Coordinates the BLE / WiFi-Direct mesh.
///
/// Discovery and advertising are delegated to the `nearby_connections` plugin;
/// payload framing is the responsibility of this class:
/// outgoing messages are JSON-encoded with `Message.toJson()` and pushed with
/// `Nearby().sendBytesPayload`; incoming bytes are decoded back into `Message`
/// instances and forwarded to the routing service for flood / dedup handling.
class MeshNetworkService extends ChangeNotifier {
  final Logger _logger = Logger();

  final Map<String, Peer> _peers = {};
  final Map<String, DateTime> _lastPeerUpdate = {};
  bool _isScanning = false;
  bool _isAdvertising = false;
  String? _deviceId;
  String? _deviceName;

  final MeshRoutingService _router = MeshRoutingService();
  StreamSubscription<Message>? _routerSubscription;

  Function(Message)? onMessageReceived;
  Function(Peer)? onPeerDiscovered;
  Function(String)? onPeerDisconnected;

  List<Peer> get peers => _peers.values.toList();
  List<Peer> get onlinePeers =>
      _peers.values.where((p) => p.status == PeerStatus.online).toList();
  bool get isScanning => _isScanning;
  bool get isAdvertising => _isAdvertising;
  String? get deviceId => _deviceId;
  String? get deviceName => _deviceName;

  Future<void> initialize(String deviceId, String deviceName) async {
    _deviceId = deviceId;
    _deviceName = deviceName;
    _logger.i('Mesh network initialized: $deviceName ($deviceId)');

    _routerSubscription?.cancel();
    _routerSubscription = _router.outboundMessages.listen(_broadcastMessage);
  }

  Future<void> startScanning() async {
    if (_isScanning) return;
    _logger.i('Starting peer discovery...');
    _isScanning = true;
    notifyListeners();

    try {
      await Nearby().startDiscovery(
        _deviceName ?? 'Unknown',
        Strategy.P2P_CLUSTER,
        onEndpointFound: (id, name, serviceId) {
          _updatePeer(Peer(
            id: id,
            name: name,
            deviceType: 'Nearby',
            lastSeen: DateTime.now(),
            signalStrength: -50,
          ));
        },
        onEndpointLost: (id) {
          if (id != null) disconnectFromPeer(id);
        },
      );
    } catch (e) {
      _logger.e('Discovery failed: $e');
      _isScanning = false;
    }
  }

  Future<void> stopScanning() async {
    if (!_isScanning) return;
    _logger.i('Stopping peer discovery...');
    await Nearby().stopDiscovery();
    _isScanning = false;
    notifyListeners();
  }

  Future<void> startAdvertising() async {
    if (_isAdvertising) return;
    _logger.i('Starting advertising: $_deviceName');
    _isAdvertising = true;
    notifyListeners();

    try {
      await Nearby().startAdvertising(
        _deviceName ?? 'Unknown',
        Strategy.P2P_CLUSTER,
        onConnectionInitiated: (id, info) {
          Nearby().acceptConnection(
            id,
            onPayLoadRecieved: _onPayloadReceived,
            onPayloadTransferUpdate: (endpointId, payloadTransferUpdate) {},
          );
        },
        onConnectionResult: (id, status) {
          if (status == Status.CONNECTED) {
            final peer = _peers[id];
            if (peer != null) {
              _updatePeer(peer.copyWith(status: PeerStatus.online));
            }
          }
        },
        onDisconnected: (id) {
          disconnectFromPeer(id);
        },
      );
    } catch (e) {
      _logger.e('Advertising failed: $e');
      _isAdvertising = false;
    }
  }

  Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;
    _logger.i('Stopping advertising');
    await Nearby().stopAdvertising();
    _isAdvertising = false;
    notifyListeners();
  }

  Future<bool> connectToPeer(String peerId) async {
    _logger.i('Connecting to peer: $peerId');
    final peer = _peers[peerId];
    if (peer == null) {
      _logger.w('Peer not found: $peerId');
      return false;
    }

    _updatePeer(peer.copyWith(status: PeerStatus.connecting));

    try {
      await Nearby().requestConnection(
        _deviceName ?? 'Unknown',
        peerId,
        onConnectionInitiated: (id, info) {
          Nearby().acceptConnection(
            id,
            onPayLoadRecieved: _onPayloadReceived,
            onPayloadTransferUpdate: (e, p) {},
          );
        },
        onConnectionResult: (id, status) {
          if (status == Status.CONNECTED) {
            _updatePeer(peer.copyWith(status: PeerStatus.online));
          } else {
            _updatePeer(peer.copyWith(status: PeerStatus.offline));
          }
        },
        onDisconnected: (id) {
          disconnectFromPeer(id);
        },
      );
      return true;
    } catch (e) {
      _logger.e('Failed connecting to peer: $e');
      _updatePeer(peer.copyWith(status: PeerStatus.offline));
      return false;
    }
  }

  Future<void> disconnectFromPeer(String peerId) async {
    _logger.i('Disconnecting from peer: $peerId');
    final peer = _peers[peerId];
    if (peer != null) {
      _updatePeer(peer.copyWith(status: PeerStatus.offline));
    }
    onPeerDisconnected?.call(peerId);
    _router.onPeerLost(peerId);
    try {
      await Nearby().disconnectFromEndpoint(peerId);
    } catch (e) {
      _logger.d('disconnectFromEndpoint($peerId) failed: $e');
    }
  }

  /// Submit a message into the mesh — the router handles flood + dedup.
  Future<bool> sendMessage(Message message) async {
    _logger.i('Sending message: ${message.id} to ${message.recipientId}');
    _router.receive(message);
    return true;
  }

  /// Push an already-encoded payload to a specific peer.
  Future<bool> _sendDirectMessage(Message message, Peer peer) async {
    try {
      final json = jsonEncode(message.toJson());
      final payload = Uint8List.fromList(utf8.encode(json));
      _logger.d('Sending ${payload.length}B to ${peer.name}: ${message.id}');
      await Nearby().sendBytesPayload(peer.id, payload);
      return true;
    } catch (e) {
      _logger.e('Failed to send message to ${peer.id}: $e');
      return false;
    }
  }

  /// Broadcast a message to all currently-online peers (epidemic routing).
  Future<bool> _broadcastMessage(Message message) async {
    final targets = onlinePeers;
    if (targets.isEmpty) return false;

    int ok = 0;
    for (final peer in targets) {
      if (await _sendDirectMessage(message, peer)) ok++;
    }
    return ok > 0;
  }

  /// Decode an inbound payload and hand it off to the routing layer.
  void _onPayloadReceived(String endpointId, Payload payload) {
    try {
      if (payload.type != PayloadType.BYTES || payload.bytes == null) {
        _logger.d('Skipping non-bytes payload from $endpointId');
        return;
      }
      final text = utf8.decode(payload.bytes!);
      final json = jsonDecode(text) as Map<String, dynamic>;
      final message = Message.fromJson(json);
      _handleReceivedMessage(message);
    } catch (e, st) {
      _logger.w('Failed to decode payload from $endpointId: $e\n$st');
    }
  }

  void _handleReceivedMessage(Message message) {
    _logger.i('Received message: ${message.id}');
    if (message.recipientId == _deviceId) {
      _logger.i('Message is for us!');
      onMessageReceived?.call(message);
      return;
    }
    if (message.canForward) {
      _router.receive(message);
    }
  }

  void _updatePeer(Peer peer) {
    final existing = _peers[peer.id];
    if (existing == null) {
      _peers[peer.id] = peer;
      onPeerDiscovered?.call(peer);
      _router.onPeerDiscovered(peer.id, []);
    } else {
      _peers[peer.id] = peer;
    }
    _lastPeerUpdate[peer.id] = DateTime.now();
    notifyListeners();
  }

  @override
  void dispose() {
    stopScanning();
    stopAdvertising();
    _routerSubscription?.cancel();
    _peers.clear();
    _lastPeerUpdate.clear();
    _router.dispose();
    super.dispose();
  }
}
