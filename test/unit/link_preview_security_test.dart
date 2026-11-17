import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:talkmate_ai/services/link_preview_service.dart';

void main() {
  group('SEC-08: LinkPreviewService SSRF & Local Probing Protection Tests', () {
    test('isPrivateOrLocalAddress identifies IPv4 loopback and private ranges', () {
      expect(LinkPreviewService.isPrivateOrLocalAddress(InternetAddress('127.0.0.1')), isTrue);
      expect(LinkPreviewService.isPrivateOrLocalAddress(InternetAddress('127.1.2.3')), isTrue);
      expect(LinkPreviewService.isPrivateOrLocalAddress(InternetAddress('10.0.0.1')), isTrue);
      expect(LinkPreviewService.isPrivateOrLocalAddress(InternetAddress('10.255.255.254')), isTrue);
      expect(LinkPreviewService.isPrivateOrLocalAddress(InternetAddress('172.16.0.1')), isTrue);
      expect(LinkPreviewService.isPrivateOrLocalAddress(InternetAddress('172.31.255.255')), isTrue);
      expect(LinkPreviewService.isPrivateOrLocalAddress(InternetAddress('192.168.1.1')), isTrue);
      expect(LinkPreviewService.isPrivateOrLocalAddress(InternetAddress('192.168.0.254')), isTrue);
      expect(LinkPreviewService.isPrivateOrLocalAddress(InternetAddress('169.254.169.254')), isTrue); // Cloud metadata
      expect(LinkPreviewService.isPrivateOrLocalAddress(InternetAddress('0.0.0.0')), isTrue);
      expect(LinkPreviewService.isPrivateOrLocalAddress(InternetAddress('100.64.0.1')), isTrue); // CGNAT
      expect(LinkPreviewService.isPrivateOrLocalAddress(InternetAddress('224.0.0.1')), isTrue); // Multicast
      expect(LinkPreviewService.isPrivateOrLocalAddress(InternetAddress('240.0.0.1')), isTrue); // Reserved
    });

    test('isPrivateOrLocalAddress identifies IPv6 loopback, ULA, and mapped ranges', () {
      expect(LinkPreviewService.isPrivateOrLocalAddress(InternetAddress('::1')), isTrue);
      expect(LinkPreviewService.isPrivateOrLocalAddress(InternetAddress('::')), isTrue);
      expect(LinkPreviewService.isPrivateOrLocalAddress(InternetAddress('fc00::1')), isTrue); // ULA
      expect(LinkPreviewService.isPrivateOrLocalAddress(InternetAddress('fd12:3456:789a::1')), isTrue); // ULA
      expect(LinkPreviewService.isPrivateOrLocalAddress(InternetAddress('fe80::1')), isTrue); // Link-local
      expect(LinkPreviewService.isPrivateOrLocalAddress(InternetAddress('ff02::1')), isTrue); // Multicast
      expect(LinkPreviewService.isPrivateOrLocalAddress(InternetAddress('::ffff:192.168.1.1')), isTrue); // Mapped private IPv4
    });

    test('isPrivateOrLocalAddress permits genuine public IPs', () {
      expect(LinkPreviewService.isPrivateOrLocalAddress(InternetAddress('8.8.8.8')), isFalse);
      expect(LinkPreviewService.isPrivateOrLocalAddress(InternetAddress('1.1.1.1')), isFalse);
      expect(LinkPreviewService.isPrivateOrLocalAddress(InternetAddress('2606:4700:4700::1111')), isFalse);
    });

    test('isSafeTarget rejects forbidden schemes and credentials', () async {
      expect(await LinkPreviewService.isSafeTarget(Uri.parse('ftp://example.com/file')), isFalse);
      expect(await LinkPreviewService.isSafeTarget(Uri.parse('file:///etc/passwd')), isFalse);
      expect(await LinkPreviewService.isSafeTarget(Uri.parse('javascript:alert(1)')), isFalse);
      expect(await LinkPreviewService.isSafeTarget(Uri.parse('data:text/html,evil')), isFalse);
      expect(await LinkPreviewService.isSafeTarget(Uri.parse('http://admin:secret@example.com')), isFalse);
    });

    test('isSafeTarget rejects local and private IP addresses directly', () async {
      expect(await LinkPreviewService.isSafeTarget(Uri.parse('http://127.0.0.1/admin')), isFalse);
      expect(await LinkPreviewService.isSafeTarget(Uri.parse('http://192.168.1.1/router')), isFalse);
      expect(await LinkPreviewService.isSafeTarget(Uri.parse('http://10.0.0.1/internal')), isFalse);
      expect(await LinkPreviewService.isSafeTarget(Uri.parse('http://169.254.169.254/latest/meta-data')), isFalse);
      expect(await LinkPreviewService.isSafeTarget(Uri.parse('http://localhost:8080/api')), isFalse);
      expect(await LinkPreviewService.isSafeTarget(Uri.parse('http://app.localhost/')), isFalse);
      expect(await LinkPreviewService.isSafeTarget(Uri.parse('http://server.local/')), isFalse);
      expect(await LinkPreviewService.isSafeTarget(Uri.parse('http://db.internal/')), isFalse);
    });

    test('fetch returns null immediately for dangerous targets without sending network request', () async {
      final result1 = await LinkPreviewService.instance.fetch('http://192.168.1.1/');
      expect(result1, isNull);

      final result2 = await LinkPreviewService.instance.fetch('http://127.0.0.1:3000/');
      expect(result2, isNull);

      final result3 = await LinkPreviewService.instance.fetch('file:///C:/Windows/win.ini');
      expect(result3, isNull);

      final result4 = await LinkPreviewService.instance.fetch('http://admin:pass@example.com');
      expect(result4, isNull);
    });
  });
}
