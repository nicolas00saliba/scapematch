import 'package:flutter/material.dart';

/// Paleta Cofre de Cobre: verde-petróleo e cobre.
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
    borderRadius: BorderRadius.circular(22),
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
      elevation: 1,
      shadowColor: const Color(0x140E1716),
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
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

const _lightPage = Color(0xFFF5F1EA);
const _darkPage = Color(0xFF0E1716);

const _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF0F4C4A),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFE5F2F0),
  onPrimaryContainer: Color(0xFF0F4C4A),
  secondary: Color(0xFF9A4F24),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFF8EBE3),
  onSecondaryContainer: Color(0xFF9A4F24),
  tertiary: Color(0xFFE3A83F),
  onTertiary: Color(0xFF2A1A05),
  tertiaryContainer: Color(0xFFFFF4D8),
  onTertiaryContainer: Color(0xFF2A1A05),
  error: Color(0xFFB3261E),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFF9DEDC),
  onErrorContainer: Color(0xFFB3261E),
  surface: Color(0xFFFFFFFF),
  onSurface: Color(0xFF142421),
  onSurfaceVariant: Color(0xFF4A5B57),
  outline: Color(0xFF5E6E6A),
  outlineVariant: Color(0xFFE3DDD3),
  shadow: Color(0xFF142421),
  scrim: Color(0xFF142421),
  inverseSurface: Color(0xFF142421),
  onInverseSurface: Color(0xFFF5F1EA),
  inversePrimary: Color(0xFF6FD1C4),
  surfaceTint: Color(0xFF0F4C4A),
  surfaceDim: Color(0xFFE6E0D6),
  surfaceBright: Color(0xFFFFFFFF),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF5F1EA),
  surfaceContainer: Color(0xFFEFEAE2),
  surfaceContainerHigh: Color(0xFFE7E2D8),
  surfaceContainerHighest: Color(0xFFDDD7CC),
);

const _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF6FD1C4),
  onPrimary: Color(0xFF00302C),
  primaryContainer: Color(0xFF0F4C4A),
  onPrimaryContainer: Color(0xFF6FD1C4),
  secondary: Color(0xFFF0A878),
  onSecondary: Color(0xFF4A1F05),
  secondaryContainer: Color(0xFF4A1F05),
  onSecondaryContainer: Color(0xFFF0A878),
  tertiary: Color(0xFFF2C46B),
  onTertiary: Color(0xFF2A1A05),
  tertiaryContainer: Color(0xFF3A2A08),
  onTertiaryContainer: Color(0xFFF2C46B),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF690005),
  onErrorContainer: Color(0xFFFFB4AB),
  surface: Color(0xFF172322),
  onSurface: Color(0xFFE8EFEC),
  onSurfaceVariant: Color(0xFFA9B8B4),
  outline: Color(0xFF8AA09B),
  outlineVariant: Color(0xFF2C3A38),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFFE8EFEC),
  onInverseSurface: Color(0xFF142421),
  inversePrimary: Color(0xFF0F4C4A),
  surfaceTint: Color(0xFF6FD1C4),
  surfaceDim: Color(0xFF0E1716),
  surfaceBright: Color(0xFF2A3A38),
  surfaceContainerLowest: Color(0xFF0E1716),
  surfaceContainerLow: Color(0xFF172322),
  surfaceContainer: Color(0xFF1E2C2A),
  surfaceContainerHigh: Color(0xFF24302E),
  surfaceContainerHighest: Color(0xFF2C3C39),
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
  alert: Color(0xFFF2C46B),
  onAlert: Color(0xFF2A1A05),
  alertContainer: Color(0xFF3A2A08),
  onAlertContainer: Color(0xFFF2C46B),
);
