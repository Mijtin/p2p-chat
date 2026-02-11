import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class Helpers {
  // Generate random 6-digit code
  static String generateSixDigitCode() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }
  
  // Format file size
  static String formatFileSize(int? bytes) {
    if (bytes == null) return 'Unknown size';
    
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  
  // Format duration
  static String formatDuration(int? milliseconds) {
    if (milliseconds == null) return '0:00';
    
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
  
  // Format date
  static String formatDate(DateTime date) {
    final now = DateTime.now();
    if (_isSameDay(date, now)) {
      return 'Today';
    } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM d, yyyy').format(date);
    }
  }
  
  // Format time
  static String formatTime(DateTime date) {
    return DateFormat('HH:mm').format(date);
  }
  
  // Check if same day
  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
  
  // Request permissions
  static Future<bool> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
      Permission.storage,
      Permission.photos,
    ].request();
    
    return statuses.values.every((status) => 
      status == PermissionStatus.granted || 
      status == PermissionStatus.limited
    );
  }
  
  // Check specific permission
  static Future<bool> checkPermission(Permission permission) async {
    final status = await permission.status;
    if (status.isGranted) return true;
    
    final result = await permission.request();
    return result.isGranted;
  }
  
  // Get temporary directory path
  static Future<String> getTempDirectory() async {
    final tempDir = await getTemporaryDirectory();
    return tempDir.path;
  }
  
  // Get application documents directory
  static Future<String> getDocumentsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return appDir.path;
  }
  
  // Create directory if not exists
  static Future<Directory> createDirectory(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }
  
  // Delete file
  static Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
  
  // Check if file exists
  static Future<bool> fileExists(String path) async {
    return File(path).exists();
  }
  
  // Get file extension
  static String getFileExtension(String fileName) {
    return fileName.split('.').last.toLowerCase();
  }
  
  // Check if file is image
  static bool isImageFile(String fileName) {
    final ext = getFileExtension(fileName);
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);
  }
  
  // Check if file is video
  static bool isVideoFile(String fileName) {
    final ext = getFileExtension(fileName);
    return ['mp4', 'avi', 'mov', 'mkv', 'flv', 'wmv'].contains(ext);
  }
  
  // Check if file is audio
  static bool isAudioFile(String fileName) {
    final ext = getFileExtension(fileName);
    return ['mp3', 'wav', 'aac', 'ogg', 'opus', 'm4a'].contains(ext);
  }
  
  // Show snackbar
  static void showSnackBar(BuildContext context, String message, {
    bool isError = false,
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: duration,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
  
  // Show dialog
  static Future<bool> showConfirmationDialog(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    bool isDangerous = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelText),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: isDangerous ? ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ) : null,
            child: Text(confirmText),
          ),
        ],
      ),
    );
    
    return result ?? false;
  }
  
  // Copy to clipboard
  static Future<void> copyToClipboard(String text) async {
    // Implementation would use clipboard package
    // For now, just a placeholder
  }
  
  // Share text
  static Future<void> shareText(String text) async {
    // Implementation would use share_plus package
    // For now, just a placeholder
  }
  
  // Generate unique ID
  static String generateUniqueId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000)}';
  }
  
  // Truncate text
  static String truncateText(String text, int maxLength, {String suffix = '...'}) {
    if (text.length <= maxLength) return text;
    return text.substring(0, maxLength - suffix.length) + suffix;
  }
  
  // Validate 6-digit code
  static bool isValidSixDigitCode(String code) {
    if (code.length != 6) return false;
    return int.tryParse(code) != null && code.startsWith(RegExp(r'[1-9]'));
  }
}
