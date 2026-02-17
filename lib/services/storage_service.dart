import 'package:hive_flutter/hive_flutter.dart';
import '../models/message.dart';
import '../models/chat.dart';
import '../utils/constants.dart';

class StorageService {
  late Box _messagesBox;
  late Box _settingsBox;
  late Box _chatsBox;

  Future<void> initialize() async {
    _messagesBox = Hive.box(AppConstants.messagesBox);
    _settingsBox = Hive.box(AppConstants.settingsBox);
    _chatsBox = Hive.box(AppConstants.chatsBox);
  }

  // ==================== MESSAGE OPERATIONS ====================

  Future<void> saveMessage(Message message) async {
    await _messagesBox.put(message.id, message.toJson());
  }

  Future<void> updateMessage(Message message) async {
    await _messagesBox.put(message.id, message.toJson());
  }

  Future<Message?> getMessage(String id) async {
    final data = _messagesBox.get(id);
    if (data == null) return null;
    return Message.fromJson(Map<String, dynamic>.from(data));
  }

  Future<List<Message>> getMessages() async {
    final messages = <Message>[];
    for (final key in _messagesBox.keys) {
      final data = _messagesBox.get(key);
      if (data != null) {
        try {
          final message = Message.fromJson(Map<String, dynamic>.from(data));
          messages.add(message);
        } catch (e) {
          print('Error parsing message: $e');
        }
      }
    }
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return messages;
  }

  Future<void> deleteMessage(String id) async {
    await _messagesBox.delete(id);
  }

  Future<void> clearAllMessages() async {
    await _messagesBox.clear();
  }

  // ==================== SYNC METHODS ====================

  /// Получить сообщения за последние N дней для синхронизации
  Future<List<Message>> getRecentMessages({int days = 2}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final allMessages = await getMessages();
    final recent = allMessages.where((m) => m.timestamp.isAfter(cutoff)).toList();
    // ★ FIX: Сортируем по времени
    recent.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return recent;
  }

  /// Получить манифест синхронизации — лёгкий список {id, timestamp, isDeleted}
  Future<List<Map<String, dynamic>>> getSyncManifest({int days = 2}) async {
    final messages = await getRecentMessages(days: days);
    return messages
        .map((m) => {
              'id': m.id,
              'timestamp': m.timestamp.toIso8601String(),
              'isDeleted': m.isDeleted,
            })
        .toList();
  }

  /// Получить сообщения по списку ID
  Future<List<Message>> getMessagesByIds(List<String> ids) async {
    final messages = <Message>[];
    for (final id in ids) {
      final msg = await getMessage(id);
      if (msg != null) messages.add(msg);
    }
    return messages;
  }

  /// Мягкое удаление — помечаем как удалённое, но сохраняем запись для синхронизации
  Future<void> softDeleteMessage(String id) async {
    final message = await getMessage(id);
    if (message != null) {
      final deleted = message.copyWith(
        isDeleted: true,
        text: '',
        filePath: null,
        fileName: null,
        fileSize: null,
      );
      await updateMessage(deleted);
    }
  }

  /// Применить удаления из синхронизации
  Future<void> applyDeletions(List<String> messageIds) async {
    for (final id in messageIds) {
      final message = await getMessage(id);
      if (message != null && !message.isDeleted) {
        final deleted = message.copyWith(
          isDeleted: true,
          text: '',
          filePath: null,
          fileName: null,
          fileSize: null,
        );
        await updateMessage(deleted);
      }
    }
  }

  /// Сохранить сообщение из синхронизации
  /// Сохраняет только если сообщения нет, или если входящее — удалённое
  Future<bool> saveMessageFromSync(Message message) async {
    final existing = await getMessage(message.id);
    if (existing == null) {
      await saveMessage(message);
      return true;
    }
    // Если существующее не удалено, а входящее удалено — применяем удаление
    if (!existing.isDeleted && message.isDeleted) {
      await updateMessage(message);
      return true;
    }
    return false;
  }

