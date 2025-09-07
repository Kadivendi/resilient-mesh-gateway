import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;

/// AES-256-GCM payload encryption + Ed25519 signing for mesh messages.
///
/// All mesh payloads are encrypted before transmission and verified on receipt
/// so a man-in-the-middle node cannot tamper with the body or forge an
/// origin identity. The Ed25519 keypair is created on first use of
/// `generateSigningKeyPair()` and is meant to be persisted via Hive by the
/// caller.
class CryptoService {
  static const int _keyLength = 32; // AES-256
  static const int _nonceLength = 12; // GCM standard nonce

  final _rng = Random.secure();
  final Ed25519 _signer = Ed25519();

  // ---------------- AES-256-GCM ----------------

  Uint8List generateKey() => Uint8List.fromList(
        List<int>.generate(_keyLength, (_) => _rng.nextInt(256)),
      );

  Uint8List generateNonce() => Uint8List.fromList(
        List<int>.generate(_nonceLength, (_) => _rng.nextInt(256)),
      );

  /// Encrypt with AES-256-GCM. Output layout: `nonce(12) | ciphertext | tag(16)`.
  Uint8List encrypt(Uint8List plaintext, Uint8List key) {
    final nonce = generateNonce();
    final encKey = encrypt_pkg.Key(key);
    final iv = encrypt_pkg.IV(nonce);
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(encKey, mode: encrypt_pkg.AESMode.gcm),
    );
    final encrypted = encrypter.encryptBytes(plaintext, iv: iv);
    return Uint8List.fromList([...nonce, ...encrypted.bytes]);
  }

  /// Decrypt AES-256-GCM. Throws on auth-tag mismatch.
  Uint8List decrypt(Uint8List payload, Uint8List key) {
    if (payload.length < _nonceLength + 16) {
      throw ArgumentError('Payload too short to be valid ciphertext');
    }
    final nonce = payload.sublist(0, _nonceLength);
    final ciphertextWithTag = payload.sublist(_nonceLength);
    final encKey = encrypt_pkg.Key(key);
    final iv = encrypt_pkg.IV(nonce);
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(encKey, mode: encrypt_pkg.AESMode.gcm),
    );
    try {
      final decrypted = encrypter.decryptBytes(
        encrypt_pkg.Encrypted(ciphertextWithTag),
        iv: iv,
      );
      return Uint8List.fromList(decrypted);
    } catch (_) {
      throw StateError('Authentication tag mismatch — message tampered or corrupted');
    }
  }

  // ---------------- Ed25519 signing ----------------

  /// Generate a fresh Ed25519 keypair. Persist it (Hive) so the public key
  /// can identify this node across reboots.
  ///
  /// The runtime implementation always returns a [SimpleKeyPair], but the
  /// `SignatureAlgorithm.newKeyPair()` return type is `Future<KeyPair>`, so
  /// we cast at the boundary rather than expose a wider type to callers.
  Future<SimpleKeyPair> generateSigningKeyPair() async {
    final kp = await _signer.newKeyPair();
    return kp as SimpleKeyPair;
  }

  /// Sign `data` with `keyPair`'s private key. Output is the raw 64-byte signature.
  Future<Uint8List> sign(Uint8List data, KeyPair keyPair) async {
    final signature = await _signer.sign(data, keyPair: keyPair);
    return Uint8List.fromList(signature.bytes);
  }

  /// Verify a 64-byte Ed25519 signature against the sender's 32-byte public key.
  Future<bool> verify(
    Uint8List data,
    Uint8List signatureBytes,
    Uint8List publicKeyBytes,
  ) async {
    final publicKey = SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519);
    return _signer.verify(
      data,
      signature: Signature(signatureBytes, publicKey: publicKey),
    );
  }

  /// Helper for JSON payloads — caller passes the serialized bytes and gets a
  /// base64-encoded signature back, matching the RAMP envelope format.
  Future<String> signBase64(Uint8List data, KeyPair keyPair) async {
    final sig = await sign(data, keyPair);
    return base64Encode(sig);
  }

  // ---------------- Misc ----------------

  /// FNV-1a 32-bit hash of a message id; used for inexpensive flood-filter keys.
  String hashMessageId(String messageId) {
    final bytes = utf8.encode(messageId);
    var h = 2166136261;
    for (final b in bytes) {
      h ^= b;
      h = (h * 16777619) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}
