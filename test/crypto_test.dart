import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:resilient_mesh_gateway/core/services/crypto_service.dart';

void main() {
  group('CryptoService', () {
    late CryptoService crypto;

    setUp(() => crypto = CryptoService());

    test('generateKey returns 32 bytes', () {
      expect(crypto.generateKey().length, equals(32));
    });

    test('generateNonce returns 12 bytes', () {
      expect(crypto.generateNonce().length, equals(12));
    });

    test('encrypt and decrypt round-trip', () {
      final key = crypto.generateKey();
      final plaintext = Uint8List.fromList('Emergency alert: evacuate now'.codeUnits);
      final ciphertext = crypto.encrypt(plaintext, key);
      final decrypted = crypto.decrypt(ciphertext, key);
      expect(decrypted, equals(plaintext));
    });

    test('tampered ciphertext throws StateError', () {
      final key = crypto.generateKey();
      final plaintext = Uint8List.fromList('test'.codeUnits);
      final ciphertext = crypto.encrypt(plaintext, key);
      ciphertext[15] ^= 0xFF; // flip bits in auth tag
      expect(() => crypto.decrypt(ciphertext, key), throwsStateError);
    });

    test('different keys produce different ciphertexts', () {
      final key1 = crypto.generateKey();
      final key2 = crypto.generateKey();
      final plaintext = Uint8List.fromList('alert'.codeUnits);
      expect(crypto.encrypt(plaintext, key1), isNot(equals(crypto.encrypt(plaintext, key2))));
    });

    test('hashMessageId is deterministic', () {
      const id = 'msg-12345';
      expect(crypto.hashMessageId(id), equals(crypto.hashMessageId(id)));
    });

    test('different IDs produce different hashes', () {
      expect(crypto.hashMessageId('id-a'), isNot(equals(crypto.hashMessageId('id-b'))));
    });
  });
}
