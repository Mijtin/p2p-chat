import 'dart:async';
import 'dart:io';
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
import '../models/connection_state.dart' as app_state;
import '../services/signaling_service.dart';
import '../services/webrtc_service.dart';
import '../services/chat_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';
import '../widgets/connection_status.dart';
import '../widgets/customization_sheet.dart';
import '../utils/theme_settings.dart';
import '../main.dart' show themeSettings;
import 'connect_screen.dart';



class ChatScreen extends StatefulWidget {
  final SignalingService signalingService;
  final StorageService storageService;
  final WebRTCService webRTCService;
  final bool isInitiator;
  final String remotePeerId;
  final String connectionCode;

  const ChatScreen({
    super.key,
    required this.signalingService,
    required this.storageService,
    required this.webRTCService,
    required this.isInitiator,
    required this.remotePeerId,
    required this.connectionCode,
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
  app_state.ConnectionStateModel _connectionState =
      const app_state.ConnectionStateModel();
  bool _isTyping = false;
  bool _isRecording = false;
  String? _currentlyPlayingAudio;
  final Map<String, double> _fileProgress = {};

  Message? _replyToMessage;
  Message? _editingMessage;

  DateTime? _recordingStartTime;
  Timer? _recordingTimer;
  Duration _recordingDuration = Duration.zero;
  Offset? _recordingStartOffset;
  bool _recordingCancelled = false;

  StreamSubscription? _audioPlayerSubscription;
  StreamSubscription? _messagesSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _typingSubscription;
  StreamSubscription? _fileProgressSubscription;

  // Анимация для input area
  late AnimationController _inputAnimController;
  late Animation<double> _inputSlideAnimation;

  @override
  void initState() {
    super.initState();
    _inputAnimController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _inputSlideAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _inputAnimController, curve: Curves.easeOut),
    );
    _inputAnimController.forward();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    _webRTCService = widget.webRTCService;
    if (!_webRTCService.isInitialized) {
      await _webRTCService.initialize(
        isInitiator: widget.isInitiator,
        remotePeerId: widget.remotePeerId,
      );
    }
    _chatService = ChatService(_webRTCService, widget.storageService);
    _setupListeners();
  }

