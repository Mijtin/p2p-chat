import 'package:flutter/material.dart';
import '../models/chat.dart';
import '../utils/constants.dart';
import '../main.dart' show themeSettings;

class ChatListTile extends StatelessWidget {
  final Chat chat;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final String lastConnectedText;

  const ChatListTile({
    super.key,
    required this.chat,
    required this.onTap,
    required this.onLongPress,
    required this.lastConnectedText,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = themeSettings.isLightTheme;
    
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isLight ? AppConstants.surfaceCardLight : AppConstants.surfaceCard,
          borderRadius: BorderRadius.circular(AppConstants.borderRadius),
          border: Border.all(color: isLight ? AppConstants.dividerColorLight : AppConstants.dividerColor),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppConstants.primaryColor.withOpacity(0.2),
                    AppConstants.secondaryColor.withOpacity(0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Icon(
                  Icons.device_hub,
                  color: AppConstants.primaryColor,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat.displayName,
                    style: TextStyle(
                      color: isLight ? AppConstants.textPrimaryLight : AppConstants.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 14,
                        color: isLight ? AppConstants.textMutedLight : AppConstants.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        lastConnectedText,
                        style: TextStyle(
                          color: isLight ? AppConstants.textMutedLight : AppConstants.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      if (chat.unreadCount > 0) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppConstants.primaryColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${chat.unreadCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Chevron
            Icon(
              Icons.chevron_right,
              color: isLight ? AppConstants.textMutedLight : AppConstants.textMuted,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
