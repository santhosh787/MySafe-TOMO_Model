# My Safe Tomo — Flutter + Firebase MVP

A consent-based personal safety app starter for Android and iOS. The package includes Flutter source, Firebase integration points, Firestore/Storage security rules, and Cloud Functions for verified guardian pairing and SOS dispatch.

> **Not an emergency-services replacement.** Test with non-emergency contacts before real use. Device permissions, OS background limits, network availability, and Firebase/Twilio configuration affect delivery.

## Included now

- Email/password registration and sign-in.
- Google Sign-In (Google provider must be enabled in Firebase).
- Firebase Phone Authentication via SMS OTP.
- Firestore user profile and FCM device-token registration.
- One-time QR guardian invite (16-minute expiry, single use).
- Guardian acceptance requires the guardian's Firebase ID token to contain a verified `phone_number` claim.
- User-confirmed SOS event creation with best-effort current GPS coordinates.
- Cloud Function dispatch to guardian FCM devices; Twilio SMS fallback if push has no successful delivery.
- Activity history for the signed-in user and paired guardians (read-only shared SOS events).
- Foreground-only connectivity and opt-in accelerometer awareness.
- Firestore and Storage rules with pairing links/invites restricted to trusted Cloud Functions.

## Not included / deliberately disabled

- No covert camera or microphone capture. The camera is used only by the user-opened QR scanner. No microphone permission is requested.
- No automatic SMS just because connectivity drops. A temporary dead zone is not proof of danger. Network state is an informational signal in this starter.
- Motion spikes only ask the user whether they are okay; they never send an SOS automatically.
- Sensor/network monitoring runs only while the app's safety screen is open. This is not a persistent background heartbeat or guaranteed background tracking service.
- Media uploads are disabled in Storage rules until a separate explicit-consent workflow, data-retention policy, and access design are implemented.
- SMS is sent only by a Cloud Function. No Twilio credentials are stored in the mobile app.

## 1. Requirements

- Flutter SDK 3.35+ (Dart 3.9+) (the sensor, connectivity, geolocation and scanner plugins are kept on compatible 6.x/13.x lines to avoid forcing AGP 8.12 / Kotlin 2.2 upgrades into older Android projects).
- Android Studio / Xcode for platform builds.
- Node.js 22 and npm for Cloud Functions.
- Firebase CLI and FlutterFire CLI.

Official Firebase setup: <https://firebase.google.com/docs/flutter/setup>

## 2. Generate native platform folders

This archive focuses on the app source and Firebase backend. Generate the Android/iOS runner scaffolding once with the included helper:

**Windows PowerShell**

```powershell
.\scripts\bootstrap_platforms.ps1
```

**macOS / Linux**

```bash
bash scripts/bootstrap_platforms.sh
```

The helper creates a temporary empty Flutter project with the correct application ID and copies only its `android/` and `ios/` runner folders here; it does not overwrite `lib/` or `pubspec.yaml`.

Then install Dart packages:

```bash
flutter pub get
```

## 3. Connect Firebase

```bash
firebase login
dart pub global activate flutterfire_cli
flutterfire configure
```

Select your Firebase project and Android/iOS platforms. FlutterFire replaces the placeholder `lib/firebase_options.dart` with the real per-platform client configuration. The generated values are client identifiers, not service-account secrets.

In Firebase Console:

1. Create/enable Cloud Firestore in the region you intend to use.
2. Authentication → Sign-in method: enable **Email/Password**, **Phone**, and **Google**.
3. Add your Android package `com.mysafetomo.my_safe_tomo` and iOS bundle ID in Project settings.
4. For Google Sign-In, register your Android SHA-1 and SHA-256 signing fingerprints in Firebase. Download the updated `google-services.json` if the FlutterFire configuration workflow does not refresh it automatically. Configure the iOS URL scheme / reversed client ID as instructed by Firebase.
5. Phone OTP requires an approved Firebase Authentication configuration and may require test phone numbers during development. Configure SMS region policies in Firebase Authentication.
6. Enable Cloud Messaging. For iOS, configure an APNs authentication key in Firebase and enable Push Notifications in Xcode.

