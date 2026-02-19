import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'screens/home_screen.dart';
import 'utils/constants.dart';
import 'utils/theme_settings.dart';
import 'services/storage_service.dart';

// Global theme settings instance - accessible from anywhere in the app
late ThemeSettings themeSettings;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  await Hive.openBox(AppConstants.messagesBox);
  await Hive.openBox(AppConstants.settingsBox);
  await Hive.openBox(AppConstants.chatsBox);

  // Initialize theme settings
  themeSettings = ThemeSettings();
  await themeSettings.init();

  // ★ MIGRATION: Очистка старых сообщений без chatId
  await _migrateMessagesWithChatId();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const P2PChatApp());
}

/// Миграция: очистка старых сообщений которые не имеют chatId
Future<void> _migrateMessagesWithChatId() async {
  try {
    final storageService = StorageService();
    await storageService.initialize();
    
    // Проверяем есть ли старые сообщения без chatId
    final messagesBox = Hive.box(AppConstants.messagesBox);
    bool hasOldMessages = false;
    
    for (final key in messagesBox.keys) {
      final data = messagesBox.get(key);
      if (data != null && data is Map) {
        // Если нет поля chatId или оно null - это старое сообщение
        if (!data.containsKey('chatId') || data['chatId'] == null) {
          hasOldMessages = true;
          break;
        }
      }
    }
    
    if (hasOldMessages) {
      debugPrint('[MIGRATION] Found old messages without chatId, clearing...');
      await storageService.clearAllMessagesForMigration();
      debugPrint('[MIGRATION] Old messages cleared');
    } else {
      debugPrint('[MIGRATION] No old messages to clear');
    }
  } catch (e) {
    debugPrint('[MIGRATION] Error: $e');
  }
}

class P2PChatApp extends StatefulWidget {
  const P2PChatApp({super.key});

  @override
  State<P2PChatApp> createState() => _P2PChatAppState();
}

class _P2PChatAppState extends State<P2PChatApp> {
  @override
  void initState() {
    super.initState();
    // Update system UI overlay based on theme
    _updateSystemUI();
  }

  void _updateSystemUI() {
    final isLight = themeSettings.isLightTheme;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: isLight ? AppConstants.surfaceLight : AppConstants.surfaceDark,
      systemNavigationBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      themeMode: themeSettings.isLightTheme ? ThemeMode.light : ThemeMode.dark,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      home: const HomeScreen(),
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

  ThemeData _buildLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppConstants.surfaceLight,
      colorScheme: const ColorScheme.light(
        primary: AppConstants.primaryColor,
        secondary: AppConstants.secondaryColor,
        surface: AppConstants.surfaceCardLight,
        error: AppConstants.errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppConstants.textPrimaryLight,
        onError: Colors.white,
      ),
      useMaterial3: true,
      fontFamily: 'Inter',
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: AppConstants.surfaceCardLight,
        foregroundColor: AppConstants.textPrimaryLight,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: AppConstants.textPrimaryLight,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
        ),
        iconTheme: IconThemeData(color: AppConstants.textPrimaryLight),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppConstants.surfaceCardLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppConstants.borderRadius)),
          side: BorderSide(color: AppConstants.dividerColorLight, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppConstants.dividerColorLight,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppConstants.surfaceInputLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          borderSide: BorderSide(color: AppConstants.dividerColorLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          borderSide: BorderSide(color: AppConstants.dividerColorLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          borderSide: const BorderSide(color: AppConstants.primaryColor, width: 2),
        ),
        labelStyle: const TextStyle(color: AppConstants.textSecondaryLight),
        hintStyle: const TextStyle(color: AppConstants.textMutedLight),
        prefixIconColor: AppConstants.textMutedLight,
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
        backgroundColor: AppConstants.surfaceElevatedLight,
        contentTextStyle: const TextStyle(color: AppConstants.textPrimaryLight),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppConstants.surfaceCardLight,
        titleTextStyle: const TextStyle(
          color: AppConstants.textPrimaryLight,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(
          color: AppConstants.textSecondaryLight,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppConstants.surfaceCardLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        textColor: AppConstants.textPrimaryLight,
        iconColor: AppConstants.textSecondaryLight,
      ),
    );
  }
}
