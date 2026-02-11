import 'dart:developer' as developer;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/signaling_service.dart';
import '../services/storage_service.dart';
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
  final _serverUrlController = TextEditingController();
  final _codeController = TextEditingController();
  
  String? _generatedCode;
  bool _isConnecting = false;
  bool _isJoining = false;
  String? _errorMessage;
  bool _showServerSettings = false;
  bool _isReconnecting = false;
  
  @override
  void initState() {
    super.initState();
    _initializeAndCheckConnection();
  }
  
  Future<void> _initializeAndCheckConnection() async {
    try {
      await _storageService.initialize();
      developer.log('Storage initialized', name: 'ConnectScreen');
      
      // Check if there was a previous connection
      await _checkPreviousConnection();
    } catch (e) {
      developer.log('Storage init error: $e', name: 'ConnectScreen');
    }
  }
  
  Future<void> _checkPreviousConnection() async {
    final wasConnected = await _storageService.getIsConnected();
    final savedServerUrl = await _storageService.getServerUrl();
    final savedPeerId = await _storageService.getPeerId();
    final savedRemotePeerId = await _storageService.getRemotePeerId();
    
    developer.log('Checking previous connection: wasConnected=$wasConnected, peerId=$savedPeerId, remotePeerId=$savedRemotePeerId', name: 'ConnectScreen');
    
    if (wasConnected && savedServerUrl != null && savedPeerId != null && savedRemotePeerId != null) {
      // Auto-reconnect to previous chat
      setState(() {
        _isReconnecting = true;
        _serverUrlController.text = savedServerUrl;
      });
      
      try {
        developer.log('Auto-reconnecting to previous chat...', name: 'ConnectScreen');
        
        await _signalingService.connect(
          customPeerId: savedPeerId,
          serverUrl: savedServerUrl,
        );
        
        developer.log('Auto-reconnect successful', name: 'ConnectScreen');
        
        // Navigate to chat with saved connection
        _navigateToChat(
          isInitiator: false, // We're rejoining existing connection
          remotePeerId: savedRemotePeerId,
          connectionCode: savedPeerId,
        );
        
      } catch (e) {
        developer.log('Auto-reconnect failed: $e', name: 'ConnectScreen');
        setState(() {
          _isReconnecting = false;
        });
        // Stay on connect screen, user can manually reconnect
      }
    } else {
      // No previous connection, set default server URL
      _serverUrlController.text = 'http://192.168.0.163:3000';
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
      developer.log('Connecting to signaling server...', name: 'ConnectScreen');
      final serverUrl = _serverUrlController.text.trim();
      
      // Save server URL
      await _storageService.saveServerUrl(serverUrl);
      
      // Initiator connects with their code
      await _signalingService.connect(
        customPeerId: code,
        serverUrl: serverUrl.isNotEmpty ? serverUrl : null,
      );
      
      // Save connection data
      await _storageService.savePeerId(code);
      await _storageService.saveConnectionCode(code);
      await _storageService.saveIsConnected(true);
      
      developer.log('Connected successfully with code: $code', name: 'ConnectScreen');
      
      // Navigate to chat
      _navigateToChat(
        isInitiator: true, 
        remotePeerId: code,
        connectionCode: code,
      );
      
    } catch (e) {
      developer.log('Connection error: $e', name: 'ConnectScreen');
      setState(() {
        _isConnecting = false;
        _errorMessage = 'Failed to connect: $e';
      });
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
      developer.log('Joining with code: $enteredCode', name: 'ConnectScreen');
      
      final serverUrl = _serverUrlController.text.trim();
      
      // Save server URL
      await _storageService.saveServerUrl(serverUrl);
      
      // Joiner connects with room code
      final myPeerId = await _signalingService.connect(
        roomCode: enteredCode,  // <-- Передаём код комнаты!
        serverUrl: serverUrl.isNotEmpty ? serverUrl : null,
      );
      
      // Save connection data
      await _storageService.savePeerId(myPeerId);
      await _storageService.saveRemotePeerId(enteredCode);
      await _storageService.saveConnectionCode(enteredCode);
      await _storageService.saveIsConnected(true);
      
      developer.log('Joined successfully, my ID: $myPeerId', name: 'ConnectScreen');
      
      _navigateToChat(
        isInitiator: false, 
        remotePeerId: enteredCode,
        connectionCode: enteredCode,
      );
      
    } catch (e) {
      developer.log('Join error: $e', name: 'ConnectScreen');
      setState(() {
        _isJoining = false;
        _errorMessage = 'Failed to join: $e';
      });
    }
  }
  
  void _navigateToChat({
    required bool isInitiator, 
    required String remotePeerId,
    required String connectionCode,
  }) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          signalingService: _signalingService,
          storageService: _storageService,
          isInitiator: isInitiator,
          remotePeerId: remotePeerId,
          connectionCode: connectionCode,
        ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
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
                
                // Logo/Icon - smaller for mobile
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
                
                const SizedBox(height: 24),
                
                // Server URL Settings - compact
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
                              hintText: 'http://192.168.0.163:3000',
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(AppConstants.borderRadius),
                              ),
                              prefixIcon: const Icon(Icons.link, size: 20),
                              helperText: 'Default: your PC IP:3000',
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
                
                // Compact Divider
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
    _signalingService.dispose();
    _serverUrlController.dispose();
    _codeController.dispose();
    super.dispose();
  }
}
