## 0.1.2

- Added a refresh button to the SDK header so users can manually reload the verification page.
- When camera/microphone/location permissions are granted, the SDK now automatically reloads the page once so the WebView can detect updated permissions.

## 0.1.1

- **Breaking:** Replaced `webview_flutter` with `flutter_inappwebview` for camera/mic/location in WebView.
- Added `onPermissionRequest` and `onGeolocationPermissionsShowPrompt` so the WebView receives camera, microphone, and location access when the app has already been granted these permissions (fixes white/blank camera screen on iOS and Android).
- Updated to `InAppWebViewSettings` and `onReceivedError` (replacing deprecated `initialOptions` and `onLoadError`).

## 0.1.0

- Initial release of the `meon_face_verification` Flutter SDK.
- Provides Meon face verification flow using WebView, permissions handling, and result modal UI.

