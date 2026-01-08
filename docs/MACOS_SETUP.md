# macOS Build Setup

**Requirements**: Xcode, macOS 10.14+  
**Target**: macOS desktop application

## Prerequisites

**Flutter SDK**: 3.38.5+ (Dart 3.10.4+)  
**Xcode**: Latest stable version  
**CocoaPods**: Ruby gem for dependency management

## Initial Setup

### Install Xcode Command Line Tools

```bash
xcode-select --install
```

### Install CocoaPods

```bash
sudo gem install cocoapods
```

### Add macOS Platform Support

If macOS platform not already added:

```bash
cd /path/to/sleepy_ui
flutter create . --platforms=macos
```

### Verify Toolchain

```bash
flutter doctor -v
```

Expected output:
```
[✓] Xcode - develop for iOS and macOS
```

## Build Commands

### Debug Build

```bash
flutter build macos --debug
```

Output: `build/macos/Build/Products/Debug/sleepy_ui.app`

### Release Build

```bash
flutter build macos --release
```

Output: `build/macos/Build/Products/Release/sleepy_ui.app`

## Running the Application

### From Command Line

```bash
flutter run -d macos
```

### From Build Output

```bash
open build/macos/Build/Products/Release/sleepy_ui.app
```

## Credential Storage

macOS uses plain text JSON storage at:
```
~/Library/Application Support/sleepy_ui/config.json
```

File permissions are managed by macOS directory ACLs.

## Troubleshooting

### Pod Install Failures

**Issue**: CocoaPods dependencies fail to install  
**Solution**: Update CocoaPods and clear cache:
```bash
cd macos
pod repo update
pod install --repo-update
```

### Code Signing Issues

**Issue**: `Code signing is required`  
**Solution**: Open `macos/Runner.xcworkspace` in Xcode and configure signing team.

### Build Failures

**Issue**: Xcode version mismatch  
**Solution**: Update Xcode via Mac App Store and accept license:
```bash
sudo xcodebuild -license accept
```

## References

- [Flutter: macOS Desktop Support](https://docs.flutter.dev/platform-integration/macos/building)
- [Apple Developer: Xcode](https://developer.apple.com/xcode/)
