import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

import '../models/ncry_contact.dart';
import '../models/ncry_enc.dart';
import '../models/ncry_identity.dart';
import '../services/ncry_aes.dart';
import '../services/ncry_crypto.dart';
import '../services/ncry_keys.dart';
import '../services/ncry_package.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key, this.onEasterEggChanged});

  final ValueChanged<bool>? onEasterEggChanged;

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  bool _isLoading = true;
  bool _isEncrypting = false;
  List<IdentityProfile> _identities = const [];
  String? _selectedIdentityId;
  List<Contact> _contacts = const [];
  Contact? _selectedContact;
  String? _selectedFilePath;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  IdentityProfile? get _selectedIdentity {
    final id = _selectedIdentityId;
    if (id == null) return null;
    for (final identity in _identities) {
      if (identity.id == id) return identity;
    }
    return null;
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final identities = await KeyStore.loadIdentities();
      final activeIdentityId = await KeyStore.loadActiveIdentityId();
      final contacts = await KeyStore.loadContacts();
      contacts.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _identities = identities;
        _selectedIdentityId = activeIdentityId ?? (identities.isEmpty ? null : identities.first.id);
        _contacts = contacts;
        _selectedContact = contacts.isEmpty ? null : contacts.first;
        _isLoading = false;
      });
      final selected = _selectedIdentity;
      if (selected != null) {
        widget.onEasterEggChanged?.call(KeyStore.isIdentityMaxProfile(selected));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load data: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _status = null;
    });

    final result = await FilePicker.platform.pickFiles(
      withData: false,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null || path.trim().isEmpty) {
      setState(() {
        _error = 'Selected file has no local path on this platform.';
      });
      return;
    }

    setState(() {
      _selectedFilePath = path;
    });
  }

  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  String? _guessMimeType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    return null;
  }

  Future<void> _encryptAndSave() async {
    final contact = _selectedContact;
    final identity = _selectedIdentity;
    final filePath = _selectedFilePath;

    if (identity == null) {
      setState(() => _error = 'Create/select an identity profile first in My Key.');
      return;
    }
    if (contact == null) {
      setState(() => _error = 'Select a contact first.');
      return;
    }
    if (filePath == null) {
      setState(() => _error = 'Pick a file first.');
      return;
    }

    setState(() {
      _isEncrypting = true;
      _error = null;
      _status = 'Encrypting...';
    });

    try {
      final privateKey = CryptoService.pemToPrivateKey(identity.privateKeyPem);
      final recipientPublicKey = CryptoService.pemToPublicKey(contact.publicKeyPem);

      final plaintext = await File(filePath).readAsBytes();
      final originalFilename = _basename(filePath);
      final ownPublic = CryptoService.pemToPublicKey(identity.publicKeyPem);
      final senderFingerprint = CryptoService.fingerprint(ownPublic);

      final aesKey = AesService.generateKey();
      final nonce = AesService.generateNonce();
      final ciphertext = AesService.encrypt(plaintext, aesKey, nonce);
      final wrappedKey = CryptoService.wrapAesKey(aesKey, recipientPublicKey);
      final signature = CryptoService.sign(plaintext, privateKey);

      final package = EncPackage(
        wrappedKey: wrappedKey,
        nonce: nonce,
        ciphertext: ciphertext,
        signature: signature,
        originalFilename: originalFilename,
        mimeType: _guessMimeType(originalFilename),
        originalFileSize: plaintext.length,
        senderFingerprint: senderFingerprint,
      );
      final encoded = PackageService.encode(package);

      final outputPath = '$filePath.ncry';
      await File(outputPath).writeAsBytes(encoded, flush: true);

      if (!mounted) return;
      setState(() {
        _status = 'Saved encrypted file:\n$outputPath\nSender identity: ${identity.displayName}';
        _isEncrypting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Encryption complete')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Encryption failed: $e';
        _isEncrypting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Send Encrypted File',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedIdentityId,
                    items: _identities
                        .map(
                          (identity) => DropdownMenuItem<String>(
                            value: identity.id,
                            child: Text(identity.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: _isEncrypting
                        ? null
                        : (value) async {
                            if (value == null) return;
                            setState(() => _selectedIdentityId = value);
                            await KeyStore.setActiveIdentityId(value);
                            final selected = _selectedIdentity;
                            if (selected != null) {
                              widget.onEasterEggChanged?.call(KeyStore.isIdentityMaxProfile(selected));
                            }
                          },
                    decoration: const InputDecoration(
                      labelText: 'Sender Identity',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Contact>(
                    initialValue: _selectedContact,
                    items: _contacts
                        .map(
                          (c) => DropdownMenuItem<Contact>(
                            value: c,
                            child: Text('${c.displayName} (${c.fingerprint})'),
                          ),
                        )
                        .toList(),
                    onChanged: _isEncrypting
                        ? null
                        : (value) => setState(() => _selectedContact = value),
                    decoration: const InputDecoration(
                      labelText: 'Recipient',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _isEncrypting ? null : _pickFile,
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Pick File'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _selectedFilePath ?? 'No file selected',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isEncrypting ? null : _encryptAndSave,
                    icon: const Icon(Icons.lock),
                    label: Text(_isEncrypting ? 'Encrypting...' : 'Encrypt and Save .ncry'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  if (_status != null) ...[
                    const SizedBox(height: 12),
                    Text(_status!),
                  ],
                  if (_contacts.isEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'No contacts found. Add a contact first in the Contacts tab.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (_identities.isEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'No identity profile found. Create one in the My Key tab.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
