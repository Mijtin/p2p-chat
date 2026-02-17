import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/chat.dart';
import 'storage_service.dart';

/// Менеджер чатов — управляет списком чатов и активным чатом
class ChatManager extends ChangeNotifier {
  final StorageService _storageService;
  final _uuid = const Uuid();

  List<Chat> _chats = [];
  Chat? _activeChat;
  bool _isLoading = false;

  final _chatsController = StreamController<List<Chat>>.broadcast();
  final _activeChatController = StreamController<Chat?>.broadcast();

  Stream<List<Chat>> get chatsStream => _chatsController.stream;
  Stream<Chat?> get activeChatStream => _activeChatController.stream;

  List<Chat> get chats => List.unmodifiable(_chats);
  Chat? get activeChat => _activeChat;
  bool get isLoading => _isLoading;

  ChatManager(this._storageService);

  /// Инициализация — загрузка списка чатов
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _storageService.initialize();
      _chats = await _storageService.getChats();
      _activeChat = null; // При старте нет активного чата

      _chatsController.add(List.unmodifiable(_chats));
      _activeChatController.add(null);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Создать новый чат (инициатор)
  Future<Chat> createChat({
    required String roomCode,
    required String serverUrl,
    String? deviceName,
  }) async {
    // Генерируем peerId из кода комнаты и device ID
    final deviceId = await _storageService.getDeviceId();
    final peerId = '${roomCode}_$deviceId';

    final chat = Chat(
      id: _uuid.v4(),
      peerId: peerId,
      deviceName: deviceName,
      roomCode: roomCode,
      serverUrl: serverUrl,
      createdAt: DateTime.now(),
      lastConnectedAt: DateTime.now(),
    );

    await _storageService.saveChat(chat);
    await _storageService.saveConnectionCode(roomCode);
    await _storageService.savePeerId(peerId);
    await _storageService.saveServerUrl(serverUrl);

    _chats.insert(0, chat);
    _chatsController.add(List.unmodifiable(_chats));
    notifyListeners();

    return chat;
  }

  /// Присоединиться к существующему чату (не инициатор)
  Future<Chat?> joinChat({
    required String roomCode,
    required String serverUrl,
    String? deviceName,
  }) async {
    // Проверяем, есть ли уже чат с таким roomCode
    Chat? existingChat;
    try {
      existingChat = _chats.firstWhere((c) => c.roomCode == roomCode);
    } catch (_) {
      // Чат не найден
    }

    if (existingChat != null && !existingChat.isArchived) {
      // Обновляем существующий
      final existingChatId = existingChat.id; // Сохраняем id для избежания warning
      final updated = existingChat.copyWith(
        lastConnectedAt: DateTime.now(),
        deviceName: deviceName ?? existingChat.deviceName,
      );
      await _storageService.saveChat(updated);
      _chats.removeWhere((c) => c.id == existingChatId);
      _chats.insert(0, updated);
      _chatsController.add(List.unmodifiable(_chats));
      notifyListeners();
      return updated;
    } else if (existingChat != null && existingChat.isArchived) {
      // Чат архивирован — создаём новый
    }

    // Создаём новый чат
    final deviceId = await _storageService.getDeviceId();
    final peerId = '${roomCode}_$deviceId';

    final chat = Chat(
      id: _uuid.v4(),
      peerId: peerId,
      deviceName: deviceName ?? 'Device ${peerId.substring(0, 6)}',
      roomCode: roomCode,
      serverUrl: serverUrl,
      createdAt: DateTime.now(),
      lastConnectedAt: DateTime.now(),
    );

    await _storageService.saveChat(chat);
    await _storageService.saveConnectionCode(roomCode);
    await _storageService.savePeerId(peerId);
    await _storageService.saveServerUrl(serverUrl);

    _chats.insert(0, chat);
    _chatsController.add(List.unmodifiable(_chats));
    notifyListeners();

    return chat;
  }

