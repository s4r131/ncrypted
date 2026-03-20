// lib/services/ncry_crypto.dart
//
// All RSA operations — the Flutter/Dart equivalent of:
//   Python: from cryptography.hazmat.primitives.asymmetric import rsa, padding
//   Python: from cryptography.hazmat.primitives import hashes
//
// Covers:
//   - RSA-2048 key pair generation
//   - RSA-OAEP wrap / unwrap (encrypts/decrypts the AES session key)
//   - RSA-PSS sign / verify   (signs/verifies the file hash)
//   - PEM serialization / deserialization
//   - Public key fingerprint generation

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

class CryptoService {
  static SecureRandom _newFortunaRandom() {
    final random = FortunaRandom();
    final seedSource = Random.secure();
    final seed = Uint8List.fromList(
      List<int>.generate(32, (_) => seedSource.nextInt(256)),
    );
    random.seed(KeyParameter(seed));
    return random;
  }

  // ── Key Generation ────────────────────────────────────────────────────────

  // Generate a fresh RSA key pair.
  //
  // Equivalent to Python:
  //   private_key = rsa.generate_private_key(
  //     public_exponent=<publicExponent>,
  //     key_size=<bitStrength>
  //   )
  //
  // Returns an AsymmetricKeyPair containing both the private and public key.
  // Call this once on first launch. Store the result via KeyStore.
  static AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> generateKeyPair({
    int bitStrength = 2048,
    int publicExponent = 65537,
  }) {
    if (bitStrength < 2048) {
      throw ArgumentError.value(bitStrength, 'bitStrength', 'Must be at least 2048 bits');
    }
    if (bitStrength % 256 != 0) {
      throw ArgumentError.value(bitStrength, 'bitStrength', 'Must be a multiple of 256 bits');
    }
    if (publicExponent < 3 || publicExponent.isEven) {
      throw ArgumentError.value(publicExponent, 'publicExponent', 'Must be an odd integer >= 3');
    }

    final secureRandom = _newFortunaRandom();

    // RSAKeyGeneratorParameters sets:
    //   publicExponent = configurable e (recommended: 65537)
    //   bitStrength    = configurable key size in bits
    //   certainty      = 64     (Miller-Rabin primality test rounds)
    final keyParams = RSAKeyGeneratorParameters(
      BigInt.from(publicExponent), // e — public exponent
      bitStrength, // key size in bits
      64, // primality certainty
    );

    final keyGen = RSAKeyGenerator()
      ..init(ParametersWithRandom(keyParams, secureRandom));

    final pair = keyGen.generateKeyPair();

    return AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>(
      pair.publicKey as RSAPublicKey,
      pair.privateKey as RSAPrivateKey,
    );
  }

  // ── RSA-OAEP Key Wrap / Unwrap ────────────────────────────────────────────

  // Wrap (encrypt) the AES session key using the recipient's RSA public key.
  //
  // Equivalent to Python:
  //   wrapped_key = recipient_pk.encrypt(
  //     aes_key,
  //     padding.OAEP(
  //       mgf=padding.MGF1(algorithm=hashes.SHA256()),
  //       algorithm=hashes.SHA256(),
  //       label=None,
  //     )
  //   )
  //
  // [aesKey]      — the 32-byte AES-256 session key to protect
  // [recipientPk] — the recipient's RSA public key (loaded from their contact entry)
  //
  // Returns 256 bytes — the RSA-2048 output is always exactly key_size / 8 bytes.
  // Only the holder of the corresponding private key can unwrap this.
  static Uint8List wrapAesKey(Uint8List aesKey, RSAPublicKey recipientPk) {
    // OAEPEncoding wraps RSAEngine with OAEP padding.
    // The two SHA256Digest() calls set:
    //   digest    → the main OAEP hash (SHA-256)
    //   mgfDigest → the Mask Generation Function hash (MGF1 with SHA-256)
    // This matches Python's OAEP(mgf=MGF1(SHA256()), algorithm=SHA256())
    final cipher = OAEPEncoding.withSHA256(RSAEngine())
      ..init(
        true, // true = encrypt (wrapping)
        ParametersWithRandom(
          PublicKeyParameter<RSAPublicKey>(recipientPk),
          _newFortunaRandom(),
        ),
      );

    return cipher.process(aesKey);
  }

  // Unwrap (decrypt) the AES session key using our RSA private key.
  //
  // Equivalent to Python:
  //   aes_key = private_key.decrypt(
  //     wrapped_key,
  //     padding.OAEP(
  //       mgf=padding.MGF1(algorithm=hashes.SHA256()),
  //       algorithm=hashes.SHA256(),
  //       label=None,
  //     )
  //   )
  //
  // [wrappedKey] — the 256-byte wrapped key from the .enc file
  // [privateKey] — our RSA private key (loaded from flutter_secure_storage)
  //
  // Returns the original 32-byte AES session key.
  // Throws if the wrapped key was not encrypted for our public key.
  static Uint8List unwrapAesKey(Uint8List wrappedKey, RSAPrivateKey privateKey) {
    final cipher = OAEPEncoding.withSHA256(RSAEngine())
      ..init(
        false, // false = decrypt (unwrapping)
        PrivateKeyParameter<RSAPrivateKey>(privateKey),
      );

    return cipher.process(wrappedKey);
  }

