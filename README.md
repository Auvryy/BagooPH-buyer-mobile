# BagooPH Buyer Mobile

Flutter application for the BagooPH buyer experience. The initial project includes Android and iOS targets; buyer features will be added in later work.

## Requirements

- Flutter stable with Dart SDK `^3.13.1` (see `pubspec.yaml`)
- Android development: Android SDK and a compatible JDK
- iOS development and builds: macOS with Xcode

Check the local toolchain with:

```sh
flutter --version
flutter doctor -v
```

## Run locally

From this repository directory:

```sh
flutter pub get
flutter devices
flutter run -d <device-id>
```

Choose a device ID printed by `flutter devices`. To let Flutter choose the connected device, run `flutter run` without `-d`.

## Verify and build

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug
```

For an Android release bundle, use `flutter build appbundle`. iOS builds require macOS and Xcode; on that machine use `flutter build ios --no-codesign` for a local build without signing.
