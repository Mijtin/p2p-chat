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

  final _connectionStateController =
      StreamController<app_state.ConnectionStateModel>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _fileChunkController = StreamController<Map<String, dynamic>>.broadcast();
  final _typingController = StreamController<Map<String, dynamic>>.broadcast();
  final _deliveryController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<app_state.ConnectionStateModel> get connectionState =>
      _connectionStateController.stream;
  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  Stream<Map<String, dynamic>> get fileChunks => _fileChunkController.stream;
  Stream<Map<String, dynamic>> get typingIndicators => _typingController.stream;
  Stream<Map<String, dynamic>> get deliveryReceipts => _deliveryController.stream;

  String? _localPeerId;
  String? _remotePeerId;
  bool _isInitiator = false;

  Timer? _keepAliveTimer;
  static const Duration _keepAliveInterval = Duration(seconds: 5);

  final List<Map<String, dynamic>> _pendingSignals = [];
  bool _initialized = false;

  // ИСПРАВЛЕНИЕ: Буфер ICE кандидатов до установки remote description
  final List<RTCIceCandidate> _pendingIceCandidates = [];
  bool _remoteDescriptionSet = false;

  WebRTCService(this._signalingService) {
    // ИСПРАВЛЕНИЕ: Устанавливаем callback СРАЗУ в конструкторе
    // Это гарантирует что сигналы не потеряются между connect() и initialize()
    _signalingService.onSignalCallback = _onSignalReceived;
    print('WebRTCService: Constructor — callback registered on SignalingService');
  }

  /// Callback получения сигнала — вызывается из SignalingService
  void _onSignalReceived(Map<String, dynamic> signal) {
    final type = signal['type'];
    final from = signal['from'];
    print('WebRTCService: 📩 Signal received: type=$type from=$from (initialized=$_initialized, peerConnection=${_peerConnection != null})');

    if (!_initialized || _peerConnection == null) {
      print('WebRTCService: ⏳ Buffering signal type=$type (not ready yet)');
      _pendingSignals.add(signal);
      return;
    }

    _handleSignalingMessage(signal);
  }

  /// Initialize WebRTC connection
  Future<void> initialize({required bool isInitiator, String? remotePeerId}) async {
    if (_peerConnection != null) {
      print('WebRTCService: Closing existing connection');
      await closeConnection();
    }

    // ★ ИСПРАВЛЕНИЕ: Гарантируем что callback установлен
    _signalingService.onSignalCallback = _onSignalReceived;
    print('WebRTCService: Callback re-registered in initialize()');

    _isInitiator = isInitiator;
    _remotePeerId = (remotePeerId != null && remotePeerId.isNotEmpty) ? remotePeerId : null;
    _localPeerId = _signalingService.peerId;
    _initialized = false;
    _remoteDescriptionSet = false;       // ИСПРАВЛЕНИЕ: Сбрасываем флаг
    _pendingIceCandidates.clear();       // ИСПРАВЛЕНИЕ: Очищаем буфер ICE кандидатов

    // НЕ очищаем _pendingSignals — там могут быть сигналы с момента connect()
    print('WebRTCService: Initializing... isInitiator=$_isInitiator, localId=$_localPeerId, remoteId=$_remotePeerId, pendingSignals=${_pendingSignals.length}');

    _updateConnectionState(status: AppConstants.statusConnecting);

    try {
      // ИСПРАВЛЕНИЕ: Расширенная конфигурация ICE с TURN поддержкой
      final config = {
        ...AppConstants.iceServers,
        'sdpSemantics': 'unified-plan',
        'iceCandidatePoolSize': 10,
      };
      print('WebRTCService: Creating PeerConnection with TURN support and unified-plan');
      _peerConnection = await createPeerConnection(config);

      _peerConnection!.onConnectionState = (state) {
        print('WebRTCService: PeerConnection state: $state');
        _handleConnectionStateChange(state);
      };

      _peerConnection!.onIceConnectionState = (state) {
        print('WebRTCService: ICE state: $state');
        _handleIceConnectionStateChange(state);
      };

      _peerConnection!.onIceGatheringState = (state) {
        print('WebRTCService: ICE gathering: $state');
      };

      _peerConnection!.onIceCandidate = (candidate) {
        if (candidate.candidate != null && _remotePeerId != null) {
          // ИСПРАВЛЕНИЕ: Логируем тип кандидата для отладки
          final candidateStr = candidate.candidate ?? '';
          String candidateType = 'unknown';
          if (candidateStr.contains('typ host')) {
            candidateType = 'host (local)';
          } else if (candidateStr.contains('typ srflx')) {
            candidateType = 'srflx (STUN)';
          } else if (candidateStr.contains('typ relay')) {
            candidateType = 'relay (TURN)';
          }
          print('WebRTCService: Sending ICE candidate [$candidateType] to $_remotePeerId');

          _signalingService.sendSignal({
            'type': 'ice-candidate',
            'candidate': candidate.toMap(),
            'to': _remotePeerId,
          });
        }
      };

      if (isInitiator) {
        print('WebRTCService: Initiator — creating data channel');
        await _createDataChannel();
      } else {
        print('WebRTCService: Joiner — waiting for data channel');
        _peerConnection!.onDataChannel = (channel) {
          print('WebRTCService: Joiner received data channel');
          _setupDataChannel(channel);
        };
      }

      _initialized = true;
      print('WebRTCService: ✅ Initialized! Initiator=$_isInitiator, localId=$_localPeerId, remoteId=$_remotePeerId');

      // Process buffered signals
      if (_pendingSignals.isNotEmpty) {
        print('WebRTCService: Processing ${_pendingSignals.length} buffered signals...');
        final signals = List<Map<String, dynamic>>.from(_pendingSignals);
        _pendingSignals.clear();
        for (final signal in signals) {
          await _handleSignalingMessage(signal);
        }
      }

      // Check if peers already in room
      if (_isInitiator && (_remotePeerId == null || _remotePeerId!.isEmpty)) {
        final peersInRoom = _signalingService.peersInRoom;
        if (peersInRoom.isNotEmpty) {
          _remotePeerId = peersInRoom.first;
          print('WebRTCService: 🚀 Found peer in room: $_remotePeerId — creating offer');
          await _createOffer();
        } else {
          print('WebRTCService: No peers in room yet, waiting...');
        }
      }

    } catch (e) {
      print('WebRTCService: ❌ Error initializing: $e');
      _updateConnectionState(
        status: AppConstants.statusError,
        errorMessage: 'Failed to initialize WebRTC: $e',
      );
    }
  }

  Future<void> _createDataChannel() async {
    final init = RTCDataChannelInit()
      ..ordered = true
      ..maxRetransmits = 30;

    _dataChannel = await _peerConnection!.createDataChannel('chat', init);
    print('WebRTCService: Data channel created');
    _setupDataChannel(_dataChannel!);
  }

  void _setupDataChannel(RTCDataChannel channel) {
    _dataChannel = channel;

    channel.onDataChannelState = (state) {
      print('WebRTCService: DataChannel state: $state');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        print('WebRTCService: ✅ DataChannel OPEN — ready to chat!');
        _updateConnectionState(status: AppConstants.statusOnline);
        _startKeepAlive();
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        print('WebRTCService: ❌ DataChannel CLOSED');
        _stopKeepAlive();
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
      switch (message['type']) {
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
          break;
      }
    } catch (e) {
      print('WebRTCService: Error parsing DC message: $e');
    }
  }

  // ============================================================
  // SIGNALING
  // ============================================================

  Future<void> _handleSignalingMessage(Map<String, dynamic> signal) async {
    final type = signal['type'];
    final from = signal['from'];

    print('WebRTCService: 📨 Processing signal type=$type from=$from');

    // Update remote peer ID
    if (from != null && from != _localPeerId) {
      if (_remotePeerId == null || _remotePeerId!.isEmpty) {
        _remotePeerId = from;
        print('WebRTCService: Set remotePeerId=$from');
      }
    }

    switch (type) {
      case 'offer':
        await _handleOffer(signal);
        break;
      case 'answer':
        await _handleAnswer(signal);
        break;
      case 'ice-candidate':
        if (signal['candidate'] != null) {
          await _handleIceCandidate(signal['candidate']);
        }
        break;
      case 'peer-connected':
      case 'peer-joined':
        if (from != null && from != _localPeerId) {
          _remotePeerId = from;
          if (_isInitiator) {
            print('WebRTCService: 🚀 Initiator: peer $from connected — creating offer');
            await _createOffer();
          } else {
            print('WebRTCService: Joiner: peer $from connected — waiting for offer');
          }
        }
        break;
      case 'peer-disconnected':
        print('WebRTCService: Peer $from disconnected');
        break;
    }
  }

  Future<void> _createOffer() async {
    if (_peerConnection == null) {
      print('WebRTCService: ❌ Cannot create offer — no peerConnection');
      return;
    }
    if (_remotePeerId == null || _remotePeerId!.isEmpty) {
      print('WebRTCService: ❌ Cannot create offer — no remotePeerId');
      return;
    }

    try {
      if (_isInitiator && _dataChannel == null) {
        await _createDataChannel();
      }

      print('WebRTCService: Creating offer for $_remotePeerId...');
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      await _signalingService.sendSignal({
        'type': 'offer',
        'sdp': offer.toMap(),
        'to': _remotePeerId!,
      });
      print('WebRTCService: ✅ Offer sent to $_remotePeerId');
    } catch (e) {
      print('WebRTCService: ❌ Error creating offer: $e');
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> signal) async {
    try {
      final from = signal['from'];
      if (from != null) _remotePeerId = from;

      final sdpMap = signal['sdp'];
      final offer = RTCSessionDescription(sdpMap['sdp'], sdpMap['type']);

      print('WebRTCService: Setting remote description (offer)');
      _remoteDescriptionSet = false;
      await _peerConnection!.setRemoteDescription(offer);
      _remoteDescriptionSet = true;
      print('WebRTCService: Remote description (offer) set ✅');

      // ИСПРАВЛЕНИЕ: Применяем буферизованные ICE кандидаты
      await _applyPendingIceCandidates();

      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      await _signalingService.sendSignal({
        'type': 'answer',
        'sdp': answer.toMap(),
        'to': _remotePeerId!,
      });
      print('WebRTCService: ✅ Answer sent to $_remotePeerId');
    } catch (e) {
      print('WebRTCService: ❌ Error handling offer: $e');
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> signal) async {
    try {
      final sdpMap = signal['sdp'];
      final answer = RTCSessionDescription(sdpMap['sdp'], sdpMap['type']);

      print('WebRTCService: Setting remote description (answer)');
      _remoteDescriptionSet = false;
      await _peerConnection!.setRemoteDescription(answer);
      _remoteDescriptionSet = true;
      print('WebRTCService: ✅ Answer applied');

      // ИСПРАВЛЕНИЕ: Применяем буферизованные ICE кандидаты
      await _applyPendingIceCandidates();
    } catch (e) {
      print('WebRTCService: ❌ Error handling answer: $e');
    }
  }

  Future<void> _handleIceCandidate(Map<String, dynamic> candidateMap) async {
    try {
      final candidate = RTCIceCandidate(
        candidateMap['candidate'],
        candidateMap['sdpMid'],
        candidateMap['sdpMLineIndex'],
      );

      if (!_remoteDescriptionSet) {
        // ИСПРАВЛЕНИЕ: Буферизуем — remote description ещё не установлен
        print('WebRTCService: ⏳ Buffering ICE candidate (remote description not set yet)');
        _pendingIceCandidates.add(candidate);
      } else {
        // Применяем сразу
        await _peerConnection!.addCandidate(candidate);
        print('WebRTCService: ✅ ICE candidate applied');
      }
    } catch (e) {
      print('WebRTCService: ❌ Error handling ICE candidate: $e');
    }
  }

  /// ИСПРАВЛЕНИЕ: Применить все буферизованные ICE кандидаты
  Future<void> _applyPendingIceCandidates() async {
    if (_pendingIceCandidates.isEmpty) return;

    print('WebRTCService: Applying ${_pendingIceCandidates.length} buffered ICE candidates...');
    final candidates = List<RTCIceCandidate>.from(_pendingIceCandidates);
    _pendingIceCandidates.clear();

    for (final candidate in candidates) {
      try {
        await _peerConnection!.addCandidate(candidate);
        print('WebRTCService: ✅ Buffered ICE candidate applied');
      } catch (e) {
        print('WebRTCService: ❌ Error applying buffered ICE candidate: $e');
      }
    }
  }

  // ============================================================
  // CONNECTION STATE
  // ============================================================

  void _handleConnectionStateChange(RTCPeerConnectionState state) {
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        print('WebRTCService: ✅ PeerConnection CONNECTED');
        _updateConnectionState(status: AppConstants.statusOnline);
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        _stopKeepAlive();
        _updateConnectionState(status: AppConstants.statusOffline);
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _stopKeepAlive();
        _updateConnectionState(status: AppConstants.statusError, errorMessage: 'Connection failed');
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        _stopKeepAlive();
        _updateConnectionState(status: AppConstants.statusOffline);
        break;
      default:
        break;
    }
  }

  void _handleIceConnectionStateChange(RTCIceConnectionState state) {
    if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
      _updateConnectionState(status: AppConstants.statusError, errorMessage: 'ICE failed');
    }
  }

  void _updateConnectionState({required String status, String? errorMessage}) {
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(app_state.ConnectionStateModel(
        status: status,
        errorMessage: errorMessage,
        peerId: _localPeerId,
        remotePeerId: _remotePeerId,
        connectedAt: status == AppConstants.statusOnline ? DateTime.now() : null,
      ));
    }
  }

  // ============================================================
  // SEND
  // ============================================================

  Future<void> sendMessage(Map<String, dynamic> data) async {
    if (_dataChannel?.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw Exception('Data channel not open');
    }
    _dataChannel!.send(RTCDataChannelMessage(jsonEncode({'type': 'message', 'data': data})));
  }

  Future<void> sendFileChunk(Map<String, dynamic> data) async {
    if (_dataChannel?.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw Exception('Data channel not open');
    }
    _dataChannel!.send(RTCDataChannelMessage(jsonEncode({'type': 'file-chunk', 'data': data})));
  }

  Future<void> sendTypingIndicator(bool isTyping) async {
    if (_dataChannel?.state != RTCDataChannelState.RTCDataChannelOpen) return;
    _dataChannel!.send(RTCDataChannelMessage(jsonEncode({
      'type': 'typing',
      'data': {'userId': _localPeerId, 'isTyping': isTyping, 'timestamp': DateTime.now().toIso8601String()},
    })));
  }

  Future<void> sendDeliveryReceipt(String messageId, String status) async {
    if (_dataChannel?.state != RTCDataChannelState.RTCDataChannelOpen) return;
    _dataChannel!.send(RTCDataChannelMessage(jsonEncode({
      'type': 'delivery',
      'data': {'messageId': messageId, 'status': status, 'timestamp': DateTime.now().toIso8601String()},
    })));
  }

  // ============================================================
  // GETTERS
  // ============================================================

  String? get localPeerId => _localPeerId;
  String? get remotePeerId => _remotePeerId;
  bool get isConnected => _dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen;
  bool get isInitialized => _peerConnection != null;

  // ============================================================
  // KEEP-ALIVE
  // ============================================================

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(_keepAliveInterval, (_) {
      if (_dataChannel?.state == RTCDataChannelState.RTCDataChannelOpen) {
        try {
          _dataChannel!.send(RTCDataChannelMessage(
            jsonEncode({'type': 'keep-alive', 'timestamp': DateTime.now().toIso8601String()}),
          ));
        } catch (_) {}
      }
    });
  }

  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  // ============================================================
  // CLEANUP
  // ============================================================

  Future<void> closeConnection() async {
    _stopKeepAlive();
    _initialized = false;
    _remoteDescriptionSet = false;
    _pendingIceCandidates.clear();  // ИСПРАВЛЕНИЕ: Очищаем буфер ICE кандидатов
    await _dataChannel?.close();
    await _peerConnection?.close();
    _dataChannel = null;
    _peerConnection = null;
    // ИСПРАВЛЕНИЕ: НЕ трогаем onSignalCallback!
    // Он должен оставаться активным для приема сигналов
    _updateConnectionState(status: AppConstants.statusOffline);
  }

  Future<void> dispose() async {
    _stopKeepAlive();
    _signalingService.onSignalCallback = null;
    _initialized = false;
    _pendingSignals.clear();
    await _dataChannel?.close();
    await _peerConnection?.close();
    _dataChannel = null;
    _peerConnection = null;
    if (!_connectionStateController.isClosed) _connectionStateController.close();
    if (!_messageController.isClosed) _messageController.close();
    if (!_fileChunkController.isClosed) _fileChunkController.close();
    if (!_typingController.isClosed) _typingController.close();
    if (!_deliveryController.isClosed) _deliveryController.close();
  }
}