  // ── RSA-PSS Sign / Verify ─────────────────────────────────────────────────

  // Sign the file bytes using our RSA private key.
  //
  // Equivalent to Python:
  //   sigma = private_key.sign(
  //     file_bytes,
  //     padding.PSS(
  //       mgf=padding.MGF1(hashes.SHA256()),
  //       salt_length=padding.PSS.MAX_LENGTH,
  //     ),
  //     hashes.SHA256()
  //   )
  //
  // We sign the plaintext file bytes directly.
  // pointycastle's PSSSigner computes SHA-256(data) internally before signing,
  // so we do not need to pre-hash.
  //
  // [fileBytes]  — the original plaintext file bytes
  // [privateKey] — our RSA private key
  //
  // Returns 256 bytes — the RSA-PSS signature.
  static Uint8List sign(Uint8List fileBytes, RSAPrivateKey privateKey) {
    // PSSSigner takes:
    //   RSAEngine()    — the underlying RSA primitive
    //   SHA256Digest() — hash used for the message digest
    //   SHA256Digest() — hash used for the MGF1 mask generation
    final signer = PSSSigner(RSAEngine(), SHA256Digest(), SHA256Digest())
      ..init(
        true, // true = signing
        ParametersWithSaltConfiguration(
          PrivateKeyParameter<RSAPrivateKey>(privateKey),
          _newFortunaRandom(),
          32, // SHA-256 digest size in bytes
        ),
      );

    return signer.generateSignature(fileBytes).bytes;
  }

  // Verify a signature using the sender's RSA public key.
  //
  // Equivalent to Python:
  //   sender_pk.verify(
  //     sigma,
  //     file_bytes,
  //     padding.PSS(mgf=MGF1(SHA256()), salt_length=PSS.MAX_LENGTH),
  //     hashes.SHA256()
  //   )
  //
  // [fileBytes]  — the decrypted plaintext file bytes
  // [signature]  — the 256-byte signature from the .enc file
  // [senderPk]   — the sender's public key (looked up from contacts)
  //
  // Returns true if the signature is valid — the file came from the
  // person whose QR code you scanned and it was not modified in transit.
  static bool verify(
    Uint8List fileBytes,
    Uint8List signature,
    RSAPublicKey senderPk,
  ) {
    try {
      final verifier = PSSSigner(RSAEngine(), SHA256Digest(), SHA256Digest())
        ..init(
          false, // false = verifying
          ParametersWithSaltConfiguration(
            PublicKeyParameter<RSAPublicKey>(senderPk),
            _newFortunaRandom(),
            32, // SHA-256 digest size in bytes
          ),
        );

      return verifier.verifySignature(
        fileBytes,
        PSSSignature(signature),
      );
    } catch (_) {
      // Any exception during verification means the signature is invalid.
      return false;
    }
  }

  // ── PEM Serialization ─────────────────────────────────────────────────────

  // Serialize an RSA public key to a PEM string.
  //
  // The PEM string is what gets encoded into the QR code.
  // It is also what gets saved to flutter_secure_storage for each contact.
  //
  // Output looks like:
  //   -----BEGIN PUBLIC KEY-----
  //   MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...
  //   -----END PUBLIC KEY-----
  static String publicKeyToPem(RSAPublicKey publicKey) {
    final asn1Seq = ASN1Sequence();

    // SubjectPublicKeyInfo structure (RFC 5480):
    //   SEQUENCE {
    //     SEQUENCE { OID (rsaEncryption), NULL }
    //     BIT STRING { SEQUENCE { INTEGER (n), INTEGER (e) } }
    //   }
    final algorithmSeq = ASN1Sequence();
    algorithmSeq.add(ASN1ObjectIdentifier.fromName('rsaEncryption'));
    algorithmSeq.add(ASN1Null());

    final publicKeySeq = ASN1Sequence();
    publicKeySeq.add(ASN1Integer(publicKey.modulus!)); // N — the modulus
    publicKeySeq.add(ASN1Integer(publicKey.exponent!)); // e — public exponent

    final publicKeyBitString = ASN1BitString(
      stringValues: publicKeySeq.encode(),
    );

    asn1Seq.add(algorithmSeq);
    asn1Seq.add(publicKeyBitString);

    final base64Encoded = base64.encode(asn1Seq.encode());
    final chunks = RegExp(r'.{1,64}')
        .allMatches(base64Encoded)
        .map((m) => m.group(0)!)
        .join('\n');

    return '-----BEGIN PUBLIC KEY-----\n$chunks\n-----END PUBLIC KEY-----';
  }

