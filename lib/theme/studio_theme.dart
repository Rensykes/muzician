import 'package:flutter/material.dart';

import '../models/app_theme_variant.dart';
import 'muzician_theme.dart';

/// Immutable presentation tokens. Musical state always lives outside the theme.
@immutable
class StudioPalette extends ThemeExtension<StudioPalette> {
  const StudioPalette._({
    required this.scaffoldBg,
    required this.surface,
    required this.dialogBg,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textDim,
    required this.sky,
    required this.teal,
    required this.violet,
    required this.purple,
    required this.emerald,
    required this.orange,
    required this.red,
    required this.glassBg,
    required this.glassBorder,
    required this.onAccent,
    required this.gradientColors,
    required this.isStudio,
  });

  final Color scaffoldBg;
  final Color surface;
  final Color dialogBg;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textDim;
  final Color sky;
  final Color teal;
  final Color violet;
  final Color purple;
  final Color emerald;
  final Color orange;
  final Color red;
  final Color glassBg;
  final Color glassBorder;
  final Color onAccent;
  final List<Color> gradientColors;
  final bool isStudio;

  /// Existing unthemed hosts deliberately retain the legacy presentation.
  static StudioPalette of(BuildContext context) =>
      Theme.of(context).extension<StudioPalette>() ?? legacy;

  static const studio = StudioPalette._(
    scaffoldBg: Color(0xFF171C1B),
    surface: Color(0xFF1D2421),
    dialogBg: Color(0xFF242B29),
    textPrimary: Color(0xFFF1F5F3),
    textSecondary: Color(0xFFB5C3BC),
    textMuted: Color(0xFF99ABA1),
    textDim: Color(0xFF63756B),
    sky: Color(0xFF9EE7BF),
    teal: Color(0xFF72C7AF),
    violet: Color(0xFFC5CFAB),
    purple: Color(0xFFC5CFAB),
    emerald: Color(0xFFE5C07B),
    orange: Color(0xFFF0B86E),
    red: Color(0xFFF08B88),
    glassBg: Color(0xFF242B29),
    glassBorder: Color(0xFF45534C),
    onAccent: Color(0xFF14251B),
    gradientColors: [
      Color(0xFF171C1B),
      Color(0xFF171C1B),
      Color(0xFF171C1B),
      Color(0xFF171C1B),
    ],
    isStudio: true,
  );

  static const studioMuzician = StudioPalette._(
    scaffoldBg: Color(0xFF0A0A1E),
    surface: Color(0xFF0A0F1E),
    dialogBg: Color(0xFF161B2E),
    textPrimary: Color(0xFFF1F5F9),
    textSecondary: Color(0xFF94A3B8),
    textMuted: Color(0xFF8B9DC3),
    textDim: Color(0xFF64748B),
    sky: Color(0xFF38BDF8),
    teal: Color(0xFF4ECDC4),
    violet: Color(0xFFA78BFA),
    purple: Color(0xFFC084FC),
    emerald: Color(0xFF34D399),
    orange: Color(0xFFFB923C),
    red: Color(0xFFF87171),
    glassBg: Color(0xFF161B2E),
    glassBorder: Color(0xFF465578),
    onAccent: Color(0xFF071722),
    gradientColors: [
      Color(0xFF0A0A1E),
      Color(0xFF1A1034),
      Color(0xFF16213E),
      Color(0xFF0F3460),
    ],
    isStudio: true,
  );

  static const legacy = StudioPalette._(
    scaffoldBg: Color(0xFF0A0A1E),
    surface: Color(0xFF0A0F1E),
    dialogBg: Color(0xFF161B2E),
    textPrimary: Color(0xFFF1F5F9),
    textSecondary: Color(0xFF94A3B8),
    textMuted: Color(0xFF8B9DC3),
    textDim: Color(0xFF334155),
    sky: Color(0xFF38BDF8),
    teal: Color(0xFF4ECDC4),
    violet: Color(0xFFA78BFA),
    purple: Color(0xFFC084FC),
    emerald: Color(0xFF34D399),
    orange: Color(0xFFFB923C),
    red: Color(0xFFF87171),
    glassBg: Color(0x08FFFFFF),
    glassBorder: Color(0x12FFFFFF),
    onAccent: Color(0xFF071722),
    gradientColors: [
      Color(0xFF0A0A1E),
      Color(0xFF1A1034),
      Color(0xFF16213E),
      Color(0xFF0F3460),
    ],
    isStudio: false,
  );

  @override
  StudioPalette copyWith({
    Color? scaffoldBg,
    Color? surface,
    Color? dialogBg,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textDim,
    Color? sky,
    Color? teal,
    Color? violet,
    Color? purple,
    Color? emerald,
    Color? orange,
    Color? red,
    Color? glassBg,
    Color? glassBorder,
    Color? onAccent,
    List<Color>? gradientColors,
    bool? isStudio,
  }) => StudioPalette._(
    scaffoldBg: scaffoldBg ?? this.scaffoldBg,
    surface: surface ?? this.surface,
    dialogBg: dialogBg ?? this.dialogBg,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textMuted: textMuted ?? this.textMuted,
    textDim: textDim ?? this.textDim,
    sky: sky ?? this.sky,
    teal: teal ?? this.teal,
    violet: violet ?? this.violet,
    purple: purple ?? this.purple,
    emerald: emerald ?? this.emerald,
    orange: orange ?? this.orange,
    red: red ?? this.red,
    glassBg: glassBg ?? this.glassBg,
    glassBorder: glassBorder ?? this.glassBorder,
    onAccent: onAccent ?? this.onAccent,
    gradientColors: gradientColors == null
        ? this.gradientColors
        : List<Color>.unmodifiable(gradientColors),
    isStudio: isStudio ?? this.isStudio,
  );

