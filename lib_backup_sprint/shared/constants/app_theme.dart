import 'package:flutter/material.dart';

class AppTheme {
  // Ana tema renkleri - Sadece 3 renk: Yeşil, Siyah, Beyaz
  static Color greenColor = const Color(0xFF00BA7C); // Yeşil renk (vurgu rengi)
  static Color blackColor = Colors.black; // Siyah
  static Color whiteColor = Colors.white; // Beyaz
  
  // Geriye dönük uyumluluk için eski renk referansları
  static Color primaryColor = greenColor; // Eski kodlar için
  static Color accentColor = greenColor; // Eski kodlar için
  static Color secondaryColor = greenColor; // Eski kodlar için
  
  // Açık tema renkleri
  static Color lightBackgroundColor = whiteColor;
  static Color lightSurfaceColor = whiteColor;
  static Color lightCardColor = whiteColor;
  static Color lightPrimaryTextColor = blackColor;
  static Color lightSecondaryTextColor = blackColor.withAlpha(153); // Siyahın hafif transparanı
  static Color lightIconColor = blackColor;
  static Color lightDividerColor = blackColor.withAlpha(26); // Siyahın çok hafif transparanı
  static Color lightBorderColor = blackColor.withAlpha(26);
  static Color lightTextColor = whiteColor; // Butonlar için
  static Color lightShadowColor = blackColor.withAlpha(26); // Gölgeler için
  
  // Koyu tema renkleri
  static Color darkBackgroundColor = blackColor;
  static Color darkSurfaceColor = blackColor;
  static Color darkCardColor = blackColor;
  static Color darkPrimaryTextColor = whiteColor;
  static Color darkSecondaryTextColor = whiteColor.withAlpha(153); // Beyazın hafif transparanı
  static Color darkIconColor = whiteColor;
  static Color darkDividerColor = whiteColor.withAlpha(26); // Beyazın çok hafif transparanı
  static Color darkBorderColor = whiteColor.withAlpha(26);
  static Color darkTextColor = whiteColor; // Butonlar için
  static Color darkShadowColor = whiteColor.withAlpha(26); // Gölgeler için
  
  // Açık tema
  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor: greenColor,
    scaffoldBackgroundColor: lightBackgroundColor,
    cardColor: lightCardColor,
    dividerColor: lightDividerColor,
    shadowColor: lightShadowColor,
    colorScheme: ColorScheme.light(
      primary: greenColor,
      secondary: greenColor,
      surface: lightSurfaceColor,
      onSurface: lightPrimaryTextColor,
      onPrimary: whiteColor,
      onSecondary: whiteColor,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: lightBackgroundColor,
      foregroundColor: lightPrimaryTextColor,
      elevation: 0,
      iconTheme: IconThemeData(color: lightIconColor),
      titleTextStyle: TextStyle(
        color: lightPrimaryTextColor,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    textTheme: TextTheme(
      bodyLarge: TextStyle(color: lightPrimaryTextColor),
      bodyMedium: TextStyle(color: lightPrimaryTextColor),
      titleMedium: TextStyle(color: lightPrimaryTextColor),
      titleLarge: TextStyle(color: lightPrimaryTextColor, fontWeight: FontWeight.bold),
      labelLarge: TextStyle(color: lightPrimaryTextColor),
    ),
    iconTheme: IconThemeData(
      color: lightIconColor,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: greenColor,
        foregroundColor: whiteColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: greenColor,
        side: BorderSide(color: greenColor),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: greenColor,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: greenColor,
      foregroundColor: whiteColor,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
        if (states.contains(MaterialState.selected)) {
          return greenColor;
        }
        return lightBorderColor;
      }),
      checkColor: MaterialStateProperty.all(whiteColor),
    ),
    radioTheme: RadioThemeData(
      fillColor: MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
        if (states.contains(MaterialState.selected)) {
          return greenColor;
        }
        return lightBorderColor;
      }),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
        if (states.contains(MaterialState.selected)) {
          return greenColor;
        }
        return lightBorderColor;
      }),
      trackColor: MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
        if (states.contains(MaterialState.selected)) {
          return greenColor.withAlpha(128);
        }
        return lightBorderColor.withAlpha(128);
      }),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderSide: BorderSide(color: lightBorderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: greenColor),
        borderRadius: BorderRadius.circular(8),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: lightBorderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.red),
        borderRadius: BorderRadius.circular(8),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.red),
        borderRadius: BorderRadius.circular(8),
      ),
      labelStyle: TextStyle(color: lightSecondaryTextColor),
      hintStyle: TextStyle(color: lightSecondaryTextColor),
    ),
  );
  
  // Koyu tema
  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: greenColor,
    scaffoldBackgroundColor: darkBackgroundColor,
    cardColor: darkCardColor,
    dividerColor: darkDividerColor,
    shadowColor: darkShadowColor,
    colorScheme: ColorScheme.dark(
      primary: greenColor,
      secondary: greenColor,
      surface: darkSurfaceColor,
      onSurface: darkPrimaryTextColor,
      onPrimary: whiteColor,
      onSecondary: whiteColor,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: darkBackgroundColor,
      foregroundColor: darkPrimaryTextColor,
      elevation: 0,
      iconTheme: IconThemeData(color: darkIconColor),
      titleTextStyle: TextStyle(
        color: darkPrimaryTextColor,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),
    textTheme: TextTheme(
      bodyLarge: TextStyle(color: darkPrimaryTextColor),
      bodyMedium: TextStyle(color: darkPrimaryTextColor),
      titleMedium: TextStyle(color: darkPrimaryTextColor),
      titleLarge: TextStyle(color: darkPrimaryTextColor, fontWeight: FontWeight.bold),
      labelLarge: TextStyle(color: darkPrimaryTextColor),
    ),
    iconTheme: IconThemeData(
      color: darkIconColor,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: greenColor,
        foregroundColor: whiteColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: greenColor,
        side: BorderSide(color: greenColor),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: greenColor,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: greenColor,
      foregroundColor: whiteColor,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
        if (states.contains(MaterialState.selected)) {
          return greenColor;
        }
        return darkBorderColor;
      }),
      checkColor: MaterialStateProperty.all(whiteColor),
    ),
    radioTheme: RadioThemeData(
      fillColor: MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
        if (states.contains(MaterialState.selected)) {
          return greenColor;
        }
        return darkBorderColor;
      }),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
        if (states.contains(MaterialState.selected)) {
          return greenColor;
        }
        return darkBorderColor;
      }),
      trackColor: MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
        if (states.contains(MaterialState.selected)) {
          return greenColor.withAlpha(128);
        }
        return darkBorderColor.withAlpha(128);
      }),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderSide: BorderSide(color: darkBorderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: greenColor),
        borderRadius: BorderRadius.circular(8),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: darkBorderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.red),
        borderRadius: BorderRadius.circular(8),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Colors.red),
        borderRadius: BorderRadius.circular(8),
      ),
      labelStyle: TextStyle(color: darkSecondaryTextColor),
      hintStyle: TextStyle(color: darkSecondaryTextColor),
    ),
  );
} 