## 4. Add platform permissions

After generating `android/` and `ios/`, add the following Android permissions inside `android/app/src/main/AndroidManifest.xml`, above the `<application>` element:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

`CAMERA` is for the QR scanner opened by the user. Location is requested only when the user confirms an SOS. Do not add `RECORD_AUDIO`, `SEND_SMS`, `ACCESS_BACKGROUND_LOCATION`, or a camera/microphone foreground-service declaration for this MVP.

Add these keys to the iOS `ios/Runner/Info.plist` inside the top-level `<dict>`:

```xml
<key>NSCameraUsageDescription</key>
<string>My Safe Tomo uses the camera only when you open the guardian QR scanner.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>My Safe Tomo can attach your current location when you choose to send an SOS alert.</string>
```

The platform must also be configured for Firebase Messaging / APNs on iOS before push delivery can work.

## 5. Deploy Firestore rules and Cloud Functions

Set the active Firebase project:

```bash
firebase use --add
```

Deploy the database and storage rules:

```bash
firebase deploy --only firestore:rules,storage
```

Install/build functions:

```bash
cd functions
npm install
npm run build
cd ..
firebase deploy --only functions
```

The callable functions run in `us-central1`, matching the default `FirebaseFunctions.instance` client region.

### Optional Twilio SMS fallback

The SOS Cloud Function first sends FCM to registered devices belonging to each paired guardian. If no push is successfully delivered, it attempts SMS using the verified phone number captured when the guardian accepted the QR invite.

Set Twilio secrets (use an E.164 sender number supported by your Twilio account):

```bash
firebase functions:secrets:set TWILIO_ACCOUNT_SID
firebase functions:secrets:set TWILIO_AUTH_TOKEN
firebase functions:secrets:set TWILIO_FROM_NUMBER
```

Redeploy functions after setting secrets:

```bash
firebase deploy --only functions
```

If Twilio secrets are not configured, SOS events are still recorded and FCM is still attempted, but SMS fallback will be marked `not_configured` in the server dispatch log. SMS costs and carrier delivery delays may apply.

## 6. Run the app

```bash
flutter run
```

For a release APK after configuring a real Firebase project:

```bash
flutter build apk --release
```

The APK is created at `build/app/outputs/flutter-apk/app-release.apk`.

## 7. Data layout

```text
users/{uid}
  displayName, email, phoneNumber, createdAt, updatedAt, lastCheckInAt
  devices/{sha256(fcmToken)}
    token, platform, updatedAt
  incidents/{incidentId}
    type, message, status, createdAt, location?

guardianLinks/{ownerUid}_{guardianUid}
  userUid, guardianUid, ownerName, ownerEmail,
  guardianName, guardianPhone, status, linkedAt

guardianInvites/{sha256(inviteCode)}
  ownerUid, expiresAt, used, ...       # server-only

dispatchLogs/{logId}                  # server-only
```

## 8. Verification checklist

- [ ] `flutter pub get` completes.
- [ ] Email sign-up/sign-in works and creates `users/{uid}`.
- [ ] Google sign-in works on configured Android/iOS devices.
- [ ] Phone OTP sign-in works with Firebase test phone numbers.
- [ ] The invite QR expires after 15 minutes and cannot be reused.
- [ ] A guardian cannot accept an invite until phone authentication is verified.
- [ ] The owner and paired guardian can read the permitted link / incident data; unrelated users cannot.
- [ ] SOS creates an incident document even when GPS permission is denied (location is null).
- [ ] A paired guardian receives an FCM notification when a token exists.
- [ ] Twilio fallback sends to the guardian's verified phone when FCM has no successful delivery.
- [ ] Motion candidate only displays a safety prompt; no automatic alert occurs.
- [ ] Network loss does not dispatch an alert.

## 9. Known MVP limitations

This repository was assembled as source code but could not be compiled in this environment because the Flutter and Dart SDKs are not installed here. Run `flutter pub get`, `flutter analyze`, and `flutter test` on your development machine after the Firebase and native platform setup. Resolve any SDK-specific package or Gradle differences reported by your installed Flutter stable release before shipping.
