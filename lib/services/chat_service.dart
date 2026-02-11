import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:mime/mime.dart';
import '../models/message.dart';
import '../models/file_chunk.dart';
import '../utils/constants.dart';
import 'webrtc_service.dart';
import 'storage_service.dart';

class ChatService {
  final WebRTCService _webRTCService;
  final StorageService _storageService;
  final _uuid = const Uuid();
  
  final _messagesController = StreamController<List<Message>>.broadcast();
  final _typingController = StreamController<bool>.broadcast();
  final _fileProgressController = StreamController<Map<String, double>>.broadcast();
  
  Stream<List<Message>> get messages => _messagesController.stream;
  Stream<bool> get typingIndicator => _typingController.stream;
  Stream<Map<String, double>> get fileProgress => _fileProgressController.stream;
  
  // File transfer tracking
  final Map<String, FileTransferState> _activeFileTransfers = {};
  Timer? _typingTimer;
  
  ChatService(this._webRTCService, this._storageService) {
    _setupListeners();
    _loadMessages();
  }
  
  void _setupListeners() {
    // Listen for incoming messages
    _webRTCService.messages.listen(_handleIncomingMessage);
    
    // Listen for file chunks
    _webRTCService.fileChunks.listen(_handleFileChunk);
    
    // Listen for typing indicators
    _webRTCService.typingIndicators.listen(_handleTypingIndicator);
    
    // Listen for delivery receipts
    _webRTCService.deliveryReceipts.listen(_handleDeliveryReceipt);
  }
  
  Future<void> _loadMessages() async {
    final messages = await _storageService.getMessages();
    _messagesController.add(messages);
  }
  
  // Send text message
  Future<Message> sendTextMessage(String text, {String? replyToMessageId}) async {
    final message = Message(
      id: _uuid.v4(),
      text: text,
      timestamp: DateTime.now(),
      isOutgoing: true,
      type: AppConstants.messageTypeText,
      replyToMessageId: replyToMessageId,
    );
    
    // Save to local storage
    await _storageService.saveMessage(message);
    await _loadMessages();
    
    // Send via WebRTC
    try {
      await _webRTCService.sendMessage(message.toJson());
      final updatedMessage = message.copyWith(status: 'sent');
      await _storageService.updateMessage(updatedMessage);
      await _loadMessages();
      return updatedMessage;
    } catch (e) {
      final updatedMessage = message.copyWith(status: 'failed');
      await _storageService.updateMessage(updatedMessage);
      await _loadMessages();
      throw Exception('Failed to send message: $e');
    }
  }
  
  // Send file (image or document)
  Future<Message> sendFile(String filePath, {String? caption}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File does not exist');
    }
    
    final fileSize = await file.length();
    if (fileSize > AppConstants.maxFileSize) {
      throw Exception('File size exceeds 100MB limit');
    }
    
    final fileName = filePath.split('/').last;
    final mimeType = lookupMimeType(filePath) ?? 'application/octet-stream';
    final isImage = mimeType.startsWith('image/');
    
    final message = Message(
      id: _uuid.v4(),
      text: caption ?? fileName,
      timestamp: DateTime.now(),
      isOutgoing: true,
      type: isImage ? AppConstants.messageTypeImage : AppConstants.messageTypeFile,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
      status: 'sending',
    );
    
    // Save to local storage
    await _storageService.saveMessage(message);
    await _loadMessages();
    