  void _setupListeners() {
    _messagesSubscription = _chatService.messages.listen((messages) {
      setState(() {
        _messages = messages;
      });
      _scrollToBottom();
    });

    _connectionSubscription = _webRTCService.connectionState.listen((state) {
      setState(() {
        _connectionState = state;
      });
      if (state.status == AppConstants.statusOnline && state.remotePeerId != null) {
        _savePairedDevice(state.remotePeerId!);
      }
    });

    _typingSubscription = _chatService.typingIndicator.listen((isTyping) {
      setState(() {
        _isTyping = isTyping;
      });
    });

    _fileProgressSubscription = _chatService.fileProgress.listen((progress) {
      setState(() {
        _fileProgress.addAll(progress);
        progress.forEach((key, value) {
          if (value >= 1.0) {
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                setState(() {
                  _fileProgress.remove(key);
                });
              }
            });
          }
        });
      });
    });
  }

  Future<void> _savePairedDevice(String remotePeerId) async {
    try {
      final messages = await widget.storageService.getMessages();
      final deviceName = 'Device ${remotePeerId.substring(0, 6)}';
      await widget.storageService.addPairedDevice(
        deviceId: remotePeerId,
        deviceName: deviceName,
        connectionCode: widget.connectionCode,
        lastConnectedAt: DateTime.now().toIso8601String(),
        totalMessages: messages.length,
      );
    } catch (e) {
      print('Error saving paired device: $e');
    }
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

  Future<void> _disconnect() async {
    await widget.storageService.clearConnectionData();
    _chatService.dispose();
    await widget.webRTCService.dispose();
    await widget.signalingService.disconnect();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const ConnectScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.surfaceDark,
      appBar: AppBar(
        backgroundColor: AppConstants.surfaceCard,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chat', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ConnectionStatusWidget(state: _connectionState),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.tune,
              color: AppConstants.textSecondary,
              size: 24,
            ),
            onPressed: _showCustomizationSheet,
            tooltip: 'Customization',
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
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
            child: Icon(Icons.chat_bubble_outline, size: 56, color: AppConstants.primaryColor.withOpacity(0.5)),
          ),
          const SizedBox(height: 20),
          Text('No messages yet', style: TextStyle(color: AppConstants.textSecondary, fontSize: 18, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text('Send a message to start the conversation', style: TextStyle(color: AppConstants.textMuted, fontSize: 14)),
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

  Widget _buildReplyPreview() {
    final message = _replyToMessage!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppConstants.surfaceElevated,
        border: Border(
          left: BorderSide(color: AppConstants.secondaryColor, width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.isOutgoing ? 'You' : 'Companion',
                  style: TextStyle(color: AppConstants.secondaryColor, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  _getReplyPreviewText(message),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppConstants.textSecondary, fontSize: 13),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _cancelReply,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, size: 20, color: AppConstants.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditPreview() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppConstants.primaryColor.withOpacity(0.08),
        border: Border(
          left: BorderSide(color: AppConstants.primaryColor, width: 3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.edit, size: 18, color: AppConstants.primaryColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Editing', style: TextStyle(color: AppConstants.primaryColor, fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Text(_editingMessage!.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppConstants.textSecondary, fontSize: 13)),
              ],
            ),
          ),
          GestureDetector(
            onTap: _cancelEditing,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, size: 20, color: AppConstants.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  String _getReplyPreviewText(Message message) {
    switch (message.type) {
      case 'image': return '📷 Photo';
      case 'file': return '📎 ${message.fileName ?? "File"}';
      case 'voice': return '🎤 Voice message';
      default: return message.text;
    }
  }

  Widget _buildInputArea() {
    return Container(
      decoration: BoxDecoration(
        color: AppConstants.surfaceCard,
        border: Border(top: BorderSide(color: AppConstants.dividerColor)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyToMessage != null) _buildReplyPreview(),
            if (_editingMessage != null) _buildEditPreview(),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  if (_editingMessage == null)
                    IconButton(
                      icon: Icon(Icons.attach_file, color: AppConstants.textSecondary),
                      onPressed: _showAttachmentOptions,
                    ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: const TextStyle(color: AppConstants.textPrimary, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: _editingMessage != null ? 'Edit message...' : 'Type a message...',
                        hintStyle: TextStyle(color: AppConstants.textMuted),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: AppConstants.surfaceInput,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      onChanged: _onTextChanged,
                      onSubmitted: (_) => _sendTextMessage(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _messageController.text.isEmpty && _editingMessage == null
                      ? GestureDetector(
                          onLongPressStart: (_) => _startRecording(),
                          onLongPressEnd: (_) => _stopRecordingAndSend(),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppConstants.primaryColor.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.mic, color: AppConstants.primaryColor, size: 24),
                          ),
                        )
                      : GestureDetector(
                          onTap: _sendTextMessage,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: AppConstants.primaryColor,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _editingMessage != null ? Icons.check : Icons.send,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                ],
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
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(color: AppConstants.dividerColor, borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.purple.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.image, color: Colors.purple),
              ),
              title: const Text('Image'),
              onTap: () { Navigator.pop(context); _sendImage(); },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppConstants.primaryColor.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.insert_drive_file, color: AppConstants.primaryColor),
              ),
              title: const Text('File'),
              onTap: () { Navigator.pop(context); _sendFile(); },
            ),
            const SizedBox(height: 8),
          ],
        ),
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
          setState(() {});
        },
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
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(color: AppConstants.dividerColor, borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              leading: Icon(Icons.info_outline, color: AppConstants.textSecondary),
              title: const Text('Connection Info'),
              onTap: () { Navigator.pop(context); _showConnectionInfo(); },
            ),
            ListTile(
              leading: Icon(Icons.copy, color: AppConstants.textSecondary),
              title: const Text('Copy Connection Code'),
              onTap: () { Navigator.pop(context); _copyConnectionCode(); },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppConstants.errorColor),
              title: const Text('Clear Chat', style: TextStyle(color: AppConstants.errorColor)),
              onTap: () { Navigator.pop(context); _showClearChatDialog(); },
            ),
            ListTile(
              leading: const Icon(Icons.exit_to_app, color: AppConstants.errorColor),
              title: const Text('Disconnect', style: TextStyle(color: AppConstants.errorColor)),
              onTap: () { Navigator.pop(context); _showDisconnectDialog(); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _copyConnectionCode() {
    Clipboard.setData(ClipboardData(text: widget.connectionCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Connection code copied'), duration: Duration(seconds: 2)),
    );
  }

  void _showConnectionInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connection Info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppConstants.primaryColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppConstants.primaryColor.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Connection Code', style: TextStyle(fontSize: 12, color: AppConstants.textMuted)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        widget.connectionCode,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppConstants.primaryColor, letterSpacing: 4),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: widget.connectionCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Code copied!'), duration: Duration(seconds: 1)),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Status', _connectionState.status),
            if (_connectionState.peerId != null) _buildInfoRow('Your ID', _connectionState.peerId!),
            if (_connectionState.remotePeerId != null) _buildInfoRow('Remote ID', _connectionState.remotePeerId!),
            if (_connectionState.connectedAt != null) _buildInfoRow('Connected', _formatDateTime(_connectionState.connectedAt!)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text('$label:', style: TextStyle(fontWeight: FontWeight.w500, color: AppConstants.textMuted))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  void _showClearChatDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Chat'),
        content: const Text('Are you sure you want to delete all messages?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); _chatService.clearAllMessages(); },
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.errorColor),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showDisconnectDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect'),
        content: const Text('Are you sure you want to disconnect?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () { Navigator.pop(context); _disconnect(); },
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.errorColor),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
  }

  BoxDecoration _buildChatBackground() {
    // Image background (type 3)
    if (themeSettings.backgroundType == 3 && themeSettings.backgroundImagePath.isNotEmpty) {
      final file = File(themeSettings.backgroundImagePath);
      if (file.existsSync()) {
        return BoxDecoration(
          image: DecorationImage(
            image: FileImage(file),
            fit: BoxFit.cover,
            opacity: 0.3,
          ),
        );
      }
    }
    
    // Preset gradient background (type 2)
    if (themeSettings.backgroundType == 2 && themeSettings.selectedPreset >= 0) {
      final preset = ThemeSettings.presetBackgrounds[themeSettings.selectedPreset];
      final colors = preset['colors'] as List<Color>;
      return BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      );
    }
    
    // Solid color background (type 0) or default
    return BoxDecoration(
      color: themeSettings.backgroundColor,
    );
  }

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;


  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (_isSameDay(date, now)) return 'Today';
    if (_isSameDay(date, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    return DateFormat('MMM d, yyyy').format(date);
  }

  String _formatDateTime(DateTime date) => DateFormat('MMM d, yyyy HH:mm').format(date);

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    _connectionSubscription?.cancel();
    _typingSubscription?.cancel();
    _fileProgressSubscription?.cancel();
    _audioPlayerSubscription?.cancel();
    _recordingTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    _audioRecorder.dispose();
    _inputAnimController.dispose();
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
    _controller = AnimationController(duration: const Duration(milliseconds: 800), vsync: this)
      ..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: AppConstants.errorColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppConstants.errorColor.withOpacity(0.4),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
