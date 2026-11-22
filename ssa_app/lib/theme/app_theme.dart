import 'package:flutter/material.dart';

// ============================================
// STSYS Dark Theme — Figma-based design tokens
// ============================================

class StsysTheme {
  // --- Color Palette (from Figma) ---
  static const Color background = Color(0xFF080A0C);
  static const Color surfaceContainerLowest = Color(0xFF080B0E);

  // Mobile shell tokens from the Figma train-flow redesign.
  static const Color mobileBackground = Color(0xFF0C0E11);
  static const Color mobileSurface = Color(0xFF111418);
  static const Color mobileBorder = Color(0xFF1F242C);
  static const Color cyan = Color(0xFF00E5FF);
  static const Color liveRed = Color(0xFFFF4D5A);
  static const Color successGreen = Color(0xFF39D98A);
  static const Color mobileMutedText = Color(0xFF8B8B8B);
  static const Color surfaceContainerLow = Color(0xFF111418);
  static const Color surfaceContainer = Color(0xFF15191E);
  static const Color surfaceContainerHigh = Color(0xFF1B2027);
  static const Color surfaceContainerHighest = Color(0xFF232932);
  static const Color surfaceBright = Color(0xFF2C333C);
  static const Color surfaceDim = Color(0xFF0C0E11);
  static const Color mobileHeaderTrain = Color(0xFF102A35);
  static const Color mobileHeaderHistory = Color(0xFF241C35);
  static const Color mobileHeaderTracking = Color(0xFF18332E);
  static const Color mobileHeaderSettings = Color(0xFF1B2027);

