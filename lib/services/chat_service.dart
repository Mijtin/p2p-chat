import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:mime/mime.dart';
import '../models/message.dart';
import '../models/file_chunk.dart';
import '../utils/constants.dart';
import 'webrtc_service.dart';
import 'storage_service.dart';

/// Статус синхронизации
enum SyncStatus {
  idle,
  syncing,
  completed,
  error,
}

class ChatService extends ChangeNotifier {
  final WebRTCService _webRTCService;
  final StorageService _storageService;
  final _uuid = const Uuid();

  final _messagesController =
      StreamController<List<Message>>.broadcast();
  final _typingController = StreamController<bool>.broadcast();
  final _fileProgressController =
      StreamController<Map<String, double>>.broadcast();
  final _syncStatusController =
      StreamController<SyncStatus>.broadcast();

  Stream<List<Message>> get messages => _messagesController.stream;
  Stream<bool> get typingIndicator => _typingController.stream;
  Stream<Map<String, double>> get fileProgress =>
      _fileProgressController.stream;
  Stream<SyncStatus> get syncStatus => _syncStatusController.stream;

  // File transfer tracking
  final Map<String, FileTransferState> _activeFileTransfers = {};
  Timer? _typingTimer;
  List<Message> _currentMessages = [];

  // Sync state
  bool _isSyncing = false;
  bool _syncCompleted = false;

  // ★ FIX: Кэшируем deviceId чтобы не вызывать async каждый раз
  String? _cachedDeviceId;

  StreamSubscription<String>? _dataChannelStateSub;

  ChatService(this._webRTCService, this._storageService) {
    _setupListeners();
    _initDeviceId(); // ★ FIX
    _loadMessages();
  }

  // ★ FIX: Инициализация deviceId при создании сервиса
  Future<void> _initDeviceId() async {
    _cachedDeviceId = await _storageService.getDeviceId();
    debugPrint('[CHAT] Device ID cached: $_cachedDeviceId');
  }

  void _setupListeners() {
    _webRTCService.messages.listen(_handleIncomingMessage);
    _webRTCService.fileChunks.listen(_handleFileChunk);
    _webRTCService.typingIndicators.listen(_handleTypingIndicator);
    _webRTCService.deliveryReceipts.listen(_handleDeliveryReceipt);
    _dataChannelStateSub =
        _webRTCService.dataChannelState.listen(_handleDataChannelStateChange);
  }

  Future<void> _loadMessages() async {
    _currentMessages = await _storageService.getMessages();
    final visibleMessages =
        _currentMessages.where((m) => !m.isDeleted).toList();
    _messagesController.add(List.unmodifiable(visibleMessages));
    notifyListeners();
  }

  // ============================================================
  // SYNC LOGIC
  // ============================================================

  void _handleDataChannelStateChange(String state) {
    debugPrint('[SYNC] DataChannel state changed: $state');

    if (state == 'open') {
      _syncCompleted = false;
      _isSyncing = false;
      Future.delayed(const Duration(milliseconds: 500), () {
        _startSync();
      });
    } else if (state == 'closed') {
      _isSyncing = false;
      _syncCompleted = false;
      _syncStatusController.add(SyncStatus.idle);
    }
  }

  Future<void> _startSync() async {
    if (_isSyncing) {
      debugPrint('[SYNC] Already syncing, skipping');
      return;
    }
    if (!_webRTCService.isConnected) {
      debugPrint('[SYNC] Not connected, skipping sync');
      return;
    }

    _isSyncing = true;
    _syncStatusController.add(SyncStatus.syncing);

    try {
      await _storageService.cleanupOldDeletedMessages();

      final manifest = await _storageService.getSyncManifest(days: 2);

      // ★ FIX: Используем кэшированный deviceId
      final deviceId = _cachedDeviceId ?? await _storageService.getDeviceId() ?? 'unknown';

      final syncRequest = {
        'type': 'sync_request',
        'manifest': manifest,
        'deviceId': deviceId,
        'syncTimestamp': DateTime.now().toIso8601String(),
      };

      await _webRTCService.sendMessage(syncRequest);
      debugPrint(
          '[SYNC] Sent sync_request with ${manifest.length} message refs, deviceId=$deviceId');
    } catch (e) {
      debugPrint('[SYNC] Error starting sync: $e');
      _isSyncing = false;
      _syncStatusController.add(SyncStatus.error);
    }
  }

