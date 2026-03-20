# ncrypted iOS Deployment Handoff

This package is ready to move to a Mac for iOS build/signing.

## 1) Open on Mac

- Unzip this project.
- In Terminal:
  - `cd <unzipped-folder>`
  - `flutter pub get`
  - `pod repo update`
  - `flutter build ios --release --no-codesign`

## 2) Xcode signing setup

- Open `ios/Runner.xcworkspace` in Xcode (not `Runner.xcodeproj`).
- Select the `Runner` target.
- Set:
  - Team
  - Bundle Identifier (unique, e.g. `com.yourname.ncrypted`)
  - Signing Certificate / Provisioning Profile (automatic is fine to start)

## 3) App icon

- iOS AppIcon is already generated from `assets/branding/ncry_logo_icon.png`.
- Icon set is in `ios/Runner/Assets.xcassets/AppIcon.appiconset/`.

## 4) Archive for App Store Connect

- In Xcode: `Product` -> `Archive`.
- In Organizer: `Distribute App` -> `App Store Connect` -> `Upload`.

## 5) Optional command-line IPA export

- `flutter build ipa --release`

