# Android Build Setup

**Requirements**: Android SDK API 34, Java 17  
**Minimum Target**: Android 5.0 (API 21+)

## Prerequisites

**Flutter SDK**: 3.38.5+ (Dart 3.10.4+)  
**Android SDK**: API Level 34  
**Build Tools**: 34.0.0  
**Java**: OpenJDK 17 or later

## Command Line Setup

### Install Android Command Line Tools

```bash
cd $ANDROID_HOME

# Download cmdline-tools from:
# https://developer.android.com/studio#command-line-tools-only

# Extract to correct location
unzip commandlinetools-*.zip
mkdir -p cmdline-tools/latest
mv cmdline-tools/* cmdline-tools/latest/
```

### Install SDK Components

```bash
export ANDROID_HOME=/path/to/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools

# Update SDK
sdkmanager --update

# Install API 34 components
sdkmanager "platforms;android-34" "build-tools;34.0.0" "platform-tools"

# Accept licenses
flutter doctor --android-licenses
```

### Verify Toolchain

```bash
flutter doctor -v
```

Expected output:
```
[✓] Android toolchain - develop for Android devices (Android SDK version 34.0.0)
```

## Build Commands

### Debug APK

```bash
flutter build apk --debug
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`

### Release APK

Requires signing configuration (see Release Signing section).

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

### Android App Bundle (Play Store)

```bash
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`

## Android Studio Setup (Alternative)

### 1. Install Android Studio

```bash
# Download from https://developer.android.com/studio
# Or use snap:
sudo snap install android-studio --classic

# Launch
android-studio
```

### 2. SDK Setup (Automatic)

1. First launch: "Install Type" → "Standard"
2. Accept licenses
3. Wait for SDK download (6-8 GB)
4. Tools → SDK Manager → Install:
   - Android SDK Platform 34
   - Android SDK Build-Tools 34.0.0
   - Android Emulator (optional, for testing)

### 3. Flutter Integration

```bash
# In Android Studio:
# File → Settings → Plugins → Install "Flutter" plugin
# Restart Android Studio
```

### 4. Build from Command Line

```bash
cd /path/to/sleepy_ui
flutter build apk --release
```

**OR** build from Android Studio:
- Open project in Android Studio
- Build → Flutter → Build APK

## Testing on Device

### Permissions (AndroidManifest.xml)

Already added by `flutter create`:
```xml
<uses-permission android:name="android.permission.INTERNET" />
```

**Needed for SSE connection** ✅

### Package Name

Default: `com.example.sleepy_ui`

**Change before release**:
```bash
# Edit android/app/build.gradle.kts
namespace = "com.artemiscloud.sleepy_ui"  # Change this
applicationId = "com.artemiscloud.sleepy_ui"  # And this
```

### App Name

```bash
# Edit android/app/src/main/AndroidManifest.xml
android:label="SLEEPY UI"  # Change from "sleepy_ui"
```

### Version

```bash
# Edit pubspec.yaml
version: 1.0.0+1  # Format: X.Y.Z+buildNumber
```

Flutter converts this to Android versionCode and versionName automatically.

---

## Build Types

### Debug APK (Development)

```bash
flutter build apk --debug
# Output: build/app/outputs/flutter-apk/app-debug.apk
# Size: ~60-80 MB (includes debug symbols)
# Use for: Testing, development
# Install: adb install app-debug.apk
```

### Release APK (Distribution)

```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk  
# Size: ~20-30 MB (optimized)
# Use for: Sideloading, direct distribution
# Install: adb install app-release.apk
```

### Release AAB (Play Store)

```bash
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
# Size: ~18-25 MB
# Use for: Google Play Store upload only
# Cannot install directly - Play Store generates APKs
```

---

## Testing on Device

1. Enable Developer Options:
   - Settings → About Phone → Tap "Build Number" 7 times

2. Enable USB Debugging:
   - Settings → Developer Options → USB Debugging

3. Connect device via USB:
   ```bash
   flutter devices
   ```

4. Run app:
   ```bash
   flutter run
   ```

## Troubleshooting

**License errors**: `flutter doctor --android-licenses`

**Build failures**: `flutter clean && flutter pub get`

**Device not detected**: Enable USB debugging, check cable
