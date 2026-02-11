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
    final dataChannelInit = RTCDataChannelInit()
      ..ordered = true
      ..maxRetransmits = 30;
    
    _dataChannel = await _peerConnection!.createDataChannel(
      'chat',
      dataChannelInit,
    );
    
    _setupDataChannel(_dataChannel!);
  }
  
  void _setupDataChannel(RTCDataChannel channel) {
    _dataChannel = channel;
    
    channel.onDataChannelState = (state) {
      print('Data channel state: $state');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _updateConnectionState(status: AppConstants.statusOnline);
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _updateConnectionState(status: AppConstants.statusOffline);
      }
    };
    
    channel.onMessage = (data) {
      _handleDataChannelMessage(data);
    };
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
    } catch (e) {
      print('Error handling offer: $e');
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
    print('RTCPeerConnection state changed: $state');
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        print('RTC Peer Connection CONNECTED!');
        _updateConnectionState(status: AppConstants.statusOnline);
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        print('RTC Peer Connection DISCONNECTED');
        _updateConnectionState(status: AppConstants.statusOffline);
        _attemptReconnect();
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        print('RTC Peer Connection FAILED');
        _updateConnectionState(
          status: AppConstants.statusError,
          errorMessage: 'Connection failed',
        );
        _attemptReconnect();
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        print('RTC Peer Connection CLOSED');
        _updateConnectionState(status: AppConstants.statusOffline);
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        print('RTC Peer Connection CONNECTING...');
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
        print('RTC Peer Connection NEW');
        break;
      default:
        print('RTC Peer Connection state: $state');
        break;
    }
  }

  
  void _attemptReconnect() {
    Future.delayed(AppConstants.reconnectDelay, () {
      if (_connectionStateController.hasListener && 
          _connectionStateController.stream.isBroadcast) {
        print('Attempting to reconnect...');
      }
    });
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
    await _dataChannel?.close();
    await _peerConnection?.close();
    _connectionStateController.close();
    _messageController.close();
    _fileChunkController.close();
    _typingController.close();
    _deliveryController.close();
  }
  
  Future<void> closeConnection() async {
    await _dataChannel?.close();
    await _peerConnection?.close();
    _dataChannel = null;
    _peerConnection = null;
    _updateConnectionState(status: AppConstants.statusOffline);
  }
}
