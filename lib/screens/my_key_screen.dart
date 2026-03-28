import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pointycastle/api.dart' show AsymmetricKeyPair;
import 'package:pointycastle/asymmetric/api.dart' show RSAPrivateKey, RSAPublicKey;
import 'package:qr_flutter/qr_flutter.dart';

import '../models/ncry_identity.dart';
import '../services/ncry_crypto.dart';
import '../services/ncry_keys.dart';
import '../services/security_preferences.dart';

class MyKeyScreen extends StatefulWidget {
  const MyKeyScreen({
    super.key,
    this.easterEggEnabled = false,
    this.onEasterEggChanged,
  });

  final bool easterEggEnabled;
  final ValueChanged<bool>? onEasterEggChanged;

  @override
  State<MyKeyScreen> createState() => _MyKeyScreenState();
}

class _MyKeyScreenState extends State<MyKeyScreen> {
  bool _isLoading = true;
  String? _error;
  List<IdentityProfile> _identities = const [];
  String? _activeIdentityId;
  String? _publicPem;
  String? _fingerprint;

  IdentityProfile? get _activeIdentity {
    final id = _activeIdentityId;
    if (id == null) return null;
    for (final identity in _identities) {
      if (identity.id == id) return identity;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadOrCreateIdentity();
  }

  Future<AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>> _generateConfiguredPair() async {
    final settings = await SecurityPreferences.load();
    return CryptoService.generateKeyPair(
      bitStrength: settings.rsaKeyBits,
      publicExponent: settings.rsaPublicExponent,
    );
  }

  Future<void> _loadOrCreateIdentity() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      var identities = await KeyStore.loadIdentities();
      if (identities.isEmpty) {
        final pair = await _generateConfiguredPair();
        await KeyStore.createIdentity(
          displayName: 'Default',
          publicKeyPem: CryptoService.publicKeyToPem(pair.publicKey),
          privateKeyPem: CryptoService.privateKeyToPem(pair.privateKey),
          setActive: true,
        );
        identities = await KeyStore.loadIdentities();
      }

      final active = await KeyStore.loadActiveIdentity();
      final selected = active ?? identities.first;
      widget.onEasterEggChanged?.call(KeyStore.isIdentityMaxProfile(selected));
      final publicKey = CryptoService.pemToPublicKey(selected.publicKeyPem);
      final fingerprint = CryptoService.fingerprint(publicKey);

      if (!mounted) return;
      setState(() {
        _identities = identities;
        _activeIdentityId = selected.id;
        _publicPem = selected.publicKeyPem;
        _fingerprint = fingerprint;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load identity: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _copyPem() async {
    final pem = _publicPem;
    if (pem == null) return;

    await Clipboard.setData(ClipboardData(text: pem));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Public key copied to clipboard')),
    );
  }

  Future<void> _regenerateIdentity() async {
    final active = _activeIdentity;
    if (active == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Regenerate Identity Key?'),
          content: const Text(
            'This creates a new identity. Existing contacts will see a new '
            'fingerprint, and previously established trust checks will no '
            'longer match.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Create New Key'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final pair = await _generateConfiguredPair();
      await KeyStore.saveOrUpdateActiveIdentity(
        publicKeyPem: CryptoService.publicKeyToPem(pair.publicKey),
        privateKeyPem: CryptoService.privateKeyToPem(pair.privateKey),
      );
      await _loadOrCreateIdentity();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${active.displayName} key regenerated')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to regenerate identity: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _switchIdentity(String identityId) async {
    await KeyStore.setActiveIdentityId(identityId);
    await _loadOrCreateIdentity();
  }

  Future<void> _createIdentityProfile() async {
    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Identity Profile'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Profile name',
            hintText: 'Work Profile',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    final rawName = controller.text.trim();
    controller.dispose();
    if (accepted != true) return;

    final displayName = rawName.isEmpty ? 'Identity ${_identities.length + 1}' : rawName;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final pair = await _generateConfiguredPair();
      await KeyStore.createIdentity(
        displayName: displayName,
        publicKeyPem: CryptoService.publicKeyToPem(pair.publicKey),
        privateKeyPem: CryptoService.privateKeyToPem(pair.privateKey),
        setActive: true,
      );
      await _loadOrCreateIdentity();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created profile: $displayName')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to create identity profile: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _renameActiveIdentity() async {
    final active = _activeIdentity;
    if (active == null) return;
    final controller = TextEditingController(text: active.displayName);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Identity Profile'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Profile name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final nextName = controller.text.trim();
    controller.dispose();
    if (accepted != true) return;
    if (nextName.isEmpty) return;

    await KeyStore.renameIdentity(active.id, nextName);
    await _loadOrCreateIdentity();
  }

  Future<void> _deleteActiveIdentity() async {
    final active = _activeIdentity;
    if (active == null) return;
    if (_identities.length <= 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one identity profile is required.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Identity Profile?'),
        content: Text(
          'Delete "${active.displayName}"? You may lose ability to identify files tied to this profile.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await KeyStore.deleteIdentity(active.id);
    await _loadOrCreateIdentity();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 42),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loadOrCreateIdentity,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final contentMaxWidth = screenWidth >= 900 ? 760.0 : (screenWidth >= 700 ? 620.0 : 460.0);
    final horizontalPadding = screenWidth >= 900 ? 28.0 : 16.0;
    final qrSize = screenWidth >= 900 ? 340.0 : 260.0;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Your Identity Key',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _activeIdentityId,
                    isExpanded: true,
                    items: _identities
                        .map(
                          (identity) => DropdownMenuItem<String>(
                            value: identity.id,
                            child: Text(
                              identity.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    selectedItemBuilder: (context) {
                      return _identities
                          .map(
                            (identity) => Tooltip(
                              message: identity.displayName,
                              child: Text(
                                identity.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList();
                    },
                    onChanged: _isLoading
                        ? null
                        : (value) {
                            if (value == null || value == _activeIdentityId) return;
                            _switchIdentity(value);
                          },
                    decoration: const InputDecoration(
                      labelText: 'Active Identity Profile',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _createIdentityProfile,
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Add Profile'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _renameActiveIdentity,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Rename'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _deleteActiveIdentity,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Profile: ${_activeIdentity?.displayName ?? 'Unknown'}',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Fingerprint: ${_fingerprint!}',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Align(
                      alignment: Alignment.center,
                      child: QrImageView(
                        data: _publicPem!,
                        size: qrSize,
                        version: QrVersions.auto,
                        gapless: false,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _copyPem,
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy Public Key'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _loadOrCreateIdentity,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh Key'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _regenerateIdentity,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Create New Key'),
                  ),
                  const SizedBox(height: 12),
                  ExpansionTile(
                    title: const Text('Advanced: View Public Key'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: _copyPem,
                            icon: const Icon(Icons.copy),
                            label: const Text('Copy Public Key'),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          _publicPem!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
