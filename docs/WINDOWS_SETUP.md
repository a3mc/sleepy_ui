# Windows Build Setup

**Requirements**: Visual Studio 2022, Windows 10 (1903+) or Windows 11  
**Target**: Windows desktop application

## Prerequisites

**Flutter SDK**: 3.38.5+ (Dart 3.10.4+)  
**Visual Studio**: 2022 or 2019 (16.11+)  
**Workload**: "Desktop development with C++"  
**Components**: MSVC v142/v143, Windows 10/11 SDK

## Visual Studio Setup

### Install Required Workload

1. Download Visual Studio 2022 Community (free): https://visualstudio.microsoft.com/downloads/
2. During installation, select **"Desktop development with C++"**
3. Ensure Windows 10/11 SDK is checked

### Verify Toolchain

```powershell
flutter doctor -v
```

Expected output:
```
[✓] Visual Studio - develop for Windows
```

## Build Commands

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

## Deployment

The `Release` folder contains all required files for deployment:

- `sleepy_ui.exe` (main executable)
- `flutter_windows.dll` (Flutter engine)
- `data\` folder (Flutter assets)
- Plugin DLLs (flutter_secure_storage_windows_plugin.dll, etc.)

**Copy the entire `Release` folder to the target machine.**

## Credential Storage

Windows uses plain text JSON storage at:
```
%APPDATA%\sleepy_ui\config.json
```

File permissions are managed by Windows directory ACLs.

## Troubleshooting

### Missing MSVC Components

**Issue**: `MSVC v142/v143 build tools not found`  
**Solution**: Run Visual Studio Installer → Modify → Desktop development with C++

### Windows SDK Not Found

**Issue**: `Windows SDK not found`  
**Solution**: Install via Visual Studio Installer → Individual Components → Windows 10/11 SDK

### Build Failures

**Issue**: CMake errors during build  
**Solution**: Clean build directory and retry:
```powershell
flutter clean
flutter pub get
flutter build windows --release
```

## References

- [Flutter: Windows Desktop Support](https://docs.flutter.dev/platform-integration/windows/building)
- [Visual Studio Downloads](https://visualstudio.microsoft.com/downloads/)
