// lib/services/ncry_package.dart
//
// Serializes an EncPackage to the .ncry binary file format
// and deserializes it back.
//
// Binary layout:
//   Offset   Size        Field
//   ──────   ──────────  ─────────────────────────────────────────
//   0        6 bytes     Magic: ASCII "NCRYPT"
//   6        2 bytes     Version: 0x0002 (uint16 big-endian)
//   8        12 bytes    Nonce (AES-GCM 96-bit IV)
//   20       2 bytes     wrapped_key length (uint16 big-endian)
//   22       2 bytes     signature length (uint16 big-endian)
//   24       4 bytes     ciphertext length (uint32 big-endian)
//   28       4 bytes     filename length in bytes (uint32 big-endian)
//   32       4 bytes     mime type length (uint32 big-endian)
//   36       4 bytes     sender fingerprint length (uint32 big-endian)
//   40       8 bytes     original file size (uint64 big-endian)
//   48       variable    wrapped_key
//   ...      variable    signature
//   ...      variable    ciphertext (encrypted file bytes + 16-byte GCM tag)
//   ...      variable    original filename (UTF-8 encoded)
//   ...      variable    mime type (UTF-8)
//   ...      variable    sender fingerprint (UTF-8)
//
import 'dart:convert';
import 'dart:typed_data';
import '../models/ncry_enc.dart';

class PackageService {
  // Magic bytes that identify a file as a ncrypted package.
  // Registered as a custom file type so the OS opens it in ncrypted directly.
  // Same idea as a PDF starting with %PDF or a PNG with \x89PNG.
  static final _magic = Uint8List.fromList(utf8.encode('NCRYPT'));

  static const _version = 0x0002;

  // Nonce size is fixed; key/signature sizes are variable in v0x0002.
  static const _nonceSize = 12; // AES-GCM nonce

  // ── Serialize ─────────────────────────────────────────────────────────────

  // Write an EncPackage to a binary Uint8List ready to save as a .ncry file.
  //
  // This is the Flutter equivalent of building your Python tuple and
  // writing it to disk:
  //   package = (wrapped_key, nonce, ciphertext, salt)
  //   open("file.ncry", "wb").write(serialize(package))
  static Uint8List encode(EncPackage package) {
    final filenameBytes = utf8.encode(package.originalFilename);
    final mimeBytes = utf8.encode(package.mimeType ?? '');
    final senderFpBytes = utf8.encode(package.senderFingerprint ?? '');
    final originalFileSize = package.originalFileSize ?? 0;
    final wrappedLen = package.wrappedKey.length;
    final signatureLen = package.signature.length;

    if (wrappedLen == 0 || wrappedLen > 0xFFFF) {
      throw const FormatException('Invalid wrapped key length for package');
    }
    if (signatureLen == 0 || signatureLen > 0xFFFF) {
      throw const FormatException('Invalid signature length for package');
    }

    final totalSize = 6 +
        2 +
        _nonceSize +
        2 + // wrapped key length
        2 + // signature length
        4 + // ciphertext length
        4 + // filename length
        4 + // mime length
        4 + // sender fp length
        8 + // original file size
        wrappedLen +
        signatureLen +
        package.ciphertext.length +
        filenameBytes.length +
        mimeBytes.length +
        senderFpBytes.length;

    final buf = ByteData(totalSize);
    final bytes = Uint8List.view(buf.buffer);
    int offset = 0;

    // Magic "NCRYPT" — 6 bytes
    bytes.setRange(offset, offset + 6, _magic);
    offset += 6;

    // Version — 2 bytes, big-endian uint16
    buf.setUint16(offset, _version, Endian.big);
    offset += 2;

    // Nonce — 12 bytes
    bytes.setRange(offset, offset + _nonceSize, package.nonce);
    offset += _nonceSize;

    // Wrapped key length — 2 bytes, big-endian uint16
    buf.setUint16(offset, wrappedLen, Endian.big);
    offset += 2;

    // Signature length — 2 bytes, big-endian uint16
    buf.setUint16(offset, signatureLen, Endian.big);
    offset += 2;

    // Ciphertext length — 4 bytes, big-endian uint32
    buf.setUint32(offset, package.ciphertext.length, Endian.big);
    offset += 4;

    // Filename length — 4 bytes, big-endian uint32
    buf.setUint32(offset, filenameBytes.length, Endian.big);
    offset += 4;

    // MIME length — 4 bytes, big-endian uint32
    buf.setUint32(offset, mimeBytes.length, Endian.big);
    offset += 4;

    // Sender fingerprint length — 4 bytes, big-endian uint32
    buf.setUint32(offset, senderFpBytes.length, Endian.big);
    offset += 4;

    // Original file size — 8 bytes, big-endian uint64
    buf.setUint64(offset, originalFileSize, Endian.big);
    offset += 8;

    // Wrapped key — variable
    bytes.setRange(offset, offset + wrappedLen, package.wrappedKey);
    offset += wrappedLen;

    // Signature — variable
    bytes.setRange(offset, offset + signatureLen, package.signature);
    offset += signatureLen;

    // Ciphertext — variable
    bytes.setRange(
      offset,
      offset + package.ciphertext.length,
      package.ciphertext,
    );
    offset += package.ciphertext.length;

    // Filename — variable (UTF-8)
    bytes.setRange(offset, offset + filenameBytes.length, filenameBytes);
    offset += filenameBytes.length;

    // MIME type — variable (UTF-8)
    bytes.setRange(offset, offset + mimeBytes.length, mimeBytes);
    offset += mimeBytes.length;

    // Sender fingerprint — variable (UTF-8)
    bytes.setRange(offset, offset + senderFpBytes.length, senderFpBytes);

    return bytes;
  }

