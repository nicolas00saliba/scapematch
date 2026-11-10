import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const adminTeal = Color(0xFF0F4C4A);
const adminCopper = Color(0xFFD2642A);
const adminInk = Color(0xFF1F1F22);

/// Marca exclusiva do Admin: pino grafite, miolo dourado, coroa e estrela.
class AdminMark extends StatelessWidget {
  const AdminMark({
    super.key,
    this.height = 40,
    this.onDark = false,
    this.wordmark = false,
    this.plate = true,
  });

  final double height;
  final bool onDark;

  /// Letreiro ao lado do ícone, no trilho largo.
  final bool wordmark;

  /// Ícone com fundo preto arredondado. Falso é o símbolo transparente,
  /// para a abertura preta, onde o brilho encontra o fundo.
  final bool plate;

  static const plateAsset = 'assets/brand/logo_admin_icone.svg';
  static const symbolAsset = 'assets/brand/logo_admin_simbolo.svg';

  /// viewBox do símbolo transparente.
  static const symbolAspect = 244 / 328;

  @override
  Widget build(BuildContext context) {
    final mark = SvgPicture.asset(
      plate ? plateAsset : symbolAsset,
      height: height,
      width: plate ? height : height * symbolAspect,
      fit: BoxFit.contain,
      semanticsLabel: 'EscapeMatch Admin',
    );
    if (!wordmark) return mark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(width: height * 0.28),
        Text(
          'EscapeMatch',
          style: TextStyle(
            color: onDark ? Colors.white : adminInk,
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w500,
            fontSize: height * 0.42,
          ),
        ),
      ],
    );
  }
}

/// Cartão das telas de entrada. Rola quando o teclado cobre o formulário.
class AdminAuthCard extends StatelessWidget {
  const AdminAuthCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(padding: const EdgeInsets.all(24), child: child),
            ),
          ),
        ),
      ),
    );
  }
}

ThemeData adminTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: adminTeal).copyWith(
    primary: adminTeal,
    secondary: adminCopper,
    onSecondary: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF6F3EE),
    fontFamily: 'Poppins',
    appBarTheme: const AppBarTheme(
      backgroundColor: adminTeal,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: adminTeal,
      selectedIconTheme: IconThemeData(color: Colors.white),
      unselectedIconTheme: IconThemeData(color: Color(0xFFD7E4E2)),
      selectedLabelTextStyle: TextStyle(
        color: Colors.white,
        fontFamily: 'Poppins',
      ),
      unselectedLabelTextStyle: TextStyle(
        color: Color(0xFFD7E4E2),
        fontFamily: 'Poppins',
      ),
      indicatorColor: adminCopper,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: adminTeal,
        foregroundColor: Colors.white,
      ),
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: Color(0xFFE7E0D8)),
      ),
    ),
  );
}