  @override
  StudioPalette lerp(covariant StudioPalette? other, double t) {
    if (other == null) return this;
    return StudioPalette._(
      scaffoldBg: Color.lerp(scaffoldBg, other.scaffoldBg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      dialogBg: Color.lerp(dialogBg, other.dialogBg, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      sky: Color.lerp(sky, other.sky, t)!,
      teal: Color.lerp(teal, other.teal, t)!,
      violet: Color.lerp(violet, other.violet, t)!,
      purple: Color.lerp(purple, other.purple, t)!,
      emerald: Color.lerp(emerald, other.emerald, t)!,
      orange: Color.lerp(orange, other.orange, t)!,
      red: Color.lerp(red, other.red, t)!,
      glassBg: Color.lerp(glassBg, other.glassBg, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      gradientColors: List<Color>.unmodifiable([
        for (var i = 0; i < gradientColors.length; i++)
          Color.lerp(gradientColors[i], other.gradientColors[i], t)!,
      ]),
      isStudio: t < 0.5 ? isStudio : other.isStudio,
    );
  }
}

abstract final class StudioTheme {
  static ThemeData data(AppThemeVariant variant) {
    final p = variant == AppThemeVariant.studio
        ? StudioPalette.studio
        : StudioPalette.studioMuzician;
    final scheme = ColorScheme.dark(
      primary: p.sky,
      onPrimary: p.onAccent,
      secondary: p.teal,
      onSecondary: p.onAccent,
      surface: p.surface,
      onSurface: p.textPrimary,
      error: p.red,
      onError: p.onAccent,
      outline: p.textMuted,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.scaffoldBg,
      extensions: [p],
      dividerColor: p.glassBorder,
      disabledColor: p.textDim,
      iconTheme: IconThemeData(color: p.textSecondary),
      textTheme: ThemeData.dark().textTheme.apply(
        bodyColor: p.textPrimary,
        displayColor: p.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.scaffoldBg,
        foregroundColor: p.textPrimary,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.dialogBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.glassBorder),
        ),
        titleTextStyle: TextStyle(
          color: p.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(
          color: p.textSecondary,
          fontSize: 14,
          height: 1.4,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.dialogBg,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        hintStyle: TextStyle(color: p.textMuted),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: p.textMuted),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: p.sky, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: p.textPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          side: BorderSide(color: p.textMuted),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
    );
  }

  static ThemeData legacyData() =>
      MuzicianTheme.dark().copyWith(extensions: const [StudioPalette.legacy]);
}

/// A projection of canonical Settings, above Navigator and isolated editors.
class StudioThemeSource extends InheritedWidget {
  const StudioThemeSource({
    super.key,
    required this.variant,
    required super.child,
  });

  final AppThemeVariant variant;

  static AppThemeVariant? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StudioThemeSource>()?.variant;

  @override
  bool updateShouldNotify(StudioThemeSource oldWidget) =>
      variant != oldWidget.variant;
}

/// Re-resolves Studio inside captured route themes, preserving child identity.
class StudioRouteTheme extends StatelessWidget {
  const StudioRouteTheme({
    super.key,
    required this.isStudio,
    required this.child,
  });
  final bool isStudio;
  final Widget child;

  /// Capture only scope kind; never capture a palette or ThemeData snapshot.
  static WidgetBuilder builder(BuildContext caller, WidgetBuilder builder) {
    final isStudio = StudioPalette.of(caller).isStudio;
    return (context) => StudioRouteTheme(
      isStudio: isStudio,
      child: Builder(builder: builder),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isStudio) return Theme(data: StudioTheme.legacyData(), child: child);
    final variant = StudioThemeSource.maybeOf(context);
    final data = variant == null
        ? Theme.of(context)
        : StudioTheme.data(variant);
    return Theme(data: data, child: child);
  }
}

/// Dialog counterpart that keeps the launching Studio/legacy scope live.
Future<T?> showStudioDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
}) => showDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  useRootNavigator: useRootNavigator,
  builder: StudioRouteTheme.builder(context, builder),
);

/// Shared sheets use a transparent route and resolve their surface live inside.
Future<T?> showStudioModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = false,
  BoxConstraints? constraints,
}) => showModalBottomSheet<T>(
  context: context,
  backgroundColor: Colors.transparent,
  isScrollControlled: isScrollControlled,
  isDismissible: isDismissible,
  enableDrag: enableDrag,
  useRootNavigator: useRootNavigator,
  constraints: constraints,
  builder: StudioRouteTheme.builder(
    context,
    (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: StudioPalette.of(context).dialogBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: builder(context),
      ),
    ),
  ),
);
