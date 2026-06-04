import 'package:flutter/material.dart';

enum NetworkQuality { good, fair, poor, unknown }

class NetworkQualityBadge extends StatelessWidget {
  final String statusText; // 'Good', 'Fair', 'Poor' from controller
  final bool showLabel;

  const NetworkQualityBadge({
    super.key,
    required this.statusText,
    this.showLabel = true,
  });

  NetworkQuality get _quality {
    switch (statusText.toLowerCase()) {
      case 'good':
        return NetworkQuality.good;
      case 'fair':
        return NetworkQuality.fair;
      case 'poor':
        return NetworkQuality.poor;
      default:
        return NetworkQuality.unknown;
    }
  }

  Color get _color {
    switch (_quality) {
      case NetworkQuality.good:
        return Colors.greenAccent;
      case NetworkQuality.fair:
        return Colors.orangeAccent;
      case NetworkQuality.poor:
        return Colors.redAccent;
      case NetworkQuality.unknown:
        return Colors.grey;
    }
  }

  String _getFriendlyMessage(BuildContext context) {
    switch (_quality) {
      case NetworkQuality.good:
        return 'اتصال ممتاز';
      case NetworkQuality.fair:
        return 'الاتصال متوسط';
      case NetworkQuality.poor:
        return 'الاتصال ضعيف، نحاول تحسين الجودة...';
      case NetworkQuality.unknown:
        return 'جاري التحقق من الشبكة...';
    }
  }

  IconData get _icon {
    switch (_quality) {
      case NetworkQuality.good:
        return Icons.signal_cellular_alt_rounded;
      case NetworkQuality.fair:
        return Icons.signal_cellular_alt_2_bar_rounded;
      case NetworkQuality.poor:
        return Icons.signal_cellular_connected_no_internet_0_bar_rounded;
      case NetworkQuality.unknown:
        return Icons.signal_cellular_null_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _getFriendlyMessage(context),
      triggerMode: TooltipTriggerMode.tap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _color.withValues(alpha: 0.6),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _color.withValues(alpha: 0.2),
              blurRadius: 8,
              spreadRadius: 1,
            )
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Icon(
                _icon,
                key: ValueKey(_quality),
                size: 16,
                color: _color,
              ),
            ),
            if (showLabel) ...[
              const SizedBox(width: 6),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: TextStyle(
                  color: _color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo', // Assuming app uses Cairo or similar
                ),
                child: Text(
                    statusText), // keeping technical for debug, or map to simple text
              ),
            ],
          ],
        ),
      ),
    );
  }
}
