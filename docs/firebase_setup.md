# Firebase Setup (Android + iOS)

Your app code is already wired to initialize Firebase safely. To enable real push/auth analytics, complete the steps below.

## 1) Create Firebase project
- Go to Firebase Console and create/select project.
- Add Android app with package name: `com.freshmandi.app`.
- Add iOS app with bundle id: `com.freshmandi.app`.

## 2) Register SHA certificates (Android)
Run from terminal:

```bash
keytool -list -v -alias androiddebugkey -keystore ~/.android/debug.keystore -storepass android -keypass android
```

Copy SHA-1 and SHA-256 to Firebase Android app settings.

For release keystore:

```bash
keytool -list -v -alias <release_alias> -keystore <path_to_release_keystore>
```

## 3) Download and place config files
- Android: place `google-services.json` at:
  - `app/android/app/google-services.json`
- iOS: place `GoogleService-Info.plist` at:
  - `app/ios/Runner/GoogleService-Info.plist`

## 4) iOS additional setup
```bash
cd app/ios
pod install
```

Open Xcode (`Runner.xcworkspace`), verify:
- Push Notifications capability enabled
- Background Modes includes `Remote notifications`

## 5) Generate FlutterFire options (recommended)
Install FlutterFire CLI and run:

```bash
flutterfire configure --project=<firebase-project-id> --out=lib/firebase_options.dart --platforms=android,ios
```

Then initialize with options in `main.dart` if you prefer explicit setup.

## 6) Verify
```bash
cd app
flutter clean
flutter pub get
flutter run
```

If Firebase is still not initialized, verify file locations and package/bundle IDs exactly match:
- Android `applicationId`: `com.freshmandi.app`
- iOS bundle id: `com.freshmandi.app`
