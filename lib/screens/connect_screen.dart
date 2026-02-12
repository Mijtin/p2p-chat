import 'dart:developer' as developer;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/signaling_service.dart';
import '../services/storage_service.dart';
import '../services/room_manager.dart';
import '../services/webrtc_service.dart';
import '../utils/constants.dart';
import 'chat_screen.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _signalingService = SignalingService();
  final _storageService = StorageService();
  late final WebRTCService _webRTCService;
  late final RoomManager _roomManager;
  
  final _serverUrlController = TextEditingController();
  final _codeController = TextEditingController();
  
  String? _generatedCode;
  bool _isConnecting = false;
  bool _isJoining = false;
  String? _errorMessage;
  bool _showServerSettings = false;
  bool _isReconnecting = false;
  bool _isAutoJoining = false;
  bool _hasPreviousConnection = false;
  
  // Paired devices
  List<Map<String, dynamic>> _pairedDevices = [];
  bool _isLoadingDevices = false;
  
  @override
  void initState() {
    super.initState();
    _webRTCService = WebRTCService(_signalingService);
    _roomManager = RoomManager(_storageService, _webRTCService);
    _initializeAndCheckConnection();
  }
  
  Future<void> _initializeAndCheckConnection() async {
    try {
      await _storageService.initialize();
      developer.log('Storage initialized', name: 'ConnectScreen');
      
      // Load paired devices
      await _loadPairedDevices();
      
      // Check if we have previous connection
      _hasPreviousConnection = await _storageService.getIsConnected();
      setState(() {});
      
      // First try auto-join (no code needed if previously connected)
      await _tryAutoJoin();
    } catch (e) {
      developer.log('Storage init error: $e', name: 'ConnectScreen');
    }
  }
  
  Future<void> _loadPairedDevices() async {
    setState(() {
      _isLoadingDevices = true;
    });
    
    try {
      final devices = await _storageService.getPairedDevices();
      setState(() {
        _pairedDevices = devices;
        _isLoadingDevices = false;
      });
      developer.log('Loaded ${devices.length} paired devices', name: 'ConnectScreen');
    } catch (e) {
      developer.log('Error loading paired devices: $e', name: 'ConnectScreen');
      setState(() {
        _isLoadingDevices = false;
      });
    }
  }
  
  /// Try to auto-join without code if previously connected
  Future<void> _tryAutoJoin() async {
    setState(() {
      _isAutoJoining = true;
    });
    
    final result = await _roomManager.tryAutoJoin();
    
    developer.log('Auto-join result: $result', name: 'ConnectScreen');
    
    switch (result) {
      case AutoJoinResult.joinedAsInitiator:
        final savedRoomCode = await _storageService.getConnectionCode();
        final savedPeerId = await _storageService.getPeerId();
        final savedServerUrl = await _storageService.getServerUrl();

        if (savedRoomCode == null || savedPeerId == null) {
          setState(() {
            _isAutoJoining = false;
          });
          return;
        }

        try {
          await _signalingService.connect(
            roomCode: savedRoomCode,
            customPeerId: savedPeerId,
            serverUrl: savedServerUrl ?? _serverUrlController.text.trim(),
            isInitiator: true,  // Первый в комнате = initiator
          );

          await _roomManager.createOrJoinRoom(
            savedRoomCode, savedPeerId,
            savedServerUrl ?? _serverUrlController.text.trim(),
          );

          // ИСПРАВЛЕНИЕ: Проверяем есть ли кто в комнате
          final otherPeers = _signalingService.peersInRoom;
          bool isInitiator;
          if (otherPeers.isEmpty) {
            isInitiator = true;
          } else {
            isInitiator = savedPeerId.compareTo(otherPeers.first) < 0;
          }

          _navigateToChat(
            isInitiator: isInitiator,
            remotePeerId: otherPeers.isNotEmpty ? otherPeers.first : '',
            connectionCode: savedRoomCode,
            isAutoJoin: true,
          );
        } catch (e) {
          developer.log('Auto-join error: $e', name: 'ConnectScreen');
          setState(() {
            _isAutoJoining = false;
          });
          await _checkPreviousConnection();
        }
        return;
        
      case AutoJoinResult.joinedAsNonInitiator:
        // Joined existing room
        _navigateToChat(
          isInitiator: false,
          remotePeerId: _roomManager.otherPeerId ?? '',
          connectionCode: _roomManager.roomCode!,
          isAutoJoin: true, // ИСПРАВЛЕНИЕ: Явно указываем, что это авто-подключение
        );
        return;
        
      case AutoJoinResult.noPreviousRoom:
        // No previous room, show normal connect screen
        setState(() {
          _isAutoJoining = false;
          _isReconnecting = false;
        });
        // Set default server URL
        _serverUrlController.text = 'https://p2p-chat-csjq.onrender.com';
        return;
        
      case AutoJoinResult.failed:
        // Auto-join failed, try manual reconnect
        setState(() {
          _isAutoJoining = false;
        });
        await _checkPreviousConnection();
        return;
    }
  }
  
  /// Check previous connection for manual reconnect
  Future<void> _checkPreviousConnection() async {
    final wasConnected = await _storageService.getIsConnected();
    final savedServerUrl = await _storageService.getServerUrl();
    final savedPeerId = await _storageService.getPeerId();
    final savedRemotePeerId = await _storageService.getRemotePeerId();
    final savedConnectionCode = await _storageService.getConnectionCode();
    
    developer.log('Checking previous connection: wasConnected=$wasConnected, peerId=$savedPeerId, remotePeerId=$savedRemotePeerId, code=$savedConnectionCode', name: 'ConnectScreen');
    
    if (wasConnected && savedServerUrl != null && savedPeerId != null && savedRemotePeerId != null) {
      setState(() {
        _isReconnecting = true;
        _serverUrlController.text = savedServerUrl;
      });
    } else {
      _serverUrlController.text = 'https://p2p-chat-csjq.onrender.com';
    }
  }
  
  String _generateSixDigitCode() {
    final random = Random();
    final code = (100000 + random.nextInt(900000)).toString();
    developer.log('Generated code: $code', name: 'ConnectScreen');
    return code;
  }
  
  Future<void> _generateCode() async {
    developer.log('Generate code pressed', name: 'ConnectScreen');
    
    final code = _generateSixDigitCode();
    
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
      _generatedCode = code;
    });
    
    try {
      developer.log('=== CONNECT DEBUG (Generate Code) ===', name: 'ConnectScreen');
      developer.log('Code: $code', name: 'ConnectScreen');
      developer.log('Server: ${_serverUrlController.text.trim()}', name: 'ConnectScreen');
      developer.log('IsInitiator: true', name: 'ConnectScreen');

      final serverUrl = _serverUrlController.text.trim();
      
      // Save server URL
      await _storageService.saveServerUrl(serverUrl);
      
      // ИСПРАВЛЕНИЕ: Используем постоянный deviceId из storage
      final deviceId = await _getOrCreateDeviceId();
      final peerId = '${code}_$deviceId';
      developer.log('Generated peerId: $peerId (deviceId: $deviceId)', name: 'ConnectScreen');

      // ИСПРАВЛЕНИЕ: Явно передаём roomCode (только 6 цифр), а не peerId
      // roomCode = имя комнаты (код для подключения)
      // peerId = уникальный идентификатор устройства
      developer.log('*** BEFORE connect: roomCode="$code", peerId="$peerId" ***', name: 'ConnectScreen');
      await _signalingService.connect(
        roomCode: code,  // "390058" - имя комнаты для подключения
        customPeerId: peerId,  // "390058_571" - уникальный ID устройства
        serverUrl: serverUrl.isNotEmpty ? serverUrl : null,
        isInitiator: true, // Явно указываем, что мы создаем комнату
      );
      developer.log('*** AFTER connect: done ***', name: 'ConnectScreen');
      
      // Initialize room manager
      await _roomManager.createOrJoinRoom(code, peerId, serverUrl);
      
      developer.log('Signaling connected successfully', name: 'ConnectScreen');
      developer.log('Signaling peerId: ${_signalingService.peerId}', name: 'ConnectScreen');
      developer.log('Signaling isInitiator: ${_signalingService.isInitiator}', name: 'ConnectScreen');
      developer.log('Room created with code: $code (peerId: $peerId)', name: 'ConnectScreen');
      
      // Navigate to chat as initiator (no remote peer yet)
      _navigateToChat(
        isInitiator: true, 
        remotePeerId: null, // Will be set when peer joins
        connectionCode: code,
        isAutoJoin: false, // ИСПРАВЛЕНИЕ: Это не авто-подключение
      );

      
    } catch (e) {
      developer.log('Connection error: $e', name: 'ConnectScreen');
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _errorMessage = 'Failed to connect: $e';
        });
      }
    }
  }

  
  Future<void> _joinWithCode() async {
    final enteredCode = _codeController.text.trim();
    
    if (enteredCode.length != 6) {
      setState(() {
        _errorMessage = 'Please enter a valid 6-digit code';
      });
      return;
    }
    
    setState(() {
      _isJoining = true;
      _errorMessage = null;
    });
    
    try {
      developer.log('=== CONNECT DEBUG (Join Code) ===', name: 'ConnectScreen');
      developer.log('Code: $enteredCode', name: 'ConnectScreen');
      developer.log('Server: ${_serverUrlController.text.trim()}', name: 'ConnectScreen');

      final serverUrl = _serverUrlController.text.trim();
      
      // Save server URL
      await _storageService.saveServerUrl(serverUrl);
      
      // ИСПРАВЛЕНИЕ: Используем постоянный deviceId из storage
      final deviceId = await _getOrCreateDeviceId();
      final myPeerId = '${enteredCode}_$deviceId';
      developer.log('Generated peerId: $myPeerId (deviceId: $deviceId)', name: 'ConnectScreen');
      
      // Connect to signaling
      // Явно передаем isInitiator: false, чтобы устройство не создавало новую комнату
      developer.log('*** BEFORE join: roomCode="$enteredCode", peerId="$myPeerId" ***', name: 'ConnectScreen');
      await _signalingService.connect(
        roomCode: enteredCode,
        customPeerId: myPeerId,
        serverUrl: serverUrl.isNotEmpty ? serverUrl : null,
        isInitiator: false,
      );
      developer.log('*** AFTER join: done ***', name: 'ConnectScreen');
      
      // Join room
      await _roomManager.createOrJoinRoom(enteredCode, myPeerId, serverUrl);
      
      developer.log('Signaling connected successfully', name: 'ConnectScreen');
      developer.log('Signaling peerId: ${_signalingService.peerId}', name: 'ConnectScreen');
      developer.log('Signaling isInitiator: ${_signalingService.isInitiator}', name: 'ConnectScreen');
      developer.log('Joined room: $enteredCode, peerId: $myPeerId', name: 'ConnectScreen');
      
      // ИСПРАВЛЕНИЕ: При ручном вводе кода мы ВСЕГДА являемся Joiner
      developer.log('Role: Joiner (manual code entry)', name: 'ConnectScreen');

      _navigateToChat(
        isInitiator: false, // Мы вводим чужой код → мы joiner
        remotePeerId: _roomManager.otherPeerId ?? '',
        connectionCode: enteredCode,
        isAutoJoin: false,
      );
      
    } catch (e) {
      developer.log('Join error: $e', name: 'ConnectScreen');
      if (mounted) {
        setState(() {
          _isJoining = false;
          _errorMessage = 'Failed to join: $e';
        });
      }
    }
  }
  
  Future<String> _getOrCreateDeviceId() async {
    // ИСПРАВЛЕНИЕ: Пробуем получить deviceId из сохранённого peerId
    final savedPeerId = await _storageService.getPeerId();
    if (savedPeerId != null) {
      // Извлекаем deviceId из peerId формата "code_deviceId"
      final parts = savedPeerId.split('_');
      if (parts.length >= 2) {
        return parts.last;
      }
    }

    // ИСПРАВЛЕНИЕ: Проверяем отдельное хранилище deviceId
    String? savedDeviceId = await _storageService.getDeviceId();
    if (savedDeviceId == null) {
      final random = Random();
      savedDeviceId = '${random.nextInt(999).toString().padLeft(3, '0')}';
      await _storageService.saveDeviceId(savedDeviceId);
    }
    return savedDeviceId;
  }
  
  /// Connect to a paired device directly
  Future<void> _connectToPairedDevice(Map<String, dynamic> device) async {
    final deviceId = device['deviceId'] as String;
    final deviceName = device['deviceName'] as String? ?? 'Unknown Device';
    final connectionCode = device['connectionCode'] as String;
    
    developer.log('Connecting to paired device: $deviceName (code: $connectionCode)', name: 'ConnectScreen');
    
    setState(() {
      _isJoining = true;
      _errorMessage = null;
    });
    
    try {
      final serverUrl = await _storageService.getServerUrl() ?? 'https://p2p-chat-csjq.onrender.com';
      final deviceIdLocal = await _getOrCreateDeviceId();
      final myPeerId = '${connectionCode}_$deviceIdLocal';

      developer.log('My peerId: $myPeerId', name: 'ConnectScreen');

      // Connect to signaling — НЕ указываем роль, определим после
      await _signalingService.connect(
        roomCode: connectionCode,
        customPeerId: myPeerId,
        serverUrl: serverUrl,
        isInitiator: false,  // По умолчанию joiner при reconnect
      );
      
      // Join room
      await _roomManager.createOrJoinRoom(connectionCode, myPeerId, serverUrl);
      
      // Update last connected time
      await _storageService.updateDeviceLastConnected(deviceId);
      
      // ИСПРАВЛЕНИЕ: Определяем роль ДЕТЕРМИНИСТИЧЕСКИ
      // Устройство с меньшим peerId = initiator (всегда одинаковый результат на обоих)
      final otherPeers = _signalingService.peersInRoom;
      bool isInitiator;

      if (otherPeers.isEmpty) {
        // Никого нет — мы первые, ждём (становимся initiator)
        isInitiator = true;
        developer.log('No peers in room — becoming initiator', name: 'ConnectScreen');
      } else {
        // Кто-то есть — сравниваем peerId
        final otherPeerId = otherPeers.first;
        isInitiator = myPeerId.compareTo(otherPeerId) < 0;
        developer.log('Peer $otherPeerId in room — role: ${isInitiator ? "initiator" : "joiner"} (by peerId comparison)', name: 'ConnectScreen');
      }

      _navigateToChat(
        isInitiator: isInitiator,
        remotePeerId: otherPeers.isNotEmpty ? otherPeers.first : '',
        connectionCode: connectionCode,
        isAutoJoin: false,
      );
    } catch (e) {
      developer.log('Connect to paired device error: $e', name: 'ConnectScreen');
      if (mounted) {
        setState(() {
          _isJoining = false;
          _errorMessage = 'Failed to connect: $e';
        });
      }
    }
  }
  
  Future<void> _removePairedDevice(String deviceId) async {
    await _storageService.removePairedDevice(deviceId);
    await _loadPairedDevices();
  }
  
  Future<void> _navigateToChat({
    required bool isInitiator, 
    required String? remotePeerId,
    required String connectionCode,
    required bool isAutoJoin,
  }) async {
    // ИСПРАВЛЕНИЕ: ВСЕГДА инициализируем WebRTC перед навигацией
    // Это гарантирует, что peerConnection создан заново для каждой новой сессии
    print('ConnectScreen: Initializing WebRTC (isInitiator=$isInitiator, remote=$remotePeerId, isAutoJoin=$isAutoJoin)');

    // Если соединение уже существует, сначала закрываем его
    if (_webRTCService.isInitialized) {
      print('ConnectScreen: WebRTC already initialized, closing before reinitialize...');
      await _webRTCService.closeConnection();
    }

    await _webRTCService.initialize(
      isInitiator: isInitiator,
      remotePeerId: remotePeerId,
    );
    print('ConnectScreen: WebRTC initialized successfully');

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          signalingService: _signalingService,
          storageService: _storageService,
          webRTCService: _webRTCService,
          isInitiator: isInitiator,
          remotePeerId: remotePeerId ?? '',
          connectionCode: connectionCode,
        ),
      ),
    );
  }
  
  
  String _formatLastConnected(String? isoDate) {
    if (isoDate == null) return 'Never';
    
    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final diff = now.difference(date);
      
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes} min ago';
      if (diff.inDays < 1) return '${diff.inHours} hours ago';
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) return '${diff.inDays} days ago';
      
      return DateFormat('MMM d, yyyy').format(date);
    } catch (e) {
      return 'Unknown';
    }
  }
  
  @override
  Widget build(BuildContext context) {
    // Show loading while auto-joining
    if (_isAutoJoining) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Checking previous chat...',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Connecting without code',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // Show loading while reconnecting
    if (_isReconnecting) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Reconnecting to previous chat...',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isReconnecting = false;
                  });
                },
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      );
    }
    
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                
                // Logo/Icon
                const Icon(
                  Icons.chat_bubble_outline,
                  size: 60,
                  color: AppConstants.primaryColor,
                ),
                
                const SizedBox(height: 12),
                
                // Title
                Text(
                  AppConstants.appName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppConstants.primaryColor,
                  ),
                ),
                
                const SizedBox(height: 4),
                
                // Subtitle
                Text(
                  'Secure P2P Messaging',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
                ),
                
                // Auto-join info
                if (_hasPreviousConnection)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppConstants.successColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.sync, size: 16, color: AppConstants.successColor),
                        const SizedBox(width: 8),
                        Text(
                          'Auto-connect available',
                          style: TextStyle(
                            color: AppConstants.successColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                
                const SizedBox(height: 24),
                
                // Server URL Settings
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: () {
                            setState(() {
                              _showServerSettings = !_showServerSettings;
                            });
                          },
                          child: Row(
                            children: [
                              Icon(
                                _showServerSettings ? Icons.expand_less : Icons.expand_more,
                                color: Colors.grey,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Server Settings',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
                              ),
                              const Spacer(),
                              const Icon(Icons.settings, color: Colors.grey, size: 16),
                            ],
                          ),
                        ),
                        if (_showServerSettings) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: _serverUrlController,
                            style: const TextStyle(fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'Server URL',
                              hintText: 'https://p2p-chat-csjq.onrender.com',
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                              ),
                              prefixIcon: const Icon(Icons.link, size: 20),
                              helperText: 'Default: Render deployed server',
                              helperStyle: const TextStyle(fontSize: 11),
                            ),
                            keyboardType: TextInputType.url,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Generate Code Section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text(
                          'Create New Chat',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Generate a code and share it',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: _isConnecting ? null : _generateCode,
                            icon: _isConnecting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.add, size: 20),
                            label: Text(_isConnecting ? 'Creating...' : 'Generate Code'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // Divider
                const Row(
                  children: [
                    Expanded(child: Divider(height: 1)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('OR', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ),
                    Expanded(child: Divider(height: 1)),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Join with Code Section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text(
                          'Join Chat',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Enter 6-digit code from friend',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Code input
                        TextField(
                          controller: _codeController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 28,
                            letterSpacing: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            hintText: '000000',
                            counterText: '',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                            ),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _errorMessage = null;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        // JOIN CHAT BUTTON
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _isJoining ? null : _joinWithCode,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppConstants.secondaryColor,
                              foregroundColor: Colors.white,
                            ),
                            icon: _isJoining
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.login, size: 20),
                            label: Text(
                              _isJoining ? 'Connecting...' : 'Join Chat',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                // PAIRED DEVICES SECTION
                if (_pairedDevices.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  
                  const Row(
                    children: [
                      Expanded(child: Divider(height: 1)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('OR', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ),
                      Expanded(child: Divider(height: 1)),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Synced Devices Section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.devices,
                                color: AppConstants.primaryColor,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Synced Devices',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Spacer(),
                              if (_isLoadingDevices)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              else
                                IconButton(
                                  icon: const Icon(Icons.refresh, size: 18),
                                  onPressed: _loadPairedDevices,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Tap to reconnect instantly',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 12),
                          
                          // Device list
                          ..._pairedDevices.map((device) {
                            final deviceName = device['deviceName'] as String? ?? 'Unknown Device';
                            final lastConnected = _formatLastConnected(device['lastConnectedAt'] as String?);
                            final totalMessages = device['totalMessages'] as int? ?? 0;
                            final deviceId = device['deviceId'] as String;
                            
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                onTap: () => _connectToPairedDevice(device),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.grey[200]!),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: AppConstants.primaryColor.withOpacity(0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.smartphone,
                                          color: AppConstants.primaryColor,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              deviceName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Last: $lastConnected • $totalMessages messages',
                                              style: TextStyle(
                                                color: Colors.grey[600],
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                                        onPressed: () => _removePairedDevice(deviceId),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.chevron_right,
                                        color: Colors.grey,
                                        size: 20,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  ),
                ],
                
                const SizedBox(height: 16),
                
                // Error Message
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppConstants.errorColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppConstants.errorColor, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: AppConstants.errorColor,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                
                const SizedBox(height: 16),
                
                // Info text
                const Text(
                  'No registration required. Messages are encrypted.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 11,
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Version text
                Text(
                  'v${AppConstants.appVersion}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 10,
                  ),
                ),
                
                const SizedBox(height: 20),

              ],
            ),
          ),
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    // ИСПРАВЛЕНИЕ: НЕ dispose WebRTCService — он передаётся в ChatScreen!
    // WebRTCService будет очищен при полном отключении в ChatScreen._disconnect()
    _serverUrlController.dispose();
    _codeController.dispose();
    super.dispose();
  }
}