  // Deserialize a PEM string back into an RSAPublicKey object.
  //
  // Used when:
  //   - Loading a contact's public key from storage to wrap an AES key
  //   - Loading a sender's public key from contacts to verify a signature
  static RSAPublicKey pemToPublicKey(String pem) {
    final lines = pem
        .replaceAll('-----BEGIN PUBLIC KEY-----', '')
        .replaceAll('-----END PUBLIC KEY-----', '')
        .replaceAll('\n', '')
        .trim();

    final derBytes = base64.decode(lines);
    final asn1Parser = ASN1Parser(Uint8List.fromList(derBytes));
    final topSeq = asn1Parser.nextObject() as ASN1Sequence;

    // Skip the algorithm identifier sequence, go straight to the bit string.
    final bitString = topSeq.elements![1] as ASN1BitString;
    final innerParser = ASN1Parser(
      Uint8List.fromList(bitString.stringValues as List<int>),
    );
    final innerSeq = innerParser.nextObject() as ASN1Sequence;

    final modulus = (innerSeq.elements![0] as ASN1Integer).integer!; // N
    final exponent = (innerSeq.elements![1] as ASN1Integer).integer!; // e

    return RSAPublicKey(modulus, exponent);
  }

  // Serialize an RSA private key to a PEM string.
  //
  // This is what gets saved to flutter_secure_storage on first launch.
  // It is never transmitted or shown to the user.
  //
  // Format: PKCS#1 RSAPrivateKey (same as Python's TraditionalOpenSSL format)
  static String privateKeyToPem(RSAPrivateKey privateKey) {
    final asn1Seq = ASN1Sequence();
    asn1Seq.add(ASN1Integer(BigInt.zero)); // version
    asn1Seq.add(ASN1Integer(privateKey.modulus!)); // N
    asn1Seq.add(ASN1Integer(privateKey.exponent!)); // e (public exponent)
    asn1Seq.add(ASN1Integer(privateKey.privateExponent!)); // d (private exponent)
    asn1Seq.add(ASN1Integer(privateKey.p!)); // p
    asn1Seq.add(ASN1Integer(privateKey.q!)); // q
    asn1Seq.add(ASN1Integer(
      privateKey.privateExponent! % (privateKey.p! - BigInt.one),
    )); // d mod (p-1)
    asn1Seq.add(ASN1Integer(
      privateKey.privateExponent! % (privateKey.q! - BigInt.one),
    )); // d mod (q-1)
    asn1Seq.add(ASN1Integer(
      privateKey.q!.modInverse(privateKey.p!),
    )); // q^-1 mod p

    final base64Encoded = base64.encode(asn1Seq.encode());
    final chunks = RegExp(r'.{1,64}')
        .allMatches(base64Encoded)
        .map((m) => m.group(0)!)
        .join('\n');

    return '-----BEGIN RSA PRIVATE KEY-----\n$chunks\n-----END RSA PRIVATE KEY-----';
  }

  // Deserialize a PEM string back into an RSAPrivateKey object.
  //
  // Used when loading the private key from flutter_secure_storage
  // to unwrap an AES key or sign a file.
  static RSAPrivateKey pemToPrivateKey(String pem) {
    final lines = pem
        .replaceAll('-----BEGIN RSA PRIVATE KEY-----', '')
        .replaceAll('-----END RSA PRIVATE KEY-----', '')
        .replaceAll('\n', '')
        .trim();

    final derBytes = base64.decode(lines);
    final asn1Parser = ASN1Parser(Uint8List.fromList(derBytes));
    final seq = asn1Parser.nextObject() as ASN1Sequence;
    final els = seq.elements!;

    // PKCS#1 layout: version, N, e, d, p, q, d mod p-1, d mod q-1, q^-1 mod p
    final n = (els[1] as ASN1Integer).integer!; // modulus N
    final d = (els[3] as ASN1Integer).integer!; // private exponent d
    final p = (els[4] as ASN1Integer).integer!; // prime p
    final q = (els[5] as ASN1Integer).integer!; // prime q

    return RSAPrivateKey(n, d, p, q);
  }

  // ── Fingerprint ───────────────────────────────────────────────────────────

  // Generate a short human-readable fingerprint of a public key.
  //
  // Computed as SHA-256 of the DER-encoded public key, formatted as
  // colon-separated hex pairs: "3A:F9:12:CC:..."
  //
  // Displayed after scanning a contact's QR code so both parties can
  // read it aloud and confirm no QR was intercepted or swapped.
  // Equivalent to Signal's "safety numbers" feature.
  static String fingerprint(RSAPublicKey publicKey) {
    final pem = publicKeyToPem(publicKey);
    final lines = pem
        .replaceAll('-----BEGIN PUBLIC KEY-----', '')
        .replaceAll('-----END PUBLIC KEY-----', '')
        .replaceAll('\n', '')
        .trim();

    final derBytes = base64.decode(lines);

    final digest = SHA256Digest();
    final hash = Uint8List(digest.digestSize);
    digest
      ..update(Uint8List.fromList(derBytes), 0, derBytes.length)
      ..doFinal(hash, 0);

    // Take first 8 bytes → "3A:F9:12:CC:01:AB:7E:44"
    // Short enough to read aloud, unique enough to catch any swap.
    return hash
        .take(8)
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }
}