  Future<void> _handleSyncMessage(Map<String, dynamic> data) async {
    final type = data['type'];

    switch (type) {
      case 'sync_request':
        await _handleSyncRequest(data);
        break;
      case 'sync_response':
        await _handleSyncResponse(data);
        break;
      case 'sync_messages':
        await _handleSyncMessages(data);
        break;
      case 'sync_complete':
        _handleSyncComplete();
        break;
      case 'sync_delete':
        final messageId = data['messageId'] as String?;
        if (messageId != null) {
          await _storageService.softDeleteMessage(messageId);
          await _loadMessages();
          debugPrint('[SYNC] Applied real-time deletion: $messageId');
        }
        break;
    }
  }

  Future<void> _handleSyncRequest(Map<String, dynamic> data) async {
    debugPrint('[SYNC] Received sync_request');

    // ★ FIX: Запоминаем deviceId пира для правильного определения isOutgoing
    final peerDeviceId = data['deviceId'] as String? ?? 'unknown';
    debugPrint('[SYNC] Peer deviceId: $peerDeviceId');

    final peerManifest = (data['manifest'] as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final ourMessages = await _storageService.getRecentMessages(days: 2);
    final ourMessageMap = {for (var m in ourMessages) m.id: m};
    final ourIds = ourMessageMap.keys.toSet();

    final peerIds = <String>{};
    final peerDeletedIds = <String>{};
    for (final item in peerManifest) {
      final id = item['id'] as String;
      peerIds.add(id);
      if (item['isDeleted'] == true) {
        peerDeletedIds.add(id);
      }
    }

    final weNeed = peerIds.difference(ourIds).difference(peerDeletedIds);
    final peerNeeds = ourIds.difference(peerIds);

    final ourDeletedIds =
        ourMessages.where((m) => m.isDeleted).map((m) => m.id).toSet();
    final deletionsForPeer = ourDeletedIds.intersection(peerIds);
    final deletionsFromPeer = peerDeletedIds.intersection(ourIds);

    if (deletionsFromPeer.isNotEmpty) {
      await _storageService.applyDeletions(deletionsFromPeer.toList());
      debugPrint(
          '[SYNC] Applied ${deletionsFromPeer.length} deletions from peer');
    }

    // ★ FIX: Используем кэшированный deviceId
    final ourDeviceId = _cachedDeviceId ?? await _storageService.getDeviceId() ?? 'unknown';

    final messagesToSend = <Map<String, dynamic>>[];
    for (final id in peerNeeds) {
      final msg = ourMessageMap[id];
      if (msg != null && !msg.isDeleted) {
        final syncMsg = msg.toJson();
        // ★ FIX: Отправляем isOutgoing как оно есть у нас
        // Получатель инвертирует его
        syncMsg['_fromDeviceId'] = ourDeviceId;
        messagesToSend.add(syncMsg);
      }
    }

    const batchSize = 20;
    final messageBatches = <List<Map<String, dynamic>>>[];
    for (int i = 0; i < messagesToSend.length; i += batchSize) {
      final end = (i + batchSize < messagesToSend.length)
          ? i + batchSize
          : messagesToSend.length;
      messageBatches.add(messagesToSend.sublist(i, end));
    }

    final firstBatch =
        messageBatches.isNotEmpty ? messageBatches.first : <Map<String, dynamic>>[];

    final syncResponse = {
      'type': 'sync_response',
      'needMessages': weNeed.toList(),
      'messages': firstBatch,
      'deletions': deletionsForPeer.toList(),
      'totalBatches': messageBatches.length,
      'batchIndex': 0,
      'deviceId': ourDeviceId, // ★ FIX: Отправляем наш deviceId
    };

    await _webRTCService.sendMessage(syncResponse);
    debugPrint('[SYNC] Sent sync_response: need=${weNeed.length}, '
        'sending batch 1/${messageBatches.length} (${firstBatch.length} msgs), '
        'deletions=${deletionsForPeer.length}');

    for (int i = 1; i < messageBatches.length; i++) {
      await Future.delayed(const Duration(milliseconds: 50));

      final batchData = {
        'type': 'sync_messages',
        'messages': messageBatches[i],
        'batchIndex': i,
        'totalBatches': messageBatches.length,
        'deviceId': ourDeviceId, // ★ FIX
      };
      await _webRTCService.sendMessage(batchData);
      debugPrint(
          '[SYNC] Sent batch ${i + 1}/${messageBatches.length} (${messageBatches[i].length} msgs)');
    }

    if (!_isSyncing) {
      _isSyncing = true;
      _syncStatusController.add(SyncStatus.syncing);
    }

    await _loadMessages();
  }

  Future<void> _handleSyncResponse(Map<String, dynamic> data) async {
    debugPrint('[SYNC] Received sync_response');

    // ★ FIX: Получаем deviceId пира из ответа
    final peerDeviceId = data['deviceId'] as String? ?? 'unknown';

    // 1. Сохраняем сообщения от пира
    await _processSyncMessages(
        data['messages'] as List<dynamic>? ?? [], peerDeviceId);

    // 2. Применяем удаления
    final deletions = (data['deletions'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    if (deletions.isNotEmpty) {
      await _storageService.applyDeletions(deletions);
      debugPrint('[SYNC] Applied ${deletions.length} deletions');
    }

    // 3. Отправляем запрошенные сообщения
    final needMessageIds = (data['needMessages'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();

    if (needMessageIds.isNotEmpty) {
      final messagesToSend =
          await _storageService.getMessagesByIds(needMessageIds);
      final ourDeviceId =
          _cachedDeviceId ?? await _storageService.getDeviceId() ?? 'unknown';

      final syncMessages = messagesToSend
          .where((m) => !m.isDeleted)
          .map((m) {
        final json = m.toJson();
        json['_fromDeviceId'] = ourDeviceId; // ★ FIX
        return json;
      }).toList();

      const batchSize = 20;
      for (int i = 0; i < syncMessages.length; i += batchSize) {
        final end = (i + batchSize < syncMessages.length)
            ? i + batchSize
            : syncMessages.length;
        final batch = syncMessages.sublist(i, end);

        if (i > 0) {
          await Future.delayed(const Duration(milliseconds: 50));
        }

        final syncData = {
          'type': 'sync_messages',
          'messages': batch,
          'batchIndex': i ~/ batchSize,
          'totalBatches': (syncMessages.length / batchSize).ceil(),
          'deviceId': ourDeviceId, // ★ FIX
        };

        await _webRTCService.sendMessage(syncData);
        debugPrint(
            '[SYNC] Sent ${batch.length} requested messages (batch ${(i ~/ batchSize) + 1})');
      }
    }

    await _loadMessages();

    _isSyncing = false;
    _syncCompleted = true;
    _syncStatusController.add(SyncStatus.completed);

    try {
      await _webRTCService.sendMessage({'type': 'sync_complete'});
    } catch (_) {}

    debugPrint('[SYNC] Sync completed');
  }

  Future<void> _handleSyncMessages(Map<String, dynamic> data) async {
    final batchIndex = data['batchIndex'] ?? 0;
    final totalBatches = data['totalBatches'] ?? 1;
    final peerDeviceId = data['deviceId'] as String? ?? 'unknown'; // ★ FIX
    debugPrint(
        '[SYNC] Received sync_messages batch ${batchIndex + 1}/$totalBatches');

    await _processSyncMessages(
        data['messages'] as List<dynamic>? ?? [], peerDeviceId); // ★ FIX
    await _loadMessages();

    if (batchIndex >= totalBatches - 1) {
      _isSyncing = false;
      _syncCompleted = true;
      _syncStatusController.add(SyncStatus.completed);
      debugPrint('[SYNC] All batches received, sync completed');
    }
  }

  // ★ FIX: Полностью переработанная логика определения isOutgoing
  Future<int> _processSyncMessages(
      List<dynamic> rawMessages, String peerDeviceId) async {
    final ourDeviceId =
        _cachedDeviceId ?? await _storageService.getDeviceId() ?? 'unknown';
    int savedCount = 0;

    for (final rawMsg in rawMessages) {
      try {
        final msgData = Map<String, dynamic>.from(rawMsg);
        final message = Message.fromJson(msgData);
        final fromDeviceId = msgData['_fromDeviceId'] as String?;

        // ★ FIX: Логика определения isOutgoing:
        // Сообщение пришло от пира. У пира оно сохранено с его isOutgoing.
        // Если у пира isOutgoing=true — значит пир его написал → для нас isOutgoing=false
        // Если у пира isOutgoing=false — значит мы его написали → для нас isOutgoing=true
        //
        // Альтернативный подход через _fromDeviceId:
        // Если _fromDeviceId == наш deviceId — значит это сообщение от нас, пир его не менял
        // Если _fromDeviceId == deviceId пира — значит это от пира

        bool isOutgoingForUs;

        if (fromDeviceId != null && fromDeviceId == ourDeviceId) {
          // Пир отправил нам наше же сообщение — значит isOutgoing сохранён как у пира
          // У пира наше сообщение isOutgoing=false, значит для нас = true
          // Но проще: инвертируем isOutgoing пира
          isOutgoingForUs = !message.isOutgoing;
        } else if (fromDeviceId != null && fromDeviceId == peerDeviceId) {
          // Сообщение с устройства пира — инвертируем
          isOutgoingForUs = !message.isOutgoing;
        } else {
          // Fallback: инвертируем всегда, т.к. пир отправляет своё представление
          isOutgoingForUs = !message.isOutgoing;
        }

        final adjustedMessage = message.copyWith(isOutgoing: isOutgoingForUs);

        debugPrint('[SYNC] Message ${message.id.substring(0, 8)}: '
            'fromDevice=$fromDeviceId, '
            'peerIsOutgoing=${message.isOutgoing}, '
            'ourIsOutgoing=$isOutgoingForUs, '
            'text="${message.text.length > 20 ? message.text.substring(0, 20) : message.text}"');

        final saved =
            await _storageService.saveMessageFromSync(adjustedMessage);
        if (saved) savedCount++;
      } catch (e) {
        debugPrint('[SYNC] Error processing sync message: $e');
      }
    }

    debugPrint('[SYNC] Processed and saved $savedCount new messages');
    return savedCount;
  }

  void _handleSyncComplete() {
    debugPrint('[SYNC] Peer confirmed sync complete');
    if (!_syncCompleted) {
      _syncCompleted = true;
      _isSyncing = false;
      _syncStatusController.add(SyncStatus.completed);
    }
  }

  Future<void> forceSync() async {
    _syncCompleted = false;
    _isSyncing = false;
    await _startSync();
  }

  // ============================================================
  // SEND MESSAGES
  // ============================================================

  Future<Message> sendTextMessage(String text,
      {String? replyToMessageId}) async {
    final message = Message(
      id: _uuid.v4(),
      text: text,
      timestamp: DateTime.now(),
      isOutgoing: true,
      type: AppConstants.messageTypeText,
      replyToMessageId: replyToMessageId,
    );

    await _storageService.saveMessage(message);
    await _loadMessages();

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

  Future<Message> sendFile(String filePath, {String? caption}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('File does not exist');
    }

    final fileSize = await file.length();
    if (fileSize > AppConstants.maxFileSize) {
      throw Exception('File size exceeds 100MB limit');
    }

    final fileName = filePath.split(Platform.pathSeparator).last;
    final mimeType =
        lookupMimeType(filePath) ?? 'application/octet-stream';
    final isImage = mimeType.startsWith('image/');

    final message = Message(
      id: _uuid.v4(),
      text: caption ?? fileName,
      timestamp: DateTime.now(),
      isOutgoing: true,
      type: isImage
          ? AppConstants.messageTypeImage
          : AppConstants.messageTypeFile,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
      filePath: filePath,
      status: 'sending',
    );

    await _storageService.saveMessage(message);
    await _loadMessages();

    try {
      await _webRTCService.sendMessage({
        ...message.toJson(),
        'fileTransfer': true,
      });

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

  Future<void> _sendFileInChunks(
      String messageId, String filePath, int fileSize) async {
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

      final progress = (i + 1) / totalChunks;
      _fileProgressController.add({messageId: progress});

      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<Message> sendVoiceMessage(String audioPath, int duration) async {
    final file = File(audioPath);
    if (!await file.exists()) {
      throw Exception('Audio file does not exist');
    }

    final fileSize = await file.length();
    final fileName = audioPath.split(Platform.pathSeparator).last;

    // Определяем mimeType по расширению
    String mimeType;
    if (audioPath.endsWith('.m4a') || audioPath.endsWith('.aac')) {
      mimeType = 'audio/aac';
    } else if (audioPath.endsWith('.ogg') || audioPath.endsWith('.opus')) {
      mimeType = 'audio/opus';
    } else if (audioPath.endsWith('.wav')) {
      mimeType = 'audio/wav';
    } else {
      mimeType = 'audio/aac';
    }

    final message = Message(
      id: _uuid.v4(),
      text: 'Voice message',
      timestamp: DateTime.now(),
      isOutgoing: true,
      type: AppConstants.messageTypeVoice,
      filePath: audioPath,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: mimeType,
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
  

  // ============================================================
  // TYPING
  // ============================================================

  void sendTypingIndicator(bool isTyping) {
    _webRTCService.sendTypingIndicator(isTyping);

    if (isTyping) {
      _typingTimer?.cancel();
      _typingTimer = Timer(AppConstants.typingTimeout, () {
        sendTypingIndicator(false);
      });
    }
  }

  // ============================================================
  // INCOMING MESSAGE HANDLING
  // ============================================================

  void _handleIncomingMessage(Map<String, dynamic> data) {
    // Проверяем — это sync-сообщение?
    final type = data['type'] as String?;
    if (type != null && type.startsWith('sync_')) {
      _handleSyncMessage(data);
      return;
    }

    final isFileTransfer = data['fileTransfer'] ?? false;

    if (!isFileTransfer) {
      // ★ FIX: Обычное текстовое сообщение — всегда isOutgoing=false
      final message = Message.fromJson(data);
      final incomingMessage = message.copyWith(
        isOutgoing: false,
        status: 'delivered',
      );

      _storageService.saveMessage(incomingMessage);
      _loadMessages();

      _webRTCService.sendDeliveryReceipt(message.id, 'delivered');
    } else {
      final messageId = data['id'];
      final fileSize = data['fileSize'] ?? 0;
      final totalChunks = (fileSize / AppConstants.chunkSize).ceil();

      _activeFileTransfers[messageId] = FileTransferState(
        fileId: _uuid.v4(),
        messageId: messageId,
        fileName: data['fileName'] ?? 'unknown',
        fileSize: fileSize,
        totalChunks: totalChunks,
        chunks: List<Uint8List?>.filled(totalChunks, null),
      );

      final message = Message.fromJson(data);
      final incomingMessage = message.copyWith(
        isOutgoing: false,
        status: 'receiving',
        filePath: null,
      );
      _storageService.saveMessage(incomingMessage);
      _loadMessages();
    }
  }

  Future<void> _handleFileChunk(Map<String, dynamic> data) async {
    final messageId = data['messageId'];
    final chunkIndex = data['chunkIndex'];
    final totalChunks = data['totalChunks'];
    final chunkData = base64Decode(data['data']);

    var transferState = _activeFileTransfers[messageId];
    if (transferState == null) return;

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

    if (receivedChunks == totalChunks) {
      await _assembleFile(transferState, data);
    }
  }

  Future<void> _assembleFile(FileTransferState transferState,
      Map<String, dynamic> originalData) async {
    try {
      final BytesBuilder fileBytes = BytesBuilder();
      for (final chunk in transferState.chunks) {
        if (chunk != null) {
          fileBytes.add(chunk);
        }
      }

      final tempDir = await getTemporaryDirectory();
      final fileName = transferState.fileName;
      final filePath =
          '${tempDir.path}${Platform.pathSeparator}$fileName';
      final file = File(filePath);
      await file.writeAsBytes(fileBytes.toBytes());

      final messageId = transferState.messageId;
      final existingMessage =
          await _storageService.getMessage(messageId);

      if (existingMessage != null) {
        final completedMessage = existingMessage.copyWith(
          filePath: filePath,
          status: 'delivered',
        );

        await _storageService.updateMessage(completedMessage);
        await _loadMessages();

        _webRTCService.sendDeliveryReceipt(messageId, 'delivered');
      }

      _activeFileTransfers.remove(transferState.messageId);
    } catch (e) {
      debugPrint('Error assembling file: $e');
      _activeFileTransfers.remove(transferState.messageId);
    }
  }

  void _handleTypingIndicator(Map<String, dynamic> data) {
    final isTyping = data['isTyping'] ?? false;
    _typingController.add(isTyping);
  }

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

  // ============================================================
  // MESSAGE ACTIONS
  // ============================================================

  Future<void> markAsRead(String messageId) async {
    final message = await _storageService.getMessage(messageId);
    if (message != null &&
        !message.isOutgoing &&
        message.status != 'read') {
      final updatedMessage = message.copyWith(status: 'read');
      await _storageService.updateMessage(updatedMessage);

      _webRTCService.sendDeliveryReceipt(messageId, 'read');
      await _loadMessages();
    }
  }

  Future<void> deleteMessage(String messageId) async {
    await _storageService.softDeleteMessage(messageId);
    await _loadMessages();

    try {
      if (_webRTCService.isConnected) {
        await _webRTCService.sendMessage({
          'type': 'sync_delete',
          'messageId': messageId,
        });
      }
    } catch (_) {}
  }

  Future<void> clearAllMessages() async {
    await _storageService.clearAllMessages();
    await _loadMessages();
  }

  Future<Message?> getMessage(String id) async {
    return await _storageService.getMessage(id);
  }

  List<Message> get currentMessages =>
      List.unmodifiable(
          _currentMessages.where((m) => !m.isDeleted));

  bool get isSyncing => _isSyncing;

  @override
  void dispose() {
    _messagesController.close();
    _typingController.close();
    _fileProgressController.close();
    _syncStatusController.close();
    _dataChannelStateSub?.cancel();
    _typingTimer?.cancel();
    super.dispose();
  }
}