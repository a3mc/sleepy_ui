import 'package:flutter/material.dart';

// Dark theme with Material Design 3
class AppTheme {
  static ThemeData get darkTheme {
    const ColorScheme colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFFF9800), // Orange for primary UI elements
      onPrimary: Color(0xFF000000),
      secondary: Color(0xFF4CAF50), // Green for healthy states
      onSecondary: Color(0xFF000000),
      error: Color(0xFFF44336), // Red for critical states
      onError: Color(0xFFFFFFFF),
      surface: Color(0xFF1E1E1E), // Dark surface
      onSurface: Color(0xFFE0E0E0),
      tertiary: Color(0xFF2196F3), // Blue for info
      onTertiary: Color(0xFF000000),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF121212),
      cardColor: const Color(0xFF1E1E1E),

      // Typography
      textTheme: const TextTheme(
        displayLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Color(0xFFE0E0E0)),
        displayMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Color(0xFFE0E0E0)),
        displaySmall: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFFE0E0E0)),
        headlineMedium: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Color(0xFFE0E0E0)),
        titleLarge: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFFE0E0E0)),
        titleMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Color(0xFFE0E0E0)),
        bodyLarge: TextStyle(fontSize: 16, color: Color(0xFFE0E0E0)),
        bodyMedium: TextStyle(fontSize: 14, color: Color(0xFFE0E0E0)),
        bodySmall: TextStyle(fontSize: 12, color: Color(0xFFB0B0B0)),
        labelLarge: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFFE0E0E0)),
      ),

      // Card theme
      cardTheme: const CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8))),
        color: Color(0xFF1E1E1E),
      ),

      // AppBar theme
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1E1E1E),
        foregroundColor: Color(0xFFE0E0E0),
        elevation: 0,
      ),
    );
  }

  // Status indication colors
  static const Color healthyColor = Color(0xFF4CAF50); // Green
  static const Color warningColor = Color(0xFFFFC107); // Yellow
  static const Color degradedColor = Color(0xFFFF9800); // Orange
  static const Color criticalColor = Color(0xFFF44336); // Red
  static const Color lossColor = Color(0xFF9E9E9E); // Gray
  static const Color unknownColor = Color(0xFF9E9E9E); // Gray

  // Chart colors
  static const Color ourValidatorColor = Color(0xFFFF9800); // Orange
  static const Color rank1Color = Color(0xFF9C27B0); // Purple
  static const Color top10Color = Color(0xFF00BCD4); // Cyan

  // Circular ring visualization colors (distance metrics)
  static const Color ringExcellentColor = Color(0xFF4CAF50); // Green
  static const Color ringGoodColor = Color(0xFF42A5F5); // Blue
  static const Color ringWarningColor = Color(0xFFFFB74D); // Orange
  static const Color ringCriticalColor = Color(0xFFD32F2F); // Red
  static const Color ringOverperformColor = Color(0xFF69F0AE); // Bright green

  // UI structural colors (cross-platform consistency)
  static const Color borderColor = Color(0xFF424242); // Borders, dividers
  static const Color cardBackgroundColor =
      Color(0xFF2A2A2A); // Card/panel backgrounds
  static const Color hintTextColor = Color(0xFF555555); // Placeholder/hint text
  static const Color secondaryTextColor =
      Color(0xFFAAAAAA); // Secondary text (WCAG compliant)

  // Gap visualization colors
  static const Color gapPositiveColor = Color(0xFF00FF88); // Green
  static const Color gapNegativeColor = Color(0xFFFF4444); // Red
  static const Color gapNeutralColor = Color(0xFF666666); // Gray
  static const Color rank1GapColor = Color(0xFF00AAFF); // Cyan
  static const Color rank100GapColor = Color(0xFFFF6666); // Red
  static const Color rank200GapColor = Color(0xFF00FF88); // Green
  static const Color goldColor = Color(0xFFFFD700); // Gold
  static const Color selectedChipColor = Color(0xFF00CCFF); // Cyan
  static const Color unselectedChipColor = Color(0xFF888888); // Gray

  // Phase state colors
  static const Color forkIdleColor = Color(0xFF4169E1); // Blue
  static const Color forkStabilizingColor = Color(0xFF00D9FF); // Cyan
  static const Color forkRankSamplingColor = Color(0xFFBB86FC); // Purple
  static const Color forkCreditsLossColor = Color(0xFFFF4081); // Pink

  // Alert state colors
  static const Color alertPendingColor =
      Color(0xFFFFB300); // Amber - alert pending
  static const Color alertSentColor = Color(0xFF4CAF50); // Green - alert sent

  // Background shades (dark theme hierarchy)
  static const Color backgroundDarker = Color(0xFF1A1A1A); // Card containers
  static const Color backgroundDarkest = Color(0xFF0A0A0A); // Overlays, modals
  static const Color backgroundElevated =
      Color(0xFF2A2A2A); // Elevated surfaces

  // Border shades (separation hierarchy)
  static const Color borderSubtle = Color(0xFF333333); // Subtle dividers
  static const Color borderDefault = Color(0xFF424242); // Standard borders
  static const Color borderEmphasized = Color(0xFF555555); // Emphasized borders

  // Text shades (readability hierarchy)
  static const Color textTertiary = Color(0xFF666666); // Least important text
  static const Color textQuaternary = Color(0xFF888888); // Decorative text
  static const Color textSecondaryAlt =
      Color(0xFFAAAAAA); // Alternative secondary

  // Win/loss indicator backgrounds
  static const Color winBackgroundColor = Color(0xFF1B3B1B); // Dark green
  static const Color winBorderColor = Color(0xFF2D5F2D); // Medium green
  static const Color lossBackgroundColor = Color(0xFF2A2A2A); // Dark gray
  static const Color lossBorderColor = Color(0xFF3F3F3F); // Medium gray

  // Rank tier colors
  static const Color rankTop100Color = Color(0xFF388E3C); // Green
  static const Color rankTop200Color = Color(0xFF1976D2); // Blue
  static const Color rankOutsideColor = Color(0xFF9E9E9E); // Gray

  // Special effect colors
  static const Color purpleAccent = Color(0xFF9370DB); // Medium purple
  static const Color royalBlueAccent = Color(0xFF4169E1); // Royal blue

  // Helper: Get fork phase color by phase name
  static Color getForkPhaseColor(String phase) {
    switch (phase) {
      case 'Idle':
        return forkIdleColor;
      case 'Stabilizing':
        return forkStabilizingColor;
      case 'RankSampling':
        return forkRankSamplingColor;
      case 'CreditsLoss':
        return forkCreditsLossColor;
      default:
        return unknownColor;
    }
  }

  // Helper: Get alert state color
  static Color getAlertColor(bool sent) =>
      sent ? alertSentColor : alertPendingColor;
}
