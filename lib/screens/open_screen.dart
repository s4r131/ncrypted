import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:typed_data';

import '../models/ncry_contact.dart';
import '../models/ncry_identity.dart';
import '../services/ncry_aes.dart';
import '../services/ncry_crypto.dart';
import '../services/ncry_keys.dart';
import '../services/ncry_package.dart';
import '../services/security_preferences.dart';

class OpenScreen extends StatefulWidget {
  const OpenScreen({super.key, this.initialNcryPath});

  final String? initialNcryPath;

  @override
  State<OpenScreen> createState() => _OpenScreenState();
}

class _OpenScreenState extends State<OpenScreen> {
  bool _isDecrypting = false;
  String? _selectedEncPath;
  String? _status;
  String? _error;
  bool? _lastSignatureVerified;
  String? _lastSenderDisplay;
  String? _lastPackageInfo;
  String? _lastIdentityUsed;

  @override
  void initState() {
    super.initState();
    if (widget.initialNcryPath != null && widget.initialNcryPath!.trim().isNotEmpty) {
      _selectedEncPath = widget.initialNcryPath;
      _status = 'Loaded from app launch argument.';
    }
  }

  Future<void> _pickEncFile() async {
    setState(() {
      _error = null;
      _status = null;
    });

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: false,
      type: FileType.custom,
      allowedExtensions: const ['ncry'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null || path.trim().isEmpty) {
      setState(() => _error = 'Selected file has no local path on this platform.');
      return;
    }
    setState(() => _selectedEncPath = path);
  }

  String _safeFilename(String raw) {
    final sanitized = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (sanitized.isEmpty) return 'decrypted_output.bin';
    return sanitized;
  }

  Future<String> _uniqueOutputPath(String dir, String filename) async {
    final dot = filename.lastIndexOf('.');
    final name = dot > 0 ? filename.substring(0, dot) : filename;
    final ext = dot > 0 ? filename.substring(dot) : '';

    var candidate = '$dir${Platform.pathSeparator}$filename';
    if (!await File(candidate).exists()) return candidate;

    int i = 1;
    while (true) {
      candidate = '$dir${Platform.pathSeparator}${name}_decrypted_$i$ext';
      if (!await File(candidate).exists()) return candidate;
      i++;
    }
  }

  String _senderLabel(Contact? sender) {
    if (sender == null) return 'unknown sender';
    return '${sender.displayName} (${sender.fingerprint})';
  }

  String _friendlyDecryptError(Object e) {
    if (e is FormatException) {
      return 'This file is not a valid ncrypted package or is corrupted.';
    }

    final msg = e.toString();
    if (msg.contains('InvalidCipherTextException')) {
      return 'Decryption failed. The file may be tampered with or not encrypted for your key.';
    }
    if (msg.contains('No identity private key found')) {
      return 'No local identity key found. Open My Key first to initialize your identity.';
    }
    if (msg.contains('Unsupported ncrypted version')) {
      return 'This ncrypted file version is not supported by this app build.';
    }
    if (msg.contains('magic bytes mismatch')) {
      return 'This is not a ncrypted .ncry file.';
    }
    return 'Could not open/decrypt this file.';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024.0;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024.0;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024.0;
    return '${gb.toStringAsFixed(2)} GB';
  }

