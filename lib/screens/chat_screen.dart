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

class _ChatScreenState extends State<ChatScreen> {
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

  // Голосовая запись
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

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    _webRTCService = widget.webRTCService;

    if (!_webRTCService.isInitialized) {
      print('⚠️ ChatScreen: WebRTC not initialized! Initializing as fallback...');
      await _webRTCService.initialize(
        isInitiator: widget.isInitiator,
        remotePeerId: widget.remotePeerId,
      );
    } else {
      print('ChatScreen: WebRTC already initialized (peerId=${_webRTCService.localPeerId})');
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
      print('Saved paired device: $deviceName');
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
      await _chatService.sendTextMessage(text);
    } catch (e) {
      _showError('Failed to send message: $e');
    }
  }

  Future<void> _sendImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (image != null) {
        await _chatService.sendFile(image.path);
      }
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

  // ============================================================
  // VOICE RECORDING — Telegram-style (hold to record)
  // ============================================================

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
            content: const Text(
              'Microphone permission is required to record voice messages. '
              'Please enable it in app settings.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  openAppSettings();
                },
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

      // record v5 API — RecordConfig как первый аргумент, path как named
      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        numChannels: 1,
        bitRate: 64000,
      );

      await _audioRecorder.start(config, path: filePath);

      setState(() {
        _isRecording = true;
        _recordingCancelled = false;
        _recordingStartTime = DateTime.now();
        _recordingDuration = Duration.zero;
      });

      _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (_recordingStartTime != null && mounted) {
          setState(() {
            _recordingDuration = DateTime.now().difference(_recordingStartTime!);
          });
        }
      });

      HapticFeedback.mediumImpact();
    } catch (e) {
      print('Failed to start recording: $e');
      _showError('Failed to start recording: $e');
      setState(() {
        _isRecording = false;
      });
    }
  }

  Future<void> _stopRecordingAndSend() async {
    if (!_isRecording) return;

    _recordingTimer?.cancel();
    _recordingTimer = null;

    try {
      final path = await _audioRecorder.stop();

      setState(() {
        _isRecording = false;
      });

      if (_recordingCancelled || path == null) {
        // Удаляем файл если запись отменена
        if (path != null) {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        }
        print('Recording cancelled');
        return;
      }

      // Проверяем минимальную длительность (500ms)
      final durationMs = _recordingDuration.inMilliseconds;
      if (durationMs < 500) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
        _showError('Recording too short');
        return;
      }

      // Отправляем голосовое сообщение
      await _chatService.sendVoiceMessage(path, durationMs);
    } catch (e) {
      print('Failed to stop recording: $e');
      _showError('Failed to send voice message: $e');
      setState(() {
        _isRecording = false;
      });
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
        setState(() {
          _currentlyPlayingAudio = null;
        });
      } else {
        await _audioPlayerSubscription?.cancel();
        await _audioPlayer.play(DeviceFileSource(path));
        setState(() {
          _currentlyPlayingAudio = messageId;
        });
        _audioPlayerSubscription = _audioPlayer.onPlayerComplete.listen((_) {
          if (mounted) {
            setState(() {
              _currentlyPlayingAudio = null;
            });
          }
        });
      }
    } catch (e) {
      _showError('Failed to play audio: $e');
    }
  }

  void _onTextChanged(String text) {
    setState(() {});
    if (text.isNotEmpty) {
      _chatService.sendTypingIndicator(true);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppConstants.errorColor,
      ),
    );
  }

  void _showMessageOptions(Message message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.type != 'text')
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Download'),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(context);
                _chatService.deleteMessage(message.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
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
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chat'),
            ConnectionStatusWidget(state: _connectionState),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showChatOptions,
          ),
        ],
      ),
      body: Column(
        children: [
          // Messages List
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final showDate = index == 0 ||
                          !_isSameDay(
                              _messages[index - 1].timestamp, message.timestamp);
                      return Column(
                        children: [
                          if (showDate) _buildDateDivider(message.timestamp),
                          MessageBubble(
                            message: message,
                            isPlaying: _currentlyPlayingAudio == message.id,
                            fileProgress: _fileProgress[message.id],
                            onPlayAudio:
                                message.type == 'voice' && message.filePath != null
                                    ? () => _playAudio(message.filePath!, message.id)
                                    : null,
                            onLongPress: () => _showMessageOptions(message),
                          ),
                        ],
                      );
                    },
                  ),
          ),

          // Typing Indicator
          if (_isTyping) const TypingIndicatorWidget(),

          // Recording overlay ИЛИ обычный Input Area
          if (_isRecording) _buildRecordingOverlay() else _buildInputArea(),
        ],
      ),
    );
  }

  // ============================================================
  // RECORDING OVERLAY — Telegram-style
  // ============================================================

  Widget _buildRecordingOverlay() {
    final minutes = _recordingDuration.inMinutes;
    final seconds = _recordingDuration.inSeconds % 60;
    final timeStr = '$minutes:${seconds.toString().padLeft(2, '0')}';

    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        // Свайп влево для отмены
        if (details.delta.dx < -2) {
          setState(() {
            _recordingCancelled = true;
          });
        }
      },
      onHorizontalDragEnd: (details) {
        if (_recordingCancelled) {
          _cancelRecording();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _recordingCancelled
              ? Colors.red.withOpacity(0.1)
              : Colors.red.withOpacity(0.05),
          border: Border(
            top: BorderSide(color: Colors.grey[300]!),
          ),
        ),
        child: SafeArea(
          child: Row(
            children: [
              // Красная точка (мигает)
              _RecordingDot(),

              const SizedBox(width: 12),

              // Таймер
              Text(
                timeStr,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),

              const Spacer(),

              // Подсказка свайпа или текст отмены
              if (_recordingCancelled)
                const Text(
                  'Release to cancel',
                  style: TextStyle(color: Colors.red, fontSize: 14),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chevron_left, color: Colors.grey[400], size: 20),
                    Text(
                      'Slide to cancel',
                      style: TextStyle(color: Colors.grey[500], fontSize: 14),
                    ),
                  ],
                ),

              const SizedBox(width: 16),

              // Кнопки: Отмена и Отправить
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Кнопка отмены
                  GestureDetector(
                    onTap: _cancelRecording,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.delete_outline,
                        color: Colors.grey[600],
                        size: 24,
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Кнопка отправки
                  GestureDetector(
                    onTap: _stopRecordingAndSend,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: AppConstants.primaryColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.send,
                        color: Colors.white,
                        size: 24,
                      ),
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
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(color: Colors.grey[500], fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Send a message to start the conversation',
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
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
          Expanded(child: Divider(color: Colors.grey[300])),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _formatDate(date),
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ),
          Expanded(child: Divider(color: Colors.grey[300])),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Attachment button
            IconButton(
              icon: const Icon(Icons.attach_file),
              onPressed: _showAttachmentOptions,
            ),

            // Text input
            Expanded(
              child: TextField(
                controller: _messageController,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onChanged: _onTextChanged,
                onSubmitted: (_) => _sendTextMessage(),
              ),
            ),

            // Send / Mic button
            _messageController.text.isEmpty
                ? GestureDetector(
                    onLongPressStart: (_) => _startRecording(),
                    onLongPressEnd: (_) => _stopRecordingAndSend(),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Icon(
                        Icons.mic,
                        color: AppConstants.primaryColor,
                        size: 28,
                      ),
                    ),
                  )
                : IconButton(
                    icon: Icon(Icons.send, color: AppConstants.primaryColor),
                    onPressed: _sendTextMessage,
                  ),
          ],
        ),
      ),
    );
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('Image'),
              onTap: () {
                Navigator.pop(context);
                _sendImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: const Text('File'),
              onTap: () {
                Navigator.pop(context);
                _sendFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showChatOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Connection Info'),
              onTap: () {
                Navigator.pop(context);
                _showConnectionInfo();
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy Connection Code'),
              onTap: () {
                Navigator.pop(context);
                _copyConnectionCode();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: AppConstants.errorColor),
              title: const Text('Clear Chat',
                  style: TextStyle(color: AppConstants.errorColor)),
              onTap: () {
                Navigator.pop(context);
                _showClearChatDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.exit_to_app,
                  color: AppConstants.errorColor),
              title: const Text('Disconnect',
                  style: TextStyle(color: AppConstants.errorColor)),
              onTap: () {
                Navigator.pop(context);
                _showDisconnectDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  void _copyConnectionCode() {
    Clipboard.setData(ClipboardData(text: widget.connectionCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Connection code copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
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
                color: AppConstants.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppConstants.primaryColor.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Connection Code',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        widget.connectionCode,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppConstants.primaryColor,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: widget.connectionCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Code copied!'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const Text(
                    'Share this code to let others join',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Status', _connectionState.status),
            if (_connectionState.peerId != null)
              _buildInfoRow('Your ID', _connectionState.peerId!),
            if (_connectionState.remotePeerId != null)
              _buildInfoRow('Remote ID', _connectionState.remotePeerId!),
            if (_connectionState.connectedAt != null)
              _buildInfoRow(
                  'Connected', _formatDateTime(_connectionState.connectedAt!)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
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
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _showClearChatDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Chat'),
        content: const Text(
            'Are you sure you want to delete all messages? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _chatService.clearAllMessages();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.errorColor),
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
        content: const Text(
            'Are you sure you want to disconnect? You will need to enter the code again to reconnect.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _disconnect();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.errorColor),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (_isSameDay(date, now)) {
      return 'Today';
    } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM d, yyyy').format(date);
    }
  }

  String _formatDateTime(DateTime date) {
    return DateFormat('MMM d, yyyy HH:mm').format(date);
  }

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
    super.dispose();
  }
}

// ============================================================
// Мигающая красная точка для индикации записи
// ============================================================
class _RecordingDot extends StatefulWidget {
  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
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
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}