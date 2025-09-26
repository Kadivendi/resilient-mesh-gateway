import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:logger/logger.dart';

/// LoRa radio transport adapter for extended-range mesh delivery (5–15 km).
///
/// Talks to Semtech SX1276 / SX1278 and EBYTE E22 modules over a serial
/// connection. The framing here is a thin 12-byte header (8-byte messageId,
/// 1-byte fragment index, 1-byte total fragments, 2-byte payload length) so
/// a single message can span multiple LoRa packets (max payload = 255 B).
enum LoRaSpreadingFactor { sf7, sf8, sf9, sf10, sf11, sf12 }
enum LoRaBandwidth { bw125, bw250, bw500 }

class LoRaConfig {
  final int frequencyMhz;
  final LoRaSpreadingFactor sf;
  final LoRaBandwidth bandwidth;
  final int txPowerDbm;
  final int syncWord;

  const LoRaConfig({
    this.frequencyMhz = 915,
    this.sf = LoRaSpreadingFactor.sf9,
    this.bandwidth = LoRaBandwidth.bw125,
    this.txPowerDbm = 17,
    this.syncWord = 0xAB,
  });

  /// Estimated range based on SF and (assumed clear) terrain.
  double get estimatedRangeKm {
    switch (sf) {
      case LoRaSpreadingFactor.sf7:
        return 2.0;
      case LoRaSpreadingFactor.sf9:
        return 6.0;
      case LoRaSpreadingFactor.sf12:
        return 15.0;
      default:
        return 4.0;
    }
  }

  int get maxPayloadBytes => 255;
}

class LoRaPacket {
  final String messageId;
  final int fragmentIndex;
  final int totalFragments;
  final Uint8List payload;
  final int rssi;
  final double snr;

  const LoRaPacket({
    required this.messageId,
    required this.fragmentIndex,
    required this.totalFragments,
    required this.payload,
    this.rssi = -100,
    this.snr = 0.0,
  });

  bool get isComplete => totalFragments == 1 || fragmentIndex == totalFragments - 1;

  Uint8List toBytes() {
    final idBytes = messageId.padRight(8, ' ').codeUnits.take(8).toList(growable: false);
    return Uint8List.fromList([
      ...idBytes,
      fragmentIndex,
      totalFragments,
      (payload.length >> 8) & 0xFF,
      payload.length & 0xFF,
      ...payload,
    ]);
  }
}

class LoRaTransport {
  static final Logger _logger = Logger();

  final LoRaConfig config;
  bool _initialized = false;
  SerialPort? _port;
  StreamSubscription<Uint8List>? _serialSubscription;
  final _receiveController = StreamController<LoRaPacket>.broadcast();
  final _fragmentBuffers = <String, List<LoRaPacket?>>{};

  LoRaTransport({this.config = const LoRaConfig()});

  Stream<LoRaPacket> get receivedPackets => _receiveController.stream;

  Future<bool> initialize(String serialPortName) async {
    try {
      final port = SerialPort(serialPortName);
      if (!port.openReadWrite()) {
        throw Exception('Failed to open serial port: $serialPortName');
      }

      final cfg = SerialPortConfig()
        ..baudRate = 115200
        ..bits = 8
        ..stopBits = 1
        ..parity = SerialPortParity.none
        ..setFlowControl(SerialPortFlowControl.none);
      port.config = cfg;
      cfg.dispose();

      final reader = SerialPortReader(port);
      _serialSubscription = reader.stream.listen(_onSerialData,
          onError: (e) => _logger.w('Serial read error: $e'));

      _port = port;
      _initialized = true;
      _logger.i('LoRa transport initialized on $serialPortName at SF=${config.sf.name}');
      return true;
    } catch (e, st) {
      _logger.e('LoRa init failed: $e\n$st');
      return false;
    }
  }

  void _onSerialData(Uint8List data) {
    if (data.length <= 12) return;
    try {
      final idBytes = String.fromCharCodes(data.sublist(0, 8));
      final fragIdx = data[8];
      final totalFrag = data[9];
      final payloadLen = (data[10] << 8) | data[11];
      final end = (12 + payloadLen).clamp(12, data.length);
      final payload = data.sublist(12, end);

      final packet = LoRaPacket(
        messageId: idBytes.trim(),
        fragmentIndex: fragIdx,
        totalFragments: totalFrag,
        payload: Uint8List.fromList(payload),
      );
      _receiveController.add(packet);
    } catch (e) {
      _logger.w('Bad LoRa frame: $e');
    }
  }

  /// Send data over LoRa, fragmenting if larger than `maxPayloadBytes - 12`.
  ///
  /// Each packet is written to the serial port with a 50ms air-time gap
  /// between fragments to give the radio time to actually emit before the
  /// next write.
  Future<bool> send(String messageId, Uint8List data) async {
    if (!_initialized || _port == null) {
      _logger.w('Cannot send: LoRa transport not initialized');
      return false;
    }
    final fragments = _fragment(messageId, data);
    int written = 0;
    for (final packet in fragments) {
      final bytes = packet.toBytes();
      final n = _port!.write(bytes);
      if (n < bytes.length) {
        _logger.w('Short write on LoRa: wrote $n / ${bytes.length}');
      } else {
        written++;
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
    return written == fragments.length;
  }

  List<LoRaPacket> _fragment(String messageId, Uint8List data) {
    final maxSize = config.maxPayloadBytes - 12;
    final total = (data.length / maxSize).ceil().clamp(1, 255);
    return List.generate(total, (i) {
      final start = i * maxSize;
      final end = (start + maxSize).clamp(0, data.length);
      return LoRaPacket(
        messageId: messageId,
        fragmentIndex: i,
        totalFragments: total,
        payload: Uint8List.fromList(data.sublist(start, end)),
      );
    });
  }

  /// Reassemble fragmented packets. Returns the complete payload once every
  /// fragment has arrived, null otherwise.
  Uint8List? onPacketReceived(LoRaPacket packet) {
    final key = '${packet.messageId}_${packet.totalFragments}';
    _fragmentBuffers.putIfAbsent(key, () => List.filled(packet.totalFragments, null));
    _fragmentBuffers[key]![packet.fragmentIndex] = packet;

    final buf = _fragmentBuffers[key]!;
    if (buf.every((p) => p != null)) {
      _fragmentBuffers.remove(key);
      return Uint8List.fromList(buf.expand((p) => p!.payload).toList());
    }
    return null;
  }

  bool get isReady => _initialized;
  double get rangeKm => config.estimatedRangeKm;

  void dispose() {
    _serialSubscription?.cancel();
    _port?.close();
    _port = null;
    _initialized = false;
    _receiveController.close();
    _fragmentBuffers.clear();
  }
}
