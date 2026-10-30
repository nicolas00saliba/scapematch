import 'package:flutter/material.dart';

/// Paleta Noite de Mistério.
///
/// Os pares de texto estão no [ColorScheme] do Material 3. Sucesso e alerta
/// ficam em [ScapeStatusColors], porque o esquema não tem esses papéis.
/// O fundo da página é o [ThemeData.scaffoldBackgroundColor]; o cartão é
/// [ColorScheme.surface].
ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = dark ? _darkScheme : _lightScheme;
  final status = dark ? _darkStatus : _lightStatus;
  final page = dark ? _darkPage : _lightPage;
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: page,
    extensions: [status],
    dividerColor: scheme.outlineVariant,
    appBarTheme: AppBarTheme(
      backgroundColor: page,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        fontFamily: 'Roboto',
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: rounded,
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          fontFamily: 'Roboto',
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surface,
      selectedColor: scheme.primaryContainer,
      checkmarkColor: scheme.primary,
      labelStyle: TextStyle(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
        fontFamily: 'Roboto',
      ),
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      height: 68,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        );
      }),
    ),
    dialogTheme: DialogThemeData(backgroundColor: scheme.surfaceContainerHigh),
  );
}

/// Sucesso e alerta. O dourado de destaque é [ColorScheme.tertiary].
@immutable
class ScapeStatusColors extends ThemeExtension<ScapeStatusColors> {
  const ScapeStatusColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.alert,
    required this.onAlert,
    required this.alertContainer,
    required this.onAlertContainer,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color alert;
  final Color onAlert;
  final Color alertContainer;
  final Color onAlertContainer;

  static ScapeStatusColors of(BuildContext context) {
    final colors = Theme.of(context).extension<ScapeStatusColors>();
    assert(colors != null, 'ScapeStatusColors ausente do tema');
    return colors!;
  }

  @override
  ScapeStatusColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? alert,
    Color? onAlert,
    Color? alertContainer,
    Color? onAlertContainer,
  }) {
    return ScapeStatusColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      alert: alert ?? this.alert,
      onAlert: onAlert ?? this.onAlert,
      alertContainer: alertContainer ?? this.alertContainer,
      onAlertContainer: onAlertContainer ?? this.onAlertContainer,
    );
  }

  @override
  ScapeStatusColors lerp(ThemeExtension<ScapeStatusColors>? other, double t) {
    if (other is! ScapeStatusColors) {
      return this;
    }
    return ScapeStatusColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      alert: Color.lerp(alert, other.alert, t)!,
      onAlert: Color.lerp(onAlert, other.onAlert, t)!,
      alertContainer: Color.lerp(alertContainer, other.alertContainer, t)!,
      onAlertContainer: Color.lerp(
        onAlertContainer,
        other.onAlertContainer,
        t,
      )!,
    );
  }
}

const _lightPage = Color(0xFFF6F4FB);
const _darkPage = Color(0xFF120E1F);

const _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF3D2C8D),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFE4DCF8),
  onPrimaryContainer: Color(0xFF3D2C8D),
  secondary: Color(0xFFA3365F),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFF8E1EA),
  onSecondaryContainer: Color(0xFF5C0F30),
  tertiary: Color(0xFFF4B740),
  onTertiary: Color(0xFF241600),
  tertiaryContainer: Color(0xFFFFF3D1),
  onTertiaryContainer: Color(0xFF241600),
  error: Color(0xFFB3261E),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFF9DEDC),
  onErrorContainer: Color(0xFFB3261E),
  surface: Color(0xFFFFFFFF),
  onSurface: Color(0xFF1B1530),
  onSurfaceVariant: Color(0xFF55506B),
  outline: Color(0xFF6E6886),
  outlineVariant: Color(0xFFD4CEE6),
  shadow: Color(0xFF1B1530),
  scrim: Color(0xFF1B1530),
  inverseSurface: Color(0xFF1B1530),
  onInverseSurface: Color(0xFFF6F4FB),
  inversePrimary: Color(0xFFC3B5FF),
  surfaceTint: Color(0xFF3D2C8D),
  surfaceDim: Color(0xFFE4DFEF),
  surfaceBright: Color(0xFFFFFFFF),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF6F4FB),
  surfaceContainer: Color(0xFFF0ECF8),
  surfaceContainerHigh: Color(0xFFE8E3F4),
  surfaceContainerHighest: Color(0xFFE0DAF0),
);

const _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFC3B5FF),
  onPrimary: Color(0xFF25146B),
  primaryContainer: Color(0xFF3D2C8D),
  onPrimaryContainer: Color(0xFFC3B5FF),
  secondary: Color(0xFFFFB0C8),
  onSecondary: Color(0xFF5C0F30),
  secondaryContainer: Color(0xFF5C0F30),
  onSecondaryContainer: Color(0xFFFFB0C8),
  tertiary: Color(0xFFF4C25B),
  onTertiary: Color(0xFF241600),
  tertiaryContainer: Color(0xFF3A2C08),
  onTertiaryContainer: Color(0xFFF4C25B),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF690005),
  onErrorContainer: Color(0xFFFFB4AB),
  surface: Color(0xFF1D1830),
  onSurface: Color(0xFFECE8F7),
  onSurfaceVariant: Color(0xFFB4AECB),
  outline: Color(0xFF8E88A8),
  outlineVariant: Color(0xFF4A4464),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFFECE8F7),
  onInverseSurface: Color(0xFF1B1530),
  inversePrimary: Color(0xFF3D2C8D),
  surfaceTint: Color(0xFFC3B5FF),
  surfaceDim: Color(0xFF120E1F),
  surfaceBright: Color(0xFF38324F),
  surfaceContainerLowest: Color(0xFF120E1F),
  surfaceContainerLow: Color(0xFF1D1830),
  surfaceContainer: Color(0xFF26213A),
  surfaceContainerHigh: Color(0xFF2E2944),
  surfaceContainerHighest: Color(0xFF38324F),
);

const _lightStatus = ScapeStatusColors(
  success: Color(0xFF1E7046),
  onSuccess: Color(0xFFFFFFFF),
  successContainer: Color(0xFFD7F3E3),
  onSuccessContainer: Color(0xFF1E7046),
  alert: Color(0xFF8A5A00),
  onAlert: Color(0xFFFFFFFF),
  alertContainer: Color(0xFFFFF1D0),
  onAlertContainer: Color(0xFF8A5A00),
);

const _darkStatus = ScapeStatusColors(
  success: Color(0xFF6DD69B),
  onSuccess: Color(0xFF052818),
  successContainer: Color(0xFF0E3D26),
  onSuccessContainer: Color(0xFF6DD69B),
  alert: Color(0xFFF4C25B),
  onAlert: Color(0xFF241600),
  alertContainer: Color(0xFF3A2C08),
  onAlertContainer: Color(0xFFF4C25B),
);
