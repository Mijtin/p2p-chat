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
import '../widgets/customization_sheet.dart';
import '../main.dart' show themeSettings;
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
            isInitiator: true,
          );

          await _roomManager.createOrJoinRoom(
            savedRoomCode, savedPeerId,
            savedServerUrl ?? _serverUrlController.text.trim(),
          );

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
        _navigateToChat(
          isInitiator: false,
          remotePeerId: _roomManager.otherPeerId ?? '',
          connectionCode: _roomManager.roomCode!,
          isAutoJoin: true,
        );
        return;
        
      case AutoJoinResult.noPreviousRoom:
        setState(() {
          _isAutoJoining = false;
          _isReconnecting = false;
        });
        _serverUrlController.text = 'https://p2p-chat-csjq.onrender.com';
        return;
        
      case AutoJoinResult.failed:
        setState(() {
          _isAutoJoining = false;
        });
        await _checkPreviousConnection();
        return;
    }
  }
  
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
      
      await _storageService.saveServerUrl(serverUrl);
      
      final deviceId = await _getOrCreateDeviceId();
      final peerId = '${code}_$deviceId';
      developer.log('Generated peerId: $peerId (deviceId: $deviceId)', name: 'ConnectScreen');

      developer.log('*** BEFORE connect: roomCode="$code", peerId="$peerId" ***', name: 'ConnectScreen');
      await _signalingService.connect(
        roomCode: code,
        customPeerId: peerId,
        serverUrl: serverUrl.isNotEmpty ? serverUrl : null,
        isInitiator: true,
      );
      developer.log('*** AFTER connect: done ***', name: 'ConnectScreen');
      
      await _roomManager.createOrJoinRoom(code, peerId, serverUrl);
      
      developer.log('Signaling connected successfully', name: 'ConnectScreen');
      developer.log('Signaling peerId: ${_signalingService.peerId}', name: 'ConnectScreen');
      developer.log('Signaling isInitiator: ${_signalingService.isInitiator}', name: 'ConnectScreen');
      developer.log('Room created with code: $code (peerId: $peerId)', name: 'ConnectScreen');
      
      _navigateToChat(
        isInitiator: true, 
        remotePeerId: null,
        connectionCode: code,
        isAutoJoin: false,
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
      
      await _storageService.saveServerUrl(serverUrl);
      
      final deviceId = await _getOrCreateDeviceId();
      final myPeerId = '${enteredCode}_$deviceId';
      developer.log('Generated peerId: $myPeerId (deviceId: $deviceId)', name: 'ConnectScreen');
      
      developer.log('*** BEFORE join: roomCode="$enteredCode", peerId="$myPeerId" ***', name: 'ConnectScreen');
      await _signalingService.connect(
        roomCode: enteredCode,
        customPeerId: myPeerId,
        serverUrl: serverUrl.isNotEmpty ? serverUrl : null,
        isInitiator: false,
      );
      developer.log('*** AFTER join: done ***', name: 'ConnectScreen');
      
      await _roomManager.createOrJoinRoom(enteredCode, myPeerId, serverUrl);
      
      developer.log('Signaling connected successfully', name: 'ConnectScreen');
      developer.log('Signaling peerId: ${_signalingService.peerId}', name: 'ConnectScreen');
      developer.log('Signaling isInitiator: ${_signalingService.isInitiator}', name: 'ConnectScreen');
      developer.log('Joined room: $enteredCode, peerId: $myPeerId', name: 'ConnectScreen');
      developer.log('Role: Joiner (manual code entry)', name: 'ConnectScreen');

      _navigateToChat(
        isInitiator: false,
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
    final savedPeerId = await _storageService.getPeerId();
    if (savedPeerId != null) {
      final parts = savedPeerId.split('_');
      if (parts.length >= 2) {
        return parts.last;
      }
    }

    String? savedDeviceId = await _storageService.getDeviceId();
    if (savedDeviceId == null) {
      final random = Random();
      savedDeviceId = '${random.nextInt(999).toString().padLeft(3, '0')}';
      await _storageService.saveDeviceId(savedDeviceId);
    }
    return savedDeviceId;
  }
  
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

      await _signalingService.connect(
        roomCode: connectionCode,
        customPeerId: myPeerId,
        serverUrl: serverUrl,
        isInitiator: false,
      );
      
      await _roomManager.createOrJoinRoom(connectionCode, myPeerId, serverUrl);
      
      await _storageService.updateDeviceLastConnected(deviceId);
      
      final otherPeers = _signalingService.peersInRoom;
      bool isInitiator;

      if (otherPeers.isEmpty) {
        isInitiator = true;
        developer.log('No peers in room — becoming initiator', name: 'ConnectScreen');
      } else {
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
    print('ConnectScreen: Initializing WebRTC (isInitiator=$isInitiator, remote=$remotePeerId, isAutoJoin=$isAutoJoin)');

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
  
  @override
  Widget build(BuildContext context) {
    if (_isAutoJoining) {
      return Scaffold(
        backgroundColor: AppConstants.surfaceDark,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: AppConstants.primaryColor),
              const SizedBox(height: 16),
              Text('Checking previous chat...', style: TextStyle(color: AppConstants.textPrimary, fontSize: 16)),
              const SizedBox(height: 8),
              Text('Connecting without code', style: TextStyle(color: AppConstants.textMuted, fontSize: 14)),
            ],
          ),
        ),
      );
    }
    
    if (_isReconnecting) {
      return Scaffold(
        backgroundColor: AppConstants.surfaceDark,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: AppConstants.primaryColor),
              const SizedBox(height: 16),
              Text('Reconnecting...', style: TextStyle(color: AppConstants.textPrimary, fontSize: 16)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _isReconnecting = false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      );
    }
    
    return Scaffold(
      backgroundColor: AppConstants.surfaceDark,
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 30),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              AppConstants.primaryColor.withOpacity(0.15),
                              AppConstants.secondaryColor.withOpacity(0.08),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppConstants.primaryColor.withOpacity(0.15),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.chat_bubble_outline,
                          size: 48,
                          color: AppConstants.primaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      AppConstants.appName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Secure P2P Messaging',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppConstants.textMuted, fontSize: 14),
                    ),
                    if (_hasPreviousConnection)
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppConstants.successColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppConstants.successColor.withOpacity(0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.sync, size: 16, color: AppConstants.successColor),
                            const SizedBox(width: 8),
                            Text('Auto-connect available', style: TextStyle(color: AppConstants.successColor, fontSize: 12)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 28),
                    Container(
                      decoration: BoxDecoration(
                        color: AppConstants.surfaceCard,
                        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                        border: Border.all(color: AppConstants.dividerColor),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            InkWell(
                              onTap: () => setState(() => _showServerSettings = !_showServerSettings),
                              child: Row(
                                children: [
                                  Icon(
                                    _showServerSettings ? Icons.expand_less : Icons.expand_more,
                                    color: AppConstants.textMuted,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text('Server Settings', style: TextStyle(color: AppConstants.textMuted, fontSize: 13)),
                                  const Spacer(),
                                  Icon(Icons.settings, color: AppConstants.textMuted, size: 16),
                                ],
                              ),
                            ),
                            if (_showServerSettings) ...[
                              const SizedBox(height: 8),
                              TextField(
                                controller: _serverUrlController,
                                style: TextStyle(fontSize: 13, color: AppConstants.textPrimary),
                                decoration: InputDecoration(
                                  labelText: 'Server URL',
                                  hintText: 'https://p2p-chat-csjq.onrender.com',
                                  isDense: true,
                                  prefixIcon: Icon(Icons.link, size: 20, color: AppConstants.textMuted),
                                ),
                                keyboardType: TextInputType.url,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppConstants.surfaceCard,
                            AppConstants.surfaceElevated.withOpacity(0.5),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                        border: Border.all(color: AppConstants.dividerColor),
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_circle_outline, color: AppConstants.primaryColor, size: 20),
                              const SizedBox(width: 8),
                              const Text('Create New Chat', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppConstants.textPrimary)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('Generate a code and share it', style: TextStyle(color: AppConstants.textMuted, fontSize: 12)),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: _isConnecting ? null : _generateCode,
                              icon: _isConnecting
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.bolt, size: 20),
                              label: Text(_isConnecting ? 'Creating...' : 'Generate Code'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: Divider(color: AppConstants.dividerColor)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('OR', style: TextStyle(color: AppConstants.textMuted, fontSize: 12)),
                        ),
                        Expanded(child: Divider(color: AppConstants.dividerColor)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: AppConstants.surfaceCard,
                        borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                        border: Border.all(color: AppConstants.dividerColor),
                      ),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.login, color: AppConstants.secondaryColor, size: 20),
                              const SizedBox(width: 8),
                              const Text('Join Chat', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppConstants.textPrimary)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('Enter 6-digit code from friend', style: TextStyle(color: AppConstants.textMuted, fontSize: 12)),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _codeController,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 32,
                              letterSpacing: 14,
                              fontWeight: FontWeight.bold,
                              color: AppConstants.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: '000000',
                              hintStyle: TextStyle(color: AppConstants.textMuted.withOpacity(0.3)),
                              counterText: '',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onChanged: (value) => setState(() => _errorMessage = null),
                          ),
                          const SizedBox(height: 16),
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
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.login, size: 20),
                              label: Text(_isJoining ? 'Connecting...' : 'Join Chat', style: const TextStyle(fontSize: 16)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_pairedDevices.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: Divider(color: AppConstants.dividerColor)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('SAVED', style: TextStyle(color: AppConstants.textMuted, fontSize: 11, letterSpacing: 1)),
                          ),
                          Expanded(child: Divider(color: AppConstants.dividerColor)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._pairedDevices.map((device) {
                        final deviceName = device['deviceName'] as String? ?? 'Unknown Device';
                        final lastConnected = _formatLastConnected(device['lastConnectedAt'] as String?);
                        final totalMessages = device['totalMessages'] as int? ?? 0;
                        final deviceId = device['deviceId'] as String;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: () => _connectToPairedDevice(device),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppConstants.surfaceCard,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppConstants.dividerColor),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppConstants.secondaryColor.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.smartphone, color: AppConstants.secondaryColor, size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(deviceName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppConstants.textPrimary)),
                                        const SizedBox(height: 2),
                                        Text('$lastConnected • $totalMessages msgs', style: TextStyle(color: AppConstants.textMuted, fontSize: 11)),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.close, size: 16, color: AppConstants.textMuted),
                                    onPressed: () => _removePairedDevice(deviceId),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(Icons.chevron_right, color: AppConstants.textMuted, size: 20),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                    const SizedBox(height: 16),
                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppConstants.errorColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppConstants.errorColor.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: AppConstants.errorColor, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_errorMessage!, style: const TextStyle(color: AppConstants.errorColor, fontSize: 12))),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),
                    Text(
                      'No registration required. Messages are encrypted.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppConstants.textMuted, fontSize: 11),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'v${AppConstants.appVersion}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppConstants.textMuted.withOpacity(0.5), fontSize: 10),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
          // Gear icon in top-right corner for customization
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: Icon(
                Icons.tune,
                color: AppConstants.textSecondary,
                size: 26,
              ),
              onPressed: _showCustomizationSheet,
              tooltip: 'Customization',
            ),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _serverUrlController.dispose();
    _codeController.dispose();
    super.dispose();
  }
}
