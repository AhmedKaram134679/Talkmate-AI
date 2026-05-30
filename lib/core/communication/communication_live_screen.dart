import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:get/get.dart';
import 'package:talkmate_ai/config/theme_config.dart';
import 'package:talkmate_ai/controllers/language_controller.dart';
import 'package:talkmate_ai/controllers/rooms_controller.dart';
import 'package:talkmate_ai/controllers/theme_controller.dart';
import 'package:talkmate_ai/core/app_brain/assimilation/engine/sovereign_communication_engine.dart';
import 'package:talkmate_ai/core/communication/communication_controller.dart';
import 'package:talkmate_ai/core/communication/communication_session.dart';
import 'package:talkmate_ai/core/feedback/beta_conclusion_sheet.dart';
import 'package:talkmate_ai/core/governance/beta_feature_flags_service.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';

class CommunicationLiveScreen extends GetView<CommunicationController> {
  final String sessionId;
  final CommunicationSessionType type;

  const CommunicationLiveScreen({
    super.key,
    required this.sessionId,
    this.type = CommunicationSessionType.room,
  });

  @override
  Widget build(BuildContext context) {
    // [SOVEREIGN_UI]: Force dark theme for the communication screen to ensure high contrast and premium feel.
    final baseTheme = ThemeConfig.darkTheme;
    return Theme(
      data: baseTheme.copyWith(
        scaffoldBackgroundColor: Colors.black,
      ),
      child: Builder(builder: (context) {
        final theme = Theme.of(context);

        return Obx(
          () => PopScope(
            canPop: controller.isEnding.value,
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) {
                // 1. Capture Context before state is cleared
                final sessionCtx = {
                  'sessionId': controller.sessionId.value,
                  'type': type.toString(),
                  'timestamp': DateTime.now().toIso8601String(),
                };

                // 2. Trigger Background Cleanup
                unawaited(controller.leaveSession(reason: 'manual'));

                // 3. Show Feedback Sheet (Delayed to allow navigation to finish)
                if (BetaFeatureFlagsService
                    .instance.enableFeedbackSheet.value) {
                  Future.delayed(const Duration(milliseconds: 300), () {
                    if (Get.context != null) {
                      BetaConclusionSheet.show(Get.context!,
                          sessionContext: sessionCtx);
                    }
                  });
                }
                return;
              }

              // Initiate unified exit sequence (Stage R21.2)
              await controller.exitGracefully();
            },
            child: Scaffold(
              backgroundColor: theme.scaffoldBackgroundColor,
              appBar: _buildAppBar(context, theme),
              body: Stack(
                children: [
                  // [DEBUG]: Forensic visibility check
                  Obx(() {
                    if (!controller.showDebugOverlay.value) {
                      return const SizedBox();
                    }
                    return Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: Colors.red,
                        padding: const EdgeInsets.all(4),
                        child: Text(
                          'Ending: ${controller.isEnding.value} | Status: ${controller.statusRx.value} | Parts: ${controller.participants.length}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }),

                  // Main Content Layer (Fades out on end)
                  Obx(() => AnimatedOpacity(
                        opacity: controller.isEnding.value ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOut,
                        child: Column(
                          children: [
                            // Connection Status
                            Obx(() {
                              final status = controller.statusRx.value;
                              final engine =
                                  SovereignCommunicationEngine.instance;
                              final isFallback =
                                  engine.isFallbackToAudioRx.value;

                              if (status == CommSessionStatus.reconnecting) {
                                return Container(
                                  width: double.infinity,
                                  color: Colors.orange.withValues(alpha: 0.9),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                        Color>(Colors.white))),
                                        const SizedBox(width: 8),
                                        Text(
                                          'جاري إعادة الاتصال...',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }

                              if (isFallback) {
                                return Container(
                                  width: double.infinity,
                                  color: Colors.blueGrey.withValues(alpha: 0.9),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Center(
                                    child: Text(
                                      'تم التحويل لمكالمة صوتية بسبب الشبكة',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(color: Colors.white),
                                    ),
                                  ),
                                );
                              }

                              if (status == CommSessionStatus.connecting) {
                                return const LinearProgressIndicator();
                              }
                              return const SizedBox.shrink();
                            }),

                            _buildMicLevelHeader(theme),

                            // Dynamic Session Content
                            Expanded(
                              child: Obx(() {
                                final status = controller.statusRx.value;
                                if (controller.participants.isEmpty &&
                                    (status == CommSessionStatus.activeAudio ||
                                        status ==
                                            CommSessionStatus.activeVideo)) {
                                  final l10n = AppLocalizations.of(context);
                                  final emptyText =
                                      type == CommunicationSessionType.call
                                          ? (l10n.reconnectingQuietly)
                                          : (Get.locale?.languageCode == 'ar'
                                              ? 'الغرفة فارغة...'
                                              : 'Room is empty...');
                                  return Center(child: Text(emptyText));
                                }

                                // Binary Layout Selection: Call vs Room
                                if (type == CommunicationSessionType.call) {
                                  return _buildCallLayout(context);
                                }

                                // Otherwise, it's a Room (Grid Layout)
                                return _buildRoomGrid(context);
                              }),
                            ),
                          ],
                        ),
                      )),

                  // [ARCHITECTURAL]: Controls Bar is Decoupled from Content Fade-out
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildControlsBar(context),
                  ),

                  // [Debug] Sovereign Log Overlay
                  Positioned(
                    top: 50,
                    left: 10,
                    right: 10,
                    height: 150,
                    child: IgnorePointer(
                      child: Obx(() {
                        if (controller.debugLogs.isEmpty ||
                            !controller.showDebugOverlay.value) {
                          return const SizedBox();
                        }
                        return Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListView.builder(
                            itemCount: controller.debugLogs.length,
                            itemBuilder: (c, i) => Text(
                              controller.debugLogs[i],
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  height: 1.2),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),

                  // [UX_SAFEGUARD]: Headphone Hint for Windows
                  _buildHeadphoneHint(theme),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    final matL10n = MaterialLocalizations.of(context);

    return AppBar(
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => controller.exitGracefully(),
        tooltip: matL10n.backButtonTooltip,
      ),
      title: Column(
        children: [
          Obx(() => Text(
              controller.sessionName.value.isEmpty
                  ? (type == CommunicationSessionType.call
                      ? (Get.locale?.languageCode == 'ar' ? 'مكالمة' : 'Call')
                      : (Get.locale?.languageCode == 'ar' ? 'غرفة' : 'Room'))
                  : controller.sessionName.value,
              style: theme.textTheme.titleMedium)),
          if (type == CommunicationSessionType.room)
            Obx(() => Text(
                  '${controller.participants.length} ${Get.locale?.languageCode == 'ar' ? 'متواجدون' : 'Participants'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    fontWeight: FontWeight.bold,
                  ),
                )),
        ],
      ),
      actions: [
        // Language Toggle
        IconButton(
          icon: const Icon(Icons.language),
          onPressed: () => Get.find<LanguageController>().toggleLanguage(),
          tooltip: l10n.tooltipChangeLanguage,
        ),
        // Theme Toggle
        IconButton(
          icon: Icon(Get.isDarkMode ? Icons.light_mode : Icons.dark_mode),
          onPressed: () => Get.find<ThemeController>().toggleTheme(),
          tooltip: l10n.tooltipChangeTheme,
        ),
        // Debug Toggle
        IconButton(
          icon: Obx(() => Icon(
                Icons.bug_report,
                color: controller.showDebugOverlay.value
                    ? Colors.redAccent
                    : theme.colorScheme.onSurface,
              )),
          onPressed: () => controller.showDebugOverlay.toggle(),
          tooltip: 'Debug Logs',
        ),
      ],
    );
  }

  Widget _buildMicLevelHeader(ThemeData theme) {
    return Obx(() {
      final status = controller.statusRx.value;

      final bool isConnecting = status == CommSessionStatus.connecting ||
          status == CommSessionStatus.ringingIncoming ||
          status == CommSessionStatus.ringingOutgoing ||
          status == CommSessionStatus.dialing ||
          status == CommSessionStatus.reconnecting;

      final bool isActive = status == CommSessionStatus.activeAudio ||
          status == CommSessionStatus.activeVideo;

      final isVisible = isConnecting || (isActive && !controller.isMuted.value);

      return AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: isVisible ? 1.0 : 0.0,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              _buildNetworkIndicator(theme),
              if (isConnecting || !controller.isMuted.value) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: 100,
                  child: LinearProgressIndicator(
                    value: controller.micLevel.value,
                    borderRadius: BorderRadius.circular(4),
                    minHeight: 3,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    });
  }

  Widget _buildCallLayout(BuildContext context) {
    // 1-to-1 Call Layout (Messenger Style)
    final remoteParticipants = controller.participants
        .where((p) => p.id != controller.currentUserId)
        .toList();
    final remoteParticipant =
        remoteParticipants.isNotEmpty ? remoteParticipants.first : null;

    final langController = Get.find<LanguageController>();
    final bool isRTL = langController.isArabic;

    return Obx(() {
      final bool localCameraOn = controller.isCameraOn.value;
      final bool remoteCameraOn = remoteParticipant?.isVideoOn.value ?? false;

      return Stack(
        children: [
          // Background Layer: Remote Participant or Placeholder
          Positioned.fill(
            child: remoteParticipant != null && remoteCameraOn
                ? _ParticipantTile(
                    participant: remoteParticipant,
                    isFull: true,
                  )
                : _buildPlaceholderRemote(context),
          ),

          // Layer: Local Video (PiP if remote is on, Center if remote is off)
          if (localCameraOn)
            AnimatedAlign(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
              alignment: remoteCameraOn
                  ? (isRTL ? Alignment.bottomLeft : Alignment.bottomRight)
                  : Alignment.center,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom:
                      remoteCameraOn ? 120 : 0, // Space for controls when PiP
                  right: remoteCameraOn ? (isRTL ? 0 : 16) : 0,
                  left: remoteCameraOn ? (isRTL ? 16 : 0) : 0,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                  width: remoteCameraOn ? 120 : context.width * 0.8,
                  height: remoteCameraOn ? 180 : context.height * 0.6,
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(remoteCameraOn ? 16 : 24),
                    border: Border.all(color: Colors.white24, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      )
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(remoteCameraOn ? 16 : 24),
                    child: _LocalPreview(),
                  ),
                ),
              ),
            ),

          // Gesture layer to show controls
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: controller.startControlsTimer,
              child: const SizedBox(),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildPlaceholderRemote(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Container(
      color: theme.scaffoldBackgroundColor,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 60,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Obx(() => Text(
                    controller.sessionName.value.isNotEmpty
                        ? controller.sessionName.value[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  )),
            ),
            const SizedBox(height: 24),
            Obx(() => Text(
                  controller.sessionName.value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                )),
            const SizedBox(height: 8),
            Text(
              l10n.callStatusConnecting,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomGrid(BuildContext context) {
    // Dynamic Grid (Discord Style)
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: controller.participants.length,
      itemBuilder: (context, index) =>
          _ParticipantTile(participant: controller.participants[index]),
    );
  }

  Widget _buildControlsBar(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      // [ARCHITECTURAL_DECOUPLE]: Controls bar is now collapsible using AnimatedPositioned in the parent or AnimatedOpacity here
      final bool isVisible = controller.showControls.value;

      return AnimatedSlide(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        offset: isVisible ? Offset.zero : const Offset(0, 1),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: isVisible ? 1.0 : 0.0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1D21),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.05),
                  width: 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 30,
                  offset: const Offset(0, -10),
                )
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ControlCircle(
                  icon: Icons.settings_outlined,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  iconColor: Colors.white,
                  onTap: () {
                    controller.startControlsTimer();
                    _showSettings(theme);
                  },
                ),
                // Speaker Toggle
                Obx(() => _ControlCircle(
                      icon: controller.isSpeakerOn.value
                          ? Icons.volume_up
                          : Icons
                              .volume_down, // Earpiece icon could be volume_down or something else
                      backgroundColor: controller.isSpeakerOn.value
                          ? Colors.blueAccent
                          : Colors.white.withValues(alpha: 0.1),
                      iconColor: Colors.white,
                      onTap: controller.toggleSpeaker,
                    )),
                Obx(() => _ControlCircle(
                      icon:
                          controller.isMuted.value ? Icons.mic_off : Icons.mic,
                      backgroundColor: controller.isMuted.value
                          ? Colors.redAccent
                          : Colors.white.withValues(alpha: 0.1),
                      iconColor: Colors.white,
                      onTap: controller.toggleMute,
                    )),
                Obx(() => _ControlCircle(
                      icon: controller.isCameraOn.value
                          ? Icons.videocam
                          : Icons.videocam_off,
                      backgroundColor: controller.isCameraOn.value
                          ? Colors.green
                          : Colors.white.withValues(alpha: 0.1),
                      iconColor: Colors.white,
                      onTap: controller.toggleCamera,
                    )),
                _ControlCircle(
                  icon: Icons.call_end,
                  backgroundColor: Colors.red[700]!,
                  iconColor: Colors.white,
                  onTap: () async {
                    await controller.exitGracefully();
                  },
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  void _showSettings(ThemeData theme) {
    final roomsCtrl = Get.find<RoomsController>();
    final room = roomsCtrl.rooms.firstWhereOrNull((r) => r.id == sessionId);
    final bool isCreator = room != null && roomsCtrl.isCreator(room.createdBy);

    final nameController = TextEditingController(text: room?.name ?? '');

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              spreadRadius: 5,
            )
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      type == CommunicationSessionType.call
                          ? 'إعدادات المكالمة'
                          : 'إعدادات الغرفة',
                      style: theme.textTheme.titleLarge),
                  IconButton(
                    onPressed: () => Get.back(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // --- Personal Settings (For Everyone) ---
              Text('إعدادات الصوت الشخصية',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: theme.primaryColor)),
              const SizedBox(height: 16),

              // Microphone Input Volume
              _buildVolumeSlider(
                label: 'حساسية الميكروفون',
                icon: Icons.mic,
                value: controller.inputVolume,
                onChanged: (v) => controller.updateInputVolume(v),
              ),

              const SizedBox(height: 12),

              // Speaker Output Volume
              _buildVolumeSlider(
                label: 'مستوى صوت السماعات',
                icon: Icons.volume_up,
                value: controller.outputVolume,
                onChanged: (v) => controller.updateOutputVolume(v),
              ),

              const Divider(height: 40),

              // --- Administrative Settings (For Creator) ---
              if (isCreator) ...[
                Text(
                    type == CommunicationSessionType.call
                        ? 'إدارة المكالمة'
                        : 'إدارة الغرفة (منشئ)',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: theme.primaryColor)),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: type == CommunicationSessionType.call
                        ? 'اسم الجلسة'
                        : 'اسم الغرفة الجديد',
                    prefixIcon: const Icon(Icons.edit),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          if (nameController.text.isNotEmpty) {
                            await roomsCtrl.updateRoom(
                                room.id, nameController.text);
                            Get.back();
                            Get.snackbar(
                                'تم التحديث',
                                type == CommunicationSessionType.call
                                    ? 'تم تغيير الاسم بنجاح'
                                    : 'تم تغيير اسم الغرفة بنجاح');
                          }
                        },
                        icon: const Icon(Icons.check),
                        label: const Text('حفظ التعديلات'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: theme.primaryColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final confirmed = await Get.dialog<bool>(
                        AlertDialog(
                          title: Text(type == CommunicationSessionType.call
                              ? 'إنهاء المكالمة'
                              : 'حذف الغرفة'),
                          content: Text(type == CommunicationSessionType.call
                              ? 'هل أنت متأكد من رغبتك في إنهاء هذه المكالمة؟'
                              : 'هل أنت متأكد من رغبتك في حذف هذه الغرفة نهائياً؟'),
                          actions: [
                            TextButton(
                                onPressed: () => Get.back(result: false),
                                child: const Text('إلغاء')),
                            TextButton(
                                onPressed: () => Get.back(result: true),
                                child: const Text('حذف',
                                    style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      );

                      if (confirmed == true) {
                        await roomsCtrl.deleteRoom(room.id);
                        Get.back(); // close sheet
                        Get.back(); // leave screen
                      }
                    },
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    label: const Text('حذف الغرفة نهائياً',
                        style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ] else
                const Center(
                  child: Text(
                    'إعدادات الإدارة متاحة للمنشئ فقط.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  Widget _buildNetworkIndicator(ThemeData theme) {
    return Obx(() {
      final quality = controller.currentNetworkQuality;
      final context = Get.context;
      if (context == null) return const SizedBox.shrink();

      IconData icon;
      Color color;
      String text;

      switch (quality) {
        case NetworkQuality.good:
          icon = Icons.signal_cellular_alt;
          color = Colors.green;
          text = 'مستقر';
          break;
        case NetworkQuality.fair:
          icon = Icons.signal_cellular_alt_2_bar;
          color = Colors.orange;
          text = 'جيد';
          break;
        case NetworkQuality.poor:
          icon = Icons.signal_cellular_alt_1_bar;
          color = Colors.red;
          text = 'ضعيف';
          break;
      }

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color.withValues(alpha: 0.9),
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    });
  }

  Widget _buildHeadphoneHint(ThemeData theme) {
    return Obx(() {
      if (!controller.showHeadphoneHint.value) return const SizedBox.shrink();

      return Positioned(
        top: 100,
        left: 20,
        right: 20,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 500),
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 20 * (1 - value)),
              child: Opacity(
                opacity: value,
                child: child,
              ),
            );
          },
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer
                    .withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.3),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.headphones,
                    color: theme.colorScheme.secondary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      Get.locale?.languageCode == 'ar'
                          ? 'لأفضل جودة في ويندوز، ننصح باستخدام السماعات لتجنب الصدى.'
                          : 'For optimal quality on Windows, headphones are recommended.',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => controller.showHeadphoneHint.value = false,
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: theme.colorScheme.onSecondaryContainer
                          .withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildVolumeSlider({
    required String label,
    required IconData icon,
    required RxDouble value,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 14)),
            const Spacer(),
            Obx(() => Text(
                  '${(value.value * 100).toInt()}%',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                )),
          ],
        ),
        Obx(() => Slider(
              value: value.value,
              onChanged: onChanged,
              min: 0.0,
              max: 1.5, // Allow up to 150% volume
              divisions: 15,
            )),
      ],
    );
  }
}

class _TalkingWaveform extends StatelessWidget {
  const _TalkingWaveform();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 2.0, end: 12.0),
          duration: Duration(milliseconds: 300 + (index * 100)),
          builder: (context, value, child) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              width: 2,
              height: value,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(1),
              ),
            );
          },
        );
      }),
    );
  }
}

class _ControlCircle extends StatefulWidget {
  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final VoidCallback? onTap;

  const _ControlCircle({
    required this.icon,
    required this.backgroundColor,
    this.iconColor = Colors.black87,
    this.onTap,
  });

  @override
  State<_ControlCircle> createState() => _ControlCircleState();
}

class _ControlCircleState extends State<_ControlCircle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDisabled = widget.onTap == null;

    return GestureDetector(
      onTapDown: isDisabled ? null : (_) => _controller.forward(),
      onTapUp: isDisabled ? null : (_) => _controller.reverse(),
      onTapCancel: isDisabled ? null : () => _controller.reverse(),
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: isDisabled
                ? widget.backgroundColor.withValues(alpha: 0.3)
                : widget.backgroundColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 1,
            ),
            boxShadow: [
              if (!isDisabled)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
            ],
          ),
          child: Icon(
            widget.icon,
            color: isDisabled
                ? widget.iconColor.withValues(alpha: 0.5)
                : widget.iconColor,
            size: 26,
          ),
        ),
      ),
    );
  }
}

