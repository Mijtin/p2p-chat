import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'screens/connect_screen.dart';
import 'utils/constants.dart';
import 'utils/theme_settings.dart';

// Global theme settings instance - accessible from anywhere in the app
late ThemeSettings themeSettings;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Hive.initFlutter();
  await Hive.openBox(AppConstants.messagesBox);
  await Hive.openBox(AppConstants.settingsBox);
  
  // Initialize theme settings
  themeSettings = ThemeSettings();
  await themeSettings.init();
  
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Тёмная системная навигация
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppConstants.surfaceDark,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const P2PChatApp());
}

class P2PChatApp extends StatelessWidget {
  const P2PChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark, // ВСЕГДА тёмная тема
      theme: _buildDarkTheme(),
      darkTheme: _buildDarkTheme(),
      home: const ConnectScreen(),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppConstants.surfaceDark,
      colorScheme: const ColorScheme.dark(
        primary: AppConstants.primaryColor,
        secondary: AppConstants.secondaryColor,
        surface: AppConstants.surfaceCard,
        error: AppConstants.errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppConstants.textPrimary,
        onError: Colors.white,
      ),
      useMaterial3: true,
      fontFamily: 'Inter',
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: AppConstants.surfaceCard,
        foregroundColor: AppConstants.textPrimary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: AppConstants.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
        ),
        iconTheme: IconThemeData(color: AppConstants.textPrimary),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppConstants.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppConstants.borderRadius)),
          side: BorderSide(color: AppConstants.dividerColor, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppConstants.dividerColor,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppConstants.surfaceInput,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          borderSide: BorderSide(color: AppConstants.dividerColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          borderSide: BorderSide(color: AppConstants.dividerColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          borderSide: const BorderSide(color: AppConstants.primaryColor, width: 2),
        ),
        labelStyle: const TextStyle(color: AppConstants.textSecondary),
        hintStyle: const TextStyle(color: AppConstants.textMuted),
        prefixIconColor: AppConstants.textMuted,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppConstants.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppConstants.primaryColor,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppConstants.surfaceElevated,
        contentTextStyle: const TextStyle(color: AppConstants.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppConstants.surfaceCard,
        titleTextStyle: const TextStyle(
          color: AppConstants.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(
          color: AppConstants.textSecondary,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppConstants.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        textColor: AppConstants.textPrimary,
        iconColor: AppConstants.textSecondary,
      ),
    );
  }
}
