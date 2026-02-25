# Meon Face Verification Flutter SDK

Flutter SDK that mirrors the existing React Native `MeonFaceVerification` component.  
It handles:

- Generating a token using your `clientId` and `clientSecret`
- Initiating a verification request
- Opening the Meon verification flow in a WebView
- Handling permissions (camera, microphone, location)
- Detecting completion from the URL
- Exporting verification data and returning it to your app
- Showing a modern result screen with captured/reference images and metadata

## Installation

1. Copy the folder `flutter-meon-face-verification-sdk` to a convenient location (already created on your Desktop).
2. Add a path dependency in your app’s `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter

  meon_face_verification:
    path: ../flutter-meon-face-verification-sdk
```

Adjust the relative `path` as needed.

3. Run:

```bash
flutter pub get
```

## Android & iOS setup

This package uses:

- `webview_flutter`
- `permission_handler`

Make sure your platform-specific permission configuration is correct:

- **Android**: Add camera, microphone, and location permissions in `AndroidManifest.xml`.
- **iOS**: Add the relevant `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, and `NSLocationWhenInUseUsageDescription` keys in `Info.plist`.

Refer to each plugin’s README for the latest platform setup details.

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:meon_face_verification/meon_face_verification.dart';

class FaceVerificationScreen extends StatelessWidget {
  const FaceVerificationScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MeonFaceVerification(
        clientId: 'YOUR_CLIENT_ID',
        clientSecret: 'YOUR_CLIENT_SECRET',
        onSuccess: (data) {
          // Handle success result data
          // e.g. print(data);
        },
        onError: (message) {
          // Handle error
          // e.g. show a toast/snackbar
        },
        onClose: () {
          // Called when user exits/finishes flow
          Navigator.of(context).pop();
        },
        // Optional:
        // showHeader: true,
        // headerTitle: 'Face Verification',
        // baseUrl: 'https://face-finder.meon.co.in',
        // autoRequestPermissions: true,
        // verificationConfig: const VerificationConfig(
        //   checkLocation: false,
        //   captureVideo: false,
        //   matchFace: false,
        //   readScript: false,
        //   textScript: "Please complete the verification process",
        //   videoTime: 10,
        //   imageToBeMatch: "",
        // ),
      ),
    );
  }
}
```

The `VerificationConfig` maps directly to your existing React Native `verificationConfig` object.

## Notes

- The Flutter SDK injects the same permission-handling JavaScript into the WebView as your React Native version, so the behavior from the web app’s point of view remains consistent.
- URL completion detection uses the same logic: it looks for `success`, `complete`, or `finished` in the URL and then calls the export API.

