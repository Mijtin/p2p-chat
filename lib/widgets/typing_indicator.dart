import 'package:flutter/material.dart';
import '../utils/constants.dart';

class TypingIndicatorWidget extends StatelessWidget {
  final bool isOutgoing;
  
  const TypingIndicatorWidget({
    super.key,
    this.isOutgoing = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
        left: isOutgoing ? 0 : 16,
        right: isOutgoing ? 16 : 0,
        bottom: 8,
      ),
      child: Row(
        mainAxisAlignment: isOutgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isOutgoing) ...[
            _buildIndicator(),
            const SizedBox(width: 8),
            Text(
              'typing...',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
          ] else ...[
            Text(
              'typing...',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 8),
            _buildIndicator(isOutgoing: true),
          ],
        ],
      ),
    );
  }

  Widget _buildIndicator({bool isOutgoing = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isOutgoing ? AppConstants.primaryColor.withOpacity(0.2) : Colors.grey[200],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDot(0, isOutgoing),
          const SizedBox(width: 4),
          _buildDot(1, isOutgoing),
          const SizedBox(width: 4),
          _buildDot(2, isOutgoing),
        ],
      ),
    );
  }

  Widget _buildDot(int index, bool isOutgoing) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: isOutgoing 
            ? AppConstants.primaryColor.withOpacity(0.4 + (index * 0.2))
            : AppConstants.primaryColor.withOpacity(0.4 + (index * 0.2)),
        shape: BoxShape.circle,
      ),
    );
  }
}

class TypingIndicatorAnimated extends StatefulWidget {
  final bool isOutgoing;
  
  const TypingIndicatorAnimated({
    super.key,
    this.isOutgoing = false,
  });

  @override
  State<TypingIndicatorAnimated> createState() => _TypingIndicatorAnimatedState();
}

class _TypingIndicatorAnimatedState extends State<TypingIndicatorAnimated>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _animations = List.generate(3, (index) {
      return Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(
            index * 0.2,
            index * 0.2 + 0.6,
            curve: Curves.easeInOut,
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
        left: widget.isOutgoing ? 0 : 16,
        right: widget.isOutgoing ? 16 : 0,
        bottom: 8,
      ),
      child: Row(
        mainAxisAlignment: widget.isOutgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!widget.isOutgoing) ...[
            _buildIndicator(),
            const SizedBox(width: 8),
            const Text(
              'typing...',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
          ] else ...[
            const Text(
              'typing...',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 8),
            _buildIndicator(),
          ],
        ],
      ),
    );
  }

  Widget _buildIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: widget.isOutgoing 
            ? AppConstants.primaryColor.withOpacity(0.2) 
            : Colors.grey[200],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (index) {
          return AnimatedBuilder(
            animation: _animations[index],
            builder: (context, child) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 6,
                height: 6 + (_animations[index].value * 4),
                decoration: BoxDecoration(
                  color: AppConstants.primaryColor.withOpacity(
                    0.4 + (_animations[index].value * 0.6),
                  ),
                  shape: BoxShape.circle,
                ),
              );
            },
          );
        }),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
