import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../models/ncry_contact.dart';
import '../services/ncry_crypto.dart';
import '../services/ncry_keys.dart';
import 'scan_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  bool _isLoading = true;
  String? _error;
  List<Contact> _contacts = const [];

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final contacts = await KeyStore.loadContacts();
      contacts.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _contacts = contacts;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load contacts: $e';
        _isLoading = false;
      });
    }
  }

  String _newContactId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  bool get _scanSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> _scanAndAddContact() async {
    if (!_scanSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QR scanning is currently supported on Android and iOS.'),
        ),
      );
      return;
    }

    final scannedPem = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const ScanScreen(),
      ),
    );
    if (!mounted || scannedPem == null || scannedPem.trim().isEmpty) return;
    await _showAddContactDialog(initialPem: scannedPem.trim());
  }

  Future<void> _showAddContactDialog({String? initialPem}) async {
    final addedContact = await showDialog<Contact>(
      context: context,
      builder: (dialogContext) => _AddContactDialog(
        initialPem: initialPem,
        newContactId: _newContactId,
      ),
    );
    if (!mounted || addedContact == null) return;

    await _loadContacts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added ${addedContact.displayName}')),
    );
  }

  Future<void> _deleteContact(Contact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Contact?'),
        content: Text('Remove ${contact.displayName} from contacts?'),
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

    await KeyStore.removeContact(contact.fingerprint);
    await _loadContacts();
  }

  String _shortFp(String fp) {
    if (fp.length <= 17) return fp;
    return '${fp.substring(0, 8)}...${fp.substring(fp.length - 8)}';
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
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loadContacts,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Contacts (${_contacts.length})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _scanAndAddContact,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _showAddContactDialog,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _contacts.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No contacts yet.\nAdd one by pasting a public PEM key.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _contacts.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final contact = _contacts[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(contact.displayName.isEmpty ? '?' : contact.displayName[0].toUpperCase()),
                      ),
                      title: Text(
                        contact.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('FP ${_shortFp(contact.fingerprint)}'),
                      trailing: IconButton(
                        tooltip: 'Delete',
                        onPressed: () => _deleteContact(contact),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _AddContactDialog extends StatefulWidget {
  const _AddContactDialog({
    required this.newContactId,
    this.initialPem,
  });

  final String? initialPem;
  final String Function() newContactId;

  @override
  State<_AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<_AddContactDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _pemController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _notesController;

  bool _isSaving = false;
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _pemController = TextEditingController(text: widget.initialPem ?? '');
    _emailController = TextEditingController();
    _phoneController = TextEditingController();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pemController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final displayName = _nameController.text.trim();
    final pem = _pemController.text.trim();
    if (displayName.isEmpty || pem.isEmpty) {
      setState(() => _inlineError = 'Name and Public PEM are required.');
      return;
    }

    try {
      setState(() {
        _isSaving = true;
        _inlineError = null;
      });

      final publicKey = CryptoService.pemToPublicKey(pem);
      final fingerprint = CryptoService.fingerprint(publicKey);
      final contact = Contact(
        id: widget.newContactId(),
        displayName: displayName,
        publicKeyPem: pem,
        fingerprint: fingerprint,
        addedAt: DateTime.now().toIso8601String(),
        email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      await KeyStore.addContact(contact);
      if (!mounted) return;
      Navigator.of(context).pop(contact);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _inlineError = 'Invalid public key PEM.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final safeInsets = EdgeInsets.fromLTRB(
      math.max(0, mediaQuery.viewInsets.left),
      math.max(0, mediaQuery.viewInsets.top),
      math.max(0, mediaQuery.viewInsets.right),
      math.max(0, mediaQuery.viewInsets.bottom),
    );

    return MediaQuery(
      data: mediaQuery.copyWith(viewInsets: safeInsets),
      child: AlertDialog(
        title: const Text('Add Contact'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Display Name',
                    hintText: 'Alice',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email (optional)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone (optional)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                  minLines: 2,
                  maxLines: 3,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _pemController,
                  decoration: const InputDecoration(
                    labelText: 'Public PEM',
                    hintText: '-----BEGIN PUBLIC KEY----- ...',
                  ),
                  minLines: 6,
                  maxLines: 10,
                ),
                if (_inlineError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _inlineError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _isSaving ? null : _save,
            child: Text(_isSaving ? 'Saving...' : 'Save'),
          ),
        ],
      ),
    );
  }
}
