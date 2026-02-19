import 'package:flutter/material.dart';
import '../models/connection_state.dart';
import '../utils/constants.dart';
import '../main.dart' show themeSettings;

class ConnectionStatusWidget extends StatelessWidget {
  final ConnectionStateModel state;

  const ConnectionStatusWidget({
    super.key,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: _getStatusColor(),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          _getStatusText(),
          style: TextStyle(
            fontSize: 12,
            color: _getStatusColor(),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Color _getStatusColor() {
    switch (state.status) {
      case AppConstants.statusOnline:
        return AppConstants.onlineColor;
      case AppConstants.statusOffline:
        return AppConstants.offlineColor;
      case AppConstants.statusConnecting:
        return AppConstants.connectingColor;
      case AppConstants.statusError:
        return AppConstants.errorColor;
      default:
        return AppConstants.offlineColor;
    }
  }

  String _getStatusText() {
    switch (state.status) {
      case AppConstants.statusOnline:
        return 'online';
      case AppConstants.statusOffline:
        return 'offline';
      case AppConstants.statusConnecting:
        return 'connecting...';
      case AppConstants.statusError:
        return 'error';
      default:
        return 'offline';
    }
  }
}

class ConnectionStatusBadge extends StatelessWidget {
  final String status;
  final bool showLabel;

  const ConnectionStatusBadge({
    super.key,
    required this.status,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getBackgroundColor(),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _getStatusColor(),
              shape: BoxShape.circle,
            ),
          ),
          if (showLabel) ...[
            const SizedBox(width: 6),
            Text(
              _getStatusText(),
              style: TextStyle(
                fontSize: 11,
                color: _getStatusColor(),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getStatusColor() {
    switch (status) {
      case AppConstants.statusOnline:
        return AppConstants.onlineColor;
      case AppConstants.statusOffline:
        return AppConstants.offlineColor;
      case AppConstants.statusConnecting:
        return AppConstants.connectingColor;
      case AppConstants.statusError:
        return AppConstants.errorColor;
      default:
        return AppConstants.offlineColor;
    }
  }

  Color _getBackgroundColor() {
    switch (status) {
      case AppConstants.statusOnline:
        return AppConstants.onlineColor.withOpacity(0.1);
      case AppConstants.statusOffline:
        return AppConstants.offlineColor.withOpacity(0.1);
      case AppConstants.statusConnecting:
        return AppConstants.connectingColor.withOpacity(0.1);
      case AppConstants.statusError:
        return AppConstants.errorColor.withOpacity(0.1);
      default:
        return AppConstants.offlineColor.withOpacity(0.1);
    }
  }

  String _getStatusText() {
    switch (status) {
      case AppConstants.statusOnline:
        return 'Online';
      case AppConstants.statusOffline:
        return 'Offline';
      case AppConstants.statusConnecting:
        return 'Connecting';
      case AppConstants.statusError:
        return 'Error';
      default:
        return 'Offline';
    }
  }
}

class ReconnectingIndicator extends StatelessWidget {
  final bool isReconnecting;

  const ReconnectingIndicator({
    super.key,
    required this.isReconnecting,
  });

  @override
  Widget build(BuildContext context) {
    if (!isReconnecting) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppConstants.warningColor.withOpacity(0.1),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppConstants.warningColor),
            ),
          ),
          SizedBox(width: 8),
          Text(
            'Reconnecting...',
            style: TextStyle(
              color: AppConstants.warningColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
