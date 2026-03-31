import 'package:flutter/material.dart';

/// STASYS App Theme — Dark Professional Design
/// Deep navy background with cyan/teal glow accents
class AppTheme {
  // ========== COLORS ==========
  static const Color background = Color(0xFF0D0D1A);
  static const Color surface = Color(0xFF1A1A2E);
  static const Color surfaceLight = Color(0xFF242442);
  static const Color cardBorder = Color(0xFF2A2A4A);

  static const Color primary = Color(0xFF00D9FF);       // Cyan glow
  static const Color secondary = Color(0xFF7B61FF);     // Purple accent
  static const Color accent = Color(0xFF00FF88);        // Green accent

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8B8B9E);
  static const Color textTertiary = Color(0xFF5A5A6E);

  static const Color scoreElite = Color(0xFFFFD700);    // Gold
  static const Color scoreExpert = Color(0xFF00FF88);   // Green
  static const Color scoreAdvanced = Color(0xFF00D9FF);  // Cyan
  static const Color scoreIntermediate = Color(0xFFFFB800); // Amber
  static const Color scoreBeginner = Color(0xFFFF4757);  // Red

  static const Color success = Color(0xFF00FF88);
  static const Color warning = Color(0xFFFFB800);
  static const Color error = Color(0xFFFF4757);

  static const Color glowCyan = Color(0x3300D9FF);     // 20% opacity for glow
  static const Color glowPurple = Color(0x337B61FF);

  // Phase colors for muzzle trace
  static const Color phaseHold = Color(0xFFFF4444);
  static const Color phasePress = Color(0xFFFFFF44);
  static const Color phaseRecoil = Color(0xFF44FFFF);

  // ========== GLOW DECORATIONS ==========
  static BoxDecoration cardDecoration({Color? borderColor, bool glow = false}) {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: borderColor ?? cardBorder,
        width: 1,
      ),
      boxShadow: glow
          ? [
              BoxShadow(
                color: primary.withValues(alpha: 0.15),
                blurRadius: 20,
                spreadRadius: 0,
              ),
            ]
          : null,
    );
  }

  static BoxDecoration primaryGlowBox({double blur = 20, Color? color}) {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: primary.withValues(alpha: 0.5), width: 1),
      boxShadow: [
        BoxShadow(
          color: (color ?? primary).withValues(alpha: 0.25),
          blurRadius: blur,
          spreadRadius: 0,
        ),
      ],
    );
  }

  static BoxDecoration gradientCard() {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          surface,
          surfaceLight.withValues(alpha: 0.5),
        ],
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: cardBorder, width: 1),
    );
  }

  static BoxDecoration bottomNavDecoration(int currentIndex, int index) {
    final isActive = currentIndex == index;
    return BoxDecoration(
      color: isActive
          ? primary.withValues(alpha: 0.15)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      border: isActive
          ? Border.all(color: primary.withValues(alpha: 0.4), width: 1)
          : null,
    );
  }

  // ========== TEXT STYLES ==========
  static const TextStyle heading = TextStyle(
    color: textPrimary,
    fontSize: 28,
    fontWeight: FontWeight.bold,
    letterSpacing: 1,
  );

  static const TextStyle title = TextStyle(
    color: textPrimary,
    fontSize: 20,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle subtitle = TextStyle(
    color: textSecondary,
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle body = TextStyle(
    color: textPrimary,
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle label = TextStyle(
    color: textSecondary,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.2,
  );

  static const TextStyle statValue = TextStyle(
    color: textPrimary,
    fontSize: 32,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle statLabel = TextStyle(
    color: textSecondary,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
  );

  static const TextStyle timerDisplay = TextStyle(
    color: textPrimary,
    fontSize: 80,
    fontWeight: FontWeight.bold,
    fontFamily: 'monospace',
    letterSpacing: 2,
  );

  static const TextStyle scoreDisplay = TextStyle(
    color: textPrimary,
    fontSize: 48,
    fontWeight: FontWeight.bold,
  );

  // ========== SCORE COLOR ==========
  static Color getScoreColor(double score) {
    if (score >= 95) return scoreElite;
    if (score >= 85) return scoreExpert;
    if (score >= 70) return scoreAdvanced;
    if (score >= 50) return scoreIntermediate;
    return scoreBeginner;
  }

  static String getScoreLabel(double score) {
    if (score >= 95) return 'Elite';
    if (score >= 85) return 'Expert';
    if (score >= 70) return 'Advanced';
    if (score >= 50) return 'Intermediate';
    return 'Beginner';
  }

  // ========== FLUTTER THEME DATA ==========
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: surface,
        error: error,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: cardBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: background,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: textSecondary,
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      iconTheme: const IconThemeData(color: textSecondary),
      dividerTheme: const DividerThemeData(
        color: cardBorder,
        thickness: 1,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return primary.withValues(alpha: 0.15);
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return primary;
            }
            return textSecondary;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return BorderSide(color: primary.withValues(alpha: 0.5), width: 1);
            }
            return const BorderSide(color: cardBorder, width: 1);
          }),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: cardBorder,
        thumbColor: primary,
        overlayColor: primary.withValues(alpha: 0.2),
        valueIndicatorColor: primary,
        valueIndicatorTextStyle: const TextStyle(
          color: background,
          fontWeight: FontWeight.bold,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: const TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: title,
        contentTextStyle: body,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        showSelectedLabels: true,
        showUnselectedLabels: true,
      ),
      listTileTheme: const ListTileThemeData(
        textColor: textPrimary,
        iconColor: textSecondary,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primary,
      ),
    );
  }
}