    // Send file metadata first
    try {
      await _webRTCService.sendMessage({
        ...message.toJson(),
        'fileTransfer': true,
      });
      
      // Send file in chunks
      await _sendFileInChunks(message.id, filePath, fileSize);
      
      final updatedMessage = message.copyWith(status: 'sent');
      await _storageService.updateMessage(updatedMessage);
      await _loadMessages();
      return updatedMessage;
    } catch (e) {
      final updatedMessage = message.copyWith(status: 'failed');
      await _storageService.updateMessage(updatedMessage);
      await _loadMessages();
      throw Exception('Failed to send file: $e');
    }
  }
  
  Future<void> _sendFileInChunks(String messageId, String filePath, int fileSize) async {
    final file = File(filePath);
    final fileId = _uuid.v4();
    final totalChunks = (fileSize / AppConstants.chunkSize).ceil();
    
    final bytes = await file.readAsBytes();
    
    for (int i = 0; i < totalChunks; i++) {
      final start = i * AppConstants.chunkSize;
      final end = (start + AppConstants.chunkSize < fileSize) 
          ? start + AppConstants.chunkSize 
          : fileSize;
      
      final chunk = bytes.sublist(start, end);
      
      final chunkData = {
        'fileId': fileId,
        'messageId': messageId,
        'chunkIndex': i,
        'totalChunks': totalChunks,
        'data': base64Encode(chunk),
      };
      
      await _webRTCService.sendFileChunk(chunkData);
      
      // Update progress
      final progress = (i + 1) / totalChunks;
      _fileProgressController.add({messageId: progress});
      
      // Small delay to prevent overwhelming the connection
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }
  
  // Send voice message (placeholder for now)
  Future<Message> sendVoiceMessage(String audioPath, int duration) async {
    final file = File(audioPath);
    if (!await file.exists()) {
      throw Exception('Audio file does not exist');
    }
    
    final fileSize = await file.length();
    final fileName = audioPath.split('/').last;
    
    final message = Message(
      id: _uuid.v4(),
      text: 'Voice message',
      timestamp: DateTime.now(),
      isOutgoing: true,
      type: AppConstants.messageTypeVoice,
      filePath: audioPath,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: 'audio/opus',
      duration: duration,
      status: 'sending',
    );
    
    await _storageService.saveMessage(message);
    await _loadMessages();
    
    try {
      await _webRTCService.sendMessage({
        ...message.toJson(),
        'fileTransfer': true,
      });
      
      await _sendFileInChunks(message.id, audioPath, fileSize);
      
      final updatedMessage = message.copyWith(status: 'sent');
      await _storageService.updateMessage(updatedMessage);
      await _loadMessages();
      return updatedMessage;
    } catch (e) {
      final updatedMessage = message.copyWith(status: 'failed');
      await _storageService.updateMessage(updatedMessage);
      await _loadMessages();
      throw Exception('Failed to send voice message: $e');
    }
  }
  
  // Typing indicator
  void sendTypingIndicator(bool isTyping) {
    _webRTCService.sendTypingIndicator(isTyping);
    
    if (isTyping) {
      _typingTimer?.cancel();
      _typingTimer = Timer(AppConstants.typingTimeout, () {
        sendTypingIndicator(false);
      });
    }
  }
  
  // Handle incoming message
  void _handleIncomingMessage(Map<String, dynamic> data) {
    final isFileTransfer = data['fileTransfer'] ?? false;
    
    if (!isFileTransfer) {
      // Regular text message
      final message = Message.fromJson(data);
      final incomingMessage = message.copyWith(
        isOutgoing: false,
        status: 'delivered',
      );
      
      _storageService.saveMessage(incomingMessage);
      _loadMessages();
      
      // Send delivery receipt
      _webRTCService.sendDeliveryReceipt(message.id, 'delivered');
    } else {
      // File transfer - initialize file receiver
      final messageId = data['id'];
      final fileSize = data['fileSize'];
      final totalChunks = (fileSize / AppConstants.chunkSize).ceil();
      
      _activeFileTransfers[messageId] = FileTransferState(
        fileId: _uuid.v4(),
        messageId: messageId,
        fileName: data['fileName'] ?? 'unknown',
        fileSize: fileSize,
        totalChunks: totalChunks,
        chunks: List<Uint8List?>.filled(totalChunks, null),
      );
      
      // Save message placeholder
      final message = Message.fromJson(data);
      final incomingMessage = message.copyWith(
        isOutgoing: false,
        status: 'receiving',
      );
      _storageService.saveMessage(incomingMessage);
      _loadMessages();
    }
  }
  
  // Handle incoming file chunk
  Future<void> _handleFileChunk(Map<String, dynamic> data) async {
    final messageId = data['messageId'];
    final chunkIndex = data['chunkIndex'];
    final totalChunks = data['totalChunks'];
    final chunkData = base64Decode(data['data']);
    
    var transferState = _activeFileTransfers[messageId];
    if (transferState == null) return;
    
    // Store chunk
    final chunks = List<Uint8List?>.from(transferState.chunks);
    chunks[chunkIndex] = chunkData;
    
    final receivedChunks = chunks.where((c) => c != null).length;
    final progress = receivedChunks / totalChunks;
    
    _fileProgressController.add({messageId: progress});
    
    transferState = transferState.copyWith(
      chunks: chunks,
      receivedChunks: receivedChunks,
    );
    _activeFileTransfers[messageId] = transferState;
    
    // Check if complete
    if (receivedChunks == totalChunks) {
      await _assembleFile(transferState, data);
    }
  }
  
  Future<void> _assembleFile(FileTransferState transferState, Map<String, dynamic> originalData) async {
    try {
      // Combine all chunks
      final BytesBuilder fileBytes = BytesBuilder();
      for (final chunk in transferState.chunks) {
        if (chunk != null) {
          fileBytes.add(chunk);
        }
      }
      
      // Save to temporary directory
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/${transferState.fileName}';
      final file = File(filePath);
      await file.writeAsBytes(fileBytes.toBytes());
      
      // Update message with file path
      final message = Message.fromJson(originalData);
      final completedMessage = message.copyWith(
        isOutgoing: false,
        filePath: filePath,
        status: 'delivered',
      );
      
      await _storageService.updateMessage(completedMessage);
      await _loadMessages();
      
      // Send delivery receipt
      _webRTCService.sendDeliveryReceipt(message.id, 'delivered');
      
      // Cleanup
      _activeFileTransfers.remove(transferState.messageId);
      
    } catch (e) {
      print('Error assembling file: $e');
      _activeFileTransfers.remove(transferState.messageId);
    }
  }
  
  // Handle typing indicator
  void _handleTypingIndicator(Map<String, dynamic> data) {
    final isTyping = data['isTyping'] ?? false;
    _typingController.add(isTyping);
  }
  
  // Handle delivery receipt
  Future<void> _handleDeliveryReceipt(Map<String, dynamic> data) async {
    final messageId = data['messageId'];
    final status = data['status'];
    
    final message = await _storageService.getMessage(messageId);
    if (message != null) {
      final updatedMessage = message.copyWith(status: status);
      await _storageService.updateMessage(updatedMessage);
      await _loadMessages();
    }
  }
  
  // Mark message as read
  Future<void> markAsRead(String messageId) async {
    final message = await _storageService.getMessage(messageId);
    if (message != null && !message.isOutgoing && message.status != 'read') {
      final updatedMessage = message.copyWith(status: 'read');
      await _storageService.updateMessage(updatedMessage);
      
      // Send read receipt
      _webRTCService.sendDeliveryReceipt(messageId, 'read');
      await _loadMessages();
    }
  }
  
  // Delete message
  Future<void> deleteMessage(String messageId) async {
    await _storageService.deleteMessage(messageId);
    await _loadMessages();
  }
  
  // Clear all messages
  Future<void> clearAllMessages() async {
    await _storageService.clearAllMessages();
    await _loadMessages();
  }
  
  // Get message by ID
  Future<Message?> getMessage(String id) async {
    return await _storageService.getMessage(id);
  }
  
  void dispose() {
    _messagesController.close();
    _typingController.close();
    _fileProgressController.close();
    _typingTimer?.cancel();
  }
}
