import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/foundation.dart';

@JS('getWebPushSubscription')
external JSPromise getWebPushSubscriptionJS(JSString vapidPublicKey);

class WebPushInterop {
  static Future<String?> getSubscription(String vapidPublicKey) async {
    try {
      final promise = getWebPushSubscriptionJS(vapidPublicKey.toJS);
      final result = await promise.toDart;

      if (result != null) {
        return (result as JSString).toDart;
      }
      return null;
    } catch (e) {
      debugPrint('WebPushInterop error: $e');
      return null;
    }
  }
}
