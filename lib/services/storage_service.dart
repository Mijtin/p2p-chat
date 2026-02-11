import 'package:hive_flutter/hive_flutter.dart';
import '../models/message.dart';
import '../utils/constants.dart';

class StorageService {
  late Box _messagesBox;
  late Box _settingsBox;
  
  Future<void> initialize() async {
    _messagesBox = Hive.box(AppConstants.messagesBox);
    _settingsBox = Hive.box(AppConstants.settingsBox);
  }
  
  // Message operations
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
    
    // Sort by timestamp
    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return messages;
  }
  
  Future<void> deleteMessage(String id) async {
    await _messagesBox.delete(id);
  }
  
  Future<void> clearAllMessages() async {
    await _messagesBox.clear();
  }
  
  // Settings operations
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
  
  // Server URL
  Future<void> saveServerUrl(String serverUrl) async {
    await saveSetting('serverUrl', serverUrl);
  }
  
  Future<String?> getServerUrl() async {
    return await getSetting<String>('serverUrl');
  }
  
  // Connection status
  Future<void> saveIsConnected(bool isConnected) async {
    await saveSetting('isConnected', isConnected);
  }
  
  Future<bool> getIsConnected() async {
    return await getSetting<bool>('isConnected', defaultValue: false) ?? false;
  }
  
  // Connection code (6-digit)
  Future<void> saveConnectionCode(String code) async {
    await saveSetting('connectionCode', code);
  }
  
  Future<String?> getConnectionCode() async {
    return await getSetting<String>('connectionCode');
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
    
    // Calculate total file size
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
    // Approximate size in bytes
    int size = 0;
    for (final key in _messagesBox.keys) {
      final data = _messagesBox.get(key);
      if (data != null) {
        size += data.toString().length;
      }
    }
    return size;
  }
}
