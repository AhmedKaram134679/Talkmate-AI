import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/data/models/friend_request_model.dart';
import 'package:talkmate_ai/data/models/user_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_friend_request_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_friendship_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:talkmate_ai/utils/user_display.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _auth = Get.find<AuthController>();
  final _frRepo = Get.find<IFriendRequestRepository>();
  final _friendRepo = Get.find<IFriendshipRepository>();
  final _userRepo = Get.find<IUserRepository>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  Widget _historyActions(
      FriendRequestModel req, String currentUid, String otherId) {
    // فقط للطلبات الملغاة نعرض زر إعادة الإرسال
    if (req.status == FriendRequestStatus.canceled) {
      return IconButton(
        tooltip: 'إعادة الإرسال',
        icon:
            Icon(Icons.refresh, color: Theme.of(context).colorScheme.secondary),
        onPressed: () async {
          try {
            await _frRepo.sendRequest(
                fromUserId: currentUid, toUserId: otherId);
            Get.snackbar(
              'تم',
              'تمت إعادة إرسال طلب الصداقة',
              snackPosition: SnackPosition.BOTTOM,
            );
          } catch (e) {
            if (mounted) {
              Get.snackbar(
                'خطأ',
                e.toString(),
                snackPosition: SnackPosition.BOTTOM,
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                colorText: Theme.of(context).colorScheme.onErrorContainer,
              );
            }
          }
        },
      );
    }
    return const SizedBox.shrink();
  }

  String _formatDate(DateTime dt) {
    // مثال تنسيق: 2025/09/04 12:05
    final f = DateFormat('yyyy/MM/dd HH:mm');
    return f.format(dt);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.friendRequests),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.incoming),
            Tab(text: l10n.outgoing),
            Tab(text: l10n.history),
          ],
        ),
      ),
      body: Obx(() {
        final loggedIn = _auth.isLoggedInRx.value;
        final uid = _auth.userId;
        if (!loggedIn || uid.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return TabBarView(
          controller: _tabController,
          children: [
            // Incoming
            StreamBuilder<List<FriendRequestModel>>(
              stream: _frRepo.watchIncoming(uid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  debugPrint('Incoming stream error: ${snapshot.error}');
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = (snapshot.data ?? const <FriendRequestModel>[])
                    .where((r) => r.status == FriendRequestStatus.pending)
                    .toList();
                if (list.isEmpty) {
                  return Center(
                    child: Text(l10n.noIncomingRequests),
                  );
                }
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final req = list[index];
                    return StreamBuilder<AppUser?>(
                      stream: _userRepo.watchById(req.fromUserId),
                      builder: (context, userSnap) {
                        final u = userSnap.data;
                        return ListTile(
                          leading: UserDisplay.avatarCircle(
                              user: u, userId: req.fromUserId),
                          title: Text(
                              UserDisplay.nameOrFallback(u, req.fromUserId)),
                          subtitle: Text(
                            _statusText(req.status),
                            style: TextStyle(
                              color: _statusColor(context, req.status),
                            ),
                          ),
                          trailing: _incomingActions(l10n, req),
                        );
                      },
                    );
                  },
                );
              },
            ),
            // Outgoing
            StreamBuilder<List<FriendRequestModel>>(
              stream: _frRepo.watchOutgoing(uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = (snapshot.data ?? const <FriendRequestModel>[])
                    .where((r) => r.status == FriendRequestStatus.pending)
                    .toList();
                if (list.isEmpty) {
                  return Center(
                    child: Text(l10n.noOutgoingRequests),
                  );
                }
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final req = list[index];
                    return StreamBuilder<AppUser?>(
                      stream: _userRepo.watchById(req.toUserId),
                      builder: (context, userSnap) {
                        final u = userSnap.data;
                        return ListTile(
                          leading: UserDisplay.avatarCircle(
                              user: u, userId: req.toUserId),
                          title:
                              Text(UserDisplay.nameOrFallback(u, req.toUserId)),
                          subtitle: Text(
                            _statusText(req.status),
                            style: TextStyle(
                              color: _statusColor(context, req.status),
                            ),
                          ),
                          trailing: _outgoingActions(l10n, req),
                        );
                      },
                    );
                  },
                );
              },
            ),
            // History tab (merged incoming + outgoing, non-pending only)
            Builder(builder: (context) {
              return StreamBuilder<List<FriendRequestModel>>(
                stream: _frRepo.watchIncoming(uid),
                builder: (context, incomingSnap) {
                  return StreamBuilder<List<FriendRequestModel>>(
                    stream: _frRepo.watchOutgoing(uid),
                    builder: (context, outgoingSnap) {
                      if (incomingSnap.connectionState ==
                              ConnectionState.waiting ||
                          outgoingSnap.connectionState ==
                              ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final incoming = (incomingSnap.data ??
                              const <FriendRequestModel>[])
                          .where((r) => r.status != FriendRequestStatus.pending)
                          .toList();
                      final outgoing = (outgoingSnap.data ??
                              const <FriendRequestModel>[])
                          .where((r) => r.status != FriendRequestStatus.pending)
                          .toList();
                      final merged = <FriendRequestModel>[
                        ...incoming,
                        ...outgoing
                      ];
                      // Sort by createdAt desc
                      merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
                      if (merged.isEmpty) {
                        return Center(child: Text(l10n.noRequestHistory));
                      }
                      return ListView.separated(
                        itemCount: merged.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final req = merged[index];
                          final otherId = req.fromUserId == uid
                              ? req.toUserId
                              : req.fromUserId;
                          return StreamBuilder<AppUser?>(
                            stream: _userRepo.watchById(otherId),
                            builder: (context, userSnap) {
                              final u = userSnap.data;
                              return ListTile(
                                leading: UserDisplay.avatarCircle(
                                    user: u, userId: otherId),
                                title: Text(
                                    UserDisplay.nameOrFallback(u, otherId)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _statusText(req.status),
                                      style: TextStyle(
                                          color: _statusColor(
                                              context, req.status)),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'من: ${req.fromUserId}  →  إلى: ${req.toUserId}\nالتاريخ: ${_formatDate(req.updatedAt)}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                                trailing: _historyActions(req, uid, otherId),
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            }),
          ],
        );
      }),
    );
  }

  Widget _incomingActions(AppLocalizations l10n, FriendRequestModel req) {
    if (req.status != FriendRequestStatus.pending) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'قبول',
          icon: Icon(Icons.check_circle,
              color: Theme.of(context).colorScheme.primary),
          onPressed: () async {
            try {
              await _frRepo.accept(req.id);
              await _friendRepo.createFriendship(
                userA: req.fromUserId,
                userB: req.toUserId,
              );
              Get.snackbar(
                'تم',
                'تم قبول طلب الصداقة',
                snackPosition: SnackPosition.BOTTOM,
              );
            } catch (e) {
              if (mounted) {
                Get.snackbar(
                  'خطأ',
                  e.toString(),
                  snackPosition: SnackPosition.BOTTOM,
                  backgroundColor: Theme.of(context).colorScheme.errorContainer,
                  colorText: Theme.of(context).colorScheme.onErrorContainer,
                );
              }
            }
          },
        ),
        IconButton(
          tooltip: 'رفض',
          icon: Icon(Icons.cancel, color: Theme.of(context).colorScheme.error),
          onPressed: () async {
            try {
              await _frRepo.decline(req.id);
            } catch (e) {
              if (mounted) {
                Get.snackbar(
                  'خطأ',
                  e.toString(),
                  snackPosition: SnackPosition.BOTTOM,
                  backgroundColor: Theme.of(context).colorScheme.errorContainer,
                  colorText: Theme.of(context).colorScheme.onErrorContainer,
                );
              }
            }
          },
        ),
      ],
    );
  }

  Widget _outgoingActions(AppLocalizations l10n, FriendRequestModel req) {
    if (req.status != FriendRequestStatus.pending) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: 'إلغاء',
      icon: Icon(Icons.undo, color: Theme.of(context).colorScheme.secondary),
      onPressed: () async {
        try {
          await _frRepo.cancel(req.id);
        } catch (e) {
          if (mounted) {
            Get.snackbar(
              'خطأ',
              e.toString(),
              snackPosition: SnackPosition.BOTTOM,
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              colorText: Theme.of(context).colorScheme.onErrorContainer,
            );
          }
        }
      },
    );
  }

  String _statusText(FriendRequestStatus s) {
    switch (s) {
      case FriendRequestStatus.pending:
        return 'قيد الانتظار';
      case FriendRequestStatus.accepted:
        return 'تم القبول';
      case FriendRequestStatus.declined:
        return 'مرفوض';
      case FriendRequestStatus.canceled:
        return 'ملغي';
    }
  }

  Color _statusColor(BuildContext context, FriendRequestStatus s) {
    switch (s) {
      case FriendRequestStatus.pending:
        return Theme.of(context).colorScheme.primary;
      case FriendRequestStatus.accepted:
        return Theme.of(context).colorScheme.primary;
      case FriendRequestStatus.declined:
        return Theme.of(context).colorScheme.error;
      case FriendRequestStatus.canceled:
        return Theme.of(context).colorScheme.secondary;
    }
  }
}
