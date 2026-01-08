# Release Build Guide

**Version**: 1.1.0+2  
**Supported Platforms**: Android, Linux, macOS, Windows

## Prerequisites

- Flutter SDK 3.38.5+ (Dart 3.10.4+)
- Platform-specific toolchains (see platform setup guides)
- Release signing keys (Android only)

## Android

```bash
flutter build apk --debug
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`

## Linux

```bash
flutter build linux --release
```

Output: `build/linux/x64/release/bundle/`

## macOS

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

## Windows

### Debug Build

```powershell
flutter build windows --debug
```

Output: `build\windows\x64\runner\Debug\sleepy_ui.exe`

### Release Build

```powershell
flutter build windows --release
```

Output: `build\windows\x64\runner\Release\sleepy_ui.exe`

**Distribution**: Copy entire `Release` folder to target machine.