  Future<void> _openAndDecrypt() async {
    final encPath = _selectedEncPath;
    if (encPath == null) {
      setState(() => _error = 'Pick a .ncry file first.');
      return;
    }

    setState(() {
      _isDecrypting = true;
      _error = null;
      _status = 'Decrypting...';
      _lastSignatureVerified = null;
      _lastSenderDisplay = null;
      _lastPackageInfo = null;
      _lastIdentityUsed = null;
    });

    try {
      final identities = await KeyStore.loadIdentities();
      if (identities.isEmpty) {
        throw Exception('No identity private key found. Open My Key first.');
      }

      final encBytes = await File(encPath).readAsBytes();
      final package = PackageService.decode(encBytes);
      final metaName = package.originalFilename;
      final metaType = package.mimeType ?? 'unknown';
      final metaSize = package.originalFileSize == null
          ? 'unknown'
          : _formatBytes(package.originalFileSize!);
      final metaSender = package.senderFingerprint ?? 'not provided';
      _lastPackageInfo = 'File: $metaName\nType: $metaType\nSize: $metaSize\nSender FP: $metaSender';

      Uint8List? plaintext;
      IdentityProfile? decryptIdentity;
      for (final identity in identities) {
        try {
          final privateKey = CryptoService.pemToPrivateKey(identity.privateKeyPem);
          final aesKey = CryptoService.unwrapAesKey(package.wrappedKey, privateKey);
          final decrypted = AesService.decrypt(package.ciphertext, aesKey, package.nonce);
          plaintext = decrypted;
          decryptIdentity = identity;
          break;
        } catch (_) {
          // Try next identity profile.
        }
      }
      if (plaintext == null || decryptIdentity == null) {
        throw Exception('No matching identity key could decrypt this file.');
      }
      final usedIdentity = decryptIdentity;

      final contacts = await KeyStore.loadContacts();
      Contact? verifiedSender;
      for (final contact in contacts) {
        try {
          final pub = CryptoService.pemToPublicKey(contact.publicKeyPem);
          final ok = CryptoService.verify(plaintext, package.signature, pub);
          if (ok) {
            verifiedSender = contact;
            break;
          }
        } catch (_) {
          // Ignore malformed stored contact keys and continue scanning.
        }
      }

      final signatureVerified = verifiedSender != null;
      if (!signatureVerified) {
        final security = await SecurityPreferences.load();
        if (!mounted) return;
        if (security.requireVerifiedSender) {
          setState(() {
            _isDecrypting = false;
            _lastSignatureVerified = false;
            _lastSenderDisplay = null;
            _lastIdentityUsed = usedIdentity.displayName;
            _status = 'Blocked by security setting: sender signature is unverified.';
          });
          return;
        }

        final saveAnyway = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Unverified Sender'),
            content: const Text(
              'The file decrypted, but signature verification did not match any '
              'known contact. Save plaintext anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Save Anyway'),
              ),
            ],
          ),
        );

        if (saveAnyway != true) {
          if (!mounted) return;
          setState(() {
            _isDecrypting = false;
            _lastSignatureVerified = false;
            _lastSenderDisplay = null;
            _lastIdentityUsed = usedIdentity.displayName;
            _status = 'Decrypted but not saved (unverified sender).';
          });
          return;
        }
      }

      final sourceFile = File(encPath);
      final parentDir = sourceFile.parent.path;
      final outputName = _safeFilename(package.originalFilename);
      final outputPath = await _uniqueOutputPath(parentDir, outputName);
      await File(outputPath).writeAsBytes(plaintext, flush: true);

      if (!mounted) return;
      setState(() {
        _isDecrypting = false;
        _lastSignatureVerified = signatureVerified;
        _lastSenderDisplay = verifiedSender?.displayName;
        _lastIdentityUsed = usedIdentity.displayName;
        _status = 'Saved plaintext:\n$outputPath\n\nSignature: '
            '${verifiedSender == null ? 'NOT VERIFIED' : 'VERIFIED (${_senderLabel(verifiedSender)})'}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !signatureVerified
                ? 'Decrypted. Signature not verified against known contacts.'
                : 'Decrypted and signature verified.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDecrypting = false;
        _error = _friendlyDecryptError(e);
        _lastSignatureVerified = null;
        _lastSenderDisplay = null;
        _lastPackageInfo = null;
        _lastIdentityUsed = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    'Open Encrypted File',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _isDecrypting ? null : _pickEncFile,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Pick .ncry File'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _selectedEncPath ?? 'No .ncry file selected',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isDecrypting ? null : _openAndDecrypt,
                    icon: const Icon(Icons.lock_open),
                    label: Text(_isDecrypting ? 'Decrypting...' : 'Decrypt and Save'),
                  ),
                  if (_lastSignatureVerified != null) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Chip(
                        avatar: Icon(
                          _lastSignatureVerified! ? Icons.verified : Icons.warning_amber_rounded,
                          color: _lastSignatureVerified! ? Colors.green : Colors.orange,
                        ),
                        label: Text(
                          _lastSignatureVerified!
                              ? 'VERIFIED${_lastSenderDisplay == null ? '' : ': $_lastSenderDisplay'}'
                              : 'UNVERIFIED SENDER',
                        ),
                      ),
                    ),
                  ],
                  if (_lastPackageInfo != null) ...[
                    const SizedBox(height: 12),
                    Text(_lastPackageInfo!),
                  ],
                  if (_lastIdentityUsed != null) ...[
                    const SizedBox(height: 8),
                    Text('Decrypted with identity: $_lastIdentityUsed'),
                  ],
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
