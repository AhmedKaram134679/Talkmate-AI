import 'package:flutter_test/flutter_test.dart';
import 'package:talkmate_ai/controllers/chat_controller.dart';

void main() {
  group('extractFirstUrl', () {
    test('returns empty for no urls', () {
      expect(ChatController.extractFirstUrl('hello world'), '');
    });
    test('extracts http url', () {
      expect(ChatController.extractFirstUrl('check http://example.com now'), 'http://example.com');
    });
    test('extracts https url with path', () {
      expect(
        ChatController.extractFirstUrl('go to https://example.com/page?q=1 and more'),
        'https://example.com/page?q=1',
      );
    });
  });
}
