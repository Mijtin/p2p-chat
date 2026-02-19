import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:intl/intl.dart';
import '../models/message.dart';
import '../models/chat.dart';
import '../models/connection_state.dart' as app_state;
import '../services/chat_manager.dart';
import '../services/signaling_service.dart';
import '../services/webrtc_service.dart';
import '../services/chat_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/theme_settings.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';
import '../widgets/connection_status.dart';
import '../widgets/customization_sheet.dart';
import '../main.dart' show themeSettings;

class ChatScreen extends StatefulWidget {
  final Chat chat;
  final ChatManager chatManager;
  final SignalingService signalingService;
  final StorageService storageService;
  final WebRTCService webRTCService;

  const ChatScreen({
    super.key,
    required this.chat,
    required this.chatManager,
    required this.signalingService,
    required this.storageService,
    required this.webRTCService,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  late WebRTCService _webRTCService;
  late ChatService _chatService;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioRecorder _audioRecorder = AudioRecorder();

  List<Message> _messages = [];
  app_state.ConnectionStateModel _connectionState = const app_state.ConnectionStateModel(
    status: AppConstants.statusConnecting,
  );
  bool _isTyping = false;
  bool _isRecording = false;
  String? _currentlyPlayingAudio;
  final Map<String, double> _fileProgress = {};

  Message? _replyToMessage;
  Message? _editingMessage;

  DateTime? _recordingStartTime;
  Timer? _recordingTimer;
  Duration _recordingDuration = Duration.zero;
  bool _recordingCancelled = false;

  StreamSubscription? _audioPlayerSubscription;
  StreamSubscription? _messagesSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _typingSubscription;
  StreamSubscription? _fileProgressSubscription;

  bool _isConnecting = true; // По умолчанию true для показа индикатора
  bool _isInitiator = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    _webRTCService = widget.webRTCService;

    // ★ FIX: Сначала устанавливаем chatId ДО подключения к серверу
    // Это гарантирует, что сообщения не будут обработаны до установки chatId
    _chatService = ChatService(_webRTCService, widget.storageService);
    await _chatService.setChatId(widget.chat.id);

    // Теперь подключаемся к серверу
    await _connectToServer();
    _setupListeners();
  }

  Future<void> _connectToServer() async {
    setState(() {
      _isConnecting = true;
      _connectionState = const app_state.ConnectionStateModel(
        status: AppConstants.statusConnecting,
      );
    });

    try {
      // Закрываем предыдущие соединения
      await _webRTCService.closeConnection();
      await widget.signalingService.disconnect();

      final deviceId = await _getOrCreateDeviceId();
      final peerId = '${widget.chat.roomCode}_$deviceId';

      // Подключаемся к сигнальному серверу
      await widget.signalingService.connect(
        roomCode: widget.chat.roomCode,
        customPeerId: peerId,
        serverUrl: widget.chat.serverUrl,
        isInitiator: true,
      );

      // Небольшая задержка для получения списка пиров
      await Future.delayed(const Duration(milliseconds: 500));

      // Определяем, кто инициатор по peerId (меньший = инициатор)
      final otherPeers = widget.signalingService.peersInRoom;
      if (otherPeers.isEmpty) {
        _isInitiator = true;
      } else {
        final otherPeerId = otherPeers.first;
        _isInitiator = peerId.compareTo(otherPeerId) < 0;
      }

      debugPrint('[CHAT] Role: ${_isInitiator ? "Initiator" : "Joiner"}, peerId=$peerId, otherPeers=$otherPeers');

      // Инициализируем WebRTC
      await _webRTCService.initialize(
        isInitiator: _isInitiator,
        remotePeerId: otherPeers.isNotEmpty ? otherPeers.first : null,
      );

      setState(() {
        _isConnecting = false;
      });
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _connectionState = const app_state.ConnectionStateModel(
          status: AppConstants.statusError,
          errorMessage: 'Connection failed',
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection error: $e'),
            backgroundColor: AppConstants.errorColor,
            action: SnackBarAction(
              label: 'Retry',
              textColor: AppConstants.primaryColor,
              onPressed: _reconnect,
            ),
          ),
        );
      }
    }
  }

  Future<void> _reconnect() async {
    await _connectToServer();
  }

  Future<String> _getOrCreateDeviceId() async {
    String? savedDeviceId = await widget.storageService.getDeviceId();
    if (savedDeviceId == null) {
      final random = Random();
      savedDeviceId = '${random.nextInt(999).toString().padLeft(3, '0')}';
      await widget.storageService.saveDeviceId(savedDeviceId);
    }
    return savedDeviceId;
  }

  void _setupListeners() {
    _messagesSubscription = _chatService.messages.listen((messages) {
      if (mounted) {
        setState(() {
          _messages = messages;
        });
        _scrollToBottom();
      }
    });

    _connectionSubscription = _webRTCService.connectionState.listen((state) {
      if (mounted) {
        setState(() {
          _connectionState = state;
        });
      }
    });

    _typingSubscription = _chatService.typingIndicator.listen((isTyping) {
      if (mounted) {
        setState(() {
          _isTyping = isTyping;
        });
      }
    });

    _fileProgressSubscription = _chatService.fileProgress.listen((progress) {
      if (mounted) {
        setState(() {
          _fileProgress.addAll(progress);
        });
      }
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Future<void> _sendTextMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    _chatService.sendTypingIndicator(false);

    try {
      if (_editingMessage != null) {
        await _chatService.editMessage(_editingMessage!.id, text);
        setState(() => _editingMessage = null);
        return;
      }
      await _chatService.sendTextMessage(text, replyToMessageId: _replyToMessage?.id);
      setState(() => _replyToMessage = null);
    } catch (e) {
      _showError('Failed to send message: $e');
    }
  }

  void _setReplyTo(Message message) {
    setState(() {
      _replyToMessage = message;
      _editingMessage = null;
    });
    FocusScope.of(context).requestFocus(FocusNode());
  }

  void _cancelReply() {
    setState(() => _replyToMessage = null);
  }

  void _startEditing(Message message) {
    setState(() {
      _editingMessage = message;
      _replyToMessage = null;
      _messageController.text = message.text;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: message.text.length),
      );
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingMessage = null;
      _messageController.clear();
    });
  }

  Future<void> _sendImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (image != null) await _chatService.sendFile(image.path);
    } catch (e) {
      _showError('Failed to send image: $e');
    }
  }

  Future<void> _sendFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        await _chatService.sendFile(result.files.single.path!);
      }
    } catch (e) {
      _showError('Failed to send file: $e');
    }
  }

  Future<bool> _requestMicrophonePermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    final result = await Permission.microphone.request();
    if (result.isGranted) return true;
    if (result.isPermanentlyDenied) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppConstants.surfaceCard,
            title: const Text('Microphone Permission'),
            content: const Text('Please enable microphone in app settings.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () { Navigator.pop(context); openAppSettings(); },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        );
      }
    }
    return false;
  }

  Future<void> _startRecording() async {
    final hasPermission = await _requestMicrophonePermission();
    if (!hasPermission) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${tempDir.path}${Platform.pathSeparator}voice_$timestamp.m4a';
      const config = RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000, numChannels: 1, bitRate: 64000);
      await _audioRecorder.start(config, path: filePath);
      setState(() {
        _isRecording = true;
        _recordingCancelled = false;
        _recordingStartTime = DateTime.now();
        _recordingDuration = Duration.zero;
      });
      _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (_recordingStartTime != null && mounted) {
          setState(() => _recordingDuration = DateTime.now().difference(_recordingStartTime!));
        }
      });
      HapticFeedback.mediumImpact();
    } catch (e) {
      _showError('Failed to start recording: $e');
      setState(() => _isRecording = false);
    }
  }

  Future<void> _stopRecordingAndSend() async {
    if (!_isRecording) return;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    try {
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false);
      if (_recordingCancelled || path == null) {
        if (path != null) {
          final file = File(path);
          if (await file.exists()) await file.delete();
        }
        return;
      }
      final durationMs = _recordingDuration.inMilliseconds;
      if (durationMs < 500) {
        final file = File(path);
        if (await file.exists()) await file.delete();
        _showError('Recording too short');
        return;
      }
      await _chatService.sendVoiceMessage(path, durationMs);
    } catch (e) {
      _showError('Failed to send voice message: $e');
      setState(() => _isRecording = false);
    }
  }

  Future<void> _cancelRecording() async {
    _recordingCancelled = true;
    HapticFeedback.lightImpact();
    await _stopRecordingAndSend();
  }

  Future<void> _playAudio(String path, String messageId) async {
    try {
      if (_currentlyPlayingAudio == messageId) {
        await _audioPlayer.stop();
        setState(() => _currentlyPlayingAudio = null);
      } else {
        await _audioPlayerSubscription?.cancel();
        await _audioPlayer.play(DeviceFileSource(path));
        setState(() => _currentlyPlayingAudio = messageId);
        _audioPlayerSubscription = _audioPlayer.onPlayerComplete.listen((_) {
          if (mounted) setState(() => _currentlyPlayingAudio = null);
        });
      }
    } catch (e) {
      _showError('Failed to play audio: $e');
    }
  }

  void _onTextChanged(String text) {
    setState(() {});
    if (text.isNotEmpty) _chatService.sendTypingIndicator(true);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppConstants.errorColor),
    );
  }

  void _showMessageOptions(Message message) {
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
              leading: const Icon(Icons.reply, color: AppConstants.primaryColor),
              title: const Text('Reply'),
              onTap: () { Navigator.pop(context); _setReplyTo(message); },
            ),
            if (message.isOutgoing && message.type == 'text')
              ListTile(
                leading: const Icon(Icons.edit, color: AppConstants.accentColor),
                title: const Text('Edit'),
                onTap: () { Navigator.pop(context); _startEditing(message); },
              ),
            if (message.type == 'text')
              ListTile(
                leading: Icon(Icons.copy, color: AppConstants.textSecondary),
                title: const Text('Copy'),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: message.text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Message copied'), duration: Duration(seconds: 1)),
                  );
                },
              ),
            if (message.type != 'text')
              ListTile(
                leading: Icon(Icons.download, color: AppConstants.textSecondary),
                title: const Text('Download'),
                onTap: () => Navigator.pop(context),
              ),
            ListTile(
              leading: const Icon(Icons.delete, color: AppConstants.errorColor),
              title: const Text('Delete', style: TextStyle(color: AppConstants.errorColor)),
              onTap: () { Navigator.pop(context); _chatService.deleteMessage(message.id); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog() {
    final controller = TextEditingController(text: widget.chat.deviceName ?? '');

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
              await widget.chatManager.renameChat(widget.chat.id, value.trim());
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
                await widget.chatManager.renameChat(widget.chat.id, controller.text.trim());
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _copyRoomCode() {
    Clipboard.setData(ClipboardData(text: widget.chat.roomCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Room code copied!'),
        backgroundColor: AppConstants.successColor,
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _confirmClearMessages() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppConstants.surfaceCard,
        title: const Text('Clear Messages'),
        content: const Text('Are you sure you want to delete all messages in this chat? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await widget.storageService.clearAllMessages();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Messages cleared'),
                    backgroundColor: AppConstants.successColor,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.warningColor),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showChatOptions() {
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
            // Room Code
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text(
                    'Room Code',
                    style: TextStyle(
                      color: AppConstants.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppConstants.primaryColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppConstants.primaryColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          widget.chat.roomCode,
                          style: const TextStyle(
                            color: AppConstants.primaryColor,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: _copyRoomCode,
                        icon: const Icon(Icons.copy, color: AppConstants.primaryColor),
                        tooltip: 'Copy code',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppConstants.dividerColor),
            ListTile(
              leading: const Icon(Icons.edit, color: AppConstants.primaryColor),
              title: const Text('Rename Device'),
              onTap: () { Navigator.pop(context); _showRenameDialog(); },
            ),
            ListTile(
              leading: Icon(Icons.refresh, color: AppConstants.textSecondary),
              title: const Text('Reconnect'),
              onTap: () {
                Navigator.pop(context);
                _reconnect();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: AppConstants.errorColor),
              title: const Text('Clear Messages', style: TextStyle(color: AppConstants.warningColor)),
              subtitle: const Text('Free up storage space'),
              onTap: () {
                Navigator.pop(context);
                _confirmClearMessages();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: AppConstants.errorColor),
              title: const Text('Delete Chat', style: TextStyle(color: AppConstants.errorColor)),
              subtitle: const Text('Remove this chat permanently'),
              onTap: () {
                Navigator.pop(context);
                _confirmDeleteChat();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteChat() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppConstants.surfaceCard,
        title: const Text('Delete Chat'),
        content: Text('Are you sure you want to delete chat with ${widget.chat.displayName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await widget.chatManager.deleteChat(widget.chat.id);
              if (context.mounted) {
                Navigator.pop(context);
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.errorColor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _disconnect() async {
    await widget.chatManager.deactivateActiveChat();
    _chatService.dispose();
    await _webRTCService.dispose();
    await widget.signalingService.disconnect();
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  void _showCustomizationSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CustomizationBottomSheet(
        themeSettings: themeSettings,
        onThemeChanged: () {
          // Обновляем UI чата при изменении темы
          if (mounted) {
            setState(() {});
          }
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) return 'Today';
    if (messageDate == yesterday) return 'Yesterday';

    return DateFormat('MMMM d, yyyy').format(date);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final isLight = themeSettings.isLightTheme;
    
    return Scaffold(
      backgroundColor: isLight ? AppConstants.surfaceLight : AppConstants.surfaceDark,
      appBar: AppBar(
        backgroundColor: isLight ? AppConstants.surfaceCardLight : AppConstants.surfaceCard,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _disconnect,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.chat.displayName,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isLight ? AppConstants.textPrimaryLight : AppConstants.textPrimary,
              ),
            ),
            ConnectionStatusWidget(state: _connectionState),
          ],
        ),
        actions: [
          if (_connectionState.status == AppConstants.statusError ||
              _connectionState.status == AppConstants.statusOffline)
            IconButton(
              icon: const Icon(Icons.refresh, color: AppConstants.primaryColor),
              onPressed: _reconnect,
              tooltip: 'Reconnect',
            ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.tune, color: isLight ? AppConstants.textSecondaryLight : AppConstants.textSecondary),
            onPressed: _showCustomizationSheet,
            tooltip: 'Customization',
          ),
          IconButton(
            icon: Icon(Icons.more_vert, color: isLight ? AppConstants.textSecondaryLight : AppConstants.textSecondary),
            onPressed: _showChatOptions,
          ),
        ],
      ),
      body: Container(
        decoration: _buildChatBackground(),
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        final showDate = index == 0 ||
                            !_isSameDay(_messages[index - 1].timestamp, message.timestamp);
                        return Column(
                          children: [
                            if (showDate) _buildDateDivider(message.timestamp),
                            MessageBubble(
                              message: message,
                              isPlaying: _currentlyPlayingAudio == message.id,
                              fileProgress: _fileProgress[message.id],
                              onPlayAudio: message.type == 'voice' && message.filePath != null
                                  ? () => _playAudio(message.filePath!, message.id)
                                  : null,
                              onLongPress: () => _showMessageOptions(message),
                              allMessages: _messages,
                            ),
                          ],
                        );
                      },
                    ),
            ),
            if (_isTyping) const TypingIndicatorWidget(),
            if (_isRecording) _buildRecordingOverlay() else _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingOverlay() {
    final minutes = _recordingDuration.inMinutes;
    final seconds = _recordingDuration.inSeconds % 60;
    final timeStr = '$minutes:${seconds.toString().padLeft(2, '0')}';

    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        if (details.delta.dx < -2) setState(() => _recordingCancelled = true);
      },
      onHorizontalDragEnd: (details) {
        if (_recordingCancelled) _cancelRecording();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _recordingCancelled
              ? AppConstants.errorColor.withOpacity(0.1)
              : AppConstants.surfaceCard,
          border: Border(top: BorderSide(color: AppConstants.dividerColor)),
        ),
        child: SafeArea(
          child: Row(
            children: [
              _RecordingDot(),
              const SizedBox(width: 12),
              Text(
                timeStr,
                style: TextStyle(
                  color: AppConstants.errorColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              if (_recordingCancelled)
                Text('Release to cancel', style: TextStyle(color: AppConstants.errorColor, fontSize: 14))
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chevron_left, color: AppConstants.textMuted, size: 20),
                    Text('Slide to cancel', style: TextStyle(color: AppConstants.textMuted, fontSize: 14)),
                  ],
                ),
              const SizedBox(width: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _cancelRecording,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppConstants.surfaceInput,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.delete_outline, color: AppConstants.textMuted, size: 24),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _stopRecordingAndSend,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: AppConstants.primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send, color: Colors.white, size: 24),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
            'No messages yet',
            style: TextStyle(
              color: AppConstants.textSecondary,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Send a message to start the conversation',
            style: TextStyle(
              color: AppConstants.textMuted,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateDivider(DateTime date) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppConstants.dividerColor)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppConstants.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _formatDate(date),
              style: TextStyle(color: AppConstants.textMuted, fontSize: 12),
            ),
          ),
          Expanded(child: Divider(color: AppConstants.dividerColor)),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: AppConstants.surfaceCard,
        border: Border(top: BorderSide(color: AppConstants.dividerColor)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.attach_file, color: AppConstants.textSecondary),
              onPressed: () => _showAttachmentOptions(),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _messageController,
                style: const TextStyle(color: AppConstants.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Message',
                  hintStyle: TextStyle(color: AppConstants.textMuted),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                maxLines: 5,
                minLines: 1,
                onChanged: _onTextChanged,
                onSubmitted: (_) => _sendTextMessage(),
              ),
            ),
            const SizedBox(width: 8),
            if (_messageController.text.trim().isEmpty)
              GestureDetector(
                onLongPress: _startRecording,
                onLongPressUp: _stopRecordingAndSend,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: AppConstants.primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.mic, color: Colors.white, size: 24),
                ),
              )
            else
              GestureDetector(
                onTap: _sendTextMessage,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: AppConstants.primaryColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.send, color: Colors.white, size: 24),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showAttachmentOptions() {
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
              leading: const Icon(Icons.photo_library, color: AppConstants.primaryColor),
              title: const Text('Gallery'),
              onTap: () { Navigator.pop(context); _sendImage(); },
            ),
            ListTile(
              leading: const Icon(Icons.folder, color: AppConstants.accentColor),
              title: const Text('File'),
              onTap: () { Navigator.pop(context); _sendFile(); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Decoration _buildChatBackground() {
    // Image background (type 3)
    if (themeSettings.backgroundType == 3 && themeSettings.backgroundImagePath.isNotEmpty) {
      final imageFile = File(themeSettings.backgroundImagePath);
      if (imageFile.existsSync()) {
        return BoxDecoration(
          image: DecorationImage(
            image: FileImage(imageFile),
            fit: BoxFit.cover,
            opacity: 0.4,
          ),
        );
      }
    }
    
    // Preset background (type 2)
    if (themeSettings.backgroundType == 2) {
      final presetIndex = themeSettings.selectedPreset.clamp(0, ThemeSettings.presetBackgrounds.length - 1);
      final preset = ThemeSettings.presetBackgrounds[presetIndex];
      final colors = preset['colors'] as List<Color>;
      
      return BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      );
    }
    
    // Solid color background (type 0)
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          themeSettings.backgroundColor,
          themeSettings.backgroundColor.withOpacity(0.95),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    _audioPlayerSubscription?.cancel();
    _messagesSubscription?.cancel();
    _connectionSubscription?.cancel();
    _typingSubscription?.cancel();
    _fileProgressSubscription?.cancel();
    _recordingTimer?.cancel();
    super.dispose();
  }
}

class _RecordingDot extends StatefulWidget {
  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 8, end: 16).animate(_controller);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: _animation.value,
          height: _animation.value,
          decoration: BoxDecoration(
            color: AppConstants.errorColor.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: AppConstants.errorColor,
              shape: BoxShape.circle,
            ),
            margin: EdgeInsets.all((16 - _animation.value) / 2),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
