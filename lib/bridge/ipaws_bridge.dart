import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/models/cap_alert.dart';

/// Bridges FEMA IPAWS-authenticated CAP alerts into the local mesh network.
/// Polls the cap-ipaws-bridge REST API and injects verified alerts as RAMP messages.
class IpawsBridge {
  final String endpoint;
  final String apiKey;
  final Duration pollInterval;

  Timer? _pollTimer;
  final _alertController = StreamController<CapAlert>.broadcast();
  final _seenAlertIds = <String>{};
  int _alertsInjected = 0;
  DateTime? _lastSuccessfulPoll;

  IpawsBridge({
    required this.endpoint,
    required this.apiKey,
    this.pollInterval = const Duration(seconds: 30),
  });

  Stream<CapAlert> get incomingAlerts => _alertController.stream;
  int get alertsInjected => _alertsInjected;
  DateTime? get lastPoll => _lastSuccessfulPoll;

  /// Start polling the cap-ipaws-bridge for new CAP alerts.
  Future<void> startListening() async {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) => _poll());
    await _poll(); // immediate first poll
  }

  Future<void> _poll() async {
    try {
      final response = await http.get(
        Uri.parse('$endpoint/api/alerts'),
        headers: {'Authorization': 'Bearer $apiKey'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        for (var item in data) {
          processCapJson(item as Map<String, dynamic>);
        }
        _lastSuccessfulPoll = DateTime.now();
      }
    } catch (e) {
      // Log error but don't crash — mesh keeps running without IPAWS
    }
  }

  /// Process a raw CAP alert JSON payload from the bridge.
  void processCapJson(Map<String, dynamic> json) {
    try {
      final alert = CapAlert.fromJson(json);
      if (_seenAlertIds.contains(alert.id)) return;
      if (!alert.isActive) return;

      _seenAlertIds.add(alert.id);
      _alertsInjected++;
      if (!_alertController.isClosed) {
        _alertController.add(alert);
      }
    } catch (e) {
      // Malformed alert — skip without crashing
    }
  }

  /// Validate that a CAP alert's severity warrants mesh injection.
  bool shouldBroadcastViaMesh(CapAlert alert) {
    return alert.severity == AlertSeverity.extreme ||
        alert.severity == AlertSeverity.severe;
  }

  void stop() => _pollTimer?.cancel();

  void dispose() {
    stop();
    _alertController.close();
  }
}
