import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class LinkPreviewData {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;

  LinkPreviewData({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'description': description,
        'imageUrl': imageUrl,
      };

  static LinkPreviewData fromJson(Map<String, dynamic> json) => LinkPreviewData(
        url: json['url'] as String,
        title: json['title'] as String?,
        description: json['description'] as String?,
        imageUrl: json['imageUrl'] as String?,
      );
}

class LinkPreviewService {
  LinkPreviewService._();
  static final LinkPreviewService instance = LinkPreviewService._();

  static const _cacheKeyPrefix = 'link_preview_cache_';

  Future<LinkPreviewData?> fetch(String url,
      {Duration ttl = const Duration(days: 3)}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_cacheKeyPrefix${Uri.encodeComponent(url)}';
      final cachedStr = prefs.getString(cacheKey);
      if (cachedStr != null && cachedStr.isNotEmpty) {
        final map = jsonDecode(cachedStr) as Map<String, dynamic>;
        final cachedAtMs = map['cachedAt'] as int?;
        final dataMap = map['data'] as Map<String, dynamic>;
        if (cachedAtMs != null) {
          final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtMs);
          if (DateTime.now().difference(cachedAt) <= ttl) {
            return LinkPreviewData.fromJson(dataMap);
          }
        }
      }

      final res = await http.get(Uri.parse(url));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final html = res.body;

      String? extractMeta(String pattern) {
        final reg = RegExp(pattern, caseSensitive: false, multiLine: true);
        final m = reg.firstMatch(html);
        return m != null ? (m.group(1)?.trim()) : null;
      }

      // Prefer Open Graph, fallback to <title>
      final title = extractMeta(
              r'''<meta[^>]*property=["']og:title["'][^>]*content=["']([^"']+)["']''') ??
          extractMeta(r'''<title[^>]*>([^<]+)</title>''');
      final description = extractMeta(
              r'''<meta[^>]*property=["']og:description["'][^>]*content=["']([^"']+)["']''') ??
          extractMeta(
              r'''<meta[^>]*name=["']description["'][^>]*content=["']([^"']+)["']''');
      final image = extractMeta(
          r'''<meta[^>]*property=["']og:image["'][^>]*content=["']([^"']+)["']''');

      final data = LinkPreviewData(
          url: url, title: title, description: description, imageUrl: image);
      await prefs.setString(
          cacheKey,
          jsonEncode({
            'cachedAt': DateTime.now().millisecondsSinceEpoch,
            'data': data.toJson()
          }));
      return data;
    } catch (_) {
      return null;
    }
  }
}
