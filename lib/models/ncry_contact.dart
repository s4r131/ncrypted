// lib/models/ncry_contact.dart
//
// A contact is simply a name paired with their RSA public key.
// The public key is stored as a PEM string — the exact bytes that
// were encoded in their QR code when you scanned it.

class Contact {
  // Stable local identifier for this contact.
  final String id;

  // Human-readable label — entered by the user.
  final String displayName;

  // RSA-2048 public key in PEM format.
  // Looks like:
  //   -----BEGIN PUBLIC KEY-----
  //   MIIBIjANBgkq...
  //   -----END PUBLIC KEY-----
  //
  // This is safe to store unencrypted — it is the public half.
  // It contains only N and e (the modulus and public exponent).
  final String publicKeyPem;

  // SHA-256 fingerprint of the public key bytes.
  // Displayed after scanning so both parties can verify
  // no QR was swapped in transit (like Signal's safety numbers).
  // Format: "3A:F9:12:CC:..."
  final String fingerprint;

  // When the contact was added (ISO-8601 string).
  final String addedAt;

  // Optional metadata. These are user hints, not trust anchors.
  final String? notes;
  final String? email;
  final String? phone;

  const Contact({
    required this.id,
    required this.displayName,
    required this.publicKeyPem,
    required this.fingerprint,
    required this.addedAt,
    this.notes,
    this.email,
    this.phone,
  });

  // Serialize to a Map so it can be written to flutter_secure_storage as JSON.
  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'publicKeyPem': publicKeyPem,
        'fingerprint': fingerprint,
        'addedAt': addedAt,
        'notes': notes,
        'email': email,
        'phone': phone,
      };

  // Deserialize from a Map read out of flutter_secure_storage.
  // Supports older entries that used `name` and had no `id`.
  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
        id: (json['id'] as String?) ??
            (json['fingerprint'] as String?) ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        displayName: (json['displayName'] as String?) ??
            (json['name'] as String?) ??
            'Unknown Contact',
        publicKeyPem: json['publicKeyPem'] as String,
        fingerprint: json['fingerprint'] as String,
        addedAt: (json['addedAt'] as String?) ?? DateTime.now().toIso8601String(),
        notes: json['notes'] as String?,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
      );
}
