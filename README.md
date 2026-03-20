# ncrypted

`ncrypted` is a cross-platform Flutter app for end-to-end encrypted file exchange using QR-based key sharing and `.ncry` packages.

## Features

- Local identity keypair generation and secure key storage.
- Contact exchange via QR code / public key.
- File encryption to `.ncry` with hybrid crypto:
  - RSA (OAEP/PSS) for key wrapping/signatures
  - AES-256-GCM for file encryption
- Signature verification on decrypt with optional strict mode.
- Advanced security options (RSA key size/exponent) with apply-and-regenerate flow.
- Theme support with optional easter-egg terminal mode at max security profile.

## Project Structure

- `lib/main.dart` - app shell, navigation, theme wiring.
- `lib/screens/` - UI flows (`My Key`, `Contacts`, `Send`, `Open`, `Options`).
- `lib/services/` - crypto, package format, persistence, preferences.
- `lib/models/` - data models (`EncPackage`, `Contact`).
- `test/` + `ncry_test.dart` - widget + crypto/package tests.

## Quick Start

1. Install Flutter SDK.
2. From project root:

```bash
flutter pub get
flutter run
```

## Testing and Quality

```bash
flutter analyze
flutter test
```

## Release Process

- Use `RELEASE_CHECKLIST.md` for the full pre-ship and post-ship flow.

## Build Notes

- Encrypted files use the `.ncry` extension.
- Current package format version is `0x0002` (single active version).
