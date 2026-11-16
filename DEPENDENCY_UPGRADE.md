# Dependency upgrade - 2026-11-16

## Toolchain and packages

- Flutter 3.50.0 stable / Dart 3.14.0; SDK requirements declared in pubspec.yaml.
- Java 27; Android Gradle Plugin 9.5.1; Gradle 9.9.1.
- Kotlin 2.4.21; Google Services plugin 4.6.0; desugar_jdk_libs 2.1.5.
- Android compile/target SDK 37; NDK 30.0.15729638 shared across Android modules.
- Android Java/Kotlin bytecode targets 17 while the Gradle runtime uses Java 27.
- iOS deployment target 15; macOS deployment target 12, matching updated native plugins.
- All direct runtime packages use their latest stable published versions at migration time.
- Material UI moved from deprecated Flutter imports to material_ui 1.11.0.
- Google Sign-In uses the version 7 singleton/initialization/authentication API.
- Full resolved versions are checked into pubspec.lock.

## Compatibility limits

- Hive 2.2.3 / hive_flutter 1.1.0 / hive_generator 2.0.1 are still their latest stable releases.
  Hive's generator constrains analyzer/build_runner. The resolver selects build_runner 2.4.13;
  forcing 2.17.1 would require replacing the existing generator/storage ecosystem.
  Code generation is restricted to the two Hive models in build.yaml and was verified.
- Some transitive dependencies are pinned by Flutter or other packages. No dependency_overrides
  are used to bypass compatibility checks.
- Firebase Messaging's token API is retained for the existing backend's HTTP v1 token contract.
  The newer installation-registration API requires coordinated push delivery changes.
- Android currently retains the external Kotlin plugin with Flutter's legacy DSL compatibility
  flags because this remains supported by the current plugin ecosystem. Flutter emits a
  future-migration warning for built-in Kotlin; the compiler itself is updated to 2.4.21.

## Existing installations

Secure Storage 11 removed legacy Android ciphers used before version 10.
Users updating directly from this app's previous Secure Storage 9 version may need to sign in again.
Preserving their existing login requires a separately distributed version 10 bridge release
that reads/migrates their storage before version 11 is installed; merely installing version 10
on the developer machine does not migrate end-user devices.
Hive user data and pending offline actions retain their existing formats and storage keys.
Test upgrades on a device with existing data, including offline actions, before distribution.

## Verification

Run flutter analyze, flutter test, and flutter build apk --debug with the new SDK.
Verified: all 55 tests and the production Web build pass. Analysis has no errors/warnings;
two Firebase deprecation infos remain because the backend still uses registration tokens.
The Android debug APK build and Hive adapter generation also pass.
iOS builds require macOS/Xcode; real Google login, push delivery, and storage upgrade behavior
need device tests and are not established by widget/unit tests alone.
Windows desktop compilation is not verified: flutter doctor reports missing Visual Studio
C++/CMake/Windows SDK components on this machine.
