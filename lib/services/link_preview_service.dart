import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';

class LinkPreviewData {
  final String url;
  final String? title;
  final String? description;
  final String? imageUrl;
  final Uint8List? imageBytes;

  LinkPreviewData({
    required this.url,
    this.title,
    this.description,
    this.imageUrl,
    this.imageBytes,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'description': description,
        'imageUrl': imageUrl,
        if (imageBytes != null) 'imageBytes': base64Encode(imageBytes!),
      };

  static LinkPreviewData fromJson(Map<String, dynamic> json) => LinkPreviewData(
        url: json['url'] as String,
        title: json['title'] as String?,
        description: json['description'] as String?,
        imageUrl: json['imageUrl'] as String?,
        imageBytes: json['imageBytes'] != null
            ? base64Decode(json['imageBytes'] as String)
            : null,
      );
}

class LinkPreviewService {
  LinkPreviewService._();
  static final LinkPreviewService instance = LinkPreviewService._();

  static const _cacheKeyPrefix = 'link_preview_cache_';
  static const int _maxResponseBytes = 64 * 1024; // 64 KB limit for HTML
  static const int _maxImageBytes = 256 * 1024; // 256 KB limit for Open Graph preview images
  static const int _maxRedirects = 3;
  static const Duration _connectTimeout = Duration(seconds: 4);
  static const Duration _totalTimeout = Duration(seconds: 8);

  /// Operational feature flag: allows fail-closed behavior if external network fetching is disabled.
  /// Default is FALSE (fail-closed, requires explicit opt-in).
  static bool enableExternalFetching = false;

  /// Check whether an IP address belongs to loopback, private, link-local, multicast, or reserved ranges
  static bool isPrivateOrLocalAddress(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
      return true;
    }

    if (address.type == InternetAddressType.IPv4) {
      final raw = address.rawAddress;
      final b0 = raw[0];
      final b1 = raw[1];

      // 0.0.0.0/8 (Current network)
      if (b0 == 0) return true;

      // 10.0.0.0/8 (Private)
      if (b0 == 10) return true;

      // 100.64.0.0/10 (Carrier-Grade NAT / Shared Address Space)
      if (b0 == 100 && (b1 >= 64 && b1 <= 127)) return true;

      // 127.0.0.0/8 (Loopback)
      if (b0 == 127) return true;

      // 169.254.0.0/16 (Link Local / Cloud metadata)
      if (b0 == 169 && b1 == 254) return true;

      // 172.16.0.0/12 (Private: 172.16.0.0 - 172.31.255.255)
      if (b0 == 172 && (b1 >= 16 && b1 <= 31)) return true;

      // 192.0.0.0/24 (IETF Protocol Assignments)
      if (b0 == 192 && b1 == 0 && raw[2] == 0) return true;

      // 192.0.2.0/24 (TEST-NET-1)
      if (b0 == 192 && b1 == 0 && raw[2] == 2) return true;

      // 192.168.0.0/16 (Private)
      if (b0 == 192 && b1 == 168) return true;

      // 198.18.0.0/15 (Benchmarking)
      if (b0 == 198 && (b1 == 18 || b1 == 19)) return true;

      // 198.51.100.0/24 (TEST-NET-2)
      if (b0 == 198 && b1 == 51 && raw[2] == 100) return true;

      // 203.0.113.0/24 (TEST-NET-3)
      if (b0 == 203 && b1 == 0 && raw[2] == 113) return true;

      // 224.0.0.0/4 (Multicast: 224 - 239)
      if (b0 >= 224 && b0 <= 239) return true;

      // 240.0.0.0/4 (Reserved / Future use: 240 - 255)
      if (b0 >= 240) return true;

      return false;
    } else if (address.type == InternetAddressType.IPv6) {
      final raw = address.rawAddress;

      // Check for IPv4-mapped IPv6 (::ffff:w.x.y.z)
      bool isIpv4Mapped = true;
      for (int i = 0; i < 10; i++) {
        if (raw[i] != 0) {
          isIpv4Mapped = false;
          break;
        }
      }
      if (isIpv4Mapped && raw[10] == 0xff && raw[11] == 0xff) {
        final ipv4Bytes = raw.sublist(12, 16);
        final ipv4Address =
            InternetAddress.fromRawAddress(Uint8List.fromList(ipv4Bytes));
        return isPrivateOrLocalAddress(ipv4Address);
      }

      // Unspecified ::
      if (raw.every((b) => b == 0)) return true;

      // Loopback ::1
      if (raw.sublist(0, 15).every((b) => b == 0) && raw[15] == 1) return true;

      // Unique Local Addresses (fc00::/7)
      if ((raw[0] & 0xfe) == 0xfc) return true;

      // Link-local unicast (fe80::/10)
      if (raw[0] == 0xfe && (raw[1] & 0xc0) == 0x80) return true;

      // Multicast (ff00::/8)
      if (raw[0] == 0xff) return true;

      return false;
    }

