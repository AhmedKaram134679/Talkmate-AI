import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:talkmate_ai/config/theme_config.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';

import '../controllers/search_controller.dart' as app_search;

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final app_search.AppSearchController searchController =
      Get.find<app_search.AppSearchController>();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Auto focus on search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildSearchTypeFilter(),
          Expanded(
            child: Obx(
              () => searchController.showRecentSearchesObs.value
                  ? _buildRecentSearches()
                  : _buildSearchResults(),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final Color textOnSurface = theme.colorScheme.onSurface;
    final Color hintOnSurface =
        theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return AppBar(
      title: Theme(
        data: theme.copyWith(
          textSelectionTheme: TextSelectionThemeData(
            cursorColor: textOnSurface,
            selectionColor: textOnSurface.withValues(alpha: 0.25),
            selectionHandleColor: textOnSurface,
          ),
          inputDecorationTheme: theme.inputDecorationTheme.copyWith(
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            hintStyle: TextStyle(color: hintOnSurface),
          ),
        ),
        child: TextField(
          controller: _textController,
          focusNode: _focusNode,
          decoration: InputDecoration(
            hintText:
                l10n.searchInAppHint(AppLocalizations.of(context).appName),
          ),
          style: theme.textTheme.bodyLarge?.copyWith(color: textOnSurface),
          cursorColor: textOnSurface,
          onChanged: (value) => searchController.setSearchQuery(value),
          onSubmitted: (value) => searchController.setSearchQuery(value),
        ),
      ),
      actions: [
        Obx(
          () => searchController.hasQuery
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _textController.clear();
                    searchController.clearSearch();
                  },
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildSearchTypeFilter() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Obx(() {
        final selectedType = searchController.searchTypeObs.value;
        return ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: app_search.SearchType.values.length,
          itemBuilder: (context, index) {
            final type = app_search.SearchType.values[index];
            final isSelected = selectedType == type;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: FilterChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        searchController.getSearchTypeIcon(type),
                        size: 16,
                        color: isSelected
                            ? Theme.of(context).colorScheme.onPrimary
                            : null,
                      ),
                      const SizedBox(width: 4),
                      Text(searchController.getSearchTypeText(type)),
                    ],
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      searchController.setSearchType(type);
                    }
                  },
                  backgroundColor: Theme.of(context).cardTheme.color,
                  selectedColor: ThemeConfig.primaryColor,
                  labelStyle: TextStyle(
                      color: isSelected
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurface,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                          color: isSelected
                              ? Colors.transparent
                              : Theme.of(context)
                                  .dividerColor
                                  .withValues(alpha: 0.5),
                          width: 1)),
                  showCheckmark: false,
                ),
              ),
            );
          },
        );
      }),
    );
  }

  Widget _buildRecentSearches() {
    return Obx(() {
      final l10n = AppLocalizations.of(context);
      if (searchController.recentSearchesObs.isEmpty) {
        return _buildEmptyState(
          icon: Icons.history,
          title: l10n.noSearchHistory,
          subtitle: l10n.startSearchingToSave,
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.recentSearches,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: searchController.clearRecentSearches,
                  child: Text(l10n.clearAll),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: searchController.recentSearchesObs.length,
              itemBuilder: (context, index) {
                final query = searchController.recentSearchesObs[index];
                return ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(query),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => searchController.removeRecentSearch(query),
                  ),
                  onTap: () {
                    _textController.text = query;
                    searchController.selectRecentSearch(query);
                  },
                );
              },
            ),
          ),
        ],
      );
    });
  }

  Widget _buildSearchResults() {
    return Obx(() {
      final l10n = AppLocalizations.of(context);
      if (searchController.isSearchingObs.value) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: ThemeConfig.primaryColor),
              const SizedBox(height: 16),
              Text(l10n.searching,
                  style: TextStyle(color: ThemeConfig.primaryColor)),
            ],
          ),
        );
      }

      if (searchController.searchResultsObs.isEmpty) {
        return _buildEmptyState(
          icon: Icons.search_off,
          title: l10n.noResults,
          subtitle: l10n.tryDifferentKeywordsOrType,
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: searchController.searchResultsObs.length,
        itemBuilder: (context, index) {
          final result = searchController.searchResultsObs[index];
          // Staggered Animation
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 300 + (index * 50).clamp(0, 500)),
            curve: Curves.easeOutQuart,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: Opacity(opacity: value, child: child),
              );
            },
            child: _buildSearchResultItem(result),
          );
        },
      );
    });
  }

  Widget _buildSearchResultItem(app_search.SearchResult result) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ]),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: searchController
                  .getSearchResultColor(result.type)
                  .withValues(alpha: 0.1),
              shape: BoxShape.circle),
          child: Icon(
            searchController.getSearchTypeIcon(result.type),
            color: searchController.getSearchResultColor(result.type),
            size: 20,
          ),
        ),
        title: Text(result.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          result.subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: result.type == app_search.SearchType.users
            ? IconButton(
                icon: const Icon(Icons.person_add_alt_1),
                color: ThemeConfig.primaryColor,
                onPressed: () =>
                    searchController.sendFriendRequestForResult(result),
              )
            : (result.timestamp != null
                ? Text(
                    _formatTimestamp(result.timestamp!),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  )
                : null),
        onTap: () => searchController.selectSearchResult(result),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    final l10n = AppLocalizations.of(context);
    if (difference.inMinutes < 1) {
      return l10n.now;
    } else if (difference.inHours < 1) {
      return l10n.minutesAbbrev(difference.inMinutes);
    } else if (difference.inDays < 1) {
      return l10n.hoursAbbrev(difference.inHours);
    } else if (difference.inDays < 7) {
      return l10n.daysAbbrev(difference.inDays);
    } else {
      return DateFormat.Md(l10n.localeName).format(timestamp);
    }
  }
}
