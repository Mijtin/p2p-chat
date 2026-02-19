// models/message.dart
import 'package:equatable/equatable.dart';

class Message extends Equatable {
  final String id;
  final String text;
  final DateTime timestamp;
  final bool isOutgoing;
  final String type;
  final String? chatId; // ← Идентификатор чата, к которому относится сообщение
  final String? filePath;
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  final String status;
  final int? duration;
  final String? replyToMessageId;
  final bool isDeleted;
  final bool isEdited;

  Message({
    required this.id,
    required this.text,
    required this.timestamp,
    required this.isOutgoing,
    this.type = 'text',
    this.chatId,
    this.filePath,
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.status = 'sending',
    this.duration,
    this.replyToMessageId,
    this.isDeleted = false,
    this.isEdited = false,
  });

  Message copyWith({
    String? id,
    String? text,
    DateTime? timestamp,
    bool? isOutgoing,
    String? type,
    String? chatId,
    String? filePath,
    String? fileName,
    int? fileSize,
    String? mimeType,
    String? status,
    int? duration,
    String? replyToMessageId,
    bool? isDeleted,
    bool? isEdited,
  }) {
    return Message(
      id: id ?? this.id,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      type: type ?? this.type,
      chatId: chatId ?? this.chatId,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      status: status ?? this.status,
      duration: duration ?? this.duration,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      isDeleted: isDeleted ?? this.isDeleted,
      isEdited: isEdited ?? this.isEdited,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'isOutgoing': isOutgoing,
      'type': type,
      'chatId': chatId,
      'filePath': filePath,
      'fileName': fileName,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'status': status,
      'duration': duration,
      'replyToMessageId': replyToMessageId,
      'isDeleted': isDeleted,
      'isEdited': isEdited,
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] ?? '',
      text: json['text'] ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      isOutgoing: json['isOutgoing'] ?? false,
      type: json['type'] ?? 'text',
      chatId: json['chatId'],
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
        id, text, timestamp, isOutgoing, type, chatId,
        filePath, fileName, fileSize, mimeType,
        status, duration, replyToMessageId, isDeleted, isEdited,
      ];
}