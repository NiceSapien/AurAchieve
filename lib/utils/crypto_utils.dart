import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
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

SecureRandom _getSecureRandom() {
  final secureRandom = FortunaRandom();
  final random = Random.secure();
  final seeds = List<int>.generate(32, (_) => random.nextInt(256));
  secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
  return secureRandom;
}

AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> generateRSAKeyPair() {
  final keyGen = RSAKeyGenerator();
  keyGen.init(ParametersWithRandom(
    RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
    _getSecureRandom(),
  ));
  final pair = keyGen.generateKeyPair();
  return AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>(
    pair.publicKey as RSAPublicKey,
    pair.privateKey as RSAPrivateKey,
  );
}

String encodePublicKey(RSAPublicKey key) {
  return jsonEncode({
    'modulus': key.modulus.toString(),
    'exponent': key.publicExponent.toString(),
  });
}

RSAPublicKey decodePublicKey(String jsonStr) {
  final data = jsonDecode(jsonStr);
  return RSAPublicKey(
    BigInt.parse(data['modulus']),
    BigInt.parse(data['exponent']),
  );
}

String encodePrivateKey(RSAPrivateKey key) {
  return jsonEncode({
    'modulus': key.modulus.toString(),
    'privateExponent': key.privateExponent.toString(),
    'p': key.p?.toString(),
    'q': key.q?.toString(),
  });
}

RSAPrivateKey decodePrivateKey(String jsonStr) {
  final data = jsonDecode(jsonStr);
  return RSAPrivateKey(
    BigInt.parse(data['modulus']),
    BigInt.parse(data['privateExponent']),
    data['p'] != null ? BigInt.parse(data['p']) : null,
    data['q'] != null ? BigInt.parse(data['q']) : null,
  );
}

String encryptLaneKey(String laneKey, RSAPublicKey publicKey) {
  final encrypter = encrypt.Encrypter(encrypt.RSA(publicKey: publicKey));
  return encrypter.encrypt(laneKey).base64;
}

String decryptLaneKey(String encryptedBase64, RSAPrivateKey privateKey) {
  final encrypter = encrypt.Encrypter(encrypt.RSA(privateKey: privateKey));
  return encrypter.decrypt(encrypt.Encrypted.fromBase64(encryptedBase64));
}

String encryptLaneKeyWithJsonPublicKey(String laneKey, String publicKeyJson) {
  final publicKey = decodePublicKey(publicKeyJson);
  return encryptLaneKey(laneKey, publicKey);
}

String decryptLaneKeyWithJsonPrivateKey(String encryptedBase64, String privateKeyJson) {
  final privateKey = decodePrivateKey(privateKeyJson);
  return decryptLaneKey(encryptedBase64, privateKey);
}


