// lib/services/ncry_aes.dart
//
// AES-256-GCM file encryption and decryption.
//
// Flutter/Dart equivalent of Python:
//   from cryptography.hazmat.primitives.ciphers.aead import AESGCM
//   nonce = os.urandom(12)
//   aes   = AESGCM(key)
//   ciphertext = aes.encrypt(nonce, plaintext, None)
//   plaintext  = aes.decrypt(nonce, ciphertext, None)

import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

class AesService {
  // Random.secure() uses the platform CSPRNG on both iOS and Android.
  static Uint8List _secureBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  // Generate a cryptographically secure 32-byte (256-bit) AES key.
  //
  // Equivalent to Python:
  //   key = AESGCM.generate_key(bit_length=256)
  //   # which internally calls os.urandom(32)
  //
  // A fresh key is generated per file — never reuse a key.
  static Uint8List generateKey() {
    return _secureBytes(32); // 32 bytes = 256 bits
  }

  // Generate a cryptographically random 12-byte nonce.
  //
  // 12 bytes (96 bits) is the standard and recommended nonce size for AES-GCM.
  // Equivalent to Python: nonce = os.urandom(12)
  //
  // Never reuse a nonce with the same key.
  // Because we generate a fresh key per file, nonce collision is impossible.
  static Uint8List generateNonce() {
    return _secureBytes(12); // 12 bytes = 96 bits
  }

  // Encrypt file bytes using AES-256-GCM.
  //
  // Equivalent to Python:
  //   aes = AESGCM(key)
  //   ciphertext = aes.encrypt(nonce, plaintext, None)
  //
  // GCM (Galois/Counter Mode) provides two things in one pass:
  //   1. Confidentiality — Counter Mode encrypts the bytes
  //   2. Integrity      — Galois field multiplication produces a 16-byte
  //                       authentication tag appended to the ciphertext
  //
  // The authentication tag means that if anyone modifies even one byte of
  // the ciphertext, decryption will throw an exception rather than silently
  // returning corrupted plaintext.
  //
  // [plaintext] — the raw file bytes (any length, any file type)
  // [key]       — 32-byte AES-256 key from generateKey()
  // [nonce]     — 12-byte nonce from generateNonce()
  //
  // Returns: ciphertext bytes + 16-byte GCM auth tag appended at the end.
  //          Length = plaintext.length + 16
  static Uint8List encrypt(Uint8List plaintext, Uint8List key, Uint8List nonce) {
    // GCMBlockCipher wraps AESEngine and handles counter mode + GHASH.
    // AEADParameters sets:
    //   KeyParameter(key) — the 256-bit AES key
    //   128               — auth tag length in bits (16 bytes)
    //   nonce             — the 96-bit IV
    //   Uint8List(0)      — no additional authenticated data (AAD)
    //                       equivalent to Python's None as the third argument
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true, // true = encrypt
        AEADParameters(
          KeyParameter(key),
          128, // tag length in bits
          nonce,
          Uint8List(0), // no AAD
        ),
      );

    final out = Uint8List(cipher.getOutputSize(plaintext.length));
    final processed = cipher.processBytes(plaintext, 0, plaintext.length, out, 0);
    final finalized = cipher.doFinal(out, processed);
    return Uint8List.sublistView(out, 0, processed + finalized);
  }

  // Decrypt AES-256-GCM ciphertext back to the original file bytes.
  //
  // Equivalent to Python:
  //   aes = AESGCM(key)
  //   plaintext = aes.decrypt(nonce, ciphertext, None)
  //
  // GCM verifies the authentication tag BEFORE returning any plaintext.
  // If the ciphertext was tampered with — even a single bit — this will
  // throw an InvalidCipherTextException before any data is returned.
  //
  // [ciphertext] — the encrypted bytes + 16-byte auth tag (from .enc file)
  // [key]        — the 32-byte AES key (recovered via RSA-OAEP unwrap)
  // [nonce]      — the 12-byte nonce (from .enc file header)
  //
  // Returns: the original plaintext file bytes.
  // Throws:  InvalidCipherTextException if tampered or wrong key.
  static Uint8List decrypt(Uint8List ciphertext, Uint8List key, Uint8List nonce) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false, // false = decrypt
        AEADParameters(
          KeyParameter(key),
          128,
          nonce,
          Uint8List(0),
        ),
      );

    final out = Uint8List(cipher.getOutputSize(ciphertext.length));
    final processed = cipher.processBytes(ciphertext, 0, ciphertext.length, out, 0);
    final finalized = cipher.doFinal(out, processed);
    return Uint8List.sublistView(out, 0, processed + finalized);
  }
}