  /// Очистить старые удалённые сообщения (старше 3 дней)
  Future<void> cleanupOldDeletedMessages() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 3));
    final keysToDelete = <dynamic>[];

    for (final key in _messagesBox.keys) {
      final data = _messagesBox.get(key);
      if (data != null) {
        try {
          final message = Message.fromJson(Map<String, dynamic>.from(data));
          if (message.isDeleted && message.timestamp.isBefore(cutoff)) {
            keysToDelete.add(key);
          }
        } catch (_) {}
      }
    }

    for (final key in keysToDelete) {
      await _messagesBox.delete(key);
    }
  }

  // ==================== SETTINGS OPERATIONS ====================

  Future<void> saveSetting(String key, dynamic value) async {
    await _settingsBox.put(key, value);
  }

  Future<T?> getSetting<T>(String key, {T? defaultValue}) async {
    final value = _settingsBox.get(key, defaultValue: defaultValue);
    return value as T?;
  }

  Future<void> deleteSetting(String key) async {
    await _settingsBox.delete(key);
  }

  // Connection settings
  Future<void> savePeerId(String peerId) async {
    await saveSetting('peerId', peerId);
  }

  Future<String?> getPeerId() async {
    return await getSetting<String>('peerId');
  }

  Future<void> saveRemotePeerId(String remotePeerId) async {
    await saveSetting('remotePeerId', remotePeerId);
  }

  Future<String?> getRemotePeerId() async {
    return await getSetting<String>('remotePeerId');
  }

  Future<void> clearConnectionData() async {
    await deleteSetting('peerId');
    await deleteSetting('remotePeerId');
    await deleteSetting('connectionCode');
    await deleteSetting('isConnected');
  }

  Future<void> saveServerUrl(String serverUrl) async {
    await saveSetting('serverUrl', serverUrl);
  }

  Future<String?> getServerUrl() async {
    return await getSetting<String>('serverUrl');
  }

  Future<void> saveIsConnected(bool isConnected) async {
    await saveSetting('isConnected', isConnected);
  }

  Future<bool> getIsConnected() async {
    return await getSetting<bool>('isConnected', defaultValue: false) ?? false;
  }

  Future<void> saveConnectionCode(String code) async {
    await saveSetting('connectionCode', code);
  }

  Future<String?> getConnectionCode() async {
    return await getSetting<String>('connectionCode');
  }

  Future<void> saveDeviceId(String deviceId) async {
    await saveSetting('deviceId', deviceId);
  }

  Future<String?> getDeviceId() async {
    return await getSetting<String>('deviceId');
  }

  // Statistics
  Future<Map<String, dynamic>> getStatistics() async {
    final messages = await getMessages();
    final totalMessages = messages.length;
    final sentMessages = messages.where((m) => m.isOutgoing).length;
    final receivedMessages = messages.where((m) => !m.isOutgoing).length;
    final textMessages = messages.where((m) => m.type == 'text').length;
    final imageMessages = messages.where((m) => m.type == 'image').length;
    final fileMessages = messages.where((m) => m.type == 'file').length;
    final voiceMessages = messages.where((m) => m.type == 'voice').length;

    int totalFileSize = 0;
    for (final message in messages) {
      if (message.fileSize != null) {
        totalFileSize += message.fileSize!;
      }
    }

    return {
      'totalMessages': totalMessages,
      'sentMessages': sentMessages,
      'receivedMessages': receivedMessages,
      'textMessages': textMessages,
      'imageMessages': imageMessages,
      'fileMessages': fileMessages,
      'voiceMessages': voiceMessages,
      'totalFileSize': totalFileSize,
      'storageUsed': await _getStorageSize(),
    };
  }

  Future<int> _getStorageSize() async {
    int size = 0;
    for (final key in _messagesBox.keys) {
      final data = _messagesBox.get(key);
      if (data != null) {
        size += data.toString().length;
      }
    }
    return size;
  }

  // Paired devices
  Future<void> addPairedDevice({
    required String deviceId,
    required String deviceName,
    required String connectionCode,
    required String? lastConnectedAt,
    required int? totalMessages,
  }) async {
    final devices = await getPairedDevices();
    final existingIndex = devices.indexWhere((d) => d['deviceId'] == deviceId);

    final deviceData = {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'connectionCode': connectionCode,
      'lastConnectedAt': lastConnectedAt ?? DateTime.now().toIso8601String(),
      'totalMessages': totalMessages ?? 0,
    };

    if (existingIndex >= 0) {
      devices[existingIndex] = deviceData;
    } else {
      devices.add(deviceData);
    }

    devices.sort((a, b) {
      final aDate =
          DateTime.tryParse(a['lastConnectedAt'] ?? '') ?? DateTime(2000);
      final bDate =
          DateTime.tryParse(b['lastConnectedAt'] ?? '') ?? DateTime(2000);
      return bDate.compareTo(aDate);
    });

    await saveSetting('pairedDevices', devices);
  }

  Future<List<Map<String, dynamic>>> getPairedDevices() async {
    final devices =
        await getSetting<List<dynamic>>('pairedDevices', defaultValue: []);
    if (devices == null) return [];
    return devices.map((d) => Map<String, dynamic>.from(d)).toList();
  }

  Future<void> removePairedDevice(String deviceId) async {
    final devices = await getPairedDevices();
    devices.removeWhere((d) => d['deviceId'] == deviceId);
    await saveSetting('pairedDevices', devices);
  }

  Future<void> updateDeviceLastConnected(String deviceId) async {
    final devices = await getPairedDevices();
    final index = devices.indexWhere((d) => d['deviceId'] == deviceId);
    if (index >= 0) {
      devices[index]['lastConnectedAt'] = DateTime.now().toIso8601String();
      await saveSetting('pairedDevices', devices);
    }
  }

  Future<void> clearAllPairedDevices() async {
    await deleteSetting('pairedDevices');
  }

  // ==================== CHAT OPERATIONS ====================

  /// Сохранить чат
  Future<void> saveChat(Chat chat) async {
    await _chatsBox.put(chat.id, chat.toJson());
  }

  /// Получить чат по ID
  Future<Chat?> getChat(String id) async {
    final data = _chatsBox.get(id);
    if (data == null) return null;
    return Chat.fromJson(Map<String, dynamic>.from(data));
  }

  /// Получить все чаты (не архивные)
  Future<List<Chat>> getChats() async {
    final chats = <Chat>[];
    for (final key in _chatsBox.keys) {
      final data = _chatsBox.get(key);
      if (data != null) {
        try {
          final chat = Chat.fromJson(Map<String, dynamic>.from(data));
          if (!chat.isArchived) {
            chats.add(chat);
          }
        } catch (e) {
          print('Error parsing chat: $e');
        }
      }
    }
    // Сортируем по lastConnectedAt (новые сверху)
    chats.sort((a, b) {
      final aDate = a.lastConnectedAt ?? a.createdAt;
      final bDate = b.lastConnectedAt ?? b.createdAt;
      return bDate.compareTo(aDate);
    });
    return chats;
  }

  /// Удалить чат
  Future<void> deleteChat(String id) async {
    await _chatsBox.delete(id);
  }

  /// Очистить все чаты
  Future<void> clearAllChats() async {
    await _chatsBox.clear();
  }

  /// Получить активный чат (последний подключенный)
  Future<Chat?> getActiveChat() async {
    final chats = await getChats();
    if (chats.isEmpty) return null;
    return chats.first;
  }
}