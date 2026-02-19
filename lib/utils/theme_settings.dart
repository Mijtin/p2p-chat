import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'constants.dart';

class ThemeSettings {
  static const String _boxName = 'theme_settings';
  static const String _outgoingBubbleKey = 'outgoing_bubble_color';
  static const String _incomingBubbleKey = 'incoming_bubble_color';
  static const String _textColorKey = 'text_color';
  static const String _backgroundColorKey = 'background_color';
  static const String _backgroundTypeKey = 'background_type';
  static const String _selectedPresetKey = 'selected_preset';
  static const String _backgroundImagePathKey = 'background_image_path';
  static const String _isLightThemeKey = 'is_light_theme';

  // Default values
  static final Color defaultOutgoingBubble = AppConstants.outgoingBubble;
  static final Color defaultIncomingBubble = AppConstants.incomingBubble;
  static final Color defaultTextColor = AppConstants.textPrimary;
  static final Color defaultBackgroundColor = AppConstants.surfaceDark;
  static const int defaultBackgroundType = 0; // 0 = solid, 1 = gradient, 2 = preset, 3 = image
  static const int defaultSelectedPreset = -1; // -1 = no preset selected
  static const String defaultBackgroundImagePath = '';
  static const bool defaultIsLightTheme = false;

  late Box _box;

  // Current settings
  Color outgoingBubbleColor;
  Color incomingBubbleColor;
  Color textColor;
  Color backgroundColor;
  int backgroundType; // 0 = solid, 1 = gradient, 2 = preset, 3 = image
  int selectedPreset;
  String backgroundImagePath;
  bool isLightTheme;

