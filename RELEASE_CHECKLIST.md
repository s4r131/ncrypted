# ncrypted Release Checklist

Use this checklist before declaring a production release.

## 1) Versioning + Changelog

- [ ] Bump `version` in `pubspec.yaml` (e.g., `1.0.0+1` -> `1.0.1+2`).
- [ ] Update `CHANGELOG.md` with release notes.
- [ ] Confirm release date and release tag naming convention.

## 2) Code Quality Gate

- [ ] Run `flutter pub get`.
- [ ] Run `flutter analyze` and confirm zero issues.
- [ ] Run `flutter test` and confirm all tests pass.
- [ ] Manually smoke test core flows:
  - [ ] My Key (load/generate/regenerate)
  - [ ] Contacts (add/scan/delete)
  - [ ] Send (`.ncry` create)
  - [ ] Open (`.ncry` decrypt + verify)
  - [ ] Options (theme + advanced security apply flow)

## 3) Crypto/Format Gate

- [ ] Verify `.ncry` round-trip works on latest build.
- [ ] Verify max security profile (`4096` + max exponent) encrypt/decrypt path.
- [ ] Verify package decode rejects malformed files cleanly.
- [ ] Confirm current package version is the intended one (`0x0002`).

## 4) Branding + UX Gate

- [ ] Confirm normal branding renders correctly in light/dark.
- [ ] Confirm easter egg triggers only on max profile apply.
- [ ] Confirm terminal palette uses amber theme across key UI components.
- [ ] Confirm SABRE popup/logo asset renders cleanly on target devices.

## 5) Platform Packaging

### Android
- [ ] `flutter build apk --release` (or appbundle).
- [ ] Verify app launches, encrypt/decrypt works on physical device.
- [ ] Verify camera permission/QR scan path.
- [ ] Verify `.ncry` association/open-intent behavior.

### iOS (when building on macOS)
- [ ] `flutter build ios --release`.
- [ ] Verify keychain behavior and secure storage.
- [ ] Verify camera/QR and file open flows.
- [ ] Verify `.ncry` open/share behavior.

### Desktop (if distributed)
- [ ] Build target binaries (`windows`/`macos` as needed).
- [ ] Verify open-with `.ncry` works after registration/association.

## 6) Security + Compliance Pass

- [ ] Confirm no secrets/keys are committed.
- [ ] Confirm debug logs do not expose plaintext/key material.
- [ ] Confirm error messages are user-safe (no sensitive dumps).
- [ ] Confirm strict sender verification toggle behavior.

## 7) Release Artifacts

- [ ] Prepare store metadata/screenshots.
- [ ] Export/installable artifacts and checksums.
- [ ] Tag release in source control.
- [ ] Archive release notes and known limitations.

## 8) Post-Release Verification

- [ ] Install from release artifact and retest core flows.
- [ ] Verify crash/analytics monitoring is active (if used).
- [ ] Track first-user feedback and hotfix candidates.
