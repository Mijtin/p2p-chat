import 'package:flutter/material.dart';

class AppConstants {
  // App info
  static const String appName = 'P2P Chat';
  static const String appVersion = '1.0.0';

  // === DARK THEME COLOR PALETTE ===
  static const Color primaryColor = Color(0xFF2979FF);
  static const Color secondaryColor = Color(0xFF00BFA5);
  static const Color accentColor = Color(0xFF448AFF);

  // Surfaces
  static const Color surfaceDark = Color(0xFF121212);
  static const Color surfaceCard = Color(0xFF1E1E2E);
  static const Color surfaceElevated = Color(0xFF252540);
  static const Color surfaceInput = Color(0xFF2A2A3E);

  // Bubbles
  static const Color outgoingBubble = Color(0xFF1A3A5C);
  static const Color incomingBubble = Color(0xFF1E2D3D);

  // Text
  static const Color textPrimary = Color(0xFFE8E8F0);
  static const Color textSecondary = Color(0xFF9E9EB8);
  static const Color textMuted = Color(0xFF6B6B8A);

  // Status colors — ЭТИ БЫЛИ ПРОПУЩЕНЫ
  static const Color successColor = Color(0xFF00E676);
  static const Color errorColor = Color(0xFFFF5252);
  static const Color warningColor = Color(0xFFFFAB40);
  static const Color onlineColor = Color(0xFF00E676);
  static const Color offlineColor = Color(0xFFFF5252);
  static const Color connectingColor = Color(0xFFFFAB40);

  // Divider
  static const Color dividerColor = Color(0xFF2E2E48);

  // Storage
  static const String messagesBox = 'messages';
  static const String settingsBox = 'settings';

  // Sizing
  static const double padding = 16.0;
  static const double borderRadius = 16.0;

  // Connection status
  static const String statusConnecting = 'connecting';
  static const String statusOnline = 'online';
  static const String statusOffline = 'offline';
  static const String statusError = 'error';

  // WebRTC Configuration
  static const Map<String, dynamic> iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {
        'urls': [
          'turn:a.relay.metered.ca:80',
          'turn:a.relay.metered.ca:80?transport=tcp',
          'turn:a.relay.metered.ca:443',
          'turn:a.relay.metered.ca:443?transport=tcp',
          'turns:a.relay.metered.ca:443',
        ],
        'username': 'e8dd65b92f6dce1b1c4af5a3',
        'credential': '2VfGjLQUPHFID0Q3',
      },
    ]
  };

  // Signaling Server
  static const String signalingServerUrl = 'https://p2p-chat-csjq.onrender.com';

  // File Transfer
  static const int chunkSize = 16384;
  static const int maxFileSize = 104857600;

  // Audio
  static const String audioFormat = 'opus';
  static const int audioSampleRate = 48000;
  static const int audioBitRate = 24000;

  // Timeouts
  static const Duration connectionTimeout = Duration(seconds: 90);
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
}
