import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';
import '../models/message.dart';
import '../utils/constants.dart';
import '../utils/theme_settings.dart';
import '../main.dart' show themeSettings;
import '../screens/image_viewer_screen.dart';


class MessageBubble extends StatefulWidget {
  final Message message;
  final bool isPlaying;
  final double? fileProgress;
  final VoidCallback? onPlayAudio;
  final VoidCallback? onLongPress;
  final VoidCallback? onSaveFile;
  final List<Message>? allMessages;

  const MessageBubble({
    super.key,
    required this.message,
    this.isPlaying = false,
    this.fileProgress,
    this.onPlayAudio,
    this.onLongPress,
    this.onSaveFile,
    this.allMessages,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset(widget.message.isOutgoing ? 0.3 : -0.3, 0.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Message? _findReplyMessage() {
    if (widget.message.replyToMessageId == null || widget.allMessages == null) return null;
    try {
      return widget.allMessages!.firstWhere((m) => m.id == widget.message.replyToMessageId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOutgoing = widget.message.isOutgoing;
    final replyMessage = _findReplyMessage();

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
          child: GestureDetector(
            onLongPress: widget.onLongPress,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
              child: Row(
                mainAxisAlignment:
                    isOutgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!isOutgoing) const SizedBox(width: 4),
                  Flexible(
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      padding: _getPadding(),
                      decoration: BoxDecoration(
                        gradient: isOutgoing
                            ? LinearGradient(
                                colors: [
                                  themeSettings.outgoingBubbleColor,
                                  Color.lerp(themeSettings.outgoingBubbleColor, Colors.black, 0.1)!,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : LinearGradient(
                                colors: [
                                  themeSettings.incomingBubbleColor,
                                  Color.lerp(themeSettings.incomingBubbleColor, Colors.black, 0.1)!,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),

                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(isOutgoing ? 18 : 4),
                          bottomRight: Radius.circular(isOutgoing ? 4 : 18),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (replyMessage != null)
                            _buildReplyInBubble(replyMessage, isOutgoing),
                          _buildMessageContent(context),
                          if (widget.fileProgress != null && widget.fileProgress! < 1.0)
                            _buildProgressIndicator(),
                          const SizedBox(height: 4),
                          _buildFooter(),
                        ],
                      ),
                    ),
                  ),
                  if (isOutgoing) const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  EdgeInsets _getPadding() {
    switch (widget.message.type) {
      case 'image':
        return const EdgeInsets.all(4);
      case 'voice':
        return const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
      default:
        return const EdgeInsets.symmetric(horizontal: 14, vertical: 10);
    }
  }

  Widget _buildMessageContent(BuildContext context) {
    if (widget.message.isDeleted) {
      return Text(
        'This message was deleted',
        style: TextStyle(
          fontStyle: FontStyle.italic,
          color: AppConstants.textMuted,
        ),
      );
    }

    switch (widget.message.type) {
      case 'text':
        return _buildTextMessage();
      case 'image':
        return _buildImageMessage(context);
      case 'file':
        return _buildFileMessage(context);
      case 'voice':
        return _buildVoiceMessage();
      default:
        return _buildTextMessage();
    }
  }

  Widget _buildTextMessage() {
    return Text(
      widget.message.text,
      style: TextStyle(
        color: themeSettings.textColor,
        fontSize: 15,
        height: 1.4,
      ),
    );
  }


  Widget _buildImageMessage(BuildContext context) {
    if (widget.message.filePath != null && File(widget.message.filePath!).existsSync()) {
      return GestureDetector(
        onTap: () => _openImageViewer(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              Image.file(
                File(widget.message.filePath!),
                width: 250,
                height: 250,
                fit: BoxFit.cover,
                cacheWidth: 500,
                cacheHeight: 500,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded) return child;
                  return AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeIn,
                    child: child,
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return _buildErrorPlaceholder('Image');
                },
              ),
              if (widget.fileProgress != null && widget.fileProgress! < 1.0)
                Positioned.fill(
                  child: Container(
                    color: Colors.black54,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            value: widget.fileProgress,
                            color: AppConstants.primaryColor,
                            strokeWidth: 3,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${(widget.fileProgress! * 100).toInt()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.zoom_in,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: 250,
      height: 250,
      decoration: BoxDecoration(
        color: AppConstants.surfaceInput,
        borderRadius: BorderRadius.circular(14),
      ),
      child: widget.fileProgress != null && widget.fileProgress! < 1.0
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.image, size: 48, color: AppConstants.textMuted),
                const SizedBox(height: 16),
                SizedBox(
                  width: 100,
                  child: LinearProgressIndicator(
                    value: widget.fileProgress,
                    backgroundColor: AppConstants.dividerColor,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppConstants.primaryColor),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(widget.fileProgress! * 100).toInt()}%',
                  style: TextStyle(color: AppConstants.textMuted, fontSize: 12),
                ),
              ],
            )
          : Icon(Icons.image, size: 64, color: AppConstants.textMuted),
    );
  }

  void _openImageViewer(BuildContext context) {
    if (widget.message.filePath == null) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => ImageViewerScreen(
          imagePath: widget.message.filePath!,
          caption: widget.message.text.isNotEmpty ? widget.message.text : null,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  Widget _buildFileMessage(BuildContext context) {
    final bool isDownloaded =
        widget.message.filePath != null && File(widget.message.filePath!).existsSync();

    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _getFileIcon(),
                  color: AppConstants.primaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.message.fileName ?? 'File',
                      style: const TextStyle(
                        color: AppConstants.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatFileSize(widget.message.fileSize),
                      style: TextStyle(
                        color: AppConstants.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.fileProgress != null && widget.fileProgress! < 1.0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: widget.fileProgress,
                      backgroundColor: AppConstants.dividerColor,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppConstants.primaryColor),
                      minHeight: 4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Downloading... ${(widget.fileProgress! * 100).toInt()}%',
                    style: TextStyle(
                      color: AppConstants.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          if (isDownloaded && !widget.message.isOutgoing)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildActionButton(
                    icon: Icons.open_in_new,
                    label: 'Open',
                    onTap: () => _openFile(context),
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: Icons.download,
                    label: 'Save',
                    onTap: () => _saveFileToDownloads(context),
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: Icons.share,
                    label: 'Share',
                    onTap: () => _shareFile(context),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppConstants.primaryColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppConstants.primaryColor.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppConstants.primaryColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppConstants.primaryColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFile(BuildContext context) async {
    try {
      if (widget.message.filePath != null && await File(widget.message.filePath!).exists()) {
        final result = await OpenFilex.open(widget.message.filePath!);
        if (result.type != ResultType.done) throw Exception(result.message);
      } else {
        throw Exception('File not found');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open file: $e'), backgroundColor: AppConstants.errorColor),
        );
      }
    }
  }

  Future<void> _shareFile(BuildContext context) async {
    try {
      if (widget.message.filePath != null) {
        await Share.shareXFiles([XFile(widget.message.filePath!)]);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share: $e'), backgroundColor: AppConstants.errorColor),
      );
    }
  }

  Future<void> _saveFileToDownloads(BuildContext context) async {
    try {
      if (widget.message.filePath == null) return;

      final sourceFile = File(widget.message.filePath!);
      if (!await sourceFile.exists()) throw Exception('Source file not found');

      Directory? directory;
      String? newPath;
      String displayPath = 'Downloads';

      if (Platform.isAndroid) {
        try {
          directory = await getExternalStorageDirectory();
          if (directory != null) {
            final receivedDir = Directory('${directory.path}/ReceivedFiles');
            if (!await receivedDir.exists()) await receivedDir.create(recursive: true);
            newPath =
                '${receivedDir.path}/${widget.message.fileName ?? 'file_${DateTime.now().millisecondsSinceEpoch}'}';
            displayPath = 'ReceivedFiles';
          }
        } catch (e) {
          developer.log('Android external storage failed: $e', name: 'MessageBubble');
        }
        if (newPath == null) {
          directory = await getApplicationDocumentsDirectory();
          final receivedDir = Directory('${directory.path}/ReceivedFiles');
          if (!await receivedDir.exists()) await receivedDir.create(recursive: true);
          newPath =
              '${receivedDir.path}/${widget.message.fileName ?? 'file_${DateTime.now().millisecondsSinceEpoch}'}';
          displayPath = 'App Documents';
        }
      } else {
        try {
          directory = await getDownloadsDirectory();
        } catch (e) {
          directory = await getApplicationDocumentsDirectory();
        }
        directory ??= await getApplicationDocumentsDirectory();
        final fileName =
            widget.message.fileName ?? 'file_${DateTime.now().millisecondsSinceEpoch}';
        final separator = Platform.pathSeparator;
        newPath = '${directory.path}$separator$fileName';
        displayPath = directory.path.split(separator).last;
      }

      await sourceFile.copy(newPath!);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File saved to $displayPath/${widget.message.fileName}'),
            backgroundColor: AppConstants.successColor,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => _openSavedFile(newPath!),
            ),
          ),
        );
      }
    } catch (e) {
      developer.log('Save file error: $e', name: 'MessageBubble');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: AppConstants.errorColor),
        );
      }
    }
  }

  Future<void> _openSavedFile(String filePath) async {
    try {
      final result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done) throw Exception(result.message);
    } catch (e) {
      developer.log('Failed to open saved file: $e', name: 'MessageBubble');
    }
  }

  Widget _buildVoiceMessage() {
    return SizedBox(
      width: 200,
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onPlayAudio,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: widget.isPlaying
                    ? AppConstants.primaryColor.withOpacity(0.3)
                    : AppConstants.primaryColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.isPlaying ? Icons.stop : Icons.play_arrow,
                color: AppConstants.primaryColor,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 30,
                  child: Row(
                    children: List.generate(
                      20,
                      (index) => Expanded(
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: 100 + index * 20),
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          height: (index % 3 + 1) * 8.0,
                          decoration: BoxDecoration(
                            color: widget.isPlaying
                                ? AppConstants.primaryColor.withOpacity(0.7)
                                : AppConstants.primaryColor.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDuration(widget.message.duration),
                  style: TextStyle(
                    color: AppConstants.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: widget.fileProgress,
          backgroundColor: AppConstants.dividerColor,
          valueColor: const AlwaysStoppedAnimation<Color>(AppConstants.primaryColor),
          minHeight: 3,
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.message.isEdited)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              'edited',
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: AppConstants.textMuted,
              ),
            ),
          ),
        Text(
          DateFormat('HH:mm').format(widget.message.timestamp),
          style: TextStyle(
            color: AppConstants.textMuted,
            fontSize: 11,
          ),
        ),
        const SizedBox(width: 4),
        if (widget.message.isOutgoing) _buildStatusIcon(),
      ],
    );
  }

  Widget _buildStatusIcon() {
    IconData icon;
    Color color = AppConstants.textMuted;

    switch (widget.message.status) {
      case 'sending':
        icon = Icons.access_time;
        break;
      case 'sent':
        icon = Icons.check;
        break;
      case 'delivered':
        icon = Icons.done_all;
        break;
      case 'read':
        icon = Icons.done_all;
        color = AppConstants.secondaryColor;
        break;
      case 'failed':
        icon = Icons.error_outline;
        color = AppConstants.errorColor;
        break;
      default:
        icon = Icons.access_time;
    }

    return Icon(icon, size: 14, color: color);
  }

  Widget _buildErrorPlaceholder(String type) {
    return Container(
      width: 250,
      height: 250,
      decoration: BoxDecoration(
        color: AppConstants.surfaceInput,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image, size: 48, color: AppConstants.textMuted),
          const SizedBox(height: 8),
          Text('$type not available', style: TextStyle(color: AppConstants.textMuted)),
        ],
      ),
    );
  }

  IconData _getFileIcon() {
    final mimeType = widget.message.mimeType ?? '';
    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType.startsWith('video/')) return Icons.video_file;
    if (mimeType.startsWith('audio/')) return Icons.audio_file;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('word') || mimeType.contains('document')) return Icons.description;
    if (mimeType.contains('excel') || mimeType.contains('sheet')) return Icons.table_chart;
    if (mimeType.contains('powerpoint') || mimeType.contains('presentation')) return Icons.slideshow;
    if (mimeType.contains('zip') || mimeType.contains('compressed')) return Icons.folder_zip;
    return Icons.insert_drive_file;
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return 'Unknown size';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDuration(int? milliseconds) {
    if (milliseconds == null) return '0:00';
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildReplyInBubble(Message replyMessage, bool isOutgoing) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: AppConstants.secondaryColor,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            replyMessage.isOutgoing ? 'You' : 'Companion',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: AppConstants.secondaryColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _getReplyText(replyMessage),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: AppConstants.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  String _getReplyText(Message message) {
    switch (message.type) {
      case 'image':
        return '📷 Photo';
      case 'file':
        return '📎 ${message.fileName ?? "File"}';
      case 'voice':
        return '🎤 Voice message';
      default:
        return message.text;
    }
  }
}
