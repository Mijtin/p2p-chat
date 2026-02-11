import 'package:flutter/material.dart';

class AppConstants {
  // App Info
  static const String appName = 'P2P Chat v0.1';
  static const String appVersion = '0.1.0';

  
  // Colors
  static const Color primaryColor = Color(0xFF6366F1);
  static const Color secondaryColor = Color(0xFF8B5CF6);
  static const Color successColor = Color(0xFF10B981);
  static const Color errorColor = Color(0xFFEF4444);
  static const Color warningColor = Color(0xFFF59E0B);
  static const Color infoColor = Color(0xFF3B82F6);
  
  // Connection Colors
  static const Color onlineColor = Color(0xFF10B981);
  static const Color offlineColor = Color(0xFF6B7280);
  static const Color connectingColor = Color(0xFFF59E0B);
  
  // UI Constants
  static const double borderRadius = 12.0;
  static const double padding = 16.0;
  static const double smallPadding = 8.0;
  static const double largePadding = 24.0;
  
  // Animation Durations
  static const Duration shortAnimation = Duration(milliseconds: 200);
  static const Duration mediumAnimation = Duration(milliseconds: 300);
  static const Duration longAnimation = Duration(milliseconds: 500);
  
  // Hive Boxes
  static const String messagesBox = 'messages';
  static const String settingsBox = 'settings';
  static const String filesBox = 'files';
  
  // WebRTC Configuration
  static const Map<String, dynamic> iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ]
  };
  
  // Signaling Server
  static const String signalingServerUrl = 'https://your-render-app.onrender.com';
  static const int signalingServerPort = 9000;
  
  // File Transfer
  static const int chunkSize = 16384; // 16 KB chunks
  static const int maxFileSize = 104857600; // 100 MB
  
  // Audio
  static const String audioFormat = 'opus';
  static const int audioSampleRate = 48000;
  static const int audioBitRate = 24000;
  
  // Timeouts
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration reconnectDelay = Duration(seconds: 5);
  static const Duration typingTimeout = Duration(seconds: 3);
  static const Duration messageRetryDelay = Duration(seconds: 3);
  
  // Message Types
  static const String messageTypeText = 'text';
  static const String messageTypeImage = 'image';
  static const String messageTypeFile = 'file';
  static const String messageTypeVoice = 'voice';
  static const String messageTypeTyping = 'typing';
  static const String messageTypeDelivery = 'delivery';
  static const String messageTypeRead = 'read';
  
  // Connection Status
  static const String statusOnline = 'online';
  static const String statusOffline = 'offline';
  static const String statusConnecting = 'connecting';
  static const String statusError = 'error';
}
