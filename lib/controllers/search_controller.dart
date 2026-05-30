import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talkmate_ai/data/models/user_model.dart' as data_models;
import 'package:talkmate_ai/data/repositories/contracts/i_friend_request_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_friendship_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';
import 'package:talkmate_ai/services/observability/analytics_service.dart';
import 'package:talkmate_ai/services/observability/performance_tracker.dart';

import '../config/app_config.dart';
import '../models/chat_model.dart';
import '../models/message_model.dart';
import 'auth_controller.dart';
import 'chat_controller.dart';

enum SearchType { all, chats, messages, users }

class SearchResult {
  final String id;
  final String title;
  final String subtitle;
  final String? avatar;
  final SearchType type;
  final dynamic data; // ChatModel, MessageModel, or UserModel
  final DateTime? timestamp;

  SearchResult({
    required this.id,
    required this.title,
    required this.subtitle,
    this.avatar,
    required this.type,
    required this.data,
    this.timestamp,
  });
}

class AppSearchController extends GetxController {
  static const String _recentSearchesKey = 'recent_searches';
  static const int _maxRecentSearches = 10;

  final RxString _searchQuery = ''.obs;
  final RxList<SearchResult> _searchResults = <SearchResult>[].obs;
  final RxList<String> _recentSearches = <String>[].obs;
  final RxBool _isSearching = false.obs;
  final Rx<SearchType> _searchType = SearchType.all.obs;
  final RxBool _showRecentSearches = true.obs;

  // Getters
  String get searchQuery => _searchQuery.value;
  List<SearchResult> get searchResults => _searchResults;
  List<String> get recentSearches => _recentSearches;
  bool get isSearching => _isSearching.value;
  SearchType get searchType => _searchType.value;
  bool get showRecentSearches => _showRecentSearches.value;
  bool get hasResults => _searchResults.isNotEmpty;
  bool get hasQuery => _searchQuery.value.isNotEmpty;

  // Rx getters (for Obx dependency tracking)
  Rx<SearchType> get searchTypeObs => _searchType;
  RxBool get showRecentSearchesObs => _showRecentSearches;
  RxBool get isSearchingObs => _isSearching;
  RxList<SearchResult> get searchResultsObs => _searchResults;
  RxList<String> get recentSearchesObs => _recentSearches;

  @override
  void onInit() {
    super.onInit();
    _loadRecentSearches();
  }

  Future<void> _loadRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final searches = prefs.getStringList(_recentSearchesKey) ?? [];
      _recentSearches.value = searches;

