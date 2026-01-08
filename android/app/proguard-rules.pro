# Flutter ProGuard rules for release builds
# Keep Flutter engine classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep Dart VM service classes
-keep class dev.flutter.** { *; }

# Keep native methods
-keepclassmembers class * {
    native <methods>;
}

# Keep Parcelable implementations
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Secure storage plugin
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Window manager plugin
-keep class com.leanflutter.window_manager.** { *; }

# Wakelock Plus plugin
-keep class dev.fluttercommunity.plus.wakelock.** { *; }
-keep class com.google.android.gms.common.** { *; }

# Ignore missing Play Store classes (not needed for sideloading)
-dontwarn com.google.android.play.**
-keep class com.google.android.play.** { *; }
