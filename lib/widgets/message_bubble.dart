import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/message.dart';
import '../utils/constants.dart';
import '../screens/image_viewer_screen.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isPlaying;
  final double? fileProgress;
  final VoidCallback? onPlayAudio;
  final VoidCallback? onLongPress;
  final VoidCallback? onSaveFile;

  const MessageBubble({
    super.key,
    required this.message,
    this.isPlaying = false,
    this.fileProgress,
    this.onPlayAudio,
    this.onLongPress,
    this.onSaveFile,
  });

  @override
  Widget build(BuildContext context) {
    final isOutgoing = message.isOutgoing;
    
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Row(
          mainAxisAlignment: isOutgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isOutgoing) const SizedBox(width: 8),
            
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                padding: _getPadding(),
                decoration: BoxDecoration(
                  color: isOutgoing
                      ? AppConstants.primaryColor
                      : Colors.grey[200],
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isOutgoing ? 16 : 4),
                    bottomRight: Radius.circular(isOutgoing ? 4 : 16),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Message content based on type
                    _buildMessageContent(context),
                    
                    // File progress indicator
                    if (fileProgress != null && fileProgress! < 1.0)
                      _buildProgressIndicator(),
                    
                    const SizedBox(height: 4),
                    
                    // Timestamp and status
                    _buildFooter(),
                  ],
                ),
              ),
            ),
            
            if (isOutgoing) const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  EdgeInsets _getPadding() {
    switch (message.type) {
      case 'image':
        return const EdgeInsets.all(4);
      case 'voice':
        return const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
      default:
        return const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
    }
  }

  Widget _buildMessageContent(BuildContext context) {
    if (message.isDeleted) {
      return Text(
        'This message was deleted',
        style: TextStyle(
          fontStyle: FontStyle.italic,
          color: message.isOutgoing ? Colors.white70 : Colors.grey[600],
        ),
      );
    }

    switch (message.type) {
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
      message.text,
      style: const TextStyle(
        color: Colors.black,
        fontSize: 16,
      ),
    );
  }

  Widget _buildImageMessage(BuildContext context) {
    if (message.filePath != null && File(message.filePath!).existsSync()) {
      return GestureDetector(
        onTap: () => _openImageViewer(context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Image.file(
                File(message.filePath!),
                width: 250,
                height: 250,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildErrorPlaceholder('Image');
                },
              ),
              // Progress overlay
              if (fileProgress != null && fileProgress! < 1.0)
                Positioned.fill(
                  child: Container(
                    color: Colors.black54,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            value: fileProgress,
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${(fileProgress! * 100).toInt()}%',
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
              // Tap to view indicator
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
    
    // If file path is not available, show placeholder with progress
    return Container(
      width: 250,
      height: 250,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(12),
      ),
      child: fileProgress != null && fileProgress! < 1.0
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.image, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                SizedBox(
                  width: 100,
                  child: LinearProgressIndicator(
                    value: fileProgress,
                    backgroundColor: Colors.grey[400],
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(fileProgress! * 100).toInt()}%',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            )
          : const Icon(Icons.image, size: 64, color: Colors.grey),
    );
  }

  void _openImageViewer(BuildContext context) {
    if (message.filePath == null) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImageViewerScreen(
          imagePath: message.filePath!,
          caption: message.text.isNotEmpty ? message.text : null,
        ),
      ),
    );
  }

  Widget _buildFileMessage(BuildContext context) {
    final bool isDownloaded = message.filePath != null && 
                              File(message.filePath!).existsSync();
    
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: message.isOutgoing
                      ? Colors.white.withOpacity(0.2)
                      : AppConstants.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getFileIcon(),
                  color: message.isOutgoing
                      ? Colors.white
                      : AppConstants.primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.fileName ?? 'File',
                      style: TextStyle(
                        color: message.isOutgoing ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatFileSize(message.fileSize),
                      style: TextStyle(
                        color: message.isOutgoing
                            ? Colors.white70
                            : Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          // Progress bar for file transfer
          if (fileProgress != null && fileProgress! < 1.0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: fileProgress,
                    backgroundColor: message.isOutgoing
                        ? Colors.white.withOpacity(0.3)
                        : Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(
                      message.isOutgoing ? Colors.white : AppConstants.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Downloading... ${(fileProgress! * 100).toInt()}%',
                    style: TextStyle(
                      color: message.isOutgoing
                          ? Colors.white70
                          : Colors.grey[600],
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          
          // Action buttons
          if (isDownloaded && !message.isOutgoing)
            Padding(
              padding: const EdgeInsets.only(top: 8),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppConstants.primaryColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: AppConstants.primaryColor,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppConstants.primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFile(BuildContext context) async {
    try {
      if (message.filePath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Opening ${message.fileName}...'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open file: $e'),
          backgroundColor: AppConstants.errorColor,
        ),
      );
    }
  }

  Future<void> _shareFile(BuildContext context) async {
    try {
      if (message.filePath != null) {
        await Share.shareXFiles([XFile(message.filePath!)]);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to share: $e'),
          backgroundColor: AppConstants.errorColor,
        ),
      );
    }
  }

  Future<void> _saveFileToDownloads(BuildContext context) async {
    try {
      if (message.filePath == null) return;
      
      final directory = await getDownloadsDirectory();
      if (directory == null) {
        throw Exception('Could not access downloads directory');
      }

      final fileName = message.fileName ?? 'file_${DateTime.now().millisecondsSinceEpoch}';
      final newPath = '${directory.path}/$fileName';
      final sourceFile = File(message.filePath!);
      await sourceFile.copy(newPath);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File saved to Downloads/$fileName'),
            backgroundColor: AppConstants.successColor,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: AppConstants.errorColor,
          ),
        );
      }
    }
  }

  Widget _buildVoiceMessage() {
    return SizedBox(
      width: 200,
      child: Row(
        children: [
          GestureDetector(
            onTap: onPlayAudio,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: message.isOutgoing
                    ? Colors.white.withOpacity(0.2)
                    : AppConstants.primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPlaying ? Icons.stop : Icons.play_arrow,
                color: message.isOutgoing
                    ? Colors.white
                    : AppConstants.primaryColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
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
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          height: (index % 3 + 1) * 8.0,
                          decoration: BoxDecoration(
                            color: message.isOutgoing
                                ? Colors.white.withOpacity(0.6)
                                : AppConstants.primaryColor.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDuration(message.duration),
                  style: TextStyle(
                    color: message.isOutgoing
                        ? Colors.white70
                        : Colors.grey[600],
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
      child: LinearProgressIndicator(
        value: fileProgress,
        backgroundColor: message.isOutgoing
            ? Colors.white.withOpacity(0.3)
            : Colors.grey[300],
        valueColor: AlwaysStoppedAnimation<Color>(
          message.isOutgoing ? Colors.white : AppConstants.primaryColor,
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          DateFormat('HH:mm').format(message.timestamp),
          style: TextStyle(
            color: message.isOutgoing
                ? Colors.white70
                : Colors.grey[500],
            fontSize: 11,
          ),
        ),
        const SizedBox(width: 4),
        if (message.isOutgoing) _buildStatusIcon(),
      ],
    );
  }

  Widget _buildStatusIcon() {
    IconData icon;
    Color color = Colors.white70;

    switch (message.status) {
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
        color = Colors.blue[300]!;
        break;
      case 'failed':
        icon = Icons.error_outline;
        color = Colors.red[300]!;
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
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.broken_image, size: 48, color: Colors.grey),
          const SizedBox(height: 8),
          Text(
            '$type not available',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon() {
    final mimeType = message.mimeType ?? '';
    
    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType.startsWith('video/')) return Icons.video_file;
    if (mimeType.startsWith('audio/')) return Icons.audio_file;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('word') || mimeType.contains('document')) {
      return Icons.description;
    }
    if (mimeType.contains('excel') || mimeType.contains('sheet')) {
      return Icons.table_chart;
    }
    if (mimeType.contains('powerpoint') || mimeType.contains('presentation')) {
      return Icons.slideshow;
    }
    if (mimeType.contains('zip') || mimeType.contains('compressed')) {
      return Icons.folder_zip;
    }
    
    return Icons.insert_drive_file;
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return 'Unknown size';
    
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDuration(int? milliseconds) {
    if (milliseconds == null) return '0:00';
    
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
