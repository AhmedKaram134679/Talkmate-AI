import 'package:flutter_test/flutter_test.dart';
import 'package:talkmate_ai/utils/deep_link_logger.dart';
import 'package:talkmate_ai/utils/forensic_logger.dart';

void main() {
  group('SEC-06: DeepLinkLogger Sanitization Tests', () {
    test('sanitizeUri redacts sensitive query parameters and tokens', () {
      final uri = Uri.parse(
        'talkmate://auth/reset-password?code=pkce_secret_token_123456&source=email',
      );

      final sanitized = DeepLinkLogger.sanitizeUri(uri);

      expect(sanitized, isNot(contains('pkce_secret_token_123456')));
      expect(sanitized, contains('code=%5BREDACTED%5D'));
      expect(sanitized, contains('source=email'));
    });

    test('sanitizeUri redacts fragment authentication tokens', () {
      final uri = Uri.parse(
        'talkmate://auth/callback#access_token=secret_jwt_token&refresh_token=secret_refresh_token',
      );

      final sanitized = DeepLinkLogger.sanitizeUri(uri);

      expect(sanitized, isNot(contains('secret_jwt_token')));
      expect(sanitized, isNot(contains('secret_refresh_token')));
      expect(sanitized, contains('#%5BREDACTED%5D'));
    });

    test('sanitizeMap redacts recoveryCode, tokens, passwords and secrets', () {
      final args = <String, dynamic>{
        'recoveryCode': 'super_sensitive_code_98765',
        'chatId': 'safe-uuid-123',
        'authToken': 'bearer-token-abc',
        'nested': {
          'userPassword': 'secret_password',
          'publicFlag': true,
        },
      };

      final sanitized = DeepLinkLogger.sanitizeMap(args);

      expect(sanitized['recoveryCode'], equals('[REDACTED]'));
      expect(sanitized['chatId'], equals('safe-uuid-123'));
      expect(sanitized['authToken'], equals('[REDACTED]'));

      final nested = sanitized['nested'] as Map<String, dynamic>;
      expect(nested['userPassword'], equals('[REDACTED]'));
      expect(nested['publicFlag'], isTrue);
    });
  });

  group('SEC-07: ForensicLogger Sanitization Tests', () {
    test('sanitizeUrl strips signed tokens and query parameters from remote URLs', () {
      const signedUrl =
          'https://icdbbfsjbslzctshxytd.supabase.co/storage/v1/object/sign/talkmate/user_1/photo.jpg?token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.sensitive_signature';

      final sanitized = ForensicLogger.sanitizeUrl(signedUrl);

      expect(sanitized, isNot(contains('token=')));
      expect(sanitized, isNot(contains('sensitive_signature')));
      expect(
        sanitized,
        equals(
          'https://icdbbfsjbslzctshxytd.supabase.co/storage/v1/object/sign/talkmate/user_1/photo.jpg',
        ),
      );
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
