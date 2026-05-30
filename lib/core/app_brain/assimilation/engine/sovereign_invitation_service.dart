import 'package:get/get.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/engine/sovereign_communication_engine.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/models/comm_invitation_model.dart';
import 'package:talkmate_ai/widgets/communication/sovereign_invitation_dialog.dart';

/// Sovereign Invitation Service (Stage C7).
/// Manages the flow of incoming and outgoing communication invitations.
/// ACTS as a Governance Gatekeeper for new session requests.
class SovereignInvitationService extends GetxService {
  static SovereignInvitationService get instance =>
      Get.find<SovereignInvitationService>();

  final _commEngine = SovereignCommunicationEngine.instance;

  // In a real implementation, this would listen to a backend stream (Supabase/Firebase)
  // For C7, we simulate the flow locally to establish the governance pattern.

  /// Simulate receiving an invitation from the network.
  /// This is the entry point for all incoming requests.
  void handleIncomingInvitation(CommInvitation invitation) {
    // 1. Governance Check: Is the engine busy?
    if (_commEngine.isBusy) {
      // 1.1 Silent Auto-Decline (or Show Non-Intrusive Toast)
      // For now, we allow showing the dialog but passing the 'busy' state to it for user awareness.
      // Ideally, we might reject immediately if "Do Not Disturb" is active.
      _presentInvitationDialog(invitation);
    } else {
      // 2. Resource Free: Present Invitation
      _presentInvitationDialog(invitation);
    }
  }

  void _presentInvitationDialog(CommInvitation invitation) {
    // Check if a dialog is already open? In complex apps yes.
    // For now, simple dialog.

    SovereignInvitationDialog.show(
      invitation: invitation,
      onAccept: () => _acceptInvitation(invitation),
      onDecline: () => _declineInvitation(invitation),
    );
  }

  Future<void> _acceptInvitation(CommInvitation invitation) async {
    // 1. If busy, we must end current session first (Governance Rule).
    if (_commEngine.isBusy) {
      await _commEngine
          .endSession(_commEngine.activeSessionId); // Or force clean
      // Wait for cleanup...
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // 2. Start the new session based on type
    if (invitation.type == InvitationType.individualCall) {
      Get.snackbar('اتصال', 'جار بدء الاتصال مع ${invitation.senderName}...',
          snackPosition: SnackPosition.TOP,
          duration: const Duration(seconds: 2),
          animationDuration: const Duration(milliseconds: 500));
      // In real implementation:
      // Get.to(() => CallScreen(...), transition: Transition.fadeIn);
    } else if (invitation.type == InvitationType.roomJoin) {
      // Route to Room
      Get.snackbar('غرفة', 'جار الانضمام لغرفة ${invitation.senderName}...',
          snackPosition: SnackPosition.TOP);
    }
  }

  void _declineInvitation(CommInvitation invitation) {
    // Send rejection to backend
    Get.snackbar('تم الرفض', 'تم رفض الدعوة بنجاح.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2));
  }

  /// Send an invitation to another user.
  Future<void> sendInvitation({
    required String targetUserId,
    required InvitationType type,
    bool isVideo = false,
  }) async {
    // Create invitation object and push to backend
    // final invite = CommInvitation(...);
    // repo.send(invite);
    Get.snackbar('تم الإرسال', 'تم إرسال الدعوة إلى المستخدم.',
        snackPosition: SnackPosition.BOTTOM);
  }
}
