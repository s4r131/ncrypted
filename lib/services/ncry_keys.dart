// lib/services/ncry_keys.dart
//
// Wraps flutter_secure_storage to persist the identity key pair
// and all contact public keys.
//
// On Python/desktop we wrote PEM files to ~/.ncrypted/
// On mobile, flutter_secure_storage is the equivalent — but better:
//   iOS     → keys live in the Keychain (hardware-backed on devices with Secure Enclave)
//   Android → keys live in Android Keystore (hardware-backed on modern devices)
//
// The private key never leaves the device and is not accessible to other apps.

import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/ncry_contact.dart';
import '../models/ncry_identity.dart';
import 'ncry_crypto.dart';
import 'security_preferences.dart';

class KeyStore {
  // Storage key names — these are the "filenames" inside the secure store.
  static const _kPrivateKey = 'ncrypted.identity.private_key';
  static const _kPublicKey = 'ncrypted.identity.public_key';
  static const _kIdentitiesKey = 'ncrypted.identities.v1';
  static const _kActiveIdentityId = 'ncrypted.identity.active_id';
  static const _kContactsKey = 'ncrypted.contacts';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // ── Identity key pair ─────────────────────────────────────────────────────
  static String _newIdentityId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  static Future<void> _migrateLegacyIdentityIfNeeded() async {
    final raw = await _storage.read(key: _kIdentitiesKey);
    if (raw != null && raw.trim().isNotEmpty) return;

    final legacyPublic = await _storage.read(key: _kPublicKey);
    final legacyPrivate = await _storage.read(key: _kPrivateKey);
    if (legacyPublic == null || legacyPrivate == null) return;

    final defaultIdentity = IdentityProfile(
      id: _newIdentityId(),
      displayName: 'Default',
      publicKeyPem: legacyPublic,
      privateKeyPem: legacyPrivate,
      createdAt: DateTime.now().toIso8601String(),
    );
    await _storage.write(
      key: _kIdentitiesKey,
      value: jsonEncode([defaultIdentity.toJson()]),
    );
    await _storage.write(key: _kActiveIdentityId, value: defaultIdentity.id);
  }