  /// Активировать чат (открыть соединение)
  Future<void> activateChat(Chat chat) async {
    if (_activeChat?.id == chat.id) {
      return; // Уже активен
    }

    // Закрываем предыдущий активный чат (если есть)
    if (_activeChat != null) {
      await _deactivateCurrentChat();
    }

    _activeChat = chat;

    // Сохраняем данные подключения
    await _storageService.saveConnectionCode(chat.roomCode);
    await _storageService.savePeerId(chat.peerId);
    await _storageService.saveServerUrl(chat.serverUrl);
    await _storageService.saveIsConnected(true);

    // Обновляем lastConnectedAt
    final updatedChat = chat.copyWith(lastConnectedAt: DateTime.now());
    await _storageService.saveChat(updatedChat);

    // Обновляем список
    _chats.removeWhere((c) => c.id == chat.id);
    _chats.insert(0, updatedChat);
    _activeChat = updatedChat;

    _chatsController.add(List.unmodifiable(_chats));
    _activeChatController.add(updatedChat);
    notifyListeners();
  }

  /// Деактивировать текущий чат (закрыть соединение)
  Future<void> _deactivateCurrentChat() async {
    if (_activeChat == null) return;

    await _storageService.saveIsConnected(false);
    _activeChat = null;
    _activeChatController.add(null);
    notifyListeners();
  }

  /// Деактивировать текущий чат (публичный метод для выхода из чата)
  Future<void> deactivateActiveChat() async {
    await _deactivateCurrentChat();
  }

  /// Переименовать чат
  Future<void> renameChat(String chatId, String newName) async {
    final chatIndex = _chats.indexWhere((c) => c.id == chatId);
    if (chatIndex == -1) return;

    final chat = _chats[chatIndex];
    final updatedChat = chat.copyWith(deviceName: newName);

    await _storageService.saveChat(updatedChat);
    _chats[chatIndex] = updatedChat;

    if (_activeChat?.id == chatId) {
      _activeChat = updatedChat;
      _activeChatController.add(updatedChat);
    }

    _chatsController.add(List.unmodifiable(_chats));
    notifyListeners();
  }

  /// Архивировать чат (мягкое удаление)
  Future<void> archiveChat(String chatId) async {
    final chatIndex = _chats.indexWhere((c) => c.id == chatId);
    if (chatIndex == -1) return;

    final chat = _chats[chatIndex];
    final updatedChat = chat.copyWith(isArchived: true);

    await _storageService.saveChat(updatedChat);
    _chats.removeAt(chatIndex);

    if (_activeChat?.id == chatId) {
      await _deactivateCurrentChat();
    }

    _chatsController.add(List.unmodifiable(_chats));
    _activeChatController.add(_activeChat);
    notifyListeners();
  }

  /// Удалить чат навсегда
  Future<void> deleteChat(String chatId) async {
    final chatIndex = _chats.indexWhere((c) => c.id == chatId);
    if (chatIndex == -1) return;

    final chat = _chats[chatIndex];

    await _storageService.deleteChat(chatId);
    _chats.removeAt(chatIndex);

    if (_activeChat?.id == chatId) {
      await _deactivateCurrentChat();
    }

    _chatsController.add(List.unmodifiable(_chats));
    _activeChatController.add(_activeChat);
    notifyListeners();
  }

  /// Обновить счётчик непрочитанных
  Future<void> updateUnreadCount(String chatId, int count) async {
    final chatIndex = _chats.indexWhere((c) => c.id == chatId);
    if (chatIndex == -1) return;

    final chat = _chats[chatIndex];
    if (chat.unreadCount == count) return;

    final updatedChat = chat.copyWith(unreadCount: count);
    await _storageService.saveChat(updatedChat);
    _chats[chatIndex] = updatedChat;

    if (_activeChat?.id == chatId) {
      _activeChat = updatedChat;
    }

    _chatsController.add(List.unmodifiable(_chats));
    notifyListeners();
  }

  /// Получить чат по ID
  Chat? getChatById(String id) {
    try {
      return _chats.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Получить активный peerId для WebRTC
  String? get activePeerId => _activeChat?.peerId;

  /// Получить активный roomCode
  String? get activeRoomCode => _activeChat?.roomCode;

  /// Получить активный serverUrl
  String? get activeServerUrl => _activeChat?.serverUrl;

  @override
  void dispose() {
    _chatsController.close();
    _activeChatController.close();
    super.dispose();
  }
}
