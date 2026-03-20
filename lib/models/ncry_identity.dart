class IdentityProfile {
  const IdentityProfile({
    required this.id,
    required this.displayName,
    required this.publicKeyPem,
    required this.privateKeyPem,
    required this.createdAt,
  });

  final String id;
  final String displayName;
  final String publicKeyPem;
  final String privateKeyPem;
  final String createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'publicKeyPem': publicKeyPem,
        'privateKeyPem': privateKeyPem,
        'createdAt': createdAt,
      };

  factory IdentityProfile.fromJson(Map<String, dynamic> json) => IdentityProfile(
        id: json['id'] as String,
        displayName: (json['displayName'] as String?) ?? 'Identity',
        publicKeyPem: json['publicKeyPem'] as String,
        privateKeyPem: json['privateKeyPem'] as String,
        createdAt: (json['createdAt'] as String?) ?? DateTime.now().toIso8601String(),
      );

  IdentityProfile copyWith({
    String? id,
    String? displayName,
    String? publicKeyPem,
    String? privateKeyPem,
    String? createdAt,
  }) {
    return IdentityProfile(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      publicKeyPem: publicKeyPem ?? this.publicKeyPem,
      privateKeyPem: privateKeyPem ?? this.privateKeyPem,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