  // ── Deserialize ───────────────────────────────────────────────────────────

  // Read a .ncry binary file back into an EncPackage.
  //
  // Validates the magic bytes and version before parsing.
  // Throws a FormatException if the file is not a valid ncrypted package.
  static EncPackage decode(Uint8List fileBytes) {
    if (fileBytes.length < 8 + _nonceSize) {
      throw const FormatException('File too small to be a valid .ncry package');
    }

    final buf = ByteData.view(fileBytes.buffer);
    int offset = 0;

    // Validate magic — must be exactly "NCRYPT"
    final magic = fileBytes.sublist(0, 6);
    if (!_listEquals(magic, _magic)) {
      throw const FormatException('Not a valid ncrypted file (magic bytes mismatch)');
    }
    offset += 6;

    // Validate version
    final version = buf.getUint16(offset, Endian.big);
    if (version != _version) {
      throw FormatException('Unsupported ncrypted version: $version');
    }
    offset += 2;

    // Read nonce — 12 bytes
    final nonce = Uint8List.fromList(fileBytes.sublist(offset, offset + _nonceSize));
    offset += _nonceSize;

    const v2HeaderMin = 6 + 2 + _nonceSize + 2 + 2 + 4 + 4 + 4 + 4 + 8;
    if (fileBytes.length < v2HeaderMin) {
      throw const FormatException('File too small to be a valid .ncry package');
    }

    final wrappedLen = buf.getUint16(offset, Endian.big);
    offset += 2;
    final signatureLen = buf.getUint16(offset, Endian.big);
    offset += 2;
    final ciphertextLen = buf.getUint32(offset, Endian.big);
    offset += 4;
    final filenameLen = buf.getUint32(offset, Endian.big);
    offset += 4;
    final mimeLen = buf.getUint32(offset, Endian.big);
    offset += 4;
    final senderFpLen = buf.getUint32(offset, Endian.big);
    offset += 4;
    final originalFileSize = buf.getUint64(offset, Endian.big);
    offset += 8;

    final remainingAfterHeader = fileBytes.length - offset;
    final requiredRsaBytes = wrappedLen + signatureLen;
    if (wrappedLen == 0 || signatureLen == 0 || requiredRsaBytes > remainingAfterHeader) {
      throw const FormatException('Corrupted package: invalid wrapped key or signature length');
    }

    final wrappedKey = Uint8List.fromList(
      fileBytes.sublist(offset, offset + wrappedLen),
    );
    offset += wrappedLen;

    final signature = Uint8List.fromList(
      fileBytes.sublist(offset, offset + signatureLen),
    );
    offset += signatureLen;

    // Ensure declared lengths fit in remaining bytes.
    final remainingAfterRsa = fileBytes.length - offset;
    if (ciphertextLen > remainingAfterRsa) {
      throw const FormatException('Corrupted package: ciphertext length exceeds file size');
    }

    // Read ciphertext
    final ciphertext = Uint8List.fromList(
      fileBytes.sublist(offset, offset + ciphertextLen),
    );
    offset += ciphertextLen;

    final remainingAfterCiphertext = fileBytes.length - offset;
    if (filenameLen > remainingAfterCiphertext) {
      throw const FormatException('Corrupted package: filename length exceeds file size');
    }

    // Read filename
    final filename = utf8.decode(
      fileBytes.sublist(offset, offset + filenameLen),
    );
    offset += filenameLen;

    final remainingAfterFilename = fileBytes.length - offset;
    if (mimeLen > remainingAfterFilename) {
      throw const FormatException('Corrupted package: mime length exceeds file size');
    }
    final mimeType = utf8.decode(fileBytes.sublist(offset, offset + mimeLen));
    offset += mimeLen;

    final remainingAfterMime = fileBytes.length - offset;
    if (senderFpLen > remainingAfterMime) {
      throw const FormatException('Corrupted package: sender fingerprint length exceeds file size');
    }
    final senderFingerprint = utf8.decode(fileBytes.sublist(offset, offset + senderFpLen));
    offset += senderFpLen;

    // Trailing bytes indicate malformed/unknown layout.
    if (offset != fileBytes.length) {
      throw const FormatException('Corrupted package: unexpected trailing bytes');
    }

    return EncPackage(
      wrappedKey: wrappedKey,
      nonce: nonce,
      ciphertext: ciphertext,
      signature: signature,
      originalFilename: filename,
      mimeType: mimeType.isEmpty ? null : mimeType,
      originalFileSize: originalFileSize,
      senderFingerprint: senderFingerprint.isEmpty ? null : senderFingerprint,
    );
  }

  // Helper: compare two Uint8Lists for equality.
  static bool _listEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