  // The mobile redesign uses a near-white shell in light mode while keeping
  // the existing Night Ops palette unchanged in dark mode. These accessors
  // are intentionally limited to shell tokens; status and score colors stay
  // semantic and shared between themes.
  static bool isLight(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  static Color mobileBackgroundOf(BuildContext context) =>
      isLight(context) ? const Color(0xFFF7F9FB) : mobileBackground;
  static Color mobileSurfaceOf(BuildContext context) =>
      isLight(context) ? Colors.white : mobileSurface;
  static Color mobileBorderOf(BuildContext context) =>
      isLight(context) ? const Color(0xFFD9E0E5) : mobileBorder;
  static Color mobileMutedTextOf(BuildContext context) =>
      isLight(context) ? const Color(0xFF64748B) : mobileMutedText;
  static Color cyanOf(BuildContext context) =>
      isLight(context) ? const Color(0xFF008FA3) : cyan;
  static Color primaryOf(BuildContext context) =>
      isLight(context) ? const Color(0xFF008FA3) : primary;
  static Color onPrimaryOf(BuildContext context) =>
      isLight(context) ? Colors.white : onPrimary;

  /// Colour for text and icons drawn on top of the STASYS brand and tactical
  /// gradients. Those gradients are fixed brand colours and do not change
  /// with the theme, so the "on" colour has to stay fixed as well to keep
  /// the contrast — a white label would vanish on the cyan half of the
  /// brand gradient and on the orange tactical gradient.
  static Color onGradientOf(BuildContext context) => const Color(0xFF00252C);
  static Color onSurfaceOf(BuildContext context) =>
      isLight(context) ? const Color(0xFF17202A) : onSurface;
  static Color errorOf(BuildContext context) =>
      isLight(context) ? const Color(0xFFBA1A1A) : error;
  static Color onSurfaceVariantOf(BuildContext context) =>
      isLight(context) ? const Color(0xFF536273) : onSurfaceVariant;
  static Color surfaceContainerLowOf(BuildContext context) =>
      isLight(context) ? Colors.white : surfaceContainerLow;
  static Color surfaceContainerHighOf(BuildContext context) =>
      isLight(context) ? const Color(0xFFF1F4F6) : surfaceContainerHigh;
  static Color surfaceContainerHighestOf(BuildContext context) =>
      isLight(context) ? const Color(0xFFE3E8EC) : surfaceContainerHighest;
  static Color outlineVariantOf(BuildContext context) =>
      isLight(context) ? const Color(0xFFC0C7CB) : outlineVariant;
  static Color mobileHeaderOf(BuildContext context, Color darkColor) =>
      isLight(context) ? const Color(0xFFF2F7F9) : darkColor;

  /// Secondary accent. The dark palette uses the pale blue accent, which is
  /// unreadable on a light surface, so light mode uses a deeper blue.
  static Color secondaryOf(BuildContext context) =>
      isLight(context) ? const Color(0xFF0B6FA4) : secondary;

  /// Lowest surface — the page/background level behind cards.
  static Color surfaceContainerLowestOf(BuildContext context) =>
      isLight(context) ? const Color(0xFFF5F7FA) : surfaceContainerLowest;

  /// Score chip / badge fill that must stay legible on a light surface.
  static Color scoreChipFillOf(BuildContext context) =>
      isLight(context) ? const Color(0xFFE8EDF1) : surfaceContainerHighest;

  /// Page background behind the shell — the Scaffold fill.
  static Color backgroundOf(BuildContext context) =>
      isLight(context) ? const Color(0xFFF5F7FA) : background;

  /// Container tint used behind the active navigation item.
  static Color primaryContainerOf(BuildContext context) =>
      isLight(context) ? const Color(0xFF9DEBFA) : primaryContainer;

  /// Tertiary accent for the statistic boxes. The dark palette uses a pale
  /// blue that would disappear on the light shell, so light mode uses a
  /// deeper tone of the same hue.
  static Color tertiaryOf(BuildContext context) =>
      isLight(context) ? const Color(0xFF2F5D8C) : tertiary;

  // The primary accent follows the Figma mobile direction: cyan for actions
  // and headings, slate for the neutral chrome. The earlier warm orange
  // palette clashed with the cyan shell, so every token below now belongs to
  // the same cool family.
  static const Color primary = Color(0xFF00E5FF);
  static const Color primaryContainer = Color(0xFF008FA3);
  static const Color primaryFixed = Color(0xFF9DEBFA);
  static const Color primaryFixedDim = Color(0xFF00E5FF);
  static const Color onPrimary = Color(0xFF00363F);
  static const Color onPrimaryContainer = Color(0xFF001F26);

  static const Color secondary = Color(0xFF4D7CFE);
  static const Color secondaryContainer = Color(0xFF0CB3FF);
  static const Color secondaryFixed = Color(0xFFC9E6FF);
  static const Color secondaryFixedDim = Color(0xFF8BCEFF);
  static const Color onSecondary = Color(0xFF00287A);
  static const Color onSecondaryContainer = Color(0xFF004261);

  static const Color tertiary = Color(0xFF94A3B8);
  static const Color tertiaryContainer = Color(0xFF059EFF);
  static const Color tertiaryFixed = Color(0xFFD0E4FF);
  static const Color tertiaryFixedDim = Color(0xFF9CCAff);
  static const Color onTertiary = Color(0xFF334155);
  static const Color onTertiaryContainer = Color(0xFF003357);
  static const Color onTertiaryFixed = Color(0xFF001D35);
  static const Color onTertiaryFixedVariant = Color(0xFF00497B);

  static const Color error = Color(0xFFFF6B6B);
  static const Color errorContainer = Color(0xFF93000A);
  static const Color onError = Color(0xFF690005);
  static const Color onErrorContainer = Color(0xFFFFDAD6);

  static const Color surface = Color(0xFF0C0E11);
  static const Color onSurface = Color(0xFFF1F5F9);
  static const Color surfaceVariant = Color(0xFF1F242C);
  static const Color onSurfaceVariant = Color(0xFFC0CAD8);
  static const Color surfaceTint = Color(0xFF00E5FF);
  static const Color inverseSurface = Color(0xFFF1F5F9);
  static const Color onInverseSurface = Color(0xFF1F242C);
  static const Color inversePrimary = Color(0xFF008FA3);

  static const Color outline = Color(0xFF475569);
  static const Color outlineVariant = Color(0xFF1F242C);

  // --- Tactical Gradient ---
  // The cyan-to-blue ramp mirrors the brand gradient so a single accent
  // language runs through the whole app.
  static const LinearGradient tacticalGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Brand gradient is reserved for STASYS identity; status and score colors
  // remain semantic and are intentionally not derived from this gradient.
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFF00E5FF), Color(0xFF4D7CFE)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // --- Score Colors ---
  static Color getScoreColor(double score) {
    if (score >= 95) return const Color(0xFFFFD700); // Elite - Gold
    if (score >= 85) return const Color(0xFF4CAF50); // Expert - Green
    if (score >= 70) return const Color(0xFF2196F3); // Advanced - Blue
    if (score >= 50) return const Color(0xFF00E5FF); // Intermediate - Cyan
    return const Color(0xFFF44336); // Beginner - Red
  }

