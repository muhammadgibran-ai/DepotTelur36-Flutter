import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Utilitas hashing kredensial lokal dengan garam acak (salted SHA-256)
/// agar verifikasi login offline aman tanpa menyimpan password plaintext.
class PasswordHasher {
  PasswordHasher._();

  static String hashPassword(String rawPassword, {String? customSalt}) {
    final salt = customSalt ?? _generateSalt();
    if (salt.isEmpty || salt.contains(':')) {
      throw ArgumentError.value(
        customSalt,
        'customSalt',
        'Salt tidak boleh kosong atau mengandung karakter ":".',
      );
    }
    final digest = _computeDigest(salt, rawPassword);
    return '$salt:$digest';
  }

  static bool verify(String rawPassword, String storedHash) {
    if (storedHash.isEmpty || rawPassword.isEmpty) return false;
    final parts = storedHash.split(':');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      return false;
    }
    final expectedDigest = _computeDigest(parts[0], rawPassword);
    return _constantTimeEquals(parts[1], expectedDigest);
  }

  static String _computeDigest(String salt, String rawPassword) {
    // Key stretching ringan berbasis SHA-256 iteratif agar tetap cepat di HP kasir
    // tanpa membebani UI thread saat login offline.
    List<int> bytes = utf8.encode('$salt|$rawPassword');
    for (var i = 0; i < 1000; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return sha256.convert(bytes).toString();
  }

  static String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
