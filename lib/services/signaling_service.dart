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
  bool _isConnected = false;

  final _connectionController = StreamController<bool>.broadcast();

  Stream<bool> get onConnectionStateChanged => _connectionController.stream;

  // ГЛАВНЫЙ CALLBACK — WebRTCService устанавливает его
  Function(Map<String, dynamic>)? onSignalCallback;

  String? get peerId => _peerId;
  String? get roomCode => _roomCode;
  bool get isConnected => _isConnected;
  bool get isInitiator => _isInitiator;

  final List<String> _peersInRoom = [];
  List<String> get peersInRoom => List.unmodifiable(_peersInRoom);

  bool _isPolling = false;

  Future<String> connect({
    String? customPeerId,
    String? roomCode,
    String? serverUrl,
    bool? isInitiator,
  }) async {
    print('SignalingService: connect() called');
    print('SignalingService: customPeerId=$customPeerId, roomCode=$roomCode, isInitiator=$isInitiator');

    try {
      _serverUrl = serverUrl ?? AppConstants.signalingServerUrl;
      _serverUrl = _serverUrl!.replaceAll(RegExp(r'/$'), '');
      print('SignalingService: Server URL: $_serverUrl');

      if (isInitiator != null) {
        _isInitiator = isInitiator;
        _peerId = customPeerId;
        _roomCode = roomCode;
        print('SignalingService: Mode = ${_isInitiator ? "INITIATOR" : "JOINER"}, roomCode=$_roomCode, peerId=$_peerId');
      } else if (customPeerId != null && roomCode != null) {
        _peerId = customPeerId;
        _roomCode = roomCode;
        _isInitiator = true;
      } else {
        throw Exception('customPeerId and roomCode must be provided');
      }

      // Health check
      final response = await http.get(
        Uri.parse('$_serverUrl/status'),
      ).timeout(AppConstants.connectionTimeout);

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }

      // Register
      final requestBody = {
        'peerId': _peerId,
        'roomCode': _roomCode,
        'isInitiator': _isInitiator,
      };
      print('SignalingService: Registering: ${jsonEncode(requestBody)}');

      final registerResponse = await http.post(
        Uri.parse('$_serverUrl/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      ).timeout(AppConstants.connectionTimeout);

      print('SignalingService: Register response status=${registerResponse.statusCode}');

      if (registerResponse.statusCode == 200) {
        final data = jsonDecode(registerResponse.body);
        _isConnected = true;
        if (!_connectionController.isClosed) {
          _connectionController.add(true);
        }

        if (data['roomCode'] != null) {
          _roomCode = data['roomCode'];
        }
        if (data.containsKey('isInitiator')) {
          _isInitiator = data['isInitiator'];
        }

        // Запоминаем пиров в комнате
        _peersInRoom.clear();
        if (data['peersInRoom'] != null) {
          for (var peer in data['peersInRoom']) {
            if (peer.toString() != _peerId) {
              _peersInRoom.add(peer.toString());
            }
          }
        }
        // Также проверяем массив 'peers'
        if (data['peers'] != null) {
          for (var peer in data['peers']) {
            final peerStr = peer.toString();
            if (peerStr != _peerId && !_peersInRoom.contains(peerStr)) {
              _peersInRoom.add(peerStr);
            }
          }
        }

        print('SignalingService: Registration OK! peerId=$_peerId, roomCode=$_roomCode, isInitiator=$_isInitiator, otherPeers=$_peersInRoom');

        // Start polling
        _startPolling();

        return _peerId!;
      } else {
        throw Exception('Registration failed: ${registerResponse.statusCode}');
      }
    } catch (e, stackTrace) {
      print('SignalingService: Connection error: $e');
      _isConnected = false;
      if (!_connectionController.isClosed) {
        _connectionController.add(false);
      }
      throw Exception('Failed to connect: $e');
    }
  }

  void _startPolling() {
    print('SignalingService: Starting polling for peer $_peerId');
    _isPolling = true;
    _pollLoop();
  }

  void _stopPolling() {
    _isPolling = false;
    print('SignalingService: Polling stopped');
  }

  Future<void> _pollLoop() async {
    while (_isPolling && _isConnected) {
      await _pollSignals();
      await Future.delayed(const Duration(seconds: 1));
    }
    print('SignalingService: Poll loop ended');
  }

  Future<void> _pollSignals() async {
    if (!_isConnected || _peerId == null) return;

    try {
      final response = await http.get(
        Uri.parse('$_serverUrl/poll?peerId=$_peerId'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final signals = data['signals'] as List<dynamic>?;

        if (signals != null && signals.isNotEmpty) {
          print('SignalingService: Received ${signals.length} signals');

          for (final signal in signals) {
            final type = signal['type'];
            final from = signal['from'];
            print('SignalingService: Signal type=$type from=$from');

            // Track peers
            if (type == 'peer-connected' && from != null && !_peersInRoom.contains(from)) {
              _peersInRoom.add(from);
            }

            // ★★★ DELIVER TO WEBRTC SERVICE ★★★
            print('SignalingService: onSignalCallback is ${onSignalCallback != null ? "SET" : "NULL"}');
            if (onSignalCallback != null) {
              print('SignalingService: >>> Delivering signal type=$type to WebRTCService');
              onSignalCallback!(signal);
            } else {
              print('SignalingService: ⚠️ NO CALLBACK! Signal type=$type LOST!');
            }
          }
        }
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
      final body = {
        'from': _peerId,
        ...signal,
      };
      print('SignalingService: Sending signal type=${signal['type']} to=${signal['to']}');

      final response = await http.post(
        Uri.parse('$_serverUrl/signal'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(AppConstants.connectionTimeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to send signal: ${response.statusCode}');
      }
      print('SignalingService: Signal sent OK');
    } catch (e) {
      print('SignalingService: Error sending signal: $e');
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
      print('SignalingService: Error disconnecting: $e');
    }

    _peerId = null;
    _peersInRoom.clear();
    print('SignalingService: Disconnected');
  }

  void dispose() {
    _stopPolling();
    onSignalCallback = null;
    if (!_connectionController.isClosed) {
      _connectionController.close();
    }
  }
}