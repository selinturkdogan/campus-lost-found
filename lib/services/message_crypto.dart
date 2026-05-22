import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;

/// At-rest encryption for chat messages.
///
/// Every chat message stored in Firestore is encrypted with AES-256-CBC.
/// A fresh 16-byte IV is generated for each message and prepended to the
/// ciphertext, then the whole thing is base64-encoded. Wire format:
///
///   base64( iv (16 bytes) || ciphertext (n bytes) )
///
/// With a constant in-app key this protects against:
///   * Firestore data leaks / inspector views
///   * Anyone reading the database directly (admin, exports)
///   * Cloud Functions reading message contents
///
/// It does NOT protect against an attacker who decompiles the APK and
/// extracts the key — for that, you'd need full end-to-end encryption
/// with per-user keys. For a campus Lost & Found project this level of
/// protection is appropriate and easy to reason about.
class MessageCrypto {
  // 32-byte (256-bit) key. NOTE: in a real app this would come from
  // build-time configuration (Firebase Remote Config, env vars, etc.)
  // and would never be checked into git. For this academic project we
  // accept the trade-off of having it in source.
  static final _key = enc.Key.fromUtf8(
    'campus-lf-chat-key-v1-2026-final',
  );

  static final _encrypter = enc.Encrypter(
    enc.AES(_key, mode: enc.AESMode.cbc),
  );

  static final _rand = Random.secure();

  /// Encrypt a UTF-8 plaintext string. Returns the wire format described
  /// in the class docs (base64 of iv||ciphertext).
  static String encryptText(String plaintext) {
    final ivBytes = Uint8List.fromList(
      List<int>.generate(16, (_) => _rand.nextInt(256)),
    );
    final iv = enc.IV(ivBytes);
    final encrypted = _encrypter.encrypt(plaintext, iv: iv);
    final combined = Uint8List(ivBytes.length + encrypted.bytes.length)
      ..setRange(0, ivBytes.length, ivBytes)
      ..setRange(ivBytes.length, ivBytes.length + encrypted.bytes.length,
          encrypted.bytes);
    return base64Encode(combined);
  }

  /// Decrypt a string produced by [encryptText]. Returns the original
  /// plaintext. Throws if the input is malformed or the key doesn't
  /// match (e.g. older app version with a different key).
  static String decryptText(String wire) {
    final combined = base64Decode(wire);
    if (combined.length < 17) {
      throw const FormatException('Ciphertext too short');
    }
    final iv = enc.IV(Uint8List.fromList(combined.sublist(0, 16)));
    final cipherBytes = Uint8List.fromList(combined.sublist(16));
    final encrypted = enc.Encrypted(cipherBytes);
    return _encrypter.decrypt(encrypted, iv: iv);
  }

  /// Decrypt safely: returns the plaintext if successful, or the raw
  /// input string if decryption fails. Useful when displaying messages
  /// that might be in the old plaintext format from before encryption
  /// was rolled out.
  static String decryptOrPassthrough(String input) {
    if (input.isEmpty) return input;
    try {
      return decryptText(input);
    } catch (_) {
      return input;
    }
  }

  /// Quickly check if a string looks like a valid base64-encoded
  /// ciphertext. Used to detect legacy plaintext messages.
  static bool looksEncrypted(String input) {
    if (input.length < 24) return false;
    // Base64 strings consist of A-Z, a-z, 0-9, +, /, =
    final base64Regex = RegExp(r'^[A-Za-z0-9+/=]+$');
    return base64Regex.hasMatch(input);
  }

}
