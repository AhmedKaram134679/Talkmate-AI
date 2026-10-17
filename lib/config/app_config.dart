class AppConfig {
  // App Information
  static const String appName = 'TalkMate AI';
  static const String appVersion = '1.0.0';
  static const String appBuildNumber = '2';

  // Firebase Configuration (metadata for reference/logging)
  static const String firebaseProjectId = 'talkmate-ai-98b15';
  static const String firebaseStorageBucket =
      'talkmate-ai-98b15.firebasestorage.app';

  // API Configuration
  // Note: baseUrl might track a custom backend if separate from Supabase
  static const String baseUrl = 'https://api.talkmate-ai.com';

  // Supabase Configuration
  static const String supabaseUrl = 'https://icdbbfsjbslzctshxytd.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImljZGJiZnNqYnNsemN0c2h4eXRkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA0Mjg2NjgsImV4cCI6MjA5NjAwNDY2OH0.RXHSRZeTalHY3shnFuoHrkaS2gYT4XqgJzgfmkUschw';

  static const Duration apiTimeout = Duration(seconds: 30);

  // Agora Configuration (Provide real App ID)
  static const String agoraAppId = '38c926e82d7b42398c98b690345b1d6c';

  // File Upload Configuration
  static const int maxFileSize = 50 * 1024 * 1024; // 50MB
  static const List<String> allowedImageTypes = ['jpg', 'jpeg', 'png', 'gif'];
  static const List<String> allowedVideoTypes = ['mp4', 'mov', 'avi'];
  static const List<String> allowedAudioTypes = ['mp3', 'wav', 'aac'];
  static const List<String> allowedDocumentTypes = [
    'pdf',
    'doc',
    'docx',
    'txt'
  ];

  // Chat Configuration
  static const int maxMessageLength = 4000;
  static const int messagesPerPage = 50;
  static const Duration typingIndicatorTimeout = Duration(seconds: 3);

  // Call Configuration
  static const Duration maxCallDuration = Duration(hours: 2);
  static const Duration callTimeout =
      Duration(seconds: 45); // Increased for production reliability

  // WebRTC ICE Servers (STUN/TURN)
  // [IMPORTANT]: Replace TURN credentials with real ones in production (e.g., Twilio, Coturn, etc.)
  static const List<Map<String, dynamic>> iceServers = [
    {
      'urls': [
        'stun:stun1.l.google.com:19302',
        'stun:stun2.l.google.com:19302',
      ],
    },
    // Example TURN configuration (UDP/TCP fallback)
    // {
    //   'urls': 'turn:your-turn-server.com:3478?transport=udp',
    //   'username': 'username',
    //   'credential': 'password',
    // },
    // {
    //   'urls': 'turn:your-turn-server.com:3478?transport=tcp',
    //   'username': 'username',
    //   'credential': 'password',
    // },
  ];

  // Notification Configuration
  // Moved to NotificationChannels in lib/config/notification_channels.dart

  // Cache Configuration
  static const Duration cacheExpiration = Duration(hours: 24);
  static const int maxCacheSize = 100 * 1024 * 1024; // 100MB

  // Security Configuration
  static const Duration sessionTimeout = Duration(hours: 24);
  static const int maxLoginAttempts = 5;
  static const Duration lockoutDuration = Duration(minutes: 15);

  // UI Configuration
  static const double borderRadius = 12.0;
  static const double cardElevation = 2.0;
  static const Duration animationDuration = Duration(milliseconds: 300);

  // Development Configuration
  static const bool isDebugMode = false;
  static const bool enableLogging = true;
  static const bool enableAnalytics = true; // Enabled for Stage Z
  static bool enableFirebase = true;

  // Observability Flags (Stage Z)
  static const bool enablePerformanceMonitoring = true;
  static const bool enableErrorTracking = true;
  static const bool enableUserJourneyTracking = true;

  // Platform Specific
  static const bool enableDesktopFeatures = true;
  static const bool enableMobileFeatures = true;

  // Feature Flags
  static const bool globalCallsEnabled = true; // Emergency Kill-Switch
  static const bool enableVoiceCalls = true;
  static const bool enableVideoCalls = true;
  static const bool enableGroupCalls = true;
  static const bool enableFileSharing = true;
  static const bool enableLocationSharing = false;
  static const bool enableMessageReactions = true;
  static const bool enableMessageForwarding = true;
  static const bool enableMessageEditing = true;
  static const bool enableMessageDeletion = true;

  // Social Features
  static const bool enableUserStatus = true;
  static const bool enableLastSeen = true;
  static const bool enableTypingIndicator = true;
  static const bool enableReadReceipts = true;
  static const bool enableOnlineStatus = true;

  // Temporary Features (for testing without Backend)
  static const bool useLocalStorage = true;
  static const bool enableOfflineMode = true;
  static const bool useMockData = false;

  // Platform Expansion Flags (Stage Y)
  static const bool enableDeepLinks = true;
  static const bool enableShareIntents = true;
  static const bool enableKeyboardShortcuts = true;
  static const bool enablePWAFeatures = true;

  // Web Push VAPID Key
  // WARNING: Set your real VAPID public key here for Web Push notifications to work.
  static const String vapidPublicKey =
      'BLF3jQJLlWRgo1f-mJGfsYsIRBmVHXxJudHwlJi4iwU9lDFHOBsJeFLIyDuewZ3YHDetmH48_RvTtBoRmzG_NNQ';

  /// Central detector for stale sessions in Supabase Realtime / Auth
  /// Specifically targets expired tokens and authentication/session drops,
  /// without over-suppressing generic network timeouts or critical connection drops.
  static bool isStaleSessionError(Object? error) {
    if (error == null) return false;
    final errStr = error.toString().toLowerCase();

    // Must be auth/JWT session expiration or token rejection
    final isAuthStale = (errStr.contains('jwt') && (errStr.contains('expired') || errStr.contains('invalid') || errStr.contains('claim'))) ||
        (errStr.contains('unauthorized') && (errStr.contains('401') || errStr.contains('auth'))) ||
        errStr.contains('token has expired') ||
        errStr.contains('invalid refresh token') ||
        errStr.contains('session from storage has expired');

    // Supabase realtime channel auth drop
    final isRealtimeAuthDrop = errStr.contains('channelerror') &&
        (errStr.contains('access token') || errStr.contains('unauthorized') || errStr.contains('jwt'));

    return isAuthStale || isRealtimeAuthDrop;
  }
}