  // --- Light Theme Data ---
  static ThemeData get lightTheme {
    const lightBackground = Color(0xFFF5F7FA);
    const lightOnSurface = Color(0xFF17202A);
    const lightPrimary = Color(0xFF007C91);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBackground,
      colorScheme: const ColorScheme.light(
        primary: lightPrimary,
        onPrimary: Colors.white,
        primaryContainer: Color(0xFF9DEBFA),
        onPrimaryContainer: Color(0xFF001F26),
        secondary: lightPrimary,
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFB9EBF2),
        onSecondaryContainer: Color(0xFF001F24),
        surface: Colors.white,
        onSurface: lightOnSurface,
        error: Color(0xFFBA1A1A),
        onError: Colors.white,
        outline: Color(0xFF70777B),
        outlineVariant: Color(0xFFC0C7CB),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: lightBackground,
        foregroundColor: lightOnSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: lightPrimary,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: lightPrimary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: lightPrimary),
      ),
      iconTheme: const IconThemeData(color: lightOnSurface, size: 24),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFC0C7CB),
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: lightOnSurface,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: lightOnSurface,
        unselectedLabelColor: Color(0xFF4B5357),
      ),
    );
  }

  // --- Dark Theme Data ---
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        brightness: Brightness.dark,
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        secondary: secondary,
        onSecondary: onSecondary,
        secondaryContainer: secondaryContainer,
        onSecondaryContainer: onSecondaryContainer,
        tertiary: tertiary,
        onTertiary: onTertiary,
        tertiaryContainer: tertiaryContainer,
        onTertiaryContainer: onTertiaryContainer,
        error: error,
        onError: onError,
        errorContainer: errorContainer,
        onErrorContainer: onErrorContainer,
        surface: surface,
        onSurface: onSurface,
        surfaceContainerHighest: surfaceContainerHighest,
        surfaceContainerHigh: surfaceContainerHigh,
        surfaceContainer: surfaceContainer,
        surfaceContainerLow: surfaceContainerLow,
        surfaceContainerLowest: surfaceContainerLowest,
        outline: outline,
        outlineVariant: outlineVariant,
        inverseSurface: inverseSurface,
        onInverseSurface: onInverseSurface,
        shadow: Colors.black,
        scrim: Colors.black,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 20,
          fontWeight: FontWeight.w900,
          color: primary,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: background,
        selectedItemColor: primary,
        unselectedItemColor: Color(0xFFC0CAD8),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryContainer,
          foregroundColor: onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),
      iconTheme: const IconThemeData(color: onSurface, size: 24),
      dividerTheme: DividerThemeData(
        color: outlineVariant.withValues(alpha: 0.3),
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceContainerHighest,
        contentTextStyle: const TextStyle(color: onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: onSurface,
        unselectedLabelColor: Color(0xFFC0CAD8),
      ),
    );
  }
}

// ============================================
// Reusable Text Styles
// ============================================
class StsysText {
  // Headlines
  // The colour lives in the `*Of(context)` variants below. The const
  // variants keep the dark-palette colour and therefore only suit dark
  // surfaces — on the light shell they would be unreadable.
  static const headline = TextStyle(
    fontFamily: 'Manrope',
    fontWeight: FontWeight.w900,
    color: StsysTheme.onSurface,
  );

  static TextStyle headlineOf(BuildContext context) =>
      headline.copyWith(color: StsysTheme.onSurfaceOf(context));

  static const headlineBold = TextStyle(
    fontFamily: 'Manrope',
    fontWeight: FontWeight.w800,
    color: StsysTheme.onSurface,
  );

  static TextStyle headlineBoldOf(BuildContext context) =>
      headlineBold.copyWith(color: StsysTheme.onSurfaceOf(context));

