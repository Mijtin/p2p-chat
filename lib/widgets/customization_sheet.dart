import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/theme_settings.dart';
import '../utils/constants.dart';


class CustomizationBottomSheet extends StatefulWidget {
  final ThemeSettings themeSettings;
  final VoidCallback onThemeChanged;

  const CustomizationBottomSheet({
    super.key,
    required this.themeSettings,
    required this.onThemeChanged,
  });

  @override
  State<CustomizationBottomSheet> createState() => _CustomizationBottomSheetState();
}

class _CustomizationBottomSheetState extends State<CustomizationBottomSheet> {
  late Color _outgoingBubbleColor;
  late Color _incomingBubbleColor;
  late Color _textColor;
  late Color _backgroundColor;
  late int _backgroundType;
  late int _selectedPreset;
  late String _backgroundImagePath;
  late bool _isLightTheme;
  bool _isLight = false;


  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
    _isLight = widget.themeSettings.isLightTheme;
  }

  void _loadCurrentSettings() {
    _outgoingBubbleColor = widget.themeSettings.outgoingBubbleColor;
    _incomingBubbleColor = widget.themeSettings.incomingBubbleColor;
    _textColor = widget.themeSettings.textColor;
    _backgroundColor = widget.themeSettings.backgroundColor;
    _backgroundType = widget.themeSettings.backgroundType;
    _selectedPreset = widget.themeSettings.selectedPreset;
    _backgroundImagePath = widget.themeSettings.backgroundImagePath;
    _isLightTheme = widget.themeSettings.isLightTheme;
    _isLight = _isLightTheme;
  }


  @override
  Widget build(BuildContext context) {
    _isLight = widget.themeSettings.isLightTheme;
    
    return Container(
      decoration: BoxDecoration(
        color: _isLight ? AppConstants.surfaceCardLight : AppConstants.surfaceCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: _isLight ? AppConstants.dividerColorLight : AppConstants.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppConstants.primaryColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.palette_outlined,
                        color: AppConstants.primaryColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Customization',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: _isLight ? AppConstants.textPrimaryLight : AppConstants.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.refresh, color: _isLight ? AppConstants.textSecondaryLight : AppConstants.textSecondary),
                      onPressed: _resetToDefaults,
                      tooltip: 'Reset to defaults',
                    ),
                  ],
                ),
              ),
              Divider(color: _isLight ? AppConstants.dividerColorLight : AppConstants.dividerColor, height: 1),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Theme Toggle Section
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppConstants.primaryColor.withOpacity(0.15),
                            AppConstants.secondaryColor.withOpacity(0.1),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppConstants.primaryColor.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppConstants.primaryColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              _isLightTheme ? Icons.light_mode : Icons.dark_mode,
                              color: AppConstants.primaryColor,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isLightTheme ? 'Light Theme' : 'Dark Theme',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: _isLight ? AppConstants.textPrimaryLight : AppConstants.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _isLightTheme
                                      ? 'Green-tinted light appearance'
                                      : 'Classic dark appearance',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: _isLight ? AppConstants.textSecondaryLight : AppConstants.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _isLightTheme,
                            onChanged: (value) {
                              setState(() {
                                _isLightTheme = value;
                              });
                              widget.themeSettings.toggleTheme(value);
                              widget.onThemeChanged();
                            },
                            activeColor: AppConstants.primaryColor,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Message Bubble Colors Section
                    _buildSectionTitle('Message Bubbles'),
                    const SizedBox(height: 12),
                    _buildColorPickerRow(
                      label: 'Outgoing',
                      color: _outgoingBubbleColor,
                      onColorSelected: (color) {
                        setState(() => _outgoingBubbleColor = color);
                        widget.themeSettings.setOutgoingBubbleColor(color);
                        widget.onThemeChanged();
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildColorPickerRow(
                      label: 'Incoming',
                      color: _incomingBubbleColor,
                      onColorSelected: (color) {
                        setState(() => _incomingBubbleColor = color);
                        widget.themeSettings.setIncomingBubbleColor(color);
                        widget.onThemeChanged();
                      },
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Text Color Section
                    _buildSectionTitle('Text Color'),
                    const SizedBox(height: 12),
                    _buildColorPickerRow(
                      label: 'Text',
                      color: _textColor,
                      onColorSelected: (color) {
                        setState(() => _textColor = color);
                        widget.themeSettings.setTextColor(color);
                        widget.onThemeChanged();
                      },
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Background Section
                    _buildSectionTitle('Chat Background'),
                    const SizedBox(height: 12),
                    
                    // Background type selector
                    Container(
                      decoration: BoxDecoration(
                        color: AppConstants.surfaceInput,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildBackgroundTypeButton(
                              label: 'Solid',
                              icon: Icons.color_lens_outlined,
                              isSelected: _backgroundType == 0,
                              onTap: () => _setBackgroundType(0),
                            ),
                          ),
                          Expanded(
                            child: _buildBackgroundTypeButton(
                              label: 'Presets',
                              icon: Icons.grid_view_rounded,
                              isSelected: _backgroundType == 2,
                              onTap: () => _setBackgroundType(2),
                            ),
                          ),
                          Expanded(
                            child: _buildBackgroundTypeButton(
                              label: 'Image',
                              icon: Icons.image_outlined,
                              isSelected: _backgroundType == 3,
                              onTap: () => _setBackgroundType(3),
                            ),
                          ),
                        ],
                      ),
                    ),

                    
                    const SizedBox(height: 16),
                    
                    // Background color/preset selector
                    if (_backgroundType == 0)
                      _buildSolidBackgroundPicker()
                    else if (_backgroundType == 2)
                      _buildPresetBackgroundPicker()
                    else if (_backgroundType == 3)
                      _buildImageBackgroundPicker(),

                    
                    const SizedBox(height: 24),
                    
                    // Preview Section
                    _buildSectionTitle('Preview'),
                    const SizedBox(height: 12),
                    _buildPreview(),
                    
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: _isLight ? AppConstants.textPrimaryLight : AppConstants.textPrimary,
      ),
    );
  }

  Widget _buildColorPickerRow({
    required String label,
    required Color color,
    required Function(Color) onColorSelected,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _isLight ? AppConstants.surfaceInputLight : AppConstants.surfaceInput,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: _isLight ? AppConstants.textSecondaryLight : AppConstants.textSecondary,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _showColorPicker(label, color, onColorSelected),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _isLight ? AppConstants.dividerColorLight : AppConstants.dividerColor,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundTypeButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppConstants.primaryColor.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? AppConstants.primaryColor : (_isLight ? AppConstants.textMutedLight : AppConstants.textMuted),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? AppConstants.primaryColor : (_isLight ? AppConstants.textMutedLight : AppConstants.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSolidBackgroundPicker() {
    // Use light or dark theme colors based on current theme
    final colors = _isLightTheme
        ? ThemeSettings.backgroundColorsLight
        : ThemeSettings.backgroundColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose solid color:',
          style: TextStyle(
            fontSize: 13,
            color: _isLight ? AppConstants.textMutedLight : AppConstants.textMuted,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: colors.map((color) {
            final isSelected = _backgroundColor.value == color.value && _backgroundType == 0;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _backgroundColor = color;
                  _backgroundType = 0;
                  _selectedPreset = -1;
                });
                widget.themeSettings.setBackgroundColor(color);
                widget.onThemeChanged();
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? AppConstants.primaryColor : (_isLight ? AppConstants.dividerColorLight : AppConstants.dividerColor),
                    width: isSelected ? 3 : 1,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, color: Colors.white, size: 20)
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPresetBackgroundPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose preset:',
          style: TextStyle(
            fontSize: 13,
            color: _isLight ? AppConstants.textMutedLight : AppConstants.textMuted,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.6,
          ),
          itemCount: ThemeSettings.presetBackgrounds.length,
          itemBuilder: (context, index) {
            final preset = ThemeSettings.presetBackgrounds[index];
            final colors = preset['colors'] as List<Color>;
            final isSelected = _selectedPreset == index && _backgroundType == 2;
            
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedPreset = index;
                  _backgroundType = 2;
                });
                widget.themeSettings.setPresetBackground(index);
                widget.onThemeChanged();
              },
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? AppConstants.primaryColor : AppConstants.dividerColor,
                    width: isSelected ? 3 : 1,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      bottom: 8,
                      left: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          preset['name'] as String,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Positioned(
                        top: 6,
                        right: 6,
                        child: Icon(
                          Icons.check_circle,
                          color: AppConstants.primaryColor,
                          size: 20,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPreview() {
    DecorationImage? backgroundImage;
    if (_backgroundType == 3 && _backgroundImagePath.isNotEmpty) {
      final file = File(_backgroundImagePath);
      if (file.existsSync()) {
        backgroundImage = DecorationImage(
          image: FileImage(file),
          fit: BoxFit.cover,
          opacity: 0.4,
        );
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _backgroundType == 2 && _selectedPreset >= 0
            ? null
            : (_backgroundType == 3 ? Colors.black : _backgroundColor),
        gradient: _backgroundType == 2 && _selectedPreset >= 0
            ? LinearGradient(
                colors: ThemeSettings.presetBackgrounds[_selectedPreset]['colors'] as List<Color>,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        image: backgroundImage,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isLight ? AppConstants.dividerColorLight : AppConstants.dividerColor,
        ),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Incoming message preview
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.5,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _incomingBubbleColor,
                      Color.lerp(_incomingBubbleColor, Colors.black, 0.1)!,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(18),
                  ),
                ),
                child: Text(
                  'Hello! How are you?',
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Outgoing message preview
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.5,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _outgoingBubbleColor,
                      Color.lerp(_outgoingBubbleColor, Colors.black, 0.1)!,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: Text(
                  'I\'m doing great, thanks!',
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _setBackgroundType(int type) {
    setState(() {
      _backgroundType = type;
      if (type == 0) {
        _selectedPreset = -1;
        _backgroundImagePath = '';
      } else if (type == 2 && _selectedPreset == -1) {
        _selectedPreset = 0;
        _backgroundImagePath = '';
      } else if (type == 3) {
        _selectedPreset = -1;
      }
    });
    
    if (type == 0) {
      widget.themeSettings.setBackgroundColor(_backgroundColor);
    } else if (type == 2) {
      widget.themeSettings.setPresetBackground(_selectedPreset >= 0 ? _selectedPreset : 0);
    } else if (type == 3 && _backgroundImagePath.isNotEmpty) {
      widget.themeSettings.setBackgroundImage(_backgroundImagePath);
    }
    widget.onThemeChanged();
  }

  Future<void> _pickBackgroundImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        setState(() {
          _backgroundImagePath = path;
          _backgroundType = 3;
        });
        await widget.themeSettings.setBackgroundImage(path);
        widget.onThemeChanged();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    }
  }

  Widget _buildImageBackgroundPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose background image:',
          style: TextStyle(
            fontSize: 13,
            color: _isLight ? AppConstants.textMutedLight : AppConstants.textMuted,
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _pickBackgroundImage,
          child: Container(
            width: double.infinity,
            height: 120,
            decoration: BoxDecoration(
              color: _isLight ? AppConstants.surfaceInputLight : AppConstants.surfaceInput,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _backgroundImagePath.isNotEmpty
                    ? AppConstants.primaryColor
                    : (_isLight ? AppConstants.dividerColorLight : AppConstants.dividerColor),
                width: _backgroundImagePath.isNotEmpty ? 2 : 1,
              ),
            ),
            child: _backgroundImagePath.isNotEmpty && File(_backgroundImagePath).existsSync()
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.file(
                      File(_backgroundImagePath),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 120,
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 40,
                        color: _isLight ? AppConstants.textMutedLight : AppConstants.textMuted,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap to select image',
                        style: TextStyle(
                          color: _isLight ? AppConstants.textMutedLight : AppConstants.textMuted,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        if (_backgroundImagePath.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Selected: ${_backgroundImagePath.split('/').last}',
                  style: TextStyle(
                    color: _isLight ? AppConstants.textSecondaryLight : AppConstants.textSecondary,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                color: AppConstants.errorColor,
                onPressed: () {
                  setState(() {
                    _backgroundImagePath = '';
                    _backgroundType = 0;
                  });
                  widget.themeSettings.setBackgroundColor(_backgroundColor);
                  widget.onThemeChanged();
                },
              ),
            ],
          ),
        ],
      ],
    );
  }


  void _showColorPicker(String title, Color currentColor, Function(Color) onColorSelected) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _isLight ? AppConstants.surfaceCardLight : AppConstants.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ColorPickerSheet(
        title: title,
        initialColor: currentColor,
        isLight: _isLight,
        onColorSelected: (color) {
          onColorSelected(color);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset to Defaults'),
        content: const Text('Are you sure you want to reset all customization settings to defaults?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.errorColor,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.themeSettings.resetToDefaults();
      setState(() {
        _loadCurrentSettings();
      });
      widget.onThemeChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings reset to defaults')),
        );
      }
    }
  }
}

class _ColorPickerSheet extends StatefulWidget {
  final String title;
  final Color initialColor;
  final bool isLight;
  final Function(Color) onColorSelected;

  const _ColorPickerSheet({
    required this.title,
    required this.initialColor,
    required this.isLight,
    required this.onColorSelected,
  });

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late Color _selectedColor;
  late double _hue;
  late double _saturation;
  late double _lightness;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
    final hslColor = HSLColor.fromColor(_selectedColor);
    _hue = hslColor.hue;
    _saturation = hslColor.saturation;
    _lightness = hslColor.lightness;
  }

  void _updateColor() {
    setState(() {
      _selectedColor = HSLColor.fromAHSL(1.0, _hue, _saturation, _lightness).toColor();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: widget.isLight ? AppConstants.dividerColorLight : AppConstants.dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Choose ${widget.title} Color',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: widget.isLight ? AppConstants.textPrimaryLight : AppConstants.textPrimary,
            ),
          ),
          const SizedBox(height: 24),

          // Color preview
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _selectedColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: widget.isLight ? AppConstants.dividerColorLight : AppConstants.dividerColor,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: _selectedColor.withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Hue slider
          _buildSlider(
            label: 'Hue',
            value: _hue,
            max: 360,
            activeColor: HSLColor.fromAHSL(1.0, _hue, 1.0, 0.5).toColor(),
            onChanged: (value) {
              _hue = value;
              _updateColor();
            },
          ),

          const SizedBox(height: 16),
          
          // Saturation slider
          _buildSlider(
            label: 'Saturation',
            value: _saturation * 100,
            max: 100,
            activeColor: _selectedColor,
            onChanged: (value) {
              _saturation = value / 100;
              _updateColor();
            },
          ),
          
          const SizedBox(height: 16),
          
          // Lightness slider
          _buildSlider(
            label: 'Lightness',
            value: _lightness * 100,
            max: 100,
            activeColor: _selectedColor,
            onChanged: (value) {
              _lightness = value / 100;
              _updateColor();
            },
          ),
          
          const SizedBox(height: 24),
          
          // Preset colors
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Quick Colors',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppConstants.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: ThemeSettings.bubbleColors.map((color) {
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedColor = color;
                    final hslColor = HSLColor.fromColor(color);
                    _hue = hslColor.hue;
                    _saturation = hslColor.saturation;
                    _lightness = hslColor.lightness;
                  });
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _selectedColor.value == color.value
                          ? AppConstants.primaryColor
                          : AppConstants.dividerColor,
                      width: _selectedColor.value == color.value ? 3 : 1,
                    ),
                  ),
                  child: _selectedColor.value == color.value
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : null,
                ),
              );
            }).toList(),
          ),
          
          const SizedBox(height: 24),
          
          // Apply button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => widget.onColorSelected(_selectedColor),
              child: const Text('Apply'),
            ),
          ),
          
          const SizedBox(height: 16),
        ],
      ),
    ),
    );
  }


  Widget _buildSlider({
    required String label,
    required double value,
    required double max,
    required Color activeColor,
    required Function(double) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: widget.isLight ? AppConstants.textSecondaryLight : AppConstants.textSecondary,
              ),
            ),
            Text(
              value.toInt().toString(),
              style: TextStyle(
                fontSize: 13,
                color: widget.isLight ? AppConstants.textMutedLight : AppConstants.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: activeColor,
            inactiveTrackColor: widget.isLight ? AppConstants.surfaceInputLight : AppConstants.surfaceInput,
            thumbColor: activeColor,
            overlayColor: activeColor.withOpacity(0.2),
            trackHeight: 6,
          ),
          child: Slider(
            value: value,
            min: 0,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
