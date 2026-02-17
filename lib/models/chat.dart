import 'package:equatable/equatable.dart';

class Chat extends Equatable {
  final String id;
  final String peerId;
  final String? deviceName;
  final String roomCode;
  final String serverUrl;
  final DateTime createdAt;
  final DateTime? lastConnectedAt;
  final bool isArchived;
  final int unreadCount;

  Chat({
    required this.id,
    required this.peerId,
    this.deviceName,
    required this.roomCode,
    required this.serverUrl,
    required this.createdAt,
    this.lastConnectedAt,
    this.isArchived = false,
    this.unreadCount = 0,
  });

  Chat copyWith({
    String? id,
    String? peerId,
    String? deviceName,
    String? roomCode,
    String? serverUrl,
    DateTime? createdAt,
    DateTime? lastConnectedAt,
    bool? isArchived,
    int? unreadCount,
  }) {
    return Chat(
      id: id ?? this.id,
      peerId: peerId ?? this.peerId,
      deviceName: deviceName ?? this.deviceName,
      roomCode: roomCode ?? this.roomCode,
      serverUrl: serverUrl ?? this.serverUrl,
      createdAt: createdAt ?? this.createdAt,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      isArchived: isArchived ?? this.isArchived,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'peerId': peerId,
      'deviceName': deviceName,
      'roomCode': roomCode,
      'serverUrl': serverUrl,
      'createdAt': createdAt.toIso8601String(),
      'lastConnectedAt': lastConnectedAt?.toIso8601String(),
      'isArchived': isArchived,
      'unreadCount': unreadCount,
    };
  }

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'] ?? '',
      peerId: json['peerId'] ?? '',
      deviceName: json['deviceName'],
      roomCode: json['roomCode'] ?? '',
      serverUrl: json['serverUrl'] ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      lastConnectedAt: json['lastConnectedAt'] != null
          ? DateTime.tryParse(json['lastConnectedAt'])
          : null,
      isArchived: json['isArchived'] ?? false,
      unreadCount: json['unreadCount'] ?? 0,
    );
  }

  String get displayName => deviceName ?? 'Device ${peerId.substring(0, 6)}';

  @override
  List<Object?> get props => [
        id,
        peerId,
        deviceName,
        roomCode,
        serverUrl,
        createdAt,
        lastConnectedAt,
        isArchived,
        unreadCount,
      ];
}
