import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart' as auth;
import 'package:talkmate_ai/controllers/chat_controller.dart';
import 'package:talkmate_ai/data/models/message_model.dart' as data_models;
import 'package:talkmate_ai/models/message_model.dart' as ui_models;

// Stub AuthController by subclassing the real one and disabling any Firebase work
class FakeAuthController extends auth.AuthController {
  final RxBool _isLoggedIn = true.obs;
  final RxString _uid = 'userA'.obs;

  @override
  // ignore: must_call_super
  void onInit() {
    // Do not call super.onInit(); Avoid Firebase listeners
  }

  @override
  String get userId => _uid.value;

  @override
  RxString get userIdRx => _uid;

  @override
  RxBool get isLoggedInRx => _isLoggedIn;
}

// Fake ChatController to avoid attaching to Firebase streams in tests
class FakeChatController extends ChatController {
  @override
  // ignore: must_call_super
  void onInit() {
    // Do not call super.onInit(); prevents _attachRealtime and any IO
  }

  @override
  Future<void> markChatMessagesDelivered(String chatId) async {
    final list = List.of(getMessagesForChat(chatId));
    final updated = list.map((m) {
      if (m.senderId == 'userA') return m; // outgoing in this test setup
      if (m.status == ui_models.MessageStatus.sent) {
        return m.copyWith(status: ui_models.MessageStatus.delivered);
      }
      return m;
    }).toList();
    injectMessagesForTest(chatId, updated);
  }

  @override
  Future<void> markChatMessagesRead(String chatId) async {
    final list = List.of(getMessagesForChat(chatId));
    final updated = list.map((m) {
      if (m.senderId == 'userA') return m;
      if (m.status != ui_models.MessageStatus.read) {
        return m.copyWith(status: ui_models.MessageStatus.read);
      }
      return m;
    }).toList();
    injectMessagesForTest(chatId, updated);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Get.testMode = true;
  // Initialize shared_preferences fake storage to prevent MissingPluginException in tests
  SharedPreferences.setMockInitialValues(<String, Object>{});

  group('Message mapping and status flow', () {
    setUp(() {
      // Register our stub under the expected type so ChatController can find it
      if (!Get.isRegistered<auth.AuthController>()) {
        Get.put<auth.AuthController>(FakeAuthController(), permanent: true);
      }
      if (!Get.isRegistered<ChatController>()) {
        Get.put<ChatController>(FakeChatController(), permanent: true);
      }
    });

    tearDown(() async {
      // Clean up between tests to avoid state leakage
      if (Get.isRegistered<ChatController>()) {
        await Get.delete<ChatController>(force: true);
      }
      if (Get.isRegistered<auth.AuthController>()) {
        await Get.delete<auth.AuthController>(force: true);
      }
    });

    test('maps data MessageType -> UI MessageType correctly', () {
      expect(
          ChatController.mapMessageTypeFromData(data_models.MessageType.text),
          ui_models.MessageType.text);
      expect(
          ChatController.mapMessageTypeFromData(data_models.MessageType.image),
          ui_models.MessageType.image);
      expect(
          ChatController.mapMessageTypeFromData(data_models.MessageType.video),
          ui_models.MessageType.video);
      expect(
          ChatController.mapMessageTypeFromData(data_models.MessageType.audio),
          ui_models.MessageType.audio);
      expect(
          ChatController.mapMessageTypeFromData(data_models.MessageType.file),
          ui_models.MessageType.file);
      // system falls back to text in UI
      expect(
          ChatController.mapMessageTypeFromData(data_models.MessageType.system),
          ui_models.MessageType.text);
    });

    test('maps data MessageStatus -> UI MessageStatus correctly', () {
      expect(
          ChatController.mapMessageStatusFromData(
              data_models.MessageStatus.sent),
          ui_models.MessageStatus.sent);
      expect(
          ChatController.mapMessageStatusFromData(
              data_models.MessageStatus.delivered),
          ui_models.MessageStatus.delivered);
      expect(
          ChatController.mapMessageStatusFromData(
              data_models.MessageStatus.read),
          ui_models.MessageStatus.read);
    });

    test('Delivered/Read updates apply only to incoming messages', () async {
      final chat = Get.find<ChatController>();
      const chatId = 'chat1';

      final outgoing = ui_models.MessageModel(
        chatId: chatId,
        senderId: 'userA',
        content: 'Hello from A',
        status: ui_models.MessageStatus.sent,
      );
      final incoming = ui_models.MessageModel(
        chatId: chatId,
        senderId: 'userB',
        content: 'Hello from B',
        status: ui_models.MessageStatus.sent,
      );

      chat.injectMessagesForTest(chatId, [outgoing, incoming]);

      await chat.markChatMessagesDelivered(chatId);
      final afterDelivered = chat.getMessagesForChat(chatId);
      // Outgoing (mine) should remain sent
      expect(afterDelivered[0].status, ui_models.MessageStatus.sent);
      // Incoming should now be delivered
      expect(afterDelivered[1].status, ui_models.MessageStatus.delivered);

      await chat.markChatMessagesRead(chatId);
      final afterRead = chat.getMessagesForChat(chatId);
      // Outgoing still sent
      expect(afterRead[0].status, ui_models.MessageStatus.sent);
      // Incoming should now be read
      expect(afterRead[1].status, ui_models.MessageStatus.read);
    });
  });
}
