// models/message.dart
import 'package:equatable/equatable.dart';

class Message extends Equatable {
  final String id;
  final String text;
  final DateTime timestamp;
  final bool isOutgoing;
  final String type;
  final String? filePath;
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  final String status;
  final int? duration;
  final String? replyToMessageId;
  final bool isDeleted;
  final bool isEdited; // <-- НОВОЕ

  Message({
    required this.id,
    required this.text,
    required this.timestamp,
    required this.isOutgoing,
    this.type = 'text',
    this.filePath,
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.status = 'sending',
    this.duration,
    this.replyToMessageId,
    this.isDeleted = false,
    this.isEdited = false, // <-- НОВОЕ
  });

  Message copyWith({
    String? id,
    String? text,
    DateTime? timestamp,
    bool? isOutgoing,
    String? type,
    String? filePath,
    String? fileName,
    int? fileSize,
    String? mimeType,
    String? status,
    int? duration,
    String? replyToMessageId,
    bool? isDeleted,
    bool? isEdited, // <-- НОВОЕ
  }) {
    return Message(
      id: id ?? this.id,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      type: type ?? this.type,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      status: status ?? this.status,
      duration: duration ?? this.duration,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      isDeleted: isDeleted ?? this.isDeleted,
      isEdited: isEdited ?? this.isEdited, // <-- НОВОЕ
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'isOutgoing': isOutgoing,
      'type': type,
      'filePath': filePath,
      'fileName': fileName,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'status': status,
      'duration': duration,
      'replyToMessageId': replyToMessageId,
      'isDeleted': isDeleted,
      'isEdited': isEdited, // <-- НОВОЕ
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] ?? '',                    // ★ FIX: защита от null
      text: json['text'] ?? '',                // ★ FIX: защита от null
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      isOutgoing: json['isOutgoing'] ?? false,
      type: json['type'] ?? 'text',
      filePath: json['filePath'],
      fileName: json['fileName'],
      fileSize: json['fileSize'],
      mimeType: json['mimeType'],
      status: json['status'] ?? 'sending',
      duration: json['duration'],
      replyToMessageId: json['replyToMessageId'],
      isDeleted: json['isDeleted'] ?? false,
      isEdited: json['isEdited'] ?? false,
    );
  }

  @override
  List<Object?> get props => [
        id, text, timestamp, isOutgoing, type,
        filePath, fileName, fileSize, mimeType,
        status, duration, replyToMessageId, isDeleted, isEdited, // <-- НОВОЕ
      ];
}