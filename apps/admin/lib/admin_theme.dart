import 'package:flutter/material.dart';

const adminTeal = Color(0xFF0F4C4A);
const adminCopper = Color(0xFFD2642A);

/// Marca do painel. O pin teal e o cobre são os da logo do ScapeMatch.
class AdminMark extends StatelessWidget {
  const AdminMark({super.key, this.height = 36, this.onDark = false});

  final double height;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final ink = onDark ? Colors.white : adminTeal;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.place, color: adminCopper, size: height),
        const SizedBox(width: 4),
        Text(
          'ScapeMatch',
          style: TextStyle(
            color: ink,
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w500,
            fontSize: height * 0.42,
          ),
        ),
      ],
    );
  }
}

ThemeData adminTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: adminTeal,
  ).copyWith(primary: adminTeal, secondary: adminCopper, onSecondary: Colors.white);
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
      selectedLabelTextStyle: TextStyle(color: Colors.white, fontFamily: 'Poppins'),
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
