import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../utils/constants.dart';

class SignalingService {
  String? _peerId;
  String? _serverUrl;
  String? _roomCode;
  bool _isInitiator = false;
  Timer? _pollTimer;
  bool _isConnected = false;
  
  final _signalController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _peerConnectedController = StreamController<String>.broadcast();
  
  Stream<Map<String, dynamic>> get onSignalReceived => _signalController.stream;
  Stream<bool> get onConnectionStateChanged => _connectionController.stream;
  Stream<String> get onPeerConnected => _peerConnectedController.stream;
  
  Function(Map<String, dynamic>)? onSignal;
  Function(String)? onPeerConnectedCallback;
  
  String? get peerId => _peerId;
  bool get isConnected => _isConnected;
  bool get isInitiator => _isInitiator;
  
  Future<String> connect({String? customPeerId, String? roomCode, String? serverUrl, bool? isInitiator}) async {
    print('SignalingService: connect() called');
    print('SignalingService: customPeerId=$customPeerId, roomCode=$roomCode');
    
    try {
      _serverUrl = serverUrl ?? AppConstants.signalingServerUrl;
      _serverUrl = _serverUrl!.replaceAll(RegExp(r'/$'), '');
      print('SignalingService: Server URL: $_serverUrl');
      
      // ИСПРАВЛЕНИЕ: Используем явный параметр роли, если он передан
      if (isInitiator != null) {
        _isInitiator = isInitiator!;
        if (_isInitiator) {
          // Явный Initiator
          _peerId = customPeerId;
          _roomCode = customPeerId;
          print('SignalingService: Mode = EXPLICIT INITIATOR, peerId=$_peerId');
        } else {
          // Явный Joiner
          _isInitiator = false;
          _roomCode = roomCode;
          _peerId = customPeerId; // Joiner тоже может иметь свой ID
          print('SignalingService: Mode = EXPLICIT JOINER, roomCode=$_roomCode, peerId=$_peerId');
        }
      } else if (customPeerId != null) {
        // Обратная совместимость: Initiator - uses their code as room
        _peerId = customPeerId;
        _roomCode = customPeerId;
        _isInitiator = true;
        print('SignalingService: Mode = LEGACY INITIATOR, peerId=$_peerId');
      } else if (roomCode != null) {
        // Обратная совместимость: Joiner - has room code to join
        _isInitiator = false;
        _roomCode = roomCode;
        print('SignalingService: Mode = LEGACY JOINER, roomCode=$_roomCode');
        // peerId will be assigned by server
      } else {
        // Neither - error
        print('SignalingService: ERROR - Neither customPeerId nor roomCode provided!');
        throw Exception('Either customPeerId (initiator) or roomCode (joiner) must be provided');
      }

      
      developer.log('Connecting to server: $_serverUrl (initiator: $_isInitiator)', name: 'SignalingService');
      print('SignalingService: Checking server health...');
      
      // Check server health
      final response = await http.get(
        Uri.parse('$_serverUrl/status'),
      ).timeout(AppConstants.connectionTimeout);
      
      print('SignalingService: Health check status=${response.statusCode}');
      
      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }
      
      print('SignalingService: Registering with server...');
      // Register with server
      final registerResponse = await http.post(
        Uri.parse('$_serverUrl/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'peerId': _peerId,
          'roomCode': _roomCode,
          'isInitiator': _isInitiator,
        }),
      ).timeout(AppConstants.connectionTimeout);
      
      print('SignalingService: Register response status=${registerResponse.statusCode}');
      
