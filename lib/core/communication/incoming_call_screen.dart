import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/engine/sovereign_communication_engine.dart';
import 'package:talkmate_ai/core/communication/communication_controller.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:talkmate_ai/services/call/call_manager.dart';

class IncomingCallScreen extends GetView<CommunicationController> {
  const IncomingCallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 2),
            // Caller Info
            Obx(() {
              // We don't have the caller object easily, but we have name in controller
              // For avatar, we might need to fetch or use a placeholder
              return Column(
                children: [
                  const CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.grey,
                    child: Icon(Icons.person, size: 60, color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    controller.sessionName.value,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    controller.statusRx.value ==
                            CommSessionStatus.ringingIncoming
                        ? l10n.incomingCall
                        : controller.statusRx.value == CommSessionStatus.dialing
                            ? l10n.callStatusDialing
                            : l10n.callStatusRinging,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              );
            }),
            const Spacer(flex: 3),
            // Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Decline / Cancel
                  _buildActionButton(
                    context,
                    color: Colors.red,
                    icon: Icons.call_end,
                    label: controller.statusRx.value ==
                            CommSessionStatus.ringingIncoming
                        ? l10n.decline
                        : l10n.cancel,
                    onTap: () => controller.declineCall(),
                  ),
                  // Accept (Only for Incoming)
                  if (controller.statusRx.value ==
                      CommSessionStatus.ringingIncoming)
                    _buildActionButton(
                      context,
                      color: Colors.green,
                      icon: Icons.call,
                      label: l10n.answer,
                      onTap: () {
                        CallManager.instance.acceptCall();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context,
      {required Color color,
      required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  spreadRadius: 2,
                )
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
