import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/chat.dart';
import '../services/chat_manager.dart';
import '../services/storage_service.dart';
import '../services/signaling_service.dart';
import '../services/webrtc_service.dart';
import '../utils/constants.dart';
import '../widgets/chat_list_tile.dart';
import '../widgets/customization_sheet.dart';
import '../main.dart' show themeSettings;
import 'chat_screen.dart';
import 'create_chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late ChatManager _chatManager;
  final StorageService _storageService = StorageService();

  List<Chat> _chats = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeChatManager();
  }

  Future<void> _initializeChatManager() async {
    await _storageService.initialize();
    _chatManager = ChatManager(_storageService);
    
    // ★ FIX: Сначала подписываемся на стрим, потом инициализируем
    _chatManager.chatsStream.listen((chats) {
      if (mounted) {
        setState(() {
          _chats = chats;
          _isLoading = false;
        });
      }
    });
    
    // Инициализируем менеджер - после загрузки чаты придут в стрим
    await _chatManager.initialize();
  }

  void _openCreateChatMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => CreateChatBottomSheet(
        onCreateChat: _handleCreateChat,
        onJoinChat: _handleJoinChat,
      ),
    );
  }

  Future<void> _handleCreateChat({
    required String roomCode,
    required String serverUrl,
  }) async {
    try {
      final chat = await _chatManager.createChat(
        roomCode: roomCode,
        serverUrl: serverUrl,
      );
      await _navigateToChat(chat);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create chat: $e'),
            backgroundColor: AppConstants.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _handleJoinChat({
    required String roomCode,
    required String serverUrl,
  }) async {
    try {
      final chat = await _chatManager.joinChat(
        roomCode: roomCode,
        serverUrl: serverUrl,
      );
      if (chat != null) {
        await _navigateToChat(chat);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to join chat: $e'),
            backgroundColor: AppConstants.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _navigateToChat(Chat chat) async {
    // Активируем чат
    await _chatManager.activateChat(chat);

    final signalingService = SignalingService();
    final webRTCService = WebRTCService(signalingService);

    if (!mounted) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          chat: chat,
          chatManager: _chatManager,
          signalingService: signalingService,
          storageService: _storageService,
          webRTCService: webRTCService,
        ),
      ),
    );

    // После возврата из чата — деактивируем
    await _chatManager.deactivateActiveChat();

    // Если нужно вернуться на главный экран (например, при ошибке)
    if (result == true && mounted) {
      // Остаёмся на главном
    }
  }

  void _showRenameDialog(Chat chat) {
    final controller = TextEditingController(text: chat.deviceName ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppConstants.surfaceCard,
        title: const Text('Rename Device'),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AppConstants.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Device name',
            hintStyle: TextStyle(color: AppConstants.textMuted),
          ),
          autofocus: true,
          onSubmitted: (value) async {
            if (value.trim().isNotEmpty) {
              await _chatManager.renameChat(chat.id, value.trim());
            }
            if (context.mounted) Navigator.pop(context);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await _chatManager.renameChat(chat.id, controller.text.trim());
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showChatOptions(Chat chat) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppConstants.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: AppConstants.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: AppConstants.primaryColor),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(context);
                _showRenameDialog(chat);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: AppConstants.errorColor),
              title: const Text('Delete', style: TextStyle(color: AppConstants.errorColor)),
              onTap: () {
                Navigator.pop(context);
                _confirmDeleteChat(chat);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteChat(Chat chat) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppConstants.surfaceCard,
        title: const Text('Delete Chat'),
        content: Text('Are you sure you want to delete chat with ${chat.displayName}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _chatManager.deleteChat(chat.id);
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.errorColor,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showCustomizationSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CustomizationBottomSheet(
        themeSettings: themeSettings,
        onThemeChanged: () {
          if (mounted) {
            setState(() {});
          }
        },
      ),
    );
  }

  String _formatLastConnected(DateTime? date) {
    if (date == null) return 'Never';

    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return DateFormat('MMM d, yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final isLight = themeSettings.isLightTheme;
    
    if (_isLoading) {
      return Scaffold(
        backgroundColor: isLight ? AppConstants.surfaceLight : AppConstants.surfaceDark,
        body: const Center(
          child: CircularProgressIndicator(color: AppConstants.primaryColor),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isLight ? AppConstants.surfaceLight : AppConstants.surfaceDark,
      appBar: AppBar(
        backgroundColor: isLight ? AppConstants.surfaceCardLight : AppConstants.surfaceCard,
        title: const Text(
          AppConstants.appName,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.tune, color: isLight ? AppConstants.textSecondaryLight : AppConstants.textSecondary),
            onPressed: _showCustomizationSheet,
            tooltip: 'Customization',
          ),
        ],
      ),
      body: _chats.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _chats.length,
              itemBuilder: (context, index) {
                final chat = _chats[index];
                return ChatListTile(
                  chat: chat,
                  onTap: () => _navigateToChat(chat),
                  onLongPress: () => _showChatOptions(chat),
                  lastConnectedText: _formatLastConnected(chat.lastConnectedAt),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateChatMenu,
        backgroundColor: AppConstants.primaryColor,
        icon: const Icon(Icons.add),
        label: const Text('New Chat'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppConstants.primaryColor.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_outline,
              size: 56,
              color: AppConstants.primaryColor.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No chats yet',
            style: TextStyle(
              color: AppConstants.textSecondary,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a new chat to start messaging',
            style: TextStyle(
              color: AppConstants.textMuted,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _openCreateChatMenu,
            icon: const Icon(Icons.add),
            label: const Text('Create Chat'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _chatManager.dispose();
    super.dispose();
  }
}
