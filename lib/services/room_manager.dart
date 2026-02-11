import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'storage_service.dart';
import 'webrtc_service.dart';

/// Manages room membership and initiator role
/// 
/// Logic:
/// - First device to enter = isInitiator
/// - If initiator leaves, other device becomes initiator
/// - If both leave, room is empty, first to return = initiator
/// - Auto-reconnect without code if room was previously joined
class RoomManager extends ChangeNotifier {
  final StorageService _storageService;
  final WebRTCService _webRTCService;
  
  String? _roomCode;
  String? _myPeerId;
  bool _isInitiator = false;
  bool _isInRoom = false;
  String? _otherPeerId;
  
  // Heartbeat to track room presence
  Timer? _heartbeatTimer;
  Timer? _presenceCheckTimer;
  
  // Track other peer's presence
  DateTime? _lastOtherPeerSeen;
  bool _otherPeerOnline = false;
  
  // Streams
  final _initiatorController = StreamController<bool>.broadcast();
  final _otherPeerController = StreamController<bool>.broadcast();
  
  Stream<bool> get onInitiatorChanged => _initiatorController.stream;
  Stream<bool> get onOtherPeerPresenceChanged => _otherPeerController.stream;
  
  RoomManager(this._storageService, this._webRTCService) {
    _setupWebRTCListeners();
  }
  
  // Getters
  String? get roomCode => _roomCode;
  String? get myPeerId => _myPeerId;
  bool get isInitiator => _isInitiator;
  bool get isInRoom => _isInRoom;
  bool get otherPeerOnline => _otherPeerOnline;
  String? get otherPeerId => _otherPeerId;
  
  void _setupWebRTCListeners() {
    // Listen for custom signaling messages about room presence
    _webRTCService.messages.listen((data) {
      print('RoomManager: Received message type=${data['type']}');
      if (data['type'] == 'room_presence') {
        _handlePresenceMessage(data);
      } else if (data['type'] == 'room_join_request') {
        _handleJoinRequest(data);
      } else if (data['type'] == 'room_join_response') {
        _handleJoinResponse(data);
      }
    });
    
    // Listen for connection state changes
    _webRTCService.connectionState.listen((state) {
      print('RoomManager: Connection state changed to ${state.status}');
      if (state.status == 'online' && _isInRoom) {
        // Send presence announcement when connected
        print('RoomManager: Connection online, sending presence...');
        _announcePresence();
      } else if (state.status == 'offline') {
        _otherPeerOnline = false;
        _otherPeerController.add(false);
        notifyListeners();
      }
    });
  }
  
  /// Try to auto-join a previously connected room
  Future<AutoJoinResult> tryAutoJoin() async {
    final savedRoomCode = await _storageService.getConnectionCode();
    final savedPeerId = await _storageService.getPeerId();
    final wasConnected = await _storageService.getIsConnected();
    final savedServerUrl = await _storageService.getServerUrl();
    
    developer.log('Trying auto-join: room=$savedRoomCode, peer=$savedPeerId, wasConnected=$wasConnected', 
        name: 'RoomManager');
    
    if (savedRoomCode == null || savedPeerId == null || !wasConnected) {
      return AutoJoinResult.noPreviousRoom;
    }
    
    _roomCode = savedRoomCode;
    _myPeerId = savedPeerId;
    
    // Try to connect to signaling server
    try {
      // Connect with saved identity
      await _webRTCService.reconnectWithIdentity(
        peerId: savedPeerId,
        roomCode: savedRoomCode,
        serverUrl: savedServerUrl,
      );
      
      // Wait a moment for connection
      await Future.delayed(const Duration(seconds: 2));
      
      // Check if other peer is already in room
      final otherPeerPresent = await _checkOtherPeerPresence();
      
      if (otherPeerPresent) {
        // Other peer is there, we join as non-initiator
        _isInitiator = false;
        _isInRoom = true;
        
        // Send join request to establish WebRTC
        _sendJoinRequest();
        
        notifyListeners();
        return AutoJoinResult.joinedAsNonInitiator;
      } else {
        // Room is empty, we become initiator
        _isInitiator = true;
        _isInRoom = true;
        
        // Start heartbeat as initiator
        _startHeartbeat();
        
        notifyListeners();
        return AutoJoinResult.joinedAsInitiator;
      }
      
    } catch (e) {
      developer.log('Auto-join failed: $e', name: 'RoomManager');
      return AutoJoinResult.failed;
    }
  }
  
  /// Create or join a room with code
  Future<JoinResult> createOrJoinRoom(String roomCode, String peerId, String serverUrl) async {
    _roomCode = roomCode;
    _myPeerId = peerId;
    
    developer.log('Creating/joining room: $roomCode, peer: $peerId', name: 'RoomManager');
    
    // Save to storage for future auto-join
    await _storageService.saveConnectionCode(roomCode);
    await _storageService.savePeerId(peerId);
    await _storageService.saveServerUrl(serverUrl);
    await _storageService.saveIsConnected(true);
    
    // Check if this is first time (creating) or joining existing
    // For now, assume we're creating - the join logic will adjust dynamically
    _isInitiator = true;
    _isInRoom = true;
    
    // Start heartbeat
    _startHeartbeat();
    
    notifyListeners();
    return JoinResult.success;
  }
  
  /// Handle when other peer joins
  void _handleJoinRequest(Map<String, dynamic> data) {
    final joiningPeerId = data['peerId'];
    
    print('RoomManager: Received join request from: $joiningPeerId');
    
    _otherPeerId = joiningPeerId;
    _otherPeerOnline = true;
    _lastOtherPeerSeen = DateTime.now();
    
    // If I was initiator and alone, I stay initiator
    // If I was non-initiator, I stay non-initiator
    
    // Send response
    _sendJoinResponse(joiningPeerId);
    
    _otherPeerController.add(true);
    notifyListeners();
  }
  
