import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/connection_state.dart' as app_state;
import '../utils/constants.dart';
import 'signaling_service.dart';

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  final SignalingService _signalingService;
  
  final _connectionStateController = StreamController<app_state.ConnectionStateModel>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _fileChunkController = StreamController<Map<String, dynamic>>.broadcast();
  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  final _deliveryController = StreamController<Map<String, dynamic>>.broadcast();
  
  Stream<app_state.ConnectionStateModel> get connectionState => _connectionStateController.stream;
  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  Stream<Map<String, dynamic>> get fileChunks => _fileChunkController.stream;
  Stream<Map<String, dynamic>> get typingIndicators => _typingController.stream;
  Stream<Map<String, dynamic>> get deliveryReceipts => _deliveryController.stream;
  
  String? _localPeerId;
  String? _remotePeerId;
  bool _isInitiator = false;
  
  // Keep-alive mechanism to prevent NAT timeout
  Timer? _keepAliveTimer;
  static const Duration _keepAliveInterval = Duration(seconds: 5); // ИСПРАВЛЕНИЕ: Уменьшено с 10 до 5 сек
  
  WebRTCService(this._signalingService) {
    _setupSignalingListeners();
  }
  
  void _setupSignalingListeners() {
    _signalingService.onSignal = _handleSignalingMessage;
    
    // Listen for peer connection events
    _signalingService.onPeerConnected.listen((peerId) {
      print('SignalingService: Peer connected event: $peerId');
      if (_isInitiator && _remotePeerId == null) {
        _remotePeerId = peerId;
        print('Initiator: Setting remote peer to $peerId, creating offer...');
        _createOffer();
      }
    });
  }

  
  Future<void> initialize({required bool isInitiator, String? remotePeerId}) async {
    _isInitiator = isInitiator;
    _remotePeerId = remotePeerId;
    _localPeerId = _signalingService.peerId;
    
    _updateConnectionState(status: AppConstants.statusConnecting);
    
    try {
      // Create peer connection
      _peerConnection = await createPeerConnection(AppConstants.iceServers);
      
      // Setup connection state listeners
      _peerConnection!.onConnectionState = (state) {
        print('Connection state: $state');
        _handleConnectionStateChange(state);
      };
      
      _peerConnection!.onIceConnectionState = (state) {
        print('ICE connection state: $state');
        _handleIceConnectionStateChange(state);
      };
      
      _peerConnection!.onIceGatheringState = (state) {
        print('ICE gathering state: $state');
      };
      
      // Handle ICE candidates
      _peerConnection!.onIceCandidate = (candidate) {
        if (candidate.candidate != null && _remotePeerId != null) {
          print('Sending ICE candidate to $_remotePeerId');
          _signalingService.sendSignal({
            'type': 'ice-candidate',
            'candidate': candidate.toMap(),
            'to': _remotePeerId,
          });
        } else if (candidate.candidate == null) {
          // ICE gathering complete - all candidates have been collected
          print('ICE gathering complete - all candidates collected');
          _checkConnectionStateAfterGathering();
        }
      };
      
      // Setup data channel handling
      if (isInitiator) {
        // Initiator creates data channel
        print('Initiator: Creating data channel');
        await _createDataChannel();
      } else {
        // Joiner waits for data channel from initiator
        print('Joiner: Waiting for data channel from initiator');
        _peerConnection!.onDataChannel = (channel) {
          print('Joiner: Received data channel from initiator');
          _setupDataChannel(channel);
        };
      }
      
      print('WebRTC initialized. Initiator: $_isInitiator, Local ID: $_localPeerId');

      
    } catch (e) {
      print('Error initializing WebRTC: $e');
      _updateConnectionState(
        status: AppConstants.statusError,
        errorMessage: 'Failed to initialize WebRTC: $e',
      );
    }
  }
  
  Future<void> _createDataChannel() async {
    print('=== _createDataChannel START ===');
    final dataChannelInit = RTCDataChannelInit()
      ..ordered = true
      ..maxRetransmits = 30;
    
    try {
      print('Creating data channel with label: chat');
      _dataChannel = await _peerConnection!.createDataChannel(
        'chat',
        dataChannelInit,
      );
      print('Data channel created successfully. Label: ${_dataChannel!.label}, ID: ${_dataChannel!.id}');
      _setupDataChannel(_dataChannel!);
      print('=== _createDataChannel END ===');
    } catch (e) {
      print('ERROR creating data channel: $e');
      print('=== _createDataChannel FAILED ===');
      rethrow;
    }
  }

  void _setupDataChannel(RTCDataChannel channel) {
    print('=== _setupDataChannel START ===');
    _dataChannel = channel;
    print('Data channel label: ${channel.label}, ID: ${channel.id}');
    print('Initial state: ${channel.state}');
  
    channel.onDataChannelState = (state) {
      print('=== DATA CHANNEL STATE CHANGED ===');
      print('New state: $state');
      print('Label: ${channel.label}, ID: ${channel.id}');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        print('✅ Data channel is OPEN! Messages can be sent.');
        _updateConnectionState(status: AppConstants.statusOnline);
        // Start keep-alive when data channel opens
        _startKeepAlive();
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        print('❌ Data channel is CLOSED');
        _stopKeepAlive();
        _updateConnectionState(status: AppConstants.statusOffline);
      }
      print('=== DATA CHANNEL STATE CHANGED END ===');
    };
    
    channel.onMessage = (data) {
      print('=== DATA CHANNEL MESSAGE RECEIVED ===');
      print('Message type: ${data.runtimeType}');
      print('Message content: ${data.text}');
      _handleDataChannelMessage(data);
      print('=== DATA CHANNEL MESSAGE RECEIVED END ===');
    };
    print('=== _setupDataChannel END ===');
  }
  
  void _handleDataChannelMessage(RTCDataChannelMessage data) {
    try {
      final message = jsonDecode(data.text);
      final type = message['type'];
      
      switch (type) {
        case 'message':
          _messageController.add(message['data']);
          break;
        case 'file-chunk':
          _fileChunkController.add(message['data']);
          break;
        case 'typing':
          _typingController.add(message['data']);
          break;
        case 'delivery':
          _deliveryController.add(message['data']);
          break;
        case 'keep-alive':
          // Silent acknowledgment - just log it
          print('Keep-alive received from peer');
          break;
        default:
          print('Unknown message type: $type');
      }
    } catch (e) {
      print('Error parsing message: $e');
    }
  }
    
  Future<void> _createOffer() async {
    try {
      print('Creating offer for $_remotePeerId');
      
      // ИСПРАВЛЕНИЕ: Проверяем, что DataChannel создан и готов
      if (_isInitiator) {
        if (_dataChannel == null) {
          print('WARNING: DataChannel is null before creating offer! Creating now...');
          await _createDataChannel();
        }
        if (_dataChannel == null) {
          print('ERROR: Failed to create DataChannel!');
          throw Exception('DataChannel not initialized');
        }
        print('DataChannel is ready for offer');
      }
      
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      print('Local description (offer) set successfully');
      
      if (_remotePeerId != null) {
        await _signalingService.sendSignal({
          'type': 'offer',
          'sdp': offer.toMap(),
          'to': _remotePeerId,
        });
        print('Offer sent to $_remotePeerId');
      } else {
        print('ERROR: Cannot send offer - remotePeerId is null');
      }
    } catch (e) {
      print('Error creating offer: $e');
    }
  }

  
  Future<void> _handleSignalingMessage(Map<String, dynamic> signal) async {
    final type = signal['type'];
    final from = signal['from'];
    
    print('Received signal: $type from $from');
    
    // Update remote peer ID if not set
    if (from != null && _remotePeerId == null) {
      _remotePeerId = from;
    }
    
    switch (type) {
      case 'offer':
        await _handleOffer(signal);
        break;
      case 'answer':
        await _handleAnswer(signal);
        break;
      case 'ice-candidate':
        await _handleIceCandidate(signal['candidate']);
        break;
      case 'peer-connected':
      case 'peer-joined':
        // Peer joined our room
        if (_isInitiator && from != null) {
          print('Initiator: Peer $from joined, creating offer');
          _remotePeerId = from;
          await _createOffer();
        }
        break;

    }
  }
  
  Future<void> _handleOffer(Map<String, dynamic> signal) async {
    print('=== _handleOffer START ===');
    try {
      final from = signal['from'];
      final sdpMap = signal['sdp'];
      
      print('Received offer from $from');
      
      // Set remote peer ID from the signal
      if (from != null) {
        _remotePeerId = from;
        print('Joiner: Setting remote peer to $from');
      }
      
      final offer = RTCSessionDescription(
        sdpMap['sdp'],
        sdpMap['type'],
      );
      
      print('Setting remote description (offer)...');
      await _peerConnection!.setRemoteDescription(offer);
      print('Remote description set, creating answer...');
      
      final answer = await _peerConnection!.createAnswer();
      print('Answer created, setting local description...');
      await _peerConnection!.setLocalDescription(answer);
      print('Local description (answer) set');
      
      if (_remotePeerId != null) {
        await _signalingService.sendSignal({
          'type': 'answer',
          'sdp': answer.toMap(),
          'to': _remotePeerId,
        });
        print('Answer sent to $_remotePeerId');
      } else {
        print('ERROR: Cannot send answer - remotePeerId is null');
      }
      print('=== _handleOffer END ===');
    } catch (e) {
      print('Error handling offer: $e');
      print('=== _handleOffer FAILED ===');
    }
  }

  
  Future<void> _handleAnswer(Map<String, dynamic> signal) async {
    try {
      final from = signal['from'];
      final sdpMap = signal['sdp'];
      
      print('Received answer from $from');
      
      final answer = RTCSessionDescription(
        sdpMap['sdp'],
        sdpMap['type'],
      );
      
      print('Setting remote description (answer)...');
      await _peerConnection!.setRemoteDescription(answer);
      print('Answer applied successfully! Connection should establish soon.');
    } catch (e) {
      print('Error handling answer: $e');
    }
  }

  
  Future<void> _handleIceCandidate(Map<String, dynamic> candidateMap) async {
    try {
      final candidate = RTCIceCandidate(
        candidateMap['candidate'],
        candidateMap['sdpMid'],
        candidateMap['sdpMLineIndex'],
      );
      await _peerConnection!.addCandidate(candidate);
    } catch (e) {
      print('Error handling ICE candidate: $e');
    }
  }
  
  void _handleConnectionStateChange(RTCPeerConnectionState state) {
    print('=== PEER CONNECTION STATE CHANGED ===');
    print('New state: $state');
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        print('✅ RTC Peer Connection CONNECTED!');
        print('Data channel state: ${_dataChannel?.state}');
        _updateConnectionState(status: AppConstants.statusOnline);
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        print('❌ RTC Peer Connection DISCONNECTED');
        _stopKeepAlive();
        _updateConnectionState(status: AppConstants.statusOffline);
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        print('❌ RTC Peer Connection FAILED');
        _stopKeepAlive();
        _updateConnectionState(
          status: AppConstants.statusError,
          errorMessage: 'Connection failed',
        );
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        print('❌ RTC Peer Connection CLOSED');
        _stopKeepAlive();
        _updateConnectionState(status: AppConstants.statusOffline);
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        print('⏳ RTC Peer Connection CONNECTING...');
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
        print('⏳ RTC Peer Connection NEW');
        break;
      default:
        print('RTC Peer Connection state: $state');
        break;
    }
    print('=== PEER CONNECTION STATE CHANGED END ===');
  }

  /// ИСПРАВЛЕНИЕ: Обработка состояния ICE соединения с улучшенной диагностикой
  void _handleIceConnectionStateChange(RTCIceConnectionState state) {
    print('=== ICE CONNECTION STATE CHANGED ===');
    print('New ICE state: $state');
    switch (state) {
      case RTCIceConnectionState.RTCIceConnectionStateConnected:
        print('✅ ICE Connection CONNECTED!');
        break;
      case RTCIceConnectionState.RTCIceConnectionStateCompleted:
        print('✅ ICE Connection COMPLETED!');
        break;
      case RTCIceConnectionState.RTCIceConnectionStateFailed:
        print('❌ ICE Connection FAILED!');
        print('Possible causes:');
        print('  - NAT traversal failed (try different network)');
        print('  - Firewall blocking UDP/TCP');
        print('  - STUN/TURN servers not accessible');
        _updateConnectionState(
          status: AppConstants.statusError,
          errorMessage: 'ICE connection failed - check network/firewall',
        );
        break;
      case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        print('⚠️ ICE Connection DISCONNECTED (may reconnect...)');
        break;
      case RTCIceConnectionState.RTCIceConnectionStateClosed:
        print('❌ ICE Connection CLOSED');
        break;
      case RTCIceConnectionState.RTCIceConnectionStateChecking:
        print('⏳ ICE Connection CHECKING...');
        break;
      case RTCIceConnectionState.RTCIceConnectionStateNew:
        print('⏳ ICE Connection NEW');
        break;
      default:
        print('ICE Connection state: $state');
        break;
    }
    print('=== ICE CONNECTION STATE CHANGED END ===');
  }
  
  /// ИСПРАВЛЕНИЕ: Проверка состояния после сбора всех ICE кандидатов
  void _checkConnectionStateAfterGathering() {
    final iceState = _peerConnection?.iceConnectionState;
    final connState = _peerConnection?.connectionState;
    final dataChannelState = _dataChannel?.state;

    print('=== POST-GATHERING STATE CHECK ===');
    print('ICE State: $iceState');
    print('Connection State: $connState');
    print('Data Channel State: $dataChannelState');

    if (iceState == RTCIceConnectionState.RTCIceConnectionStateFailed) {
      print('❌ ICE gathering failed - connection will not establish');
      _updateConnectionState(
        status: AppConstants.statusError,
        errorMessage: 'ICE gathering failed - check network connectivity',
      );
    } else if (iceState == RTCIceConnectionState.RTCIceConnectionStateConnected ||
               iceState == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
      print('✅ ICE gathering succeeded');
      if (dataChannelState != RTCDataChannelState.RTCDataChannelOpen) {
        print('⚠️ ICE connected but data channel not open yet - waiting...');
      }
    }
    print('=== POST-GATHERING STATE CHECK END ===');
  }

  
  void _attemptReconnect() {
    // ВНИМАНИЕ: Этот метод является заглушкой и не выполняет переподключение.
    // Обрыв соединения на уровне WebRTC здесь не обрабатывается.
    // Основная логика, вероятно, находится в RoomManager (heartbeat).
    print('WARNING: _attemptReconnect() is a stub and does not perform reconnection.');
  }
  
  void _updateConnectionState({
    required String status,
    String? errorMessage,
  }) {
    _connectionStateController.add(app_state.ConnectionStateModel(
      status: status,
      errorMessage: errorMessage,
      peerId: _localPeerId,
      remotePeerId: _remotePeerId,
      connectedAt: status == AppConstants.statusOnline ? DateTime.now() : null,
    ));
  }
  
  // Send message methods
  Future<void> sendMessage(Map<String, dynamic> data) async {
    if (_dataChannel?.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw Exception('Data channel is not open');
    }
    
    final message = {
      'type': 'message',
      'data': data,
    };
    
    _dataChannel!.send(RTCDataChannelMessage(jsonEncode(message)));
  }
  
  Future<void> sendFileChunk(Map<String, dynamic> data) async {
    if (_dataChannel?.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw Exception('Data channel is not open');
    }
    
    final message = {
      'type': 'file-chunk',
      'data': data,
    };
    
    _dataChannel!.send(RTCDataChannelMessage(jsonEncode(message)));
  }
  
  Future<void> sendTypingIndicator(bool isTyping) async {
    if (_dataChannel?.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    
    final message = {
      'type': 'typing',
      'data': {
        'userId': _localPeerId,
        'isTyping': isTyping,
        'timestamp': DateTime.now().toIso8601String(),
      },
    };
    
    _dataChannel!.send(RTCDataChannelMessage(jsonEncode(message)));
  }
  
  Future<void> sendDeliveryReceipt(String messageId, String status) async {
    if (_dataChannel?.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    
    final message = {
      'type': 'delivery',
      'data': {
        'messageId': messageId,
        'status': status,
        'timestamp': DateTime.now().toIso8601String(),
      },
    };
    
    _dataChannel!.send(RTCDataChannelMessage(jsonEncode(message)));
  }
  
  // Getters
  String? get localPeerId => _localPeerId;
  String? get remotePeerId => _remotePeerId;
  bool get isConnected => _dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen;
  
  // Cleanup
  Future<void> dispose() async {
    _stopKeepAlive();
    await _dataChannel?.close();
    await _peerConnection?.close();
    _connectionStateController.close();
    _messageController.close();
    _fileChunkController.close();
    _typingController.close();
    _deliveryController.close();
  }
  
  /// Start keep-alive mechanism to prevent NAT timeout
  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(_keepAliveInterval, (_) {
      _sendKeepAlive();
    });
    print('Keep-alive timer started (interval: ${_keepAliveInterval.inSeconds}s)');
  }
  
  /// Stop keep-alive mechanism
  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    print('Keep-alive timer stopped');
  }
  
  /// Send keep-alive message through data channel
  void _sendKeepAlive() {
    if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
      try {
        final message = {
          'type': 'keep-alive',
          'timestamp': DateTime.now().toIso8601String(),
        };
        _dataChannel!.send(RTCDataChannelMessage(jsonEncode(message)));
        print('Keep-alive sent');
      } catch (e) {
        print('Error sending keep-alive: $e');
      }
    }
  }
  
  Future<void> closeConnection() async {
    await _dataChannel?.close();
    await _peerConnection?.close();
    _dataChannel = null;
    _peerConnection = null;
    _updateConnectionState(status: AppConstants.statusOffline);
  }
  
  /// Reconnect with a specific identity (peerId) and room code
  Future<void> reconnectWithIdentity({
    required String peerId,
    required String roomCode,
    String? serverUrl,
  }) async {
    _localPeerId = peerId;
    
    // Reconnect to signaling server with the same identity
    await _signalingService.connect(
      customPeerId: peerId,
      serverUrl: serverUrl,
    );
    
    // Wait for signaling connection
    await Future.delayed(const Duration(seconds: 1));
  }
}