    return true; // Reject unrecognized address types
  }

  /// Check whether a URI is safe to fetch (HTTP/HTTPS, no userinfo, not local/private/loopback/multicast)
  static Future<bool> isSafeTarget(Uri uri) async {
    // 1. Protocol check: only http and https allowed
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;

    // 2. Reject userinfo (e.g. http://user:pass@host)
    if (uri.userInfo.isNotEmpty) return false;

    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty) return false;

    // 3. Reject forbidden host patterns and domains
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal') ||
        host.endsWith('.arpa') ||
        host == '0.0.0.0' ||
        host == '127.0.0.1' ||
        host == '::1') {
      return false;
    }

    try {
      // 4. If host is an IP literal, validate directly
      final directIp = InternetAddress.tryParse(host);
      if (directIp != null) {
        return !isPrivateOrLocalAddress(directIp);
      }

      // 5. Preflight DNS resolution check
      final addresses = await InternetAddress.lookup(host).timeout(
        const Duration(seconds: 3),
        onTimeout: () => [],
      );

      if (addresses.isEmpty) return false;

      // If ANY resolved IP is private or local, reject the target
      for (final addr in addresses) {
        if (isPrivateOrLocalAddress(addr)) {
          return false;
        }
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Creates an HttpClient that pins connection to an approved safe IP address at connection time,
  /// eliminating Time-of-Check to Time-of-Use DNS rebinding vulnerabilities while preserving TLS SNI.
  static HttpClient _createPinningClient(Duration timeout) {
    final client = HttpClient();
    client.connectionTimeout = timeout;
    client.autoUncompress = true;

    client.connectionFactory =
        (Uri uri, String? proxyHost, int? proxyPort) async {
      final targetHost = (proxyHost != null && proxyHost.isNotEmpty)
          ? proxyHost.trim().toLowerCase()
          : uri.host.trim().toLowerCase();
      final targetPort = (proxyHost != null && proxyPort != null)
          ? proxyPort
          : (uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80));

      // 1. Connection-time destination IP validation and pinning
      InternetAddress? pinnedIp;
      final directIp = InternetAddress.tryParse(targetHost);
      if (directIp != null) {
        if (isPrivateOrLocalAddress(directIp)) {
          throw SocketException('Access to private/local address is forbidden: $directIp',
              address: directIp, port: targetPort);
        }
        pinnedIp = directIp;
      } else {
        final addresses = await InternetAddress.lookup(targetHost).timeout(
          timeout,
          onTimeout: () => [],
        );

        if (addresses.isEmpty) {
          throw SocketException('DNS resolution failed or timed out for $targetHost', port: targetPort);
        }

        // Validate all resolved addresses; reject if any forbidden destination is present
        for (final addr in addresses) {
          if (isPrivateOrLocalAddress(addr)) {
            throw SocketException(
                'DNS resolved to forbidden destination: ${addr.address}',
                address: addr,
                port: targetPort);
          }
        }

        // Pin socket directly to the first approved address
        pinnedIp = addresses.first;
      }

      // 2. Establish raw TCP connection directly to the pinned IP address
      // Dart HttpClient will wrap this socket in SecureSocket.secure(..., host: uri.host)
      // for HTTPS connections, preserving SNI and full certificate validation.
      return Socket.startConnect(pinnedIp, targetPort);
    };

    return client;
  }

  Future<LinkPreviewData?> fetch(
    String url, {
    Duration ttl = const Duration(days: 3),
  }) async {
    if (!enableExternalFetching) {
      return null;
    }

    try {
      final initialUri = Uri.tryParse(url);
      if (initialUri == null) return null;

      // Check cache first
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

      // Pre-flight check on initial URL
      if (!await isSafeTarget(initialUri)) {
        return null;
      }

      // Shared stopwatch to enforce hard total deadline across all redirects and image fetch
      final stopwatch = Stopwatch()..start();

      final html = await _fetchHtmlSecurely(initialUri, stopwatch);
      if (html == null || html.isEmpty) return null;

      String? extractMeta(String pattern) {
        final reg = RegExp(pattern, caseSensitive: false, multiLine: true);
        final m = reg.firstMatch(html);
        return m != null ? (m.group(1)?.trim()) : null;
      }

      // Prefer Open Graph, fallback to <title>
      final title = extractMeta(
            r'''<meta[^>]*property=["']og:title["'][^>]*content=["']([^"']+)["']''',
          ) ??
          extractMeta(r'''<title[^>]*>([^<]+)</title>''');

      final description = extractMeta(
            r'''<meta[^>]*property=["']og:description["'][^>]*content=["']([^"']+)["']''',
          ) ??
          extractMeta(
            r'''<meta[^>]*name=["']description["'][^>]*content=["']([^"']+)["']''',
          );

      String? image = extractMeta(
        r'''<meta[^>]*property=["']og:image["'][^>]*content=["']([^"']+)["']''',
      );

      Uint8List? imageBytes;
      if (image != null && image.isNotEmpty) {
        final resolvedImageUri = initialUri.resolve(image);
        if (await isSafeTarget(resolvedImageUri)) {
          // Fetch image bytes securely through same protected pipeline with shared deadline
          imageBytes = await _fetchImageBytesSecurely(resolvedImageUri, stopwatch);
        } else {
          image = null;
        }
      }

      final data = LinkPreviewData(
        url: url,
        title: title,
        description: description,
        imageUrl: image,
        imageBytes: imageBytes,
      );

      await prefs.setString(
        cacheKey,
        jsonEncode({
          'cachedAt': DateTime.now().millisecondsSinceEpoch,
          'data': data.toJson(),
        }),
      );

      return data;
    } catch (_) {
      return null;
    }
  }

  /// Securely fetch HTML using connection-time IP pinning, strict streaming cancellation,
  /// strict Content-Type checks, and redirect revalidation.
  Future<String?> _fetchHtmlSecurely(Uri initialUri, Stopwatch stopwatch) async {
    HttpClient? client;
    StreamSubscription<List<int>>? subscription;
    try {
      final remainingInitial = _totalTimeout - stopwatch.elapsed;
      if (remainingInitial <= Duration.zero) return null;

      final connectTimeout = remainingInitial < _connectTimeout ? remainingInitial : _connectTimeout;
      client = _createPinningClient(connectTimeout);

      Uri currentUri = initialUri;
      int redirects = 0;

      Future<void> safeDrain(HttpClientResponse res) async {
        final rem = _totalTimeout - stopwatch.elapsed;
        if (rem <= Duration.zero) {
          client?.close(force: true);
          return;
        }
        try {
          await res.drain().timeout(rem, onTimeout: () {
            client?.close(force: true);
          });
        } catch (_) {
          client?.close(force: true);
        }
      }

      while (redirects <= _maxRedirects) {
        final remaining = _totalTimeout - stopwatch.elapsed;
        if (remaining <= Duration.zero) return null;

        final stepTimeout = remaining < _connectTimeout ? remaining : _connectTimeout;

        final request = await client.getUrl(currentUri).timeout(stepTimeout);
        request.followRedirects = false; // Handle redirects manually
        request.headers.set(HttpHeaders.acceptHeader, 'text/html, application/xhtml+xml');
        request.headers.set(HttpHeaders.userAgentHeader, 'TalkMate-LinkPreview/1.0');

        final response = await request.close().timeout(stepTimeout);

        // Check for redirects (301, 302, 303, 307, 308)
        if (response.isRedirect ||
            (response.statusCode >= 300 && response.statusCode < 400)) {
          redirects++;
          if (redirects > _maxRedirects) {
            await safeDrain(response);
            return null;
          }

          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null || location.isEmpty) {
            await safeDrain(response);
            return null;
          }

          final redirectUri = currentUri.resolve(location);
          await safeDrain(response);

          // CRITICAL: Re-validate redirect target to prevent SSRF via open redirect
          if (!await isSafeTarget(redirectUri)) {
            return null;
          }

          currentUri = redirectUri;
          continue;
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          await safeDrain(response);
          return null;
        }

        // Strict Content-Type validation: Missing or non-HTML types are rejected
        final contentType = response.headers.contentType;
        if (contentType == null) {
          await safeDrain(response);
          return null;
        }

        final mime = contentType.mimeType.toLowerCase().trim();
        if (mime != 'text/html' && mime != 'application/xhtml+xml') {
          await safeDrain(response);
          return null;
        }

        // Read stream with real cancellation, hard size limit, and absolute deadline timer
        final builder = BytesBuilder(copy: false);
        final completer = Completer<bool>();

        final streamTimeout = _totalTimeout - stopwatch.elapsed;
        if (streamTimeout <= Duration.zero) return null;

        // REAL DEADLINE TIMER: Guarantees termination even if stream stalls without emitting chunks
        final deadlineTimer = Timer(streamTimeout, () {
          subscription?.cancel();
          client?.close(force: true);
          if (!completer.isCompleted) {
            completer.complete(false);
          }
        });

        subscription = response.listen(
          (chunk) {
            if (stopwatch.elapsed >= _totalTimeout) {
              subscription?.cancel();
              client?.close(force: true);
              if (!completer.isCompleted) completer.complete(false);
              return;
            }

            if (builder.length + chunk.length > _maxResponseBytes) {
              final remainingBytes = _maxResponseBytes - builder.length;
              if (remainingBytes > 0) {
                builder.add(chunk.sublist(0, remainingBytes));
              }
              subscription?.cancel();
              if (!completer.isCompleted) completer.complete(true);
            } else {
              builder.add(chunk);
            }
          },
          onError: (_) {
            if (!completer.isCompleted) completer.complete(false);
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete(true);
          },
          cancelOnError: true,
        );

        final success = await completer.future;
        deadlineTimer.cancel();
        if (!success) {
          return null;
        }

        final bytes = builder.takeBytes();
        if (bytes.isEmpty) return null;

        // Decode HTML using UTF-8 with malformed fallback
        return utf8.decode(bytes, allowMalformed: true);
      }

      return null;
    } catch (_) {
      return null;
    } finally {
      await subscription?.cancel();
      client?.close(force: true);
    }
  }

  /// Securely fetch preview image bytes with connection-time IP pinning, size caps, and cancellation
  Future<Uint8List?> _fetchImageBytesSecurely(Uri initialUri, Stopwatch stopwatch) async {
    HttpClient? client;
    StreamSubscription<List<int>>? subscription;
    try {
      final remainingInitial = _totalTimeout - stopwatch.elapsed;
      if (remainingInitial <= Duration.zero) return null;

      final connectTimeout = remainingInitial < _connectTimeout ? remainingInitial : _connectTimeout;
      client = _createPinningClient(connectTimeout);

      Uri currentUri = initialUri;
      int redirects = 0;

      Future<void> safeDrain(HttpClientResponse res) async {
        final rem = _totalTimeout - stopwatch.elapsed;
        if (rem <= Duration.zero) {
          client?.close(force: true);
          return;
        }
        try {
          await res.drain().timeout(rem, onTimeout: () {
            client?.close(force: true);
          });
        } catch (_) {
          client?.close(force: true);
        }
      }

      while (redirects <= _maxRedirects) {
        final remaining = _totalTimeout - stopwatch.elapsed;
        if (remaining <= Duration.zero) return null;

        final stepTimeout = remaining < _connectTimeout ? remaining : _connectTimeout;

        final request = await client.getUrl(currentUri).timeout(stepTimeout);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, 'image/jpeg, image/png, image/webp, image/gif');
        request.headers.set(HttpHeaders.userAgentHeader, 'TalkMate-LinkPreview/1.0');

        final response = await request.close().timeout(stepTimeout);

        if (response.isRedirect ||
            (response.statusCode >= 300 && response.statusCode < 400)) {
          redirects++;
          if (redirects > _maxRedirects) {
            await safeDrain(response);
            return null;
          }

          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null || location.isEmpty) {
            await safeDrain(response);
            return null;
          }

          final redirectUri = currentUri.resolve(location);
          await safeDrain(response);

          if (!await isSafeTarget(redirectUri)) {
            return null;
          }

          currentUri = redirectUri;
          continue;
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          await safeDrain(response);
          return null;
        }

        // Strict image MIME validation
        final contentType = response.headers.contentType;
        if (contentType == null) {
          await safeDrain(response);
          return null;
        }

        final mime = contentType.mimeType.toLowerCase().trim();
        if (mime != 'image/jpeg' &&
            mime != 'image/png' &&
            mime != 'image/webp' &&
            mime != 'image/gif') {
          await safeDrain(response);
          return null;
        }

        final builder = BytesBuilder(copy: false);
        final completer = Completer<bool>();

        final streamTimeout = _totalTimeout - stopwatch.elapsed;
        if (streamTimeout <= Duration.zero) return null;

        // REAL DEADLINE TIMER: Guarantees termination if image stream stalls without emitting chunks
        final deadlineTimer = Timer(streamTimeout, () {
          subscription?.cancel();
          client?.close(force: true);
          if (!completer.isCompleted) {
            completer.complete(false);
          }
        });

        subscription = response.listen(
          (chunk) {
            if (stopwatch.elapsed >= _totalTimeout) {
              subscription?.cancel();
              client?.close(force: true);
              if (!completer.isCompleted) completer.complete(false);
              return;
            }

            if (builder.length + chunk.length > _maxImageBytes) {
              final remainingBytes = _maxImageBytes - builder.length;
              if (remainingBytes > 0) {
                builder.add(chunk.sublist(0, remainingBytes));
              }
              subscription?.cancel();
              if (!completer.isCompleted) completer.complete(true);
            } else {
              builder.add(chunk);
            }
          },
          onError: (_) {
            if (!completer.isCompleted) completer.complete(false);
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete(true);
          },
          cancelOnError: true,
        );

        final success = await completer.future;
        deadlineTimer.cancel();
        if (!success) {
          return null;
        }

        final bytes = builder.takeBytes();
        return bytes.isNotEmpty ? bytes : null;
      }

      return null;
    } catch (_) {
      return null;
    } finally {
      await subscription?.cancel();
      client?.close(force: true);
    }
  }
}
