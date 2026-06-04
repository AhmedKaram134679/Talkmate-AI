import 'package:flutter/material.dart';

class SkeletonChatList extends StatefulWidget {
  const SkeletonChatList({super.key});

  @override
  State<SkeletonChatList> createState() => _SkeletonChatListState();
}

class _SkeletonChatListState extends State<SkeletonChatList>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 8, // Simulate enough items to fill screen
      padding: const EdgeInsets.symmetric(vertical: 8),
      physics:
          const NeverScrollableScrollPhysics(), // Disable scroll for skeleton
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Avatar Skeleton
              _buildShimmerBox(
                width: 50,
                height: 50,
                shape: BoxShape.circle,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name Skeleton
                    _buildShimmerBox(
                      width: 120,
                      height: 16,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    const SizedBox(height: 8),
                    // Message Skeleton
                    _buildShimmerBox(
                      width: double.infinity,
                      height: 12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShimmerBox({
    double? width,
    double? height,
    BoxShape shape = BoxShape.rectangle,
    BorderRadius? borderRadius,
  }) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            shape: shape,
            borderRadius: borderRadius,
            gradient: LinearGradient(
              colors: [
                Colors.grey.withValues(alpha: 0.1),
                Colors.grey.withValues(alpha: 0.3),
                Colors.grey.withValues(alpha: 0.1),
              ],
              stops: const [0.1, 0.5, 0.9],
              begin: Alignment(-1.0 + (_controller.value * 2), -0.5),
              end: Alignment(1.0 + (_controller.value * 2), 0.5),
            ),
          ),
        );
      },
    );
  }
}
