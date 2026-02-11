import 'dart:typed_data';
import 'package:equatable/equatable.dart';

class FileChunk extends Equatable {
  final String fileId;
  final String messageId;
  final int chunkIndex;
  final int totalChunks;
  final List<int> data;
  final String? fileName;
  final String? mimeType;
  final int? fileSize;

  const FileChunk({
    required this.fileId,
    required this.messageId,
    required this.chunkIndex,
    required this.totalChunks,
    required this.data,
    this.fileName,
    this.mimeType,
    this.fileSize,
  });

  Map<String, dynamic> toJson() {
    return {
      'fileId': fileId,
      'messageId': messageId,
      'chunkIndex': chunkIndex,
      'totalChunks': totalChunks,
      'data': data,
      'fileName': fileName,
      'mimeType': mimeType,
      'fileSize': fileSize,
    };
  }

  factory FileChunk.fromJson(Map<String, dynamic> json) {
    return FileChunk(
      fileId: json['fileId'],
      messageId: json['messageId'],
      chunkIndex: json['chunkIndex'],
      totalChunks: json['totalChunks'],
      data: List<int>.from(json['data']),
      fileName: json['fileName'],
      mimeType: json['mimeType'],
      fileSize: json['fileSize'],
    );
  }

  @override
  List<Object?> get props => [
        fileId,
        messageId,
        chunkIndex,
        totalChunks,
        data,
        fileName,
        mimeType,
        fileSize,
      ];
}

class FileTransferState extends Equatable {
  final String fileId;
  final String messageId;
  final String fileName;
  final int fileSize;
  final int totalChunks;
  final int receivedChunks;
  final List<Uint8List?> chunks;
  final bool isComplete;
  final bool isFailed;
  final String? errorMessage;

  const FileTransferState({
    required this.fileId,
    required this.messageId,
    required this.fileName,
    required this.fileSize,
    required this.totalChunks,
    this.receivedChunks = 0,
    required this.chunks,
    this.isComplete = false,
    this.isFailed = false,
    this.errorMessage,
  });

  double get progress => totalChunks > 0 ? receivedChunks / totalChunks : 0;

  FileTransferState copyWith({
    String? fileId,
    String? messageId,
    String? fileName,
    int? fileSize,
    int? totalChunks,
    int? receivedChunks,
    List<Uint8List?>? chunks,
    bool? isComplete,
    bool? isFailed,
    String? errorMessage,
  }) {
    return FileTransferState(
      fileId: fileId ?? this.fileId,
      messageId: messageId ?? this.messageId,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      totalChunks: totalChunks ?? this.totalChunks,
      receivedChunks: receivedChunks ?? this.receivedChunks,
      chunks: chunks ?? this.chunks,
      isComplete: isComplete ?? this.isComplete,
      isFailed: isFailed ?? this.isFailed,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        fileId,
        messageId,
        fileName,
        fileSize,
        totalChunks,
        receivedChunks,
        chunks,
        isComplete,
        isFailed,
        errorMessage,
      ];
}
