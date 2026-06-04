import 'package:get/get.dart';
import 'package:talkmate_ai/config/app_config.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_block_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_call_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_chat_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_friend_request_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_friendship_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_local_message_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_message_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_notification_repository.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_typing_repository.dart';
// Contracts
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';
import 'package:talkmate_ai/data/repositories/local/local_message_repository.dart';
import 'package:talkmate_ai/data/repositories/mocks/mock_call_repository.dart';
import 'package:talkmate_ai/data/repositories/mocks/mock_chat_repository.dart';
import 'package:talkmate_ai/data/repositories/mocks/mock_friendship_repository.dart';
import 'package:talkmate_ai/data/repositories/mocks/mock_message_repository.dart';
import 'package:talkmate_ai/data/repositories/mocks/mock_notification_repository.dart';
// Mock implementations (in-memory)
import 'package:talkmate_ai/data/repositories/mocks/mock_user_repository.dart';
import 'package:talkmate_ai/data/repositories/supabase/supabase_block_repository.dart';
import 'package:talkmate_ai/data/repositories/supabase/supabase_call_repository.dart';
import 'package:talkmate_ai/data/repositories/supabase/supabase_chat_repository.dart';
import 'package:talkmate_ai/data/repositories/supabase/supabase_friend_request_repository.dart';
import 'package:talkmate_ai/data/repositories/supabase/supabase_friendship_repository.dart';
import 'package:talkmate_ai/data/repositories/supabase/supabase_message_repository.dart';
import 'package:talkmate_ai/data/repositories/supabase/supabase_notification_repository.dart';
import 'package:talkmate_ai/data/repositories/supabase/supabase_typing_repository.dart';
// Real implementations (Supabase / Firestore)
import 'package:talkmate_ai/data/repositories/supabase/supabase_user_repository.dart';
// Services
import 'package:talkmate_ai/data/services/chat_sync_engine.dart';

class DataBindings {
  static void init() {
    if (AppConfig.useMockData) {
      // Mocks
      Get.put<IUserRepository>(MockUserRepository.instance, permanent: true);
      Get.put<IChatRepository>(MockChatRepository.instance, permanent: true);
      Get.put<IMessageRepository>(MockMessageRepository.instance,
          permanent: true);
      Get.put<IFriendshipRepository>(MockFriendshipRepository.instance,
          permanent: true);
      Get.put<ITypingRepository>(SupabaseTypingRepository(),
          permanent: true); // Fallback to supabase even in mock for now
      Get.put<INotificationRepository>(MockNotificationRepository.instance,
          permanent: true);
      Get.put<ICallRepository>(MockCallRepository.instance, permanent: true);
      Get.put<ILocalMessageRepository>(LocalMessageRepository(),
          permanent: true);
    } else {
      // Supabase-backed repos (Primary)
      Get.put<IUserRepository>(SupabaseUserRepository(), permanent: true);
      Get.put<IChatRepository>(SupabaseChatRepository(), permanent: true);
      Get.put<IMessageRepository>(SupabaseMessageRepository(), permanent: true);
      Get.put<IFriendshipRepository>(SupabaseFriendshipRepository(),
          permanent: true);
      Get.put<ITypingRepository>(SupabaseTypingRepository(), permanent: true);
      Get.put<INotificationRepository>(SupabaseNotificationRepository(),
          permanent: true);
      Get.put<ICallRepository>(SupabaseCallRepository(), permanent: true);
      Get.put<IBlockRepository>(SupabaseBlockRepository(), permanent: true);
      Get.put<IFriendRequestRepository>(SupabaseFriendRequestRepository(),
          permanent: true);
      Get.put<ILocalMessageRepository>(LocalMessageRepository(),
          permanent: true);
    }

    // Services (Common for both Mock/Supabase)
    Get.put(ChatSyncEngine(), permanent: true);
  }
}
