import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:talkmate_ai/config/theme_config.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:talkmate_ai/services/observability/analytics_service.dart';

import 'calls_screen.dart';
import 'chats_screen.dart';
import 'groups_screen.dart';
import 'profile_screen.dart';
import 'rooms_screen.dart';

class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  final RxInt _currentIndex = 0.obs;

  final List<Widget> _screens = [
    const ChatsScreen(),
    const CallsScreen(),
    const RoomsScreen(),
    const GroupsScreen(),
    const ProfileScreen(),
  ];

  void _onItemTapped(int index) {
    if (_currentIndex.value == index) return;
    String screenName = 'Unknown';
    switch (index) {
      case 0:
        screenName = 'Chats';
        break;
      case 1:
        screenName = 'Calls';
        break;
      case 2:
        screenName = 'Rooms';
        break;
      case 3:
        screenName = 'Groups';
        break;
      case 4:
        screenName = 'Profile';
        break;
    }
    AnalyticsService.instance
        .logInteraction('tab_switch_$screenName', type: 'navigation');
    _currentIndex.value = index;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth >= 900;

        if (isWideScreen) {
          return Scaffold(
            body: Row(
              children: [
                Obx(
                  () => NavigationRail(
                    selectedIndex: _currentIndex.value,
                    onDestinationSelected: _onItemTapped,
                    labelType: NavigationRailLabelType.all,
                    backgroundColor: theme.scaffoldBackgroundColor,
                    indicatorColor: ThemeConfig.primaryColor.withValues(alpha: 0.15),
                    selectedIconTheme: const IconThemeData(color: ThemeConfig.primaryColor),
                    unselectedIconTheme: const IconThemeData(color: Colors.grey),
                    selectedLabelTextStyle: const TextStyle(
                      color: ThemeConfig.primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    unselectedLabelTextStyle: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                    destinations: [
                      NavigationRailDestination(
                        icon: const Icon(Icons.chat_bubble_outline_rounded),
                        selectedIcon: const Icon(Icons.chat_bubble_rounded),
                        label: Text(l10n.chats),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.call_outlined),
                        selectedIcon: const Icon(Icons.call),
                        label: Text(l10n.calls),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.meeting_room_outlined),
                        selectedIcon: const Icon(Icons.meeting_room_rounded),
                        label: Text(l10n.rooms),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.groups_outlined),
                        selectedIcon: const Icon(Icons.groups_rounded),
                        label: Text(l10n.groups),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.person_outline_rounded),
                        selectedIcon: const Icon(Icons.person_rounded),
                        label: Text(l10n.profile),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: Obx(
                    () => IndexedStack(
                      index: _currentIndex.value,
                      children: _screens,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          body: Obx(() => IndexedStack(
                index: _currentIndex.value,
                children: _screens,
              )),
          bottomNavigationBar: Obx(
            () => Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                        alpha: theme.brightness == Brightness.dark ? 0.3 : 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: BottomNavigationBar(
                currentIndex: _currentIndex.value,
                onTap: _onItemTapped,
                type: BottomNavigationBarType.fixed,
                backgroundColor: theme.scaffoldBackgroundColor,
                selectedItemColor: ThemeConfig.primaryColor,
                unselectedItemColor: Colors.grey,
                selectedFontSize: 12,
                unselectedFontSize: 12,
                elevation: 0,
                items: [
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    activeIcon: const Icon(Icons.chat_bubble_rounded),
                    label: l10n.chats,
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.call_outlined),
                    activeIcon: const Icon(Icons.call),
                    label: l10n.calls,
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.meeting_room_outlined),
                    activeIcon: const Icon(Icons.meeting_room_rounded),
                    label: l10n.rooms,
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.groups_outlined),
                    activeIcon: const Icon(Icons.groups_rounded),
                    label: l10n.groups,
                  ),
                  BottomNavigationBarItem(
                    icon: const Icon(Icons.person_outline_rounded),
                    activeIcon: const Icon(Icons.person_rounded),
                    label: l10n.profile,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