  /// Handle join response
  void _handleJoinResponse(Map<String, dynamic> data) {
    final respondingPeerId = data['peerId'];
    final isResponderInitiator = data['isInitiator'] ?? false;
    
    print('RoomManager: Received join response from: $respondingPeerId, isInitiator: $isResponderInitiator');
    
    _otherPeerId = respondingPeerId;
    _otherPeerOnline = true;
    _lastOtherPeerSeen = DateTime.now();
    
    // If responder is initiator, I'm not
    if (isResponderInitiator) {
      _isInitiator = false;
      _initiatorController.add(false);
    }
    
    _otherPeerController.add(true);
    notifyListeners();
  }
  
  /// Handle presence heartbeat from other peer
  void _handlePresenceMessage(Map<String, dynamic> data) {
    final peerId = data['peerId'];
    final isPeerInitiator = data['isInitiator'] ?? false;
    
    print('RoomManager: Received presence from: $peerId, isInitiator: $isPeerInitiator');
    
    if (peerId != _myPeerId) {
      _otherPeerId = peerId;
      _otherPeerOnline = true;
      _lastOtherPeerSeen = DateTime.now();
      
      // Update initiator status if needed
      if (isPeerInitiator && _isInitiator) {
        // Both think they're initiator - conflict resolution
        // Peer with lexicographically smaller ID wins
        if (peerId.compareTo(_myPeerId!) < 0) {
          _isInitiator = false;
          _initiatorController.add(false);
          notifyListeners();
        }
      }
      
      _otherPeerController.add(true);
      notifyListeners();
    }
  }
  
  /// Send presence announcement
  void _announcePresence() {
    // ИСПРАВЛЕНИЕ: Проверяем, что WebRTC соединение установлено перед отправкой
    if (!_isInRoom || _myPeerId == null || !_webRTCService.isConnected) {
      print('RoomManager: _announcePresence skipped - isInRoom=$_isInRoom, myPeerId=$_myPeerId, isConnected=${_webRTCService.isConnected}');
      return;
    }
    
    print('RoomManager: _announcePresence sending...');
    _webRTCService.sendMessage({
      'type': 'room_presence',
      'peerId': _myPeerId,
      'isInitiator': _isInitiator,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Send join request
  void _sendJoinRequest() {
    // ИСПРАВЛЕНИЕ: Проверяем, что WebRTC соединение установлено перед отправкой
    if (!_isInRoom || _myPeerId == null || !_webRTCService.isConnected) {
      return;
    }
    
    _webRTCService.sendMessage({
      'type': 'room_join_request',
      'peerId': _myPeerId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Send join response
  void _sendJoinResponse(String toPeerId) {
    // ИСПРАВЛЕНИЕ: Проверяем, что WebRTC соединение установлено перед отправкой
    if (!_isInRoom || _myPeerId == null || !_webRTCService.isConnected) {
      return;
    }
    
    _webRTCService.sendMessage({
      'type': 'room_join_response',
      'peerId': _myPeerId,
      'isInitiator': _isInitiator,
      'toPeerId': toPeerId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
  
  /// Start heartbeat timer
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      // ИСПРАВЛЕНИЕ: Отложенный запуск heartbeat - проверяем состояние соединения
      if (!_webRTCService.isConnected) {
        print('RoomManager: Heartbeat skipped - WebRTC not connected');
        return;
      }
      _announcePresence();
    });
    
    // Also check for other peer presence
    _presenceCheckTimer?.cancel();
    _presenceCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkPresenceTimeout();
    });
  }
  
  /// Check if other peer timed out
  void _checkPresenceTimeout() {
    if (_lastOtherPeerSeen == null) return;
    
    final timeout = DateTime.now().difference(_lastOtherPeerSeen!);
    if (timeout > const Duration(seconds: 20)) {
      // Other peer is gone
      if (_otherPeerOnline) {
        _otherPeerOnline = false;
        _otherPeerController.add(false);
        
        // If I was non-initiator and other (initiator) left, I become initiator
        if (!_isInitiator) {
          _isInitiator = true;
          _initiatorController.add(true);
          developer.log('Became initiator because other peer left', name: 'RoomManager');
        }
        
        notifyListeners();
      }
    }
  }
  
  /// Check if other peer is present in room
  Future<bool> _checkOtherPeerPresence() async {
    // Send a presence probe and wait for response
    _announcePresence();
    
    // Wait for responses
    await Future.delayed(const Duration(seconds: 3));
    
    return _otherPeerOnline;
  }
  
  /// Leave room (but keep ability to auto-rejoin)
  Future<void> leaveRoom() async {
    _isInRoom = false;
    _heartbeatTimer?.cancel();
    _presenceCheckTimer?.cancel();
    
    // Don't clear storage - we want to be able to auto-rejoin
    // Just mark as temporarily disconnected
    await _storageService.saveIsConnected(false);
    
    notifyListeners();
  }
  
  /// Permanently leave room (clear all data)
  Future<void> permanentlyLeaveRoom() async {
    _isInRoom = false;
    _isInitiator = false;
    _heartbeatTimer?.cancel();
    _presenceCheckTimer?.cancel();
    
    await _storageService.clearConnectionData();
    
    notifyListeners();
  }
  
  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _presenceCheckTimer?.cancel();
    _initiatorController.close();
    _otherPeerController.close();
    super.dispose();
  }
}

enum AutoJoinResult {
  noPreviousRoom,
  joinedAsInitiator,
  joinedAsNonInitiator,
  failed,
}

enum JoinResult {
  success,
  failed,
  roomFull,
}
