import 'dart:typed_data';

/// Defines the RAMP protocol version and provides backward compatibility.
///
/// As the mesh gateway evolves, devices running different firmware versions
/// must interoperate during disaster events. This module handles version
/// negotiation during the BLE/WiFi Direct handshake and provides message
/// format translation between protocol generations.

/// Semantic version for the RAMP protocol wire format.
class ProtocolVersion implements Comparable<ProtocolVersion> {
  final int major;
  final int minor;
  final int patch;

  const ProtocolVersion({
    required this.major,
    required this.minor,
    required this.patch,
  });

  /// Current protocol version shipped with this build.
  static const ProtocolVersion current = ProtocolVersion(
    major: 2,
    minor: 1,
    patch: 0,
  );

  /// Minimum version we can interoperate with via compatibility shims.
  static const ProtocolVersion minimumSupported = ProtocolVersion(
    major: 1,
    minor: 0,
    patch: 0,
  );

  /// Parse a version string like "2.1.0" into a [ProtocolVersion].
  factory ProtocolVersion.parse(String versionString) {
    final parts = versionString.split('.');
    if (parts.length != 3) {
      throw FormatException(
        'Invalid version format: "$versionString". Expected "major.minor.patch".',
      );
    }
    return ProtocolVersion(
      major: int.parse(parts[0]),
      minor: int.parse(parts[1]),
      patch: int.parse(parts[2]),
    );
  }

  /// Encode version into a 3-byte header for wire transmission.
  Uint8List toBytes() => Uint8List.fromList([major, minor, patch]);

  /// Decode a 3-byte version header from a wire frame.
  factory ProtocolVersion.fromBytes(Uint8List bytes) {
    if (bytes.length < 3) {
      throw ArgumentError('Version header requires at least 3 bytes.');
    }
    return ProtocolVersion(major: bytes[0], minor: bytes[1], patch: bytes[2]);
  }

  /// Whether this version is compatible with [other] for message exchange.
  ///
  /// Compatibility rules:
  /// - Same major version: fully compatible (minor/patch differences handled).
  /// - Major version difference of 1: compatible with degraded features.
  /// - Major version difference > 1: incompatible.
  bool isCompatibleWith(ProtocolVersion other) {
    return (major - other.major).abs() <= 1;
  }

  /// Whether this version is newer than [other].
  bool isNewerThan(ProtocolVersion other) => compareTo(other) > 0;

  @override
  int compareTo(ProtocolVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProtocolVersion &&
          major == other.major &&
          minor == other.minor &&
          patch == other.patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// Result of protocol version negotiation between two peers.
enum NegotiationResult {
  /// Both peers at same version — use full feature set.
  fullCompatibility,

  /// Peers at different but compatible versions — use common feature set.
  degradedCompatibility,

  /// Peers at incompatible versions — cannot exchange messages.
  incompatible,
}

/// Handles RAMP protocol version negotiation during the peer handshake.
///
/// When two mesh nodes connect (BLE GATT exchange or WiFi Direct socket),
/// they exchange version headers before any alert data. This negotiator
/// determines the highest common feature set and configures the message
/// serializer accordingly.
class ProtocolNegotiator {
  final ProtocolVersion _localVersion;

  ProtocolNegotiator({ProtocolVersion? localVersion})
      : _localVersion = localVersion ?? ProtocolVersion.current;

  /// The local protocol version advertised during handshake.
  ProtocolVersion get localVersion => _localVersion;

  /// Negotiate with a remote peer's advertised version.
  ///
  /// Returns the negotiation result and the effective version to use for
  /// message serialization on this link.
  ({NegotiationResult result, ProtocolVersion effectiveVersion}) negotiate(
    ProtocolVersion remoteVersion,
  ) {
    if (_localVersion == remoteVersion) {
      return (
        result: NegotiationResult.fullCompatibility,
        effectiveVersion: _localVersion,
      );
    }

    if (!_localVersion.isCompatibleWith(remoteVersion)) {
      return (
        result: NegotiationResult.incompatible,
        effectiveVersion: ProtocolVersion.minimumSupported,
      );
    }

    // Use the lower version to ensure both sides can decode messages.
    final effectiveVersion = _localVersion.isNewerThan(remoteVersion)
        ? remoteVersion
        : _localVersion;

    return (
      result: NegotiationResult.degradedCompatibility,
      effectiveVersion: effectiveVersion,
    );
  }

  /// Build the version handshake frame to send during initial connection.
  ///
  /// Frame format: [0xRA, 0xMP, major, minor, patch, features_bitmask]
  /// The magic bytes 0xRA 0xMP identify this as a RAMP handshake.
  Uint8List buildHandshakeFrame() {
    final features = _computeFeatureBitmask();
    return Uint8List.fromList([
      0xBA, // RAMP magic byte 1
      0x3D, // RAMP magic byte 2
      _localVersion.major,
      _localVersion.minor,
      _localVersion.patch,
      features,
    ]);
  }

  /// Parse a received handshake frame and extract the remote version.
  ProtocolVersion? parseHandshakeFrame(Uint8List frame) {
    if (frame.length < 6) return null;
    if (frame[0] != 0xBA || frame[1] != 0x3D) return null; // bad magic

    return ProtocolVersion(
      major: frame[2],
      minor: frame[3],
      patch: frame[4],
    );
  }

  /// Compute feature bitmask for the local version.
  ///
  /// Bit 0: encryption support
  /// Bit 1: compression support
  /// Bit 2: priority routing support
  /// Bit 3: geofence filtering support
  int _computeFeatureBitmask() {
    int mask = 0;
    if (_localVersion.major >= 1) mask |= 0x01; // encryption since v1
    if (_localVersion.major >= 1 && _localVersion.minor >= 2) {
      mask |= 0x02; // compression since v1.2
    }
    if (_localVersion.major >= 2) mask |= 0x04; // priority routing since v2
    if (_localVersion.major >= 2 && _localVersion.minor >= 1) {
      mask |= 0x08; // geofence since v2.1
    }
    return mask;
  }
}