  ThemeSettings({
    this.outgoingBubbleColor = const Color(0xFF1A3A5C),
    this.incomingBubbleColor = const Color(0xFF1E2D3D),
    this.textColor = const Color(0xFFE8E8F0),
    this.backgroundColor = const Color(0xFF121212),
    this.backgroundType = 0,
    this.selectedPreset = -1,
    this.backgroundImagePath = '',
    this.isLightTheme = false,
  });

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    _loadSettings();
  }

  void _loadSettings() {
    outgoingBubbleColor = Color(_box.get(_outgoingBubbleKey, defaultValue: defaultOutgoingBubble.value));
    incomingBubbleColor = Color(_box.get(_incomingBubbleKey, defaultValue: defaultIncomingBubble.value));
    textColor = Color(_box.get(_textColorKey, defaultValue: defaultTextColor.value));
    backgroundColor = Color(_box.get(_backgroundColorKey, defaultValue: defaultBackgroundColor.value));
    backgroundType = _box.get(_backgroundTypeKey, defaultValue: defaultBackgroundType);
    selectedPreset = _box.get(_selectedPresetKey, defaultValue: defaultSelectedPreset);
    backgroundImagePath = _box.get(_backgroundImagePathKey, defaultValue: defaultBackgroundImagePath);
    isLightTheme = _box.get(_isLightThemeKey, defaultValue: defaultIsLightTheme);
  }

  Future<void> setOutgoingBubbleColor(Color color) async {
    outgoingBubbleColor = color;
    await _box.put(_outgoingBubbleKey, color.value);
  }

  Future<void> setIncomingBubbleColor(Color color) async {
    incomingBubbleColor = color;
    await _box.put(_incomingBubbleKey, color.value);
  }

  Future<void> setTextColor(Color color) async {
    textColor = color;
    await _box.put(_textColorKey, color.value);
  }

  Future<void> setBackgroundColor(Color color) async {
    backgroundColor = color;
    backgroundType = 0;
    selectedPreset = -1;
    backgroundImagePath = '';
    await _box.put(_backgroundColorKey, color.value);
    await _box.put(_backgroundTypeKey, 0);
    await _box.put(_selectedPresetKey, -1);
    await _box.put(_backgroundImagePathKey, '');
  }

  Future<void> setPresetBackground(int presetIndex) async {
    selectedPreset = presetIndex;
    backgroundType = 2;
    backgroundImagePath = '';
    await _box.put(_selectedPresetKey, presetIndex);
    await _box.put(_backgroundTypeKey, 2);
    await _box.put(_backgroundImagePathKey, '');
  }

  Future<void> setBackgroundImage(String imagePath) async {
    backgroundImagePath = imagePath;
    backgroundType = 3;
    selectedPreset = -1;
    await _box.put(_backgroundImagePathKey, imagePath);
    await _box.put(_backgroundTypeKey, 3);
    await _box.put(_selectedPresetKey, -1);
  }

  Future<void> resetToDefaults() async {
    outgoingBubbleColor = defaultOutgoingBubble;
    incomingBubbleColor = defaultIncomingBubble;
    textColor = defaultTextColor;
    backgroundColor = defaultBackgroundColor;
    backgroundType = defaultBackgroundType;
    selectedPreset = defaultSelectedPreset;
    backgroundImagePath = defaultBackgroundImagePath;

    await _box.put(_outgoingBubbleKey, defaultOutgoingBubble.value);
    await _box.put(_incomingBubbleKey, defaultIncomingBubble.value);
    await _box.put(_textColorKey, defaultTextColor.value);
    await _box.put(_backgroundColorKey, defaultBackgroundColor.value);
    await _box.put(_backgroundTypeKey, defaultBackgroundType);
    await _box.put(_selectedPresetKey, defaultSelectedPreset);
    await _box.put(_backgroundImagePathKey, defaultBackgroundImagePath);
    // Don't reset theme - keep current setting
  }

  Future<void> toggleTheme(bool value) async {
    isLightTheme = value;
    await _box.put(_isLightThemeKey, value);
  }

  // Preset backgrounds
  static final List<Map<String, dynamic>> presetBackgrounds = [
    {
      'name': 'Midnight Blue',
      'colors': [const Color(0xFF0D0D1A), const Color(0xFF151528), const Color(0xFF0A0A14)],
      'type': 'gradient',
    },
    {
      'name': 'Forest Green',
      'colors': [const Color(0xFF0A1F0B), const Color(0xFF152815), const Color(0xFF0A1A0A)],
      'type': 'gradient',
    },
    {
      'name': 'Sunset Glow',
      'colors': [const Color(0xFF2C0E0E), const Color(0xFF3D1C1C), const Color(0xFF1F1212)],
      'type': 'gradient',
    },
    {
      'name': 'Ocean Deep',
      'colors': [const Color(0xFF0A1A2E), const Color(0xFF152538), const Color(0xFF0D1F2E)],
      'type': 'gradient',
    },
    {
      'name': 'Rose Gold',
      'colors': [const Color(0xFF2E1A1A), const Color(0xFF3D2525), const Color(0xFF1F1818)],
      'type': 'gradient',
    },
    {
      'name': 'Minimal Dark',
      'colors': [const Color(0xFF121212), const Color(0xFF121212), const Color(0xFF121212)],
      'type': 'gradient',
    },
    {
      'name': 'Aurora',
      'colors': [const Color(0xFF0D1F2D), const Color(0xFF152D3D), const Color(0xFF0A1F28)],
      'type': 'gradient',
    },
    {
      'name': 'Ember',
      'colors': [const Color(0xFF1F0F0A), const Color(0xFF2D1A15), const Color(0xFF1A100C)],
      'type': 'gradient',
    },
  ];

  // Predefined colors for pickers
  static final List<Color> bubbleColors = [
    const Color(0xFF1A3A5C), // Default blue
    const Color(0xFF1A5C3A), // Green
    const Color(0xFF5C1A3A), // Purple
    const Color(0xFF5C3A1A), // Orange/Brown
    const Color(0xFF1A5C5C), // Teal
    const Color(0xFF3A1A5C), // Violet
    const Color(0xFF5C1A1A), // Red
    const Color(0xFF1A1A5C), // Indigo
    const Color(0xFF5C5C1A), // Olive
    const Color(0xFF1A4A4A), // Cyan
    const Color(0xFF4A1A4A), // Magenta
    const Color(0xFF2A2A2A), // Gray
  ];

  static final List<Color> textColors = [
    const Color(0xFFE8E8F0), // Default white
    const Color(0xFFE8F0E8), // Light green tint
    const Color(0xFFF0E8E8), // Light red tint
    const Color(0xFFE8F0E8), // Light cyan tint
    const Color(0xFFF0F0E8), // Light yellow tint
    const Color(0xFFE8E8F0), // Light blue tint
    const Color(0xFFD0D0D0), // Gray
    const Color(0xFFB0B0B0), // Darker gray
  ];

  static final List<Color> backgroundColors = [
    const Color(0xFF121212), // Default dark
    const Color(0xFF0D0D1A), // Deep dark
    const Color(0xFF1A1A1A), // Slightly lighter
    const Color(0xFF0A0A0A), // Almost black
    const Color(0xFF151520), // Blue dark
    const Color(0xFF101015), // Purple dark
    const Color(0xFF0A1010), // Green dark
    const Color(0xFF100A10), // Red dark
  ];

  static final List<Color> backgroundColorsLight = [
    const Color(0xFFF5F9F5), // Default light green tint
    const Color(0xFFE8F0E8), // Light green
    const Color(0xFFE0E8E0), // Slightly darker green
    const Color(0xFFF0F5F0), // Very light green
    const Color(0xFFE8F0F5), // Light blue tint
    const Color(0xFFF5F0E8), // Light orange tint
    const Color(0xFFF0E8F0), // Light purple tint
    const Color(0xFFE8E8F0), // Light gray-blue
  ];
}
