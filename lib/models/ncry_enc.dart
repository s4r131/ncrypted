// lib/models/ncry_enc.dart
//
// The encrypted package — the Flutter equivalent of your Python tuple:
//   package = (wrapped_key, nonce, ciphertext, salt)
//
// This is everything the receiver needs to decrypt the file.
// It maps directly to the binary .ncry file format.

import 'dart:typed_data';

class EncPackage {
  // The AES-256 session key, RSA-OAEP encrypted with the recipient's public key.
  // Size: 256 bytes (fixed — RSA-2048 output is always 256 bytes).
  // Only the holder of the recipient's private key can unwrap this.
  final Uint8List wrappedKey;

  // 96-bit (12-byte) random nonce for AES-GCM.
  // Required for decryption — safe to transmit in the clear.
  // Never reused with the same key.
  final Uint8List nonce;

  // The encrypted file bytes, produced by AES-256-GCM.
  // Includes the 16-byte GCM authentication tag appended at the end.
  // Variable length — matches the original file size + 16 bytes.
  final Uint8List ciphertext;

  // RSA-PSS signature over the original plaintext file bytes.
  // Signed with the sender's private key.
  // Size: 256 bytes (fixed — RSA-2048 PSS output is always 256 bytes).
  // Verified with the sender's public key (from contacts).
  final Uint8List signature;

  // Original filename preserved so the receiver gets back
  // e.g. "report.pdf" not "file.ncry".
  final String originalFilename;

  // Optional metadata (v2 package format and later).
  final String? mimeType;
  final int? originalFileSize;
  final String? senderFingerprint;

  const EncPackage({
    required this.wrappedKey,
    required this.nonce,
    required this.ciphertext,
    required this.signature,
    required this.originalFilename,
    this.mimeType,
    this.originalFileSize,
    this.senderFingerprint,
  });
}
