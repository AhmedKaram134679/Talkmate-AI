import 'resilience_contracts.dart';

/// FailureClassificationEngine: Rapidly categorizes errors into standardized types.
class FailureClassificationEngine implements IFailureClassifier {
  static final FailureClassificationEngine instance =
      FailureClassificationEngine._();
  FailureClassificationEngine._();

  @override
  FailureType classify(dynamic error, StackTrace? stack) {
    final errorStr = error.toString().toLowerCase();

    if (errorStr.contains('socketexception') || errorStr.contains('network')) {
      return FailureType.network;
    }

    if (errorStr.contains('timeout')) {
      return FailureType.backendTimeout;
    }

    if (errorStr.contains('websocket') ||
        errorStr.contains('connection closed')) {
      return FailureType.webSocketDisconnect;
    }

    if (errorStr.contains('fcm') || errorStr.contains('notification')) {
      return FailureType.notificationDelivery;
    }

    return FailureType.featureCrash;
  }
}