class _ParticipantTile extends GetView<CommunicationController> {
  final CommunicationParticipant participant;
  final bool isFull;
  const _ParticipantTile({required this.participant, this.isFull = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Obx(() {
      final bool isTalking = participant.isTalking.value;
      final bool isMuted = participant.isMuted.value;

      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF121212), // Fixed Dark Background
          borderRadius: BorderRadius.circular(isFull ? 0 : 28),
          border: Border.all(
            color: isTalking ? theme.colorScheme.primary : Colors.white10,
            width: isTalking ? 3 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Layer 0: ALWAYS VISIBLE AVATAR (Fallback)
            // This ensures we never show a white screen.
            Positioned.fill(
              child: _buildAvatar(context),
            ),

            // Layer 1: Video Stream (Conditional Overlay)
            // Sits on top of the avatar. If transparent or loading, avatar shows through.
            Positioned.fill(
              child: _buildVideoLayer(context),
            ),

            // Layer 2: Glassy Name Overlay
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ColorFilter.mode(
                    Colors.black.withValues(alpha: 0.3),
                    BlendMode.darken,
                  ),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            participant.name +
                                (participant.isLocal ? ' (أنت)' : ''),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isMuted)
                          const Icon(Icons.mic_off,
                              size: 14, color: Colors.redAccent)
                        else if (isTalking)
                          const _TalkingWaveform(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildVideoLayer(BuildContext context) {
    return Obx(() {
      final bool isVideoOn = participant.isVideoOn.value;

      // Strict Guard: Only show video if explicitly ON and stream is valid.
      // Otherwise, return SizedBox.shrink() to let the Avatar layer show.
      if (!isVideoOn || controller.isEnding.value) {
        return const SizedBox.shrink();
      }

      Widget videoWidget;

      if (participant.isLocal) {
        if (controller.isCameraOn.value) {
          videoWidget = webrtc.RTCVideoView(
            controller.localRenderer,
            objectFit: webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            mirror: true,
            key: const ValueKey('local_video'),
          );
        } else {
          return const SizedBox.shrink();
        }
      } else {
        final stream = participant.remoteStream.value;
        if (stream != null) {
          videoWidget = _RemoteVideo(
              stream: stream, key: ValueKey('remote_${participant.id}'));
        } else {
          return const SizedBox.shrink();
        }
      }

      // Smooth fade-in for video to avoid harsh cuts
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: videoWidget,
      );
    });
  }

  Widget _buildAvatar(BuildContext context) {
    final theme = Theme.of(context);
    final name = participant.name;
    final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';

    // Added a slight background color to the container itself to distinguish from "white screen"
    return Container(
      color: const Color(0xFF0D0D0D), // Ultra-dark fallback
      child: Center(
        child: CircleAvatar(
          radius: isFull ? 60 : 36,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            initial,
            style: TextStyle(
              fontSize: isFull ? 40 : 24,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}

class _LocalPreview extends GetView<CommunicationController> {
  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!controller.isCameraOn.value || controller.isEnding.value) {
        return const SizedBox.shrink();
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: webrtc.RTCVideoView(controller.localRenderer,
            objectFit: webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            mirror: true),
      );
    });
  }
}

class _RemoteVideo extends StatefulWidget {
  final webrtc.MediaStream stream;
  const _RemoteVideo({required this.stream, super.key});
  @override
  State<_RemoteVideo> createState() => _RemoteVideoState();
}

class PointerEventsNone extends StatelessWidget {
  final Widget child;
  const PointerEventsNone({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(child: child);
  }
}

class _RemoteVideoState extends State<_RemoteVideo> {
  final _renderer = webrtc.RTCVideoRenderer();
  @override
  void initState() {
    super.initState();
    _renderer.initialize().then((_) {
      if (!mounted) return;
      _renderer.srcObject = widget.stream;
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(_RemoteVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream.id != widget.stream.id) {
      debugPrint('📺 [UI] Remote Stream updated: ${widget.stream.id}');
      _renderer.srcObject = widget.stream;
    }
  }

  @override
  void dispose() {
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return webrtc.RTCVideoView(_renderer,
        objectFit: webrtc.RTCVideoViewObjectFit.RTCVideoViewObjectFitCover);
  }
}