  // Body
  static const body = TextStyle(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w400,
    color: StsysTheme.onSurface,
  );

  static TextStyle bodyOf(BuildContext context) =>
      body.copyWith(color: StsysTheme.onSurfaceOf(context));

  static const bodyBold = TextStyle(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w600,
    color: StsysTheme.onSurface,
  );

  static TextStyle bodyBoldOf(BuildContext context) =>
      bodyBold.copyWith(color: StsysTheme.onSurfaceOf(context));

  // Labels (uppercase, tracking)
  static const label = TextStyle(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w500,
    fontSize: 10,
    letterSpacing: 1.5,
    color: StsysTheme.onSurfaceVariant,
  );

  static TextStyle labelOf(BuildContext context) =>
      label.copyWith(color: StsysTheme.onSurfaceVariantOf(context));

  static TextStyle labelBoldOf(BuildContext context, Color color) =>
      labelBold.copyWith(color: color);

  static const labelBold = TextStyle(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w700,
    fontSize: 10,
    letterSpacing: 1.5,
    color: StsysTheme.onSurfaceVariant,
  );

  // Score display
  static TextStyle scoreDisplay(double score) {
    return TextStyle(
      fontFamily: 'Manrope',
      fontWeight: FontWeight.w900,
      fontSize: 72,
      color: StsysTheme.getScoreColor(score),
    );
  }
}

// ============================================
// Reusable Surface Container Cards
// ============================================
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final double borderRadius;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final VoidCallback? onTap;

  const SurfaceCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 12,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor ?? StsysTheme.surfaceContainerLowOf(context),
        borderRadius: BorderRadius.circular(borderRadius),
        border: borderColor != null
            ? Border.all(color: borderColor!, width: borderWidth)
            : null,
      ),
      child: child,
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: card);
    }
    return card;
  }
}

// ============================================
// Tactical Gradient Button
// ============================================
class TacticalButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isActive;
  final IconData? icon;
  final EdgeInsets? padding;

  const TacticalButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isActive = false,
    this.icon,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding:
            padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: isActive ? StsysTheme.tacticalGradient : null,
          color: isActive ? null : StsysTheme.surfaceContainerHighOf(context),
          borderRadius: BorderRadius.circular(8),
          border: isActive
              ? null
              : Border.all(
                  color: StsysTheme.outlineVariantOf(context)
                      .withValues(alpha: 0.2),
                  width: 1,
                ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                color: isActive
                    ? StsysTheme.onGradientOf(context)
                    : StsysTheme.onSurfaceOf(context).withValues(alpha: 0.6),
                size: 18,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Manrope',
                fontWeight: FontWeight.w800,
                fontSize: 12,
                letterSpacing: 1,
                color: isActive
                    ? StsysTheme.onGradientOf(context)
                    : StsysTheme.onSurfaceOf(context).withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// Status Badge (CONNECTED / DISCONNECTED)
// ============================================
class StatusBadge extends StatelessWidget {
  final bool isConnected;
  final String? deviceName;
  final bool mutedDisconnected;

  const StatusBadge({
    super.key,
    required this.isConnected,
    this.deviceName,
    this.mutedDisconnected = false,
  });

  @override
  Widget build(BuildContext context) {
    // The status colours are semantic and shared between themes, but the
    // muted variant has to follow the shell so it stays readable.
    final primary = StsysTheme.primaryOf(context);
    final cyan = StsysTheme.cyanOf(context);
    final error = StsysTheme.errorOf(context);
    final muted = StsysTheme.mobileMutedTextOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isConnected
            ? primary.withValues(alpha: 0.15)
            : (mutedDisconnected
                  ? cyan.withValues(alpha: 0.08)
                  : error.withValues(alpha: 0.15)),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isConnected
              ? primary.withValues(alpha: 0.3)
              : (mutedDisconnected
                    ? cyan.withValues(alpha: 0.2)
                    : error.withValues(alpha: 0.3)),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isConnected
                  ? primary
                  : (mutedDisconnected ? cyan : error),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isConnected ? (deviceName ?? 'CONNECTED') : 'DISCONNECTED',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: isConnected
                  ? primary
                  : (mutedDisconnected ? muted : error),
            ),
          ),
        ],
      ),
    );
  }
}