      if (registerResponse.statusCode == 200) {
        final data = jsonDecode(registerResponse.body);
        _isConnected = true;
        if (!_connectionController.isClosed) {
          _connectionController.add(true);
        }
        
        // ИСПРАВЛЕНИЕ: Не переписываем peerId от сервера, используем только roomCode
        // peerId уже установлен клиентом и сохранён в StorageService
        if (!_isInitiator) {
          _roomCode = data['roomCode'];
        }
        
        // ИСПРАВЛЕНИЕ: Обновляем роль на основе ответа сервера.
        // Сервер теперь является источником истины (Initiator, если комната создана, иначе Joiner).
        if (data.containsKey('isInitiator')) {
          _isInitiator = data['isInitiator'];
          print('SignalingService: Updated isInitiator from server response: $_isInitiator');
        }
        
        print('SignalingService: Registration successful! peerId=$_peerId, isConnected=$_isConnected, isInitiator=$_isInitiator');
        developer.log('Connected with peer ID: $_peerId, room: $_roomCode, initiator: $_isInitiator', name: 'SignalingService');
        
        print('SignalingService: About to start polling...');
        // Start polling for signals
        _startPolling();
        print('SignalingService: Polling should be started now');
        
        // If joiner, notify initiator that we joined
        if (!_isInitiator && _roomCode != null) {
          print('SignalingService: Joiner notifying initiator $_roomCode');
          await Future.delayed(const Duration(milliseconds: 500));
          await sendSignal({
            'type': 'peer-joined',
            'to': _roomCode, // Initiator's peerId is the room code
          });
          print('SignalingService: Join notification sent to $_roomCode');
        }
        
        return _peerId!;


      } else {
        print('SignalingService: Registration failed with status ${registerResponse.statusCode}');
        throw Exception('Registration failed: ${registerResponse.statusCode}');
      }
      
    } catch (e, stackTrace) {
      print('SignalingService: Connection error: $e');
      print('SignalingService: Stack trace: $stackTrace');
      developer.log('Connection error: $e', name: 'SignalingService');
      _isConnected = false;
      if (!_connectionController.isClosed) {
        _connectionController.add(false);
      }
      throw Exception('Failed to connect: $e');
    }
  }
  
  
  String _generateSixDigitCode() {
    return (100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString();
  }
  
  bool _isPolling = false;

  void _startPolling() {
    print('SignalingService: Starting polling for peer $_peerId');
    _pollTimer?.cancel();
    _isPolling = true;
    _pollLoop();
    print('SignalingService: Polling loop started');
  }

  void _stopPolling() {
    _isPolling = false;
    _pollTimer?.cancel();
    print('SignalingService: Polling stopped');
  }

  Future<void> _pollLoop() async {
    print('SignalingService: _pollLoop() started');
    while (_isPolling && _isConnected) {
      print('SignalingService: Polling iteration...');
      await _pollSignals();
      await Future.delayed(const Duration(seconds: 1));
    }
    print('SignalingService: _pollLoop() ended');
  }



  
  Future<void> _pollSignals() async {
    print('SignalingService: _pollSignals() CALLED - isConnected=$_isConnected, peerId=$_peerId');
    
    if (!_isConnected || _peerId == null) {
      print('SignalingService: Polling skipped - not connected or no peerId');
      return;
    }
    
    try {
      print('SignalingService: Polling for signals... peerId=$_peerId');

      final response = await http.get(
        Uri.parse('$_serverUrl/poll?peerId=$_peerId'),
      ).timeout(const Duration(seconds: 5));
      
      print('SignalingService: Poll response status=${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final signals = data['signals'] as List<dynamic>?;
        
        print('SignalingService: Received ${signals?.length ?? 0} signals');
        
        if (signals != null && signals.isNotEmpty) {
          for (final signal in signals) {
            final type = signal['type'];
            final from = signal['from'];
            print('SignalingService: Processing signal type=$type from=$from');
            
            // Notify about peer connection
            if (type == 'peer-connected' && from != null) {
              print('SignalingService: Peer connected event from $from - notifying listeners');
              if (!_peerConnectedController.isClosed) {
                _peerConnectedController.add(from);
              }
              onPeerConnectedCallback?.call(from);
            }
            
            // Forward signal to handler
            if (!_signalController.isClosed) {
              _signalController.add(signal);
            }
            onSignal?.call(signal);

          }
        } else {
          print('SignalingService: No signals in queue');
        }
      } else {
        print('SignalingService: Poll failed with status ${response.statusCode}');
      }
    } catch (e) {
      print('SignalingService: Polling error: $e');
    }
  }

  
  Future<void> sendSignal(Map<String, dynamic> signal) async {
    if (!_isConnected) {
      throw Exception('Not connected to signaling server');
    }
    
    try {
      final response = await http.post(
        Uri.parse('$_serverUrl/signal'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'from': _peerId,
          ...signal,
        }),
      ).timeout(AppConstants.connectionTimeout);
      
      if (response.statusCode != 200) {
        throw Exception('Failed to send signal: ${response.statusCode}');
      }
    } catch (e) {
      developer.log('Error sending signal: $e', name: 'SignalingService');
      throw Exception('Failed to send signal: $e');
    }
  }
  
  Future<void> disconnect() async {
    _stopPolling();
    _isConnected = false;
    if (!_connectionController.isClosed) {
      _connectionController.add(false);
    }

    
    try {
      if (_peerId != null && _serverUrl != null) {
        await http.post(
          Uri.parse('$_serverUrl/disconnect'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'peerId': _peerId}),
        ).timeout(const Duration(seconds: 5));
      }
    } catch (e) {
      developer.log('Error disconnecting: $e', name: 'SignalingService');
    }
    
    _peerId = null;
    developer.log('Disconnected', name: 'SignalingService');
  }
  
  void dispose() {
    _pollTimer?.cancel();
    _signalController.close();
    _connectionController.close();
    _peerConnectedController.close();
  }
}