  static Future<List<IdentityProfile>> loadIdentities() async {
    await _migrateLegacyIdentityIfNeeded();
    final raw = await _storage.read(key: _kIdentitiesKey);
    if (raw == null || raw.trim().isEmpty) return [];

    final List<dynamic> jsonList = jsonDecode(raw);
    return jsonList
        .map((e) => IdentityProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveIdentities(List<IdentityProfile> identities) async {
    final jsonList = identities.map((i) => i.toJson()).toList();
    await _storage.write(key: _kIdentitiesKey, value: jsonEncode(jsonList));
  }

  static Future<String?> loadActiveIdentityId() async {
    await _migrateLegacyIdentityIfNeeded();
    final id = await _storage.read(key: _kActiveIdentityId);
    if (id != null && id.trim().isNotEmpty) return id;

    final identities = await loadIdentities();
    if (identities.isEmpty) return null;
    final fallback = identities.first.id;
    await _storage.write(key: _kActiveIdentityId, value: fallback);
    return fallback;
  }

  static Future<void> setActiveIdentityId(String id) async {
    final identities = await loadIdentities();
    IdentityProfile? selected;
    for (final item in identities) {
      if (item.id == id) {
        selected = item;
        break;
      }
    }
    if (selected == null) {
      throw StateError('Cannot activate unknown identity');
    }
    await _storage.write(key: _kActiveIdentityId, value: id);
    await _storage.write(key: _kPublicKey, value: selected.publicKeyPem);
    await _storage.write(key: _kPrivateKey, value: selected.privateKeyPem);
    await _syncSecurityPrefsFromIdentity(selected);
  }

  static Future<IdentityProfile?> loadActiveIdentity() async {
    final identities = await loadIdentities();
    if (identities.isEmpty) return null;
    final activeId = await loadActiveIdentityId();
    if (activeId == null) return identities.first;
    for (final identity in identities) {
      if (identity.id == activeId) return identity;
    }
    return identities.first;
  }

  static bool isIdentityMaxProfile(IdentityProfile identity) {
    final key = CryptoService.pemToPublicKey(identity.publicKeyPem);
    final bits = key.modulus?.bitLength ?? 0;
    final exponent = key.exponent?.toInt() ?? 0;
    return SecurityPreferences.isMaxProfileValues(
      rsaKeyBits: bits,
      rsaPublicExponent: exponent,
    );
  }

  static Future<bool> isActiveIdentityMaxProfile() async {
    try {
      final active = await loadActiveIdentity();
      if (active == null) return false;
      return isIdentityMaxProfile(active);
    } catch (_) {
      return false;
    }
  }

  static Future<IdentityProfile> createIdentity({
    required String displayName,
    required String publicKeyPem,
    required String privateKeyPem,
    bool setActive = true,
  }) async {
    final identities = await loadIdentities();
    final identity = IdentityProfile(
      id: _newIdentityId(),
      displayName: displayName.trim().isEmpty ? 'Identity' : displayName.trim(),
      publicKeyPem: publicKeyPem,
      privateKeyPem: privateKeyPem,
      createdAt: DateTime.now().toIso8601String(),
    );
    identities.add(identity);
    await saveIdentities(identities);
    if (setActive || identities.length == 1) {
      await _storage.write(key: _kActiveIdentityId, value: identity.id);
      await _storage.write(key: _kPublicKey, value: identity.publicKeyPem);
      await _storage.write(key: _kPrivateKey, value: identity.privateKeyPem);
      await _syncSecurityPrefsFromIdentity(identity);
    }
    return identity;
  }

  static Future<void> saveOrUpdateActiveIdentity({
    required String publicKeyPem,
    required String privateKeyPem,
  }) async {
    final identities = await loadIdentities();
    final activeId = await loadActiveIdentityId();
    if (identities.isEmpty || activeId == null) {
      await createIdentity(
        displayName: 'Default',
        publicKeyPem: publicKeyPem,
        privateKeyPem: privateKeyPem,
        setActive: true,
      );
      return;
    }

    final updated = identities
        .map((identity) => identity.id == activeId
            ? identity.copyWith(
                publicKeyPem: publicKeyPem,
                privateKeyPem: privateKeyPem,
              )
            : identity)
        .toList();
    await saveIdentities(updated);
    await _storage.write(key: _kPublicKey, value: publicKeyPem);
    await _storage.write(key: _kPrivateKey, value: privateKeyPem);
    final active = await loadActiveIdentity();
    if (active != null) {
      await _syncSecurityPrefsFromIdentity(active);
    }
  }

  static Future<void> renameIdentity(String id, String displayName) async {
    final nextName = displayName.trim();
    if (nextName.isEmpty) {
      throw ArgumentError('Identity name cannot be empty');
    }
    final identities = await loadIdentities();
    var found = false;
    final updated = identities.map((identity) {
      if (identity.id != id) return identity;
      found = true;
      return identity.copyWith(displayName: nextName);
    }).toList();
    if (!found) {
      throw StateError('Cannot rename unknown identity');
    }
    await saveIdentities(updated);
  }

  static Future<void> deleteIdentity(String id) async {
    final identities = await loadIdentities();
    if (identities.length <= 1) {
      throw StateError('At least one identity profile must remain');
    }
    final updated = identities.where((identity) => identity.id != id).toList();
    if (updated.length == identities.length) {
      throw StateError('Cannot delete unknown identity');
    }
    await saveIdentities(updated);
    final activeId = await loadActiveIdentityId();
    if (activeId == id) {
      final fallback = updated.first;
      await _storage.write(key: _kActiveIdentityId, value: fallback.id);
      await _storage.write(key: _kPublicKey, value: fallback.publicKeyPem);
      await _storage.write(key: _kPrivateKey, value: fallback.privateKeyPem);
      await _syncSecurityPrefsFromIdentity(fallback);
    }
  }

  static Future<void> _syncSecurityPrefsFromIdentity(IdentityProfile identity) async {
    try {
      final key = CryptoService.pemToPublicKey(identity.publicKeyPem);
      final bits = key.modulus?.bitLength;
      final exponent = key.exponent?.toInt();
      if (bits != null && exponent != null) {
        await SecurityPreferences.saveRsaKeyBits(bits);
        await SecurityPreferences.saveRsaPublicExponent(exponent);
      }
    } catch (_) {
      // Ignore sync failures; identity switching should still succeed.
    }
  }

  // Check if a key pair already exists.
  // Called on app launch to decide whether to show keygen or the home screen.
  static Future<bool> hasKeyPair() async {
    final active = await loadActiveIdentity();
    if (active != null) return true;
    final key = await _storage.read(key: _kPrivateKey);
    return key != null && key.isNotEmpty;
  }

  // Save the RSA private key PEM to secure storage.
  //
  // Called once on first launch after key generation.
  // Equivalent to Python: open("private.pem", "wb").write(private_bytes)
  // but stored in the OS secure enclave, not the filesystem.
  static Future<void> savePrivateKey(String privatePem) async {
    await _storage.write(key: _kPrivateKey, value: privatePem);
    final active = await loadActiveIdentity();
    if (active != null) {
      await saveOrUpdateActiveIdentity(
        publicKeyPem: active.publicKeyPem,
        privateKeyPem: privatePem,
      );
    }
  }

  // Save the RSA public key PEM to secure storage.
  //
  // Not secret — the public key is stored here for convenient access
  // when generating the QR code on the My Key screen.
  static Future<void> savePublicKey(String publicPem) async {
    await _storage.write(key: _kPublicKey, value: publicPem);
    final active = await loadActiveIdentity();
    if (active != null) {
      await saveOrUpdateActiveIdentity(
        publicKeyPem: publicPem,
        privateKeyPem: active.privateKeyPem,
      );
    }
  }

  // Load the RSA private key PEM from secure storage.
  //
  // Returns null if no key has been generated yet (first launch).
  // Equivalent to Python: open("private.pem", "rb").read()
  static Future<String?> loadPrivateKey() async {
    final active = await loadActiveIdentity();
    if (active != null) return active.privateKeyPem;
    return _storage.read(key: _kPrivateKey);
  }

  // Load the RSA public key PEM from secure storage.
  static Future<String?> loadPublicKey() async {
    final active = await loadActiveIdentity();
    if (active != null) return active.publicKeyPem;
    return _storage.read(key: _kPublicKey);
  }

  // Delete the identity key pair — effectively wipes the user's identity.
  // Use with caution. Any files encrypted for this key are permanently lost.
  static Future<void> deleteKeyPair() async {
    await _storage.delete(key: _kPrivateKey);
    await _storage.delete(key: _kPublicKey);
    await _storage.delete(key: _kIdentitiesKey);
    await _storage.delete(key: _kActiveIdentityId);
  }

  // ── Contacts ──────────────────────────────────────────────────────────────

  // Load the full contacts list from secure storage.
  //
  // Contacts are stored as a JSON array under a single key.
  // Each entry is a serialized Contact object (name + publicKeyPem + fingerprint).
  //
  // Returns an empty list if no contacts have been added yet.
  static Future<List<Contact>> loadContacts() async {
    final raw = await _storage.read(key: _kContactsKey);
    if (raw == null) return [];

    final List<dynamic> jsonList = jsonDecode(raw);
    return jsonList
        .map((e) => Contact.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // Save the full contacts list to secure storage.
  //
  // Overwrites the entire list — always call loadContacts() first,
  // modify the list, then call saveContacts() with the updated list.
  static Future<void> saveContacts(List<Contact> contacts) async {
    final jsonList = contacts.map((c) => c.toJson()).toList();
    await _storage.write(key: _kContactsKey, value: jsonEncode(jsonList));
  }

  // Add a single contact and persist.
  // Checks for duplicate fingerprints so re-scanning the same QR is idempotent.
  static Future<void> addContact(Contact contact) async {
    final contacts = await loadContacts();
    final alreadyExists =
        contacts.any((c) => c.fingerprint == contact.fingerprint);
    if (!alreadyExists) {
      contacts.add(contact);
      await saveContacts(contacts);
    }
  }

  // Remove a contact by fingerprint.
  static Future<void> removeContact(String fingerprint) async {
    final contacts = await loadContacts();
    contacts.removeWhere((c) => c.fingerprint == fingerprint);
    await saveContacts(contacts);
  }
}
