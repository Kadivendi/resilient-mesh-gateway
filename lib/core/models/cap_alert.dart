/// CAP 1.2-compatible alert model for mesh network distribution.
/// Implements the Rapid Alert Message Protocol (RAMP) schema.
enum AlertSeverity { extreme, severe, moderate, minor, unknown }
enum AlertUrgency { immediate, expected, future, past, unknown }
enum AlertCertainty { observed, likely, possible, unlikely, unknown }
enum AlertStatus { actual, exercise, system, test, draft }

class CapAlert {
  final String id;
  final String sender;
  final DateTime sent;
  final DateTime expires;
  final AlertStatus status;
  final AlertSeverity severity;
  final AlertUrgency urgency;
  final AlertCertainty certainty;
  final String event;
  final String headline;
  final String description;
  final String areaDesc;
  final List<GeoPoint> polygon;
  final GeoCircle? circle;
  final Map<String, String> parameters;

  const CapAlert({
    required this.id,
    required this.sender,
    required this.sent,
    required this.expires,
    this.status = AlertStatus.actual,
    required this.severity,
    required this.urgency,
    required this.certainty,
    required this.event,
    required this.headline,
    required this.description,
    required this.areaDesc,
    this.polygon = const [],
    this.circle,
    this.parameters = const {},
  });

  bool get isExpired => DateTime.now().isAfter(expires);
  bool get isActive => status == AlertStatus.actual && !isExpired;

  String get zoneId {
    if (circle != null) {
      return 'circ:${circle!.center.lat.toStringAsFixed(3)},'
          '${circle!.center.lon.toStringAsFixed(3)},${circle!.radiusKm}';
    }
    if (polygon.isNotEmpty) {
      final centroid = polygon.fold(
        GeoPoint(lat: 0, lon: 0),
        (prev, p) => GeoPoint(lat: prev.lat + p.lat, lon: prev.lon + p.lon),
      );
      return 'poly:${(centroid.lat / polygon.length).toStringAsFixed(3)},'
          '${(centroid.lon / polygon.length).toStringAsFixed(3)}';
    }
    return 'zone:unknown';
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'sender': sender,
    'sent': sent.toIso8601String(),
    'expires': expires.toIso8601String(),
    'status': status.name, 'severity': severity.name,
    'urgency': urgency.name, 'certainty': certainty.name,
    'event': event, 'headline': headline,
    'description': description, 'areaDesc': areaDesc,
    'polygon': polygon.map((p) => p.toJson()).toList(),
    'parameters': parameters,
  };

  factory CapAlert.fromJson(Map<String, dynamic> json) => CapAlert(
    id: json['id'] as String,
    sender: json['sender'] as String,
    sent: DateTime.parse(json['sent'] as String),
    expires: DateTime.parse(json['expires'] as String),
    status: AlertStatus.values.firstWhere(
      (e) => e.name == json['status'], orElse: () => AlertStatus.actual),
    severity: AlertSeverity.values.firstWhere(
      (e) => e.name == json['severity'], orElse: () => AlertSeverity.unknown),
    urgency: AlertUrgency.values.firstWhere(
      (e) => e.name == json['urgency'], orElse: () => AlertUrgency.unknown),
    certainty: AlertCertainty.values.firstWhere(
      (e) => e.name == json['certainty'], orElse: () => AlertCertainty.unknown),
    event: json['event'] as String,
    headline: json['headline'] as String,
    description: json['description'] as String,
    areaDesc: json['areaDesc'] as String,
    polygon: (json['polygon'] as List<dynamic>? ?? [])
        .map((p) => GeoPoint.fromJson(p as Map<String, dynamic>))
        .toList(),
    parameters: Map<String, String>.from(json['parameters'] as Map? ?? {}),
  );
}

class GeoPoint {
  final double lat;
  final double lon;
  const GeoPoint({required this.lat, required this.lon});
  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon};
  factory GeoPoint.fromJson(Map<String, dynamic> j) =>
      GeoPoint(lat: (j['lat'] as num).toDouble(), lon: (j['lon'] as num).toDouble());
}

class GeoCircle {
  final GeoPoint center;
  final double radiusKm;
  const GeoCircle({required this.center, required this.radiusKm});
}
