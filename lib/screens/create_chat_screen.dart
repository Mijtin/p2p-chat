import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import '../utils/constants.dart';

class CreateChatBottomSheet extends StatefulWidget {
  final Function({required String roomCode, required String serverUrl}) onCreateChat;
  final Function({required String roomCode, required String serverUrl}) onJoinChat;

  const CreateChatBottomSheet({
    super.key,
    required this.onCreateChat,
    required this.onJoinChat,
  });

  @override
  State<CreateChatBottomSheet> createState() => _CreateChatBottomSheetState();
}

class _CreateChatBottomSheetState extends State<CreateChatBottomSheet> {
  final _serverUrlController = TextEditingController();
  final _roomCodeController = TextEditingController();
  bool _showServerSettings = false;
  bool _isLoading = false;
  bool _isGenerateMode = true; // true = создать, false = подключиться

  @override
  void initState() {
    super.initState();
    _serverUrlController.text = AppConstants.signalingServerUrl;
    _generateRandomCode();
  }

  String _generateSixDigitCode() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  void _generateRandomCode() {
    setState(() {
      _roomCodeController.text = _generateSixDigitCode();
    });
  }

  void _handleCreateChat() async {
    final roomCode = _roomCodeController.text.trim();
    final serverUrl = _serverUrlController.text.trim();

    if (roomCode.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 6-digit code'),
          backgroundColor: AppConstants.errorColor,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await widget.onCreateChat(roomCode: roomCode, serverUrl: serverUrl);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create chat: $e'),
            backgroundColor: AppConstants.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleJoinChat() async {
    final roomCode = _roomCodeController.text.trim();
    final serverUrl = _serverUrlController.text.trim();

    if (roomCode.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 6-digit code'),
          backgroundColor: AppConstants.errorColor,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await widget.onJoinChat(roomCode: roomCode, serverUrl: serverUrl);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to join chat: $e'),
            backgroundColor: AppConstants.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: _roomCodeController.text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Code copied!'),
        backgroundColor: AppConstants.successColor,
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppConstants.surfaceCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppConstants.dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          // Title
          const Text(
            'New Chat',
            style: TextStyle(
              color: AppConstants.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _isGenerateMode 
                ? 'Generate a code and share it with your friend'
                : 'Enter the code from your friend',
            style: TextStyle(
              color: AppConstants.textMuted,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          // Mode Toggle
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppConstants.surfaceInput,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isGenerateMode = true;
                        _generateRandomCode();
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _isGenerateMode ? AppConstants.primaryColor : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_circle_outline,
                            size: 18,
                            color: _isGenerateMode ? Colors.white : AppConstants.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Create',
                            style: TextStyle(
                              color: _isGenerateMode ? Colors.white : AppConstants.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isGenerateMode = false;
                        _roomCodeController.text = '';
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: !_isGenerateMode ? AppConstants.primaryColor : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.login,
                            size: 18,
                            color: !_isGenerateMode ? Colors.white : AppConstants.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Join',
                            style: TextStyle(
                              color: !_isGenerateMode ? Colors.white : AppConstants.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Server Settings Toggle
          InkWell(
            onTap: () => setState(() => _showServerSettings = !_showServerSettings),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _showServerSettings ? Icons.expand_less : Icons.expand_more,
                    color: AppConstants.textMuted,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Server Settings',
                    style: TextStyle(
                      color: AppConstants.textMuted,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.settings, color: AppConstants.textMuted, size: 16),
                ],
              ),
            ),
          ),
          if (_showServerSettings) ...[
            TextField(
              controller: _serverUrlController,
              style: const TextStyle(fontSize: 13, color: AppConstants.textPrimary),
              decoration: InputDecoration(
                labelText: 'Server URL',
                hintText: 'https://p2p-chat-csjq.onrender.com',
                isDense: true,
                prefixIcon: const Icon(Icons.link, size: 20, color: AppConstants.textMuted),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
          ],
          // Room Code Input
          if (_isGenerateMode) ...[
            // Generate mode - show code with refresh button
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _roomCodeController,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.primaryColor,
                      letterSpacing: 4,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Room Code',
                      prefixIcon: const Icon(Icons.vpn_key, color: AppConstants.primaryColor),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.refresh, color: AppConstants.textSecondary),
                            onPressed: _generateRandomCode,
                            tooltip: 'Generate new code',
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, color: AppConstants.textSecondary),
                            onPressed: _copyCode,
                            tooltip: 'Copy code',
                          ),
                        ],
                      ),
                    ),
                    readOnly: true,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ] else ...[
            // Join mode - manual input
            TextField(
              controller: _roomCodeController,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppConstants.textPrimary,
                letterSpacing: 4,
              ),
              decoration: InputDecoration(
                labelText: 'Enter Code',
                hintText: '123456',
                prefixIcon: const Icon(Icons.vpn_key, color: AppConstants.textMuted),
                counterText: '${_roomCodeController.text.length}/6',
              ),
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
            ),
          ],
          const SizedBox(height: 24),
          // Action Button
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : (_isGenerateMode ? _handleCreateChat : _handleJoinChat),
              icon: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(_isGenerateMode ? Icons.add_circle_outline : Icons.login),
              label: Text(
                _isLoading 
                    ? (_isGenerateMode ? 'Creating...' : 'Joining...')
                    : (_isGenerateMode ? 'Create New Chat' : 'Join Existing Chat'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _roomCodeController.dispose();
    super.dispose();
  }
}
