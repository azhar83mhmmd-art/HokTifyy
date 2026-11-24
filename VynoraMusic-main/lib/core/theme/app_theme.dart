import 'package:flutter/material.dart';

class AppTheme {
  static const primaryTextStyle = TextStyle(fontFamily: "Inter", color: Colors.white);
  static const secondoryTextStyle = TextStyle(fontFamily: "Inter", color: Colors.white);
  static const secondoryTextStyleMedium =
      TextStyle(fontFamily: "Inter", fontWeight: FontWeight.w700, color: Colors.white);
  static const tertiaryTextStyle = TextStyle(fontFamily: "Inter", color: Colors.white);
  static const fontAwesomeRegularFont =
      TextStyle(fontFamily: "FontAwesome-Regular");
  static const fontAwesomeSolidFont =
      TextStyle(fontFamily: "FontAwesome-Solids");

  // ---- Palet Vynora Music (violet, selaras dengan ikon) ----------------------
  static const themeColor = Color(0xFF000000);         // latar utama (tonal gelap, gaya Sonara)
  static const primaryColor1 = Color(0xFFFFFFFF);      // putih (teks utama)
  static const primaryColor2 = Color(0xFFB9B9C9);      // teks sekunder
  static const accentColor1 = Color(0xFF8B5CF6);       // violet utama
  static const accentColor1light = Color(0xFFC4B5FD);  // violet muda
  static const accentColor2 = Color(0xFFCFBCFF);       // aksen terang (ikon/teks/tombol)
  // Token tonal Material 3 (Sonara): wadah aktif / pill navigasi
  static const primaryContainerColor = Color(0xFF4F378B);
  static const onPrimaryContainerColor = Color(0xFFEADDFF);
  static const successColor = Color(0xFF5EFF43);

  // token tambahan untuk komponen
  static const surfaceColor = Color(0xFF111115);       // kartu, dialog, sheet
  static const surfaceHighColor = Color(0xFF1C1C22);   // snackbar, menu, chip
  static const outlineColor = Color(0x14FFFFFF);       // garis tipis
  static const brandGradient = LinearGradient(
    colors: [Color(0xFF7C3AED), Color(0xFFC084FC)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  ThemeData get defaultThemeData {
    const darkScheme = ColorScheme.dark(
      primary: accentColor2,
      secondary: accentColor1,
      surface: themeColor,
      surfaceContainerHighest: surfaceHighColor,
      outline: outlineColor,
      onPrimary: Color(0xFF2E1A66), // teks gelap di atas tombol violet terang
      onSecondary: Colors.white,
      onSurface: Colors.white,  // Teks putih di atas background hitam
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: themeColor,
      dialogBackgroundColor: surfaceColor,
      primaryColorDark: accentColor2,
      fontFamily: 'Inter',
      primarySwatch: MaterialColor(
        accentColor2.value,
        {
          50: accentColor2.withValues(alpha: 0.1),
          100: accentColor2.withValues(alpha: 0.2),
          200: accentColor2.withValues(alpha: 0.3),
          300: accentColor2.withValues(alpha: 0.4),
          400: accentColor2.withValues(alpha: 0.5),
          500: accentColor2.withValues(alpha: 0.6),
          600: accentColor2.withValues(alpha: 0.7),
          700: accentColor2.withValues(alpha: 0.8),
          800: accentColor2.withValues(alpha: 0.9),
          900: accentColor2,
        },
      ),
      colorScheme: darkScheme.copyWith(
        primary: accentColor2,
        secondary: accentColor1,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(color: Colors.white, fontFamily: 'Inter'),
        displayMedium: TextStyle(color: Colors.white, fontFamily: 'Inter'),
        displaySmall: TextStyle(color: Colors.white, fontFamily: 'Inter'),
        headlineLarge: TextStyle(color: Colors.white, fontFamily: 'Inter'),
        headlineMedium: TextStyle(color: Colors.white, fontFamily: 'Inter'),
        headlineSmall: TextStyle(color: Colors.white, fontFamily: 'Inter'),
        titleLarge: TextStyle(color: Colors.white, fontFamily: 'Inter'),
        titleMedium: TextStyle(color: Colors.white, fontFamily: 'Inter'),
        titleSmall: TextStyle(color: Colors.white, fontFamily: 'Inter'),
        bodyLarge: TextStyle(color: Colors.white, fontFamily: 'Inter'),
        bodyMedium: TextStyle(color: Colors.white, fontFamily: 'Inter'),
        bodySmall: TextStyle(color: Colors.white, fontFamily: 'Inter'),
        labelLarge: TextStyle(color: Colors.white, fontFamily: 'Inter'),
        labelMedium: TextStyle(color: Colors.white, fontFamily: 'Inter'),
        labelSmall: TextStyle(color: Colors.white, fontFamily: 'Inter'),
      ),
      iconTheme: const IconThemeData(color: primaryColor1),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(accentColor1),
        interactive: true,
        radius: const Radius.circular(10),
        thickness: WidgetStateProperty.all(5),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: themeColor,
        foregroundColor: primaryColor1,
        surfaceTintColor: themeColor,
        iconTheme: IconThemeData(color: primaryColor1),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: accentColor1),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accentColor2,
        selectionColor: accentColor1.withValues(alpha: 0.35),
        selectionHandleColor: accentColor2,
      ),
      brightness: Brightness.dark,
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? accentColor1
                : Colors.white24),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accentColor2,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.14),
        thumbColor: Colors.white,
        overlayColor: accentColor1.withValues(alpha: 0.18),
        trackHeight: 4,
      ),
      searchBarTheme: const SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(surfaceColor),
        elevation: WidgetStatePropertyAll(0),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceHighColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: outlineColor),
        ),
        textStyle: const TextStyle(color: primaryColor1),
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(surfaceHighColor),
        ),
        textStyle: TextStyle(color: primaryColor1),
      ),
      menuTheme: const MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(surfaceHighColor),
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: outlineColor),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: outlineColor),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaceHighColor,
        contentTextStyle: const TextStyle(color: primaryColor1, fontSize: 14),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: outlineColor),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accentColor1,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accentColor1light,
          side: const BorderSide(color: outlineColor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accentColor1light),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceHighColor,
        selectedColor: accentColor1.withValues(alpha: 0.35),
        side: const BorderSide(color: outlineColor),
        labelStyle: const TextStyle(color: primaryColor1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceColor,
        indicatorColor: primaryContainerColor,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((st) => TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: st.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: st.contains(WidgetState.selected)
                  ? Colors.white
                  : primaryColor2,
            )),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16))),
      ),
      dividerTheme: const DividerThemeData(color: outlineColor, thickness: 1),
    );
  }
}

typedef Default_Theme = AppTheme;