      if (AppConfig.isDebugMode) {
        debugPrint('Loaded ${searches.length} recent searches');
      }
    } catch (e) {
      debugPrint('Error loading recent searches: $e');
    }
  }

  Future<void> _saveRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentSearchesKey, _recentSearches);
    } catch (e) {
      debugPrint('Error saving recent searches: $e');
    }
  }

  void setSearchType(SearchType type) {
    _searchType.value = type;
    if (_searchQuery.value.isNotEmpty) {
      _performSearch(_searchQuery.value);
    }
  }

  void setSearchQuery(String query) {
    _searchQuery.value = query;
    _showRecentSearches.value = query.isEmpty;

    if (query.isEmpty) {
      _searchResults.clear();
      _isSearching.value = false;
    } else {
      _performSearch(query);
    }
  }

  void clearSearch() {
    _searchQuery.value = '';
    _searchResults.clear();
    _isSearching.value = false;
    _showRecentSearches.value = true;
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;

    // Start tracking latency (Stage Z)
    final perf = PerformanceTracker.instance;
    await perf.startTrace('search_latency');

    _isSearching.value = true;
    _searchResults.clear();

    try {
      // Add to recent searches
      await _addToRecentSearches(query);

      // Simulate search delay
      await Future.delayed(const Duration(milliseconds: 300));

      // Ensure chats are initialized before searching
      final chatController = Get.find<ChatController>();
      int guard = 0;
      while (!chatController.isInitialized && guard < 20) {
        await Future.delayed(const Duration(milliseconds: 50));
        guard++;
      }

      final results = <SearchResult>[];

      // Search in chats
      if (_searchType.value == SearchType.all ||
          _searchType.value == SearchType.chats) {
        results.addAll(await _searchChats(query));
      }

      // Search in messages
      if (_searchType.value == SearchType.all ||
          _searchType.value == SearchType.messages) {
        results.addAll(await _searchMessages(query));
      }

      // Search in users (mock data)
      if (_searchType.value == SearchType.all ||
          _searchType.value == SearchType.users) {
        results.addAll(await _searchUsers(query));
      }

      // Sort results by relevance and timestamp
      results.sort((a, b) {
        // First by type priority (chats > messages > users)
        final typePriority = {
          SearchType.chats: 3,
          SearchType.messages: 2,
          SearchType.users: 1,
        };

        final aPriority = typePriority[a.type] ?? 0;
        final bPriority = typePriority[b.type] ?? 0;

        if (aPriority != bPriority) {
          return bPriority.compareTo(aPriority);
        }

        // Then by timestamp (newer first)
        if (a.timestamp != null && b.timestamp != null) {
          return b.timestamp!.compareTo(a.timestamp!);
        }

        return 0;
      });

      _searchResults.value = results;

      // Stop tracking latency (Stage Z)
      await perf.stopTrace('search_latency',
          attributes: {'query_length': query.length.toString()});
      unawaited(AnalyticsService.instance.logEvent(
          name: 'search_performed',
          parameters: {'type': _searchType.value.name}));

      if (AppConfig.isDebugMode) {
        debugPrint('Search completed: ${results.length} results for "$query"');
      }
    } catch (e) {
      debugPrint('Error performing search: $e');
    } finally {
      _isSearching.value = false;
    }
  }

  Future<List<SearchResult>> _searchChats(String query) async {
    final chatController = Get.find<ChatController>();
    final results = <SearchResult>[];

    final nq = _normalizeArabic(query);
    for (final chat in chatController.chats) {
      final nameN = _normalizeArabic(
          chat.getDisplayName(AppLocalizations.of(Get.context!)));
      final descN = _normalizeArabic(chat.description ?? '');
      final lastMsgN = _normalizeArabic(chat.lastMessage?.content ?? '');

      if (nameN.contains(nq) || descN.contains(nq) || lastMsgN.contains(nq)) {
        results.add(
          SearchResult(
            id: chat.id,
            title: chat.getDisplayName(AppLocalizations.of(Get.context!)),
            subtitle:
                chat.getLastMessageText(AppLocalizations.of(Get.context!)),
            type: SearchType.chats,
            data: chat,
            timestamp: chat.lastActivity,
          ),
        );
      }
    }

    return results;
  }

  Future<List<SearchResult>> _searchMessages(String query) async {
    final chatController = Get.find<ChatController>();
    final results = <SearchResult>[];

    final nq = _normalizeArabic(query);
    for (final chat in chatController.chats) {
      final messages = chatController.getMessagesForChat(chat.id);

      for (final message in messages) {
        if (_normalizeArabic(message.content).contains(nq)) {
          results.add(
            SearchResult(
              id: message.id,
              title: chat.getDisplayName(AppLocalizations.of(Get.context!)),
              subtitle: _highlightSearchTerm(message.content, query),
              type: SearchType.messages,
              data: message,
              timestamp: message.timestamp,
            ),
          );
        }
      }
    }

    return results;
  }

  Future<List<SearchResult>> _searchUsers(String query) async {
    final results = <SearchResult>[];
    final auth = Get.find<AuthController>();
    if (!auth.isLoggedIn || auth.userId.isEmpty) {
      debugPrint('Skip _searchUsers: not logged in');
      return results;
    }
    if (query.trim().isEmpty) return results;
    try {
      final users = await Get.find<IUserRepository>()
          .searchByNameOrEmail(query, limit: 25);

      for (final u in users) {
        results.add(
          SearchResult(
            id: u.id,
            title: (u.displayName ?? u.email),
            subtitle: u.email,
            type: SearchType.users,
            data: u,
          ),
        );
      }
    } catch (e) {
      debugPrint('User search error: $e');
    }
    return results;
  }

  Future<void> sendFriendRequestTo(String targetUserId) async {
    final l10n = AppLocalizations.of(Get.context!);
    try {
      final auth = Get.find<AuthController>();
      final currentUserId = auth.userId;
      if (currentUserId.isEmpty) {
        Get.snackbar(l10n.loginErrorTitle, l10n.loginErrorMessage,
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.red,
            colorText: Colors.white);
        return;
      }
      if (currentUserId == targetUserId) {
        Get.snackbar(l10n.error, 'Cannot send friend request to yourself',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.orange,
            colorText: Colors.white);
        return;
      }

      // Guard: already friends
      final alreadyFriends = await Get.find<IFriendshipRepository>()
          .areFriends(currentUserId, targetUserId);
      if (alreadyFriends) {
        Get.snackbar(
          l10n.error,
          'أنتم بالفعل أصدقاء',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        return;
      }

      await Get.find<IFriendRequestRepository>()
          .sendRequest(fromUserId: currentUserId, toUserId: targetUserId);

      Get.snackbar(l10n.sent, l10n.messageSentSuccess,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.green,
          colorText: Colors.white);
    } catch (e) {
      debugPrint('sendFriendRequestTo error: $e');
      final l10n = AppLocalizations.of(Get.context!);
      Get.snackbar(l10n.error, e.toString(),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white);
    }
  }

  Future<void> sendFriendRequestForResult(SearchResult result) async {
    if (result.type != SearchType.users) return;
    final user = result.data as data_models.AppUser;
    await sendFriendRequestTo(user.id);
  }

  String _highlightSearchTerm(String text, String searchTerm) {
    if (searchTerm.isEmpty) return text;

    final index = text.toLowerCase().indexOf(searchTerm.toLowerCase());
    if (index == -1) {
      // Try normalized match; if found, return a safe snippet without precise highlighting
      if (_normalizeArabic(text).contains(_normalizeArabic(searchTerm))) {
        final safeLen = text.length;
        final start = 0;
        final end = safeLen > 80 ? 80 : safeLen;
        final snippet = text.substring(start, end);
        return safeLen > 80 ? '$snippet...' : snippet;
      }
      return text;
    }

    // const maxLength = 100; // Reserved for future use
    final start = (index - 20).clamp(0, text.length);
    final end = (index + searchTerm.length + 20).clamp(0, text.length);

    String result = text.substring(start, end);
    if (start > 0) result = '...$result';
    if (end < text.length) result = '$result...';

    return result;
  }

  // Arabic normalization to improve search matching (remove diacritics, tatweel, unify alef forms)
  String _normalizeArabic(String input) {
    var s = input;
    // Remove tatweel
    s = s.replaceAll(RegExp('\u0640'), '');
    // Remove diacritics (harakat)
    s = s.replaceAll(RegExp('[\u064B-\u065F\u0670]'), '');
    // Unify alef forms
    s = s.replaceAll('أ', 'ا').replaceAll('إ', 'ا').replaceAll('آ', 'ا');
    // Unify yaa/aleff maqsura
    s = s.replaceAll('ى', 'ي');
    // Optional: map taa marbuta to ha for loose matching
    s = s.replaceAll('ة', 'ه');
    return s.toLowerCase();
  }

  Future<void> _addToRecentSearches(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return;

    // Remove if already exists
    _recentSearches.remove(trimmedQuery);

    // Add to beginning
    _recentSearches.insert(0, trimmedQuery);

    // Keep only max recent searches
    if (_recentSearches.length > _maxRecentSearches) {
      _recentSearches.removeRange(_maxRecentSearches, _recentSearches.length);
    }

    await _saveRecentSearches();
  }

  void selectRecentSearch(String query) {
    setSearchQuery(query);
  }

  void removeRecentSearch(String query) {
    _recentSearches.remove(query);
    _saveRecentSearches();
  }

  void clearRecentSearches() {
    _recentSearches.clear();
    _saveRecentSearches();

    final l10n = AppLocalizations.of(Get.context!);
    Get.snackbar(
      l10n.cleared,
      l10n.searchHistoryCleared,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  void selectSearchResult(SearchResult result) {
    switch (result.type) {
      case SearchType.chats:
        final chat = result.data as ChatModel;
        Get.back(); // Close search screen
        // Navigate to chat - this would be implemented based on your navigation structure
        final l10n = AppLocalizations.of(Get.context!);
        Get.snackbar(
          l10n.openChatTitle,
          l10n.openChatWithName(
              chat.getDisplayName(AppLocalizations.of(Get.context!))),
          snackPosition: SnackPosition.BOTTOM,
        );
        break;

      case SearchType.messages:
        final message = result.data as MessageModel;
        Get.back(); // Close search screen
        // Navigate to message in chat
        final l10n = AppLocalizations.of(Get.context!);
        Get.snackbar(
          l10n.goToMessageTitle,
          l10n.goToMessageBody(message.content),
          snackPosition: SnackPosition.BOTTOM,
        );
        break;

      case SearchType.users:
        final user = result.data as data_models.AppUser;
        Get.back(); // Close search screen
        // Show user profile or start chat
        final l10n = AppLocalizations.of(Get.context!);
        Get.snackbar(
          l10n.viewUserTitle,
          l10n.viewUserProfileWithName(user.displayName ?? user.email),
          snackPosition: SnackPosition.BOTTOM,
        );
        break;

      case SearchType.all:
        break;
    }
  }

  String getSearchTypeText(SearchType type) {
    final l10n = AppLocalizations.of(Get.context!);
    switch (type) {
      case SearchType.all:
        return l10n.all;
      case SearchType.chats:
        return l10n.chatsLabel;
      case SearchType.messages:
        return l10n.messagesLabel;
      case SearchType.users:
        return l10n.usersLabel;
    }
  }

  IconData getSearchTypeIcon(SearchType type) {
    switch (type) {
      case SearchType.all:
        return Icons.search;
      case SearchType.chats:
        return Icons.chat;
      case SearchType.messages:
        return Icons.message;
      case SearchType.users:
        return Icons.people;
    }
  }

  Color getSearchResultColor(SearchType type) {
    switch (type) {
      case SearchType.chats:
        return Colors.blue;
      case SearchType.messages:
        return Colors.green;
      case SearchType.users:
        return Colors.orange;
      case SearchType.all:
        return Colors.grey;
    }
  }
}
