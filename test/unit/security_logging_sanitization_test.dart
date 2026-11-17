import 'package:flutter_test/flutter_test.dart';
import 'package:talkmate_ai/utils/deep_link_logger.dart';
import 'package:talkmate_ai/utils/forensic_logger.dart';

void main() {
  group('SEC-06: DeepLinkLogger Sanitization Tests', () {
    test('sanitizeMap recursively redacts sensitive keys in nested maps and lists', () {
      final args = <String, dynamic>{
        'recoveryCode': 'super_sensitive_code_98765',
        'chatId': 'safe-uuid-123',
        'authToken': 'bearer-token-abc',
        'nestedMap': {
          'userPassword': 'secret_password',
          'publicFlag': true,
          'email': 'user@example.com',
        },
        'listOfMaps': [
          {'apiKey': 'api_key_123', 'label': 'primary'},
          {'secret': 'jwt_secret', 'count': 42},
        ],
        'nestedList': [
          [
            {'token': 'nested_token', 'safe': 'yes'}
          ]
        ],
      };

      final sanitized = DeepLinkLogger.sanitizeMap(args);

      expect(sanitized['recoveryCode'], equals('[REDACTED]'));
      expect(sanitized['chatId'], equals('safe-uuid-123'));
      expect(sanitized['authToken'], equals('[REDACTED]'));

      final nestedMap = sanitized['nestedMap'] as Map<String, dynamic>;
      expect(nestedMap['userPassword'], equals('[REDACTED]'));
      expect(nestedMap['email'], equals('[REDACTED]'));
      expect(nestedMap['publicFlag'], isTrue);

      final listOfMaps = sanitized['listOfMaps'] as List;
      expect((listOfMaps[0] as Map)['apiKey'], equals('[REDACTED]'));
      expect((listOfMaps[0] as Map)['label'], equals('primary'));
      expect((listOfMaps[1] as Map)['secret'], equals('[REDACTED]'));
      expect((listOfMaps[1] as Map)['count'], equals(42));

      final nestedList = sanitized['nestedList'] as List;
      final innerList = nestedList[0] as List;
      expect((innerList[0] as Map)['token'], equals('[REDACTED]'));
      expect((innerList[0] as Map)['safe'], equals('yes'));
    });

    test('sanitizeValue handles null, primitives, lists, and maps', () {
      expect(DeepLinkLogger.sanitizeValue(null), isNull);
      expect(DeepLinkLogger.sanitizeValue(123), equals(123));
      expect(DeepLinkLogger.sanitizeValue('text'), equals('text'));
      expect(
        DeepLinkLogger.sanitizeValue([
          {'password': 'secret'},
          'normal'
        ]),
        equals([
          {'password': '[REDACTED]'},
          'normal'
        ]),
      );
    });
  });

  group('SEC-07: ForensicLogger Sanitization Tests', () {
    test('sanitizeUrl strips signed tokens, fragments, and query parameters', () {
      const signedUrl =
          'https://icdbbfsjbslzctshxytd.supabase.co/storage/v1/object/sign/talkmate/user_1/photo.jpg?token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.sensitive_signature#section';

      final sanitized = ForensicLogger.sanitizeUrl(signedUrl);

      expect(sanitized, isNot(contains('token=')));
      expect(sanitized, isNot(contains('sensitive_signature')));
      expect(sanitized, isNot(contains('#section')));
      expect(
        sanitized,
        equals(
          'https://icdbbfsjbslzctshxytd.supabase.co/storage/v1/object/sign/talkmate/user_1/photo.jpg',
        ),
      );
    });

    test('sanitizeUrl strictly strips user credentials (username and password)', () {
      const credentialUrl = 'https://admin:super_secret_password@example.com:8080/path/to/resource?query=1';

      final sanitized = ForensicLogger.sanitizeUrl(credentialUrl);

      expect(sanitized, isNot(contains('admin')));
      expect(sanitized, isNot(contains('super_secret_password')));
      expect(sanitized, isNot(contains('query=1')));
      expect(sanitized, equals('https://example.com:8080/path/to/resource'));
    });

    test('sanitizeUrl handles null, empty and clean URLs gracefully', () {
      expect(ForensicLogger.sanitizeUrl(null), equals('N/A'));
      expect(ForensicLogger.sanitizeUrl(''), equals('N/A'));
      expect(ForensicLogger.sanitizeUrl('N/A'), equals('N/A'));

      const cleanUrl =
          'https://icdbbfsjbslzctshxytd.supabase.co/storage/v1/object/public/talkmate/avatar.png';
      expect(ForensicLogger.sanitizeUrl(cleanUrl), equals(cleanUrl));
    });
  });
}
