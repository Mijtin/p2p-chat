import 'package:equatable/equatable.dart';

class ConnectionStateModel extends Equatable {
  final String status; // online, offline, connecting, error
  final String? errorMessage;
  final DateTime? connectedAt;
  final DateTime? disconnectedAt;
  final String? peerId;
  final String? remotePeerId;
  final bool isTyping;
  final DateTime? lastActivity;

  const ConnectionStateModel({
    this.status = 'offline',
    this.errorMessage,
    this.connectedAt,
    this.disconnectedAt,
    this.peerId,
    this.remotePeerId,
    this.isTyping = false,
    this.lastActivity,
  });

  bool get isOnline => status == 'online';
  bool get isOffline => status == 'offline';
  bool get isConnecting => status == 'connecting';
  bool get hasError => status == 'error';

  ConnectionStateModel copyWith({
    String? status,
    String? errorMessage,
    DateTime? connectedAt,
    DateTime? disconnectedAt,
    String? peerId,
    String? remotePeerId,
    bool? isTyping,
    DateTime? lastActivity,
  }) {
    return ConnectionStateModel(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      connectedAt: connectedAt ?? this.connectedAt,
      disconnectedAt: disconnectedAt ?? this.disconnectedAt,
      peerId: peerId ?? this.peerId,
      remotePeerId: remotePeerId ?? this.remotePeerId,
      isTyping: isTyping ?? this.isTyping,
      lastActivity: lastActivity ?? this.lastActivity,
    );
  }

  @override
  List<Object?> get props => [
        status,
        errorMessage,
        connectedAt,
        disconnectedAt,
        peerId,
        remotePeerId,
        isTyping,
        lastActivity,
      ];
}

class ChatUser extends Equatable {
  final String id;
  final String? name;
  final String? avatar;
  final bool isOnline;
  final DateTime? lastSeen;

  const ChatUser({
    required this.id,
    this.name,
    this.avatar,
    this.isOnline = false,
    this.lastSeen,
  });

  ChatUser copyWith({
    String? id,
    String? name,
    String? avatar,
    bool? isOnline,
    DateTime? lastSeen,
  }) {
    return ChatUser(
      id: id ?? this.id,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  List<Object?> get props => [id, name, avatar, isOnline, lastSeen];
}

class TypingIndicator extends Equatable {
  final String userId;
  final bool isTyping;
  final DateTime timestamp;

  const TypingIndicator({
    required this.userId,
    required this.isTyping,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'isTyping': isTyping,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory TypingIndicator.fromJson(Map<String, dynamic> json) {
    return TypingIndicator(
      userId: json['userId'],
      isTyping: json['isTyping'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  @override
  List<Object?> get props => [userId, isTyping, timestamp];
}

class DeliveryReceipt extends Equatable {
  final String messageId;
  final String status; // delivered, read
  final DateTime timestamp;

  const DeliveryReceipt({
    required this.messageId,
    required this.status,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'status': status,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory DeliveryReceipt.fromJson(Map<String, dynamic> json) {
    return DeliveryReceipt(
      messageId: json['messageId'],
      status: json['status'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  @override
  List<Object?> get props => [messageId, status, timestamp];
}
