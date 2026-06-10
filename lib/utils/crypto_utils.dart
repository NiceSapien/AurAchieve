import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:pointycastle/export.dart';
import 'package:flutter/foundation.dart';

// In-memory cache to avoid recalculating PBKDF2 multiple times on the UI thread
final Map<String, encrypt.Key> _pbkdf2Cache = {};

class PBKDF2Args {
  final String password;
  final int iterations;
  const PBKDF2Args(this.password, this.iterations);
}

Uint8List _derivePBKDF2KeyIsolate(PBKDF2Args args) {
  final salt = utf8.encode('AurAchieve_E2E_Salt_2026');
  final hmac = HMac(SHA256Digest(), 64);
  final derivator = PBKDF2KeyDerivator(hmac);
  final params = Pbkdf2Parameters(salt, args.iterations, 32);
  derivator.init(params);
  return derivator.process(Uint8List.fromList(utf8.encode(args.password)));
}

/// Derives E2E encryption key using 600,000 iterations (OWASP standard).
encrypt.Key derivePBKDF2Key(String password) {
  if (_pbkdf2Cache.containsKey(password)) {
    return _pbkdf2Cache[password]!;
  }
  final bytes = _derivePBKDF2KeyIsolate(PBKDF2Args(password, 600000));
  final key = encrypt.Key(bytes);
  _pbkdf2Cache[password] = key;
  return key;
}

/// Asynchronously runs key derivation in a background isolate and caches the result.
Future<void> prewarmPBKDF2Key(String password) async {
  if (!_pbkdf2Cache.containsKey(password)) {
    final bytes = await compute(_derivePBKDF2KeyIsolate, PBKDF2Args(password, 600000));
    _pbkdf2Cache[password] = encrypt.Key(bytes);
  }
}

encrypt.Key getLegacyKey(String password) {
  return encrypt.Key.fromUtf8(password.padRight(32).substring(0, 32));
}
