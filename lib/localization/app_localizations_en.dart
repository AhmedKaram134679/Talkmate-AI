// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'TalkMate AI';

  @override
  String get search => 'Search';

  @override
  String get chats => 'Chats';

  @override
  String get calls => 'Calls';

  @override
  String get groups => 'Groups';

  @override
  String get profile => 'Profile';

  @override
  String get settings => 'Settings';

  @override
  String get login => 'Login';

  @override
  String get register => 'Register';

  @override
  String get continueAsGuest => 'Continue as Guest';

  @override
  String get logout => 'Logout';

  @override
  String get welcome => 'Welcome to TalkMate AI';

  @override
  String get comingSoon => 'This feature will be added soon';

  @override
  String get tooltipChangeTheme => 'Change theme';

  @override
  String get tooltipChangeLanguage => 'Change language';

  @override
  String get snackTestTitle => 'Test';

  @override
  String snackTestMessage(int count) {
    return 'Tapped $count times! 🎉';
  }

  @override
  String get guest => 'Guest';

  @override
  String get appTagline => 'Smart chat and calls app';

  @override
  String get runningOk => '✅ Running successfully!';

  @override
  String get appStatus => 'App status:';

  @override
  String get platform => 'Platform';

  @override
  String get theme => 'Theme';

  @override
  String get language => 'Language';

  @override
  String get user => 'User';

  @override
  String get loggedIn => 'Logged in';

  @override
  String get clickCount => 'Click count';

  @override
  String get availableFeatures => 'Available features:';

  @override
  String get instantMessaging => 'Instant messaging';

  @override
  String get voiceCalls => 'Voice calls';

  @override
  String get videoCalls => 'Video calls';

  @override
  String get groupsFeature => 'Groups';

  @override
  String get securityPrivacy => 'Security and privacy';

  @override
  String get settingsHeader => 'Settings:';

  @override
  String get deleteMessageTitle => 'Delete message';

  @override
  String get deleteMessageConfirm =>
      'Are you sure you want to delete this message?';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get online => 'Online';

  @override
  String get statusInCall => 'In a call';

  @override
  String get statusInRoomVoice => 'In voice room';

  @override
  String get statusInRoomVideo => 'In video room';

  @override
  String get appearanceLanguage => 'Appearance & Language';

  @override
  String get darkMode => 'Dark mode';

  @override
  String get darkModeHint => 'Enable the app\'s dark theme';

  @override
  String get arabic => 'Arabic';

  @override
  String get english => 'English';

  @override
  String get notifications => 'Notifications';

  @override
  String get enableNotifications => 'Enable notifications';

  @override
  String get newMessagesNotifications => 'Receive new message notifications';

  @override
  String get notificationSound => 'Notification sound';

  @override
  String get playSoundOnNotifications => 'Play sound when notifications arrive';

  @override
  String get notificationVibration => 'Notification vibration';

  @override
  String get vibrateOnNotifications => 'Vibrate the device on notifications';

  @override
  String get testNotifications => 'Test notifications';

  @override
  String get sendTestNotification => 'Send a test notification';

  @override
  String get privacySecurity => 'Privacy & Security';

  @override
  String get password => 'Password';

  @override
  String get changePassword => 'Change password';

  @override
  String get blockedUsers => 'Blocked users';

  @override
  String get manageBlockedUsers => 'Manage blocked list';

  @override
  String get privacySettings => 'Privacy settings';

  @override
  String get whoCanSeeInfo => 'Who can see your info';

  @override
  String get aboutApp => 'About the app';

  @override
  String get appInfo => 'App info';

  @override
  String appVersionLabel(String version) {
    return 'Version $version';
  }

  @override
  String developerLabel(String name) {
    return 'Developer: $name';
  }

  @override
  String get helpSupport => 'Help & support';

  @override
  String get faqSupport => 'FAQs and support';

  @override
  String get termsOfUse => 'Terms of use';

  @override
  String get readTerms => 'Read terms and conditions';

  @override
  String get privacyPolicy => 'Privacy policy';

  @override
  String get howWeProtectData => 'How we protect your data';

  @override
  String get account => 'Account';

  @override
  String get logoutHint => 'Sign out from the current account';

  @override
  String get deleteAccount => 'Delete account';

  @override
  String get deleteAccountPermanently => 'Delete the account permanently';

  @override
  String get chooseLanguage => 'Choose language';

  @override
  String get ok => 'OK';

  @override
  String get confirmLogout => 'Are you sure you want to log out?';

  @override
  String get confirmDeleteAccount =>
      'Are you sure you want to delete the account? This action cannot be undone.';

  @override
  String get newChat => 'New chat';

  @override
  String get searchChatsHint => 'Search chats...';

  @override
  String get noChatsYet => 'No chats yet';

  @override
  String get startNewChatWithFriends => 'Start a new chat with your friends';

  @override
  String get startNewChat => 'Start a new chat';

  @override
  String get archive => 'Archive';

  @override
  String get unarchive => 'Unarchive';

  @override
  String get mute => 'Mute';

  @override
  String get unmute => 'Unmute';

  @override
  String get pin => 'Pin';

  @override
  String get unpin => 'Unpin';

  @override
  String get newChatTitle => 'New chat';

  @override
  String get chooseChatType => 'Choose the type of chat you want to create';

  @override
  String get individualChat => 'Individual chat';

  @override
  String get group => 'Group';

  @override
  String get createIndividualChat => 'Create individual chat';

  @override
  String get personNameHint => 'Person name';

  @override
  String get create => 'Create';

  @override
  String get createGroup => 'Create group';

  @override
  String get groupNameHint => 'Group name';

  @override
  String get deleteChat => 'Delete chat';

  @override
  String get deleteChatTitle => 'Delete chat';

  @override
  String deleteChatConfirmWithName(Object name) {
    return 'Are you sure you want to delete the chat with $name?';
  }

  @override
  String confirmDeleteChatWithName(Object name) {
    return 'Delete chat with $name';
  }

  @override
  String get searchInChatHint => 'Search in chat...';

  @override
  String get typing => 'typing...';

  @override
  String get searchOptions => 'Search options';

  @override
  String get matchCase => 'Match case';

  @override
  String get wholeWord => 'Whole word';

  @override
  String get useRegex => 'Use Regex';

  @override
  String get previous => 'Previous';

  @override
  String get next => 'Next';

  @override
  String get closeSearch => 'Close search';

  @override
  String get notificationsEnabled => 'Notifications enabled';

  @override
  String get notificationsDisabled => 'Notifications disabled';

  @override
  String get notificationSoundEnabled => 'Notification sound enabled';

  @override
  String get notificationSoundDisabled => 'Notification sound disabled';

  @override
  String get notificationVibrationEnabled => 'Notification vibration enabled';

  @override
  String get notificationVibrationDisabled => 'Notification vibration disabled';

  @override
  String get notificationTitle => 'Notification';

  @override
  String openChatFromNotificationWithId(Object chatId) {
    return 'Open chat from notification: $chatId';
  }

  @override
  String get messageTypeImage => '📷 Image';

  @override
  String get messageTypeVideo => '🎥 Video';

  @override
  String get messageTypeAudio => '🎵 Voice message';

  @override
  String get messageTypeFile => '📎 File';

  @override
  String get messageTypeLocation => '📍 Location';

  @override
  String get messageTypeContact => '👤 Contact';

  @override
  String incomingCallTitleWithType(Object callType) {
    return 'Incoming $callType call';
  }

  @override
  String fromCallerName(Object callerName) {
    return 'From $callerName';
  }

  @override
  String get callsChannelName => 'TalkMate Calls';

  @override
  String get callsChannelDescription => 'Incoming call notifications';

  @override
  String get answer => 'Answer';

  @override
  String get decline => 'Decline';

  @override
  String get testChannelName => 'Notifications Test';

  @override
  String get testChannelDescription => 'Notifications test channel';

  @override
  String get notificationsTestTitle => 'Notifications Test';

  @override
  String get notificationsTestBody =>
      'This is a test notification from TalkMate AI 🚀';

  @override
  String get sent => 'Sent';

  @override
  String get testNotificationSent => 'Test notification sent successfully';

  @override
  String get error => 'Error';

  @override
  String testNotificationFailedWithError(Object error) {
    return 'Failed to send test notification: $error';
  }

  @override
  String get testNotificationDialogTitle => 'Test Notification';

  @override
  String get testNotificationDialogBody =>
      'Notifications system works properly!';

  @override
  String get testNotificationShown =>
      'Test notification displayed successfully';

  @override
  String get updated => 'Updated';

  @override
  String get chatsUpdatedSuccessfully => 'Chats updated successfully';

  @override
  String get updateChatsError => 'An error occurred while updating chats';

  @override
  String chatCreatedWithName(Object name) {
    return 'Chat created with $name';
  }

  @override
  String get newGroup => 'New group';

  @override
  String groupCreatedWithName(Object name) {
    return 'Group $name created';
  }

  @override
  String get deleted => 'Deleted';

  @override
  String get chatDeleted => 'Chat deleted';

  @override
  String get archived => 'Archived';

  @override
  String get unarchived => 'Unarchived';

  @override
  String get chatArchived => 'Chat archived';

  @override
  String get chatUnarchived => 'Chat unarchived';

  @override
  String get muted => 'Muted';

  @override
  String get unmuted => 'Unmuted';

  @override
  String get chatMuted => 'Notifications for this chat have been muted';

  @override
  String get chatUnmuted => 'Chat notifications unmuted';

  @override
  String get cleared => 'Cleared';

  @override
  String get allChatMessagesCleared => 'All chat messages cleared';

  @override
  String get messageDeleted => 'This message was deleted';

  @override
  String get videoCall => 'Video call';

  @override
  String get voiceCall => 'Voice call';

  @override
  String get viewProfile => 'View Profile';

  @override
  String get searchInChat => 'Search in chat';

  @override
  String get muteNotifications => 'Mute notifications';

  @override
  String get clearChat => 'Clear chat';

  @override
  String get startConversation => 'Start the conversation';

  @override
  String get writeFirstMessage =>
      'Write your first message to start the conversation';

  @override
  String get chatToday => 'Today';

  @override
  String get chatYesterday => 'Yesterday';

  @override
  String get attachFile => 'Attach file';

  @override
  String get emoji => 'Emoji';

  @override
  String get typeMessageHint => 'Type a message...';

  @override
  String get messageSentTitle => 'Sent';

  @override
  String get messageSentSuccess => 'Message sent successfully';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileViewComingSoon => 'Profile view will be added soon';

  @override
  String get attachFileTitle => 'Attach file';

  @override
  String get photo => 'Photo';

  @override
  String get video => 'Video';

  @override
  String get file => 'File';

  @override
  String get location => 'Location';

  @override
  String get attachImageTitle => 'Attach photo';

  @override
  String get attachVideoTitle => 'Attach video';

  @override
  String get attachFileActionTitle => 'Attach file';

  @override
  String get attachLocationTitle => 'Attach location';

  @override
  String get attachImageComingSoon =>
      'Photo attachment feature will be added soon';

  @override
  String get attachVideoComingSoon =>
      'Video attachment feature will be added soon';

  @override
  String get attachFileComingSoon =>
      'File attachment feature will be added soon';

  @override
  String get attachLocationComingSoon =>
      'Location attachment feature will be added soon';

  @override
  String get clearChatTitle => 'Clear chat';

  @override
  String get clearChatConfirm =>
      'Are you sure you want to clear all messages in this chat?';

  @override
  String get clear => 'Clear';

  @override
  String get clearedTitle => 'Cleared';

  @override
  String get chatCleared => 'All chat messages have been cleared';

  @override
  String get messageOptions => 'Message options';

  @override
  String get reply => 'Reply';

  @override
  String get copy => 'Copy';

  @override
  String get copiedTitle => 'Copied';

  @override
  String get messageCopied => 'Message copied';

  @override
  String get edit => 'Edit';

  @override
  String get editMessageTitle => 'Edit message';

  @override
  String get featureComingSoon => 'This feature will be added soon';

  @override
  String get deletedMessagePlaceholder => 'Deleted message';

  @override
  String get loginSuccessTitle => 'Login successful';

  @override
  String get loginErrorTitle => 'Login error';

  @override
  String get loginErrorMessage =>
      'An error occurred during login. Please try again.';

  @override
  String get registrationSuccessTitle => 'Account created successfully';

  @override
  String get registrationErrorTitle => 'Registration error';

  @override
  String get registrationErrorMessage =>
      'An error occurred during registration. Please try again.';

  @override
  String get loggedOutTitle => 'Logged out';

  @override
  String get loggedOutMessage => 'You have been logged out successfully';

  @override
  String get profileUpdatedTitle => 'Profile updated';

  @override
  String get changesSavedSuccessfully => 'Changes saved successfully';

  @override
  String get updateErrorTitle => 'Error';

  @override
  String get updateProfileErrorMessage =>
      'An error occurred while updating the profile';

  @override
  String get guestLoginTitle => 'Guest login';

  @override
  String get guestWelcomeMessage => 'Welcome as a guest to TalkMate AI';

  @override
  String get searchHistoryCleared => 'Search history cleared';

  @override
  String get openChatTitle => 'Open chat';

  @override
  String openChatWithName(Object name) {
    return 'Open chat with $name';
  }

  @override
  String get goToMessageTitle => 'Go to message';

  @override
  String goToMessageBody(Object content) {
    return 'Go to message: $content';
  }

  @override
  String get viewUserTitle => 'View user';

  @override
  String viewUserProfileWithName(Object name) {
    return 'View $name\'s profile';
  }

  @override
  String get all => 'All';

  @override
  String get chatsLabel => 'Chats';

  @override
  String get messagesLabel => 'Messages';

  @override
  String get usersLabel => 'Users';

  @override
  String get email => 'Email';

  @override
  String get name => 'Name';

  @override
  String get pleaseEnterEmail => 'Please enter your email';

  @override
  String get invalidEmail => 'Invalid email address';

  @override
  String get pleaseEnterPassword => 'Please enter password';

  @override
  String get pleaseEnterName => 'Please enter your name';

  @override
  String minChars(int count) {
    return 'At least $count characters required';
  }

  @override
  String searchInAppHint(String appName) {
    return 'Search in $appName...';
  }

  @override
  String get recentSearches => 'Recent searches';

  @override
  String get clearAll => 'Clear all';

  @override
  String get noSearchHistory => 'No search history';

  @override
  String get startSearchingToSave => 'Start searching to save your queries';

  @override
  String get searching => 'Searching...';

  @override
  String get noResults => 'No results';

  @override
  String get tryDifferentKeywordsOrType =>
      'Try different keywords or change the search type';

  @override
  String get now => 'Now';

  @override
  String minutesAbbrev(int count) {
    return '${count}m';
  }

  @override
  String hoursAbbrev(int count) {
    return '${count}h';
  }

  @override
  String daysAbbrev(int count) {
    return '${count}d';
  }

  @override
  String get endCall => 'End';

  @override
  String get turnCameraOn => 'Turn camera on';

  @override
  String get turnCameraOff => 'Turn camera off';

  @override
  String get speaker => 'Speaker';

  @override
  String get addParticipant => 'Add participant';

  @override
  String get dialPad => 'Dial pad';

  @override
  String get connecting => 'Connecting';

  @override
  String get live => 'Live';

  @override
  String get ended => 'Ended';

  @override
  String get missed => 'Missed call';

  @override
  String get rejected => 'Rejected';

  @override
  String get send => 'Send';

  @override
  String get noBlockedUsers => 'No blocked users';

  @override
  String get block => 'Block';

  @override
  String get unblock => 'Unblock';

  @override
  String get enterUserIdToBlock => 'Enter userId to block';

  @override
  String get flipCamera => 'Flip camera';

  @override
  String get shareScreen => 'Share screen';

  @override
  String get authErrorInvalidCredentials =>
      'Invalid email or password. Please check your credentials and try again.';

  @override
  String get authErrorEmailNotConfirmed =>
      'Your email is not confirmed yet. Please check your inbox for the confirmation link.';

  @override
  String get authErrorUserAlreadyExists =>
      'An account with this email already exists. Try logging in instead.';

  @override
  String get authErrorTooManyRequests =>
      'Too many attempts. Please wait a few seconds and try again.';

  @override
  String get authErrorNetwork =>
      'Network error. Please check your internet connection.';

  @override
  String get authErrorUnknown =>
      'An unexpected error occurred. Please try again later.';

  @override
  String get onboardingTitle1 => 'Ultra Secure & Fast';

  @override
  String get onboardingDesc1 =>
      'We use the latest Supabase tech to ensure your messages arrive instantly with top-tier encryption.';

  @override
  String get onboardingTitle2 => 'Works Even Offline';

  @override
  String get onboardingDesc2 =>
      'Smart sync system saves messages locally and sends them automatically when connection returns.';

  @override
  String get onboardingTitle3 => 'Your Privacy is Our Priority';

  @override
  String get onboardingDesc3 =>
      'Full control over your data and visibility settings. Your chats belong to you only.';

  @override
  String get getStarted => 'Get Started';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get successMomentTitle => 'Congratulations! 🎉';

  @override
  String get successMomentMessage =>
      'You successfully sent your first message. Enjoy a unique chat experience with TalkMate AI.';

  @override
  String resumeChatWith(String name) {
    return 'Resume chat with $name';
  }

  @override
  String get welcomeToAdvancedMessaging => 'Welcome to Advanced Messaging';

  @override
  String get startFirstChatHint =>
      'Start your first chat now and experience instant sync and privacy.';

  @override
  String get startNewChatAction => 'Start New Chat';

  @override
  String get accept => 'Accept';

  @override
  String get friendRequests => 'Friend Requests';

  @override
  String get incoming => 'Incoming';

  @override
  String get outgoing => 'Outgoing';

  @override
  String get history => 'History';

  @override
  String get noIncomingRequests => 'No incoming requests';

  @override
  String get noOutgoingRequests => 'No outgoing requests';

  @override
  String get noRequestHistory => 'No request history';

  @override
  String get editProfile => 'Edit Profile';

  @override
  String get friends => 'Friends';

  @override
  String get noGroupsYet => 'No groups yet';

  @override
  String get createYourFirstGroup => 'Create your first group';

  @override
  String get bio => 'Bio';

  @override
  String get joinDate => 'Join Date';

  @override
  String get noBio => 'No bio yet';

  @override
  String get member => 'Member';

  @override
  String get fullName => 'Full Name';

  @override
  String get saveChanges => 'Save Changes';

  @override
  String get welcomeBack => 'Welcome back';

  @override
  String get loginToContinue => 'Login to continue';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get or => 'Or';

  @override
  String get dontHaveAccount => 'Don\'t have an account?';

  @override
  String verificationSent(int seconds) {
    return 'Verification link sent. Wait ${seconds}s.';
  }

  @override
  String get resendVerification => 'Resend verification link';

  @override
  String get createAccountHeader => 'Create new account';

  @override
  String get joinUs => 'Join us and start chatting';

  @override
  String get statusOnline => 'Online';

  @override
  String get statusOffline => 'Offline';

  @override
  String get statusAway => 'Away';

  @override
  String get statusBusy => 'Busy';

  @override
  String get msgTypeText => 'Text';

  @override
  String get msgTypeImage => 'Image';

  @override
  String get msgTypeVideo => 'Video';

  @override
  String get msgTypeAudio => 'Audio';

  @override
  String get msgTypeFile => 'File';

  @override
  String get msgTypeLocation => 'Location';

  @override
  String get msgTypeContact => 'Contact';

  @override
  String get msgTypeChat => 'Chat';

  @override
  String get msgTypeCall => 'Call';

  @override
  String get msgStatusPending => 'Sending...';

  @override
  String get msgStatusSent => 'Sent';

  @override
  String get msgStatusDelivered => 'Delivered';

  @override
  String get msgStatusRead => 'Read';

  @override
  String get msgStatusFailed => 'Failed';

  @override
  String get chatTypeIndividual => 'Individual Chat';

  @override
  String get chatTypeGroup => 'Group';

  @override
  String get chatTypeChannel => 'Channel';

  @override
  String get chatTypeChat => 'Chat';

  @override
  String get noMessages => 'No messages';

  @override
  String get timeNow => 'Now';

  @override
  String timeMinutes(int count) {
    return '$count min';
  }

  @override
  String timeHours(int count) {
    return '$count h';
  }

  @override
  String timeDays(int count) {
    return '$count d';
  }

  @override
  String timeWeeks(int count) {
    return '$count w';
  }

  @override
  String get youDeletedMessage => 'You deleted this message';

  @override
  String deletedBy(String name) {
    return 'Deleted by $name';
  }

  @override
  String get imageLoadError => 'Failed to load image';

  @override
  String get stickerUploadFailed => 'Sticker upload failed';

  @override
  String get stickerUploadError => 'Failed to upload sticker';

  @override
  String get lastSeen => 'Last seen';

  @override
  String minutesAgo(int minutes) {
    return '$minutes min ago';
  }

  @override
  String todayAt(String time) {
    return 'Today at $time';
  }

  @override
  String yesterdayAt(String time) {
    return 'Yesterday at $time';
  }

  @override
  String dateTimeAt(String date, String time) {
    return '$date at $time';
  }

  @override
  String throttledMessagesCount(int count) {
    return '$count messages';
  }

  @override
  String selectedCountLabel(int count) {
    return '$count selected';
  }

  @override
  String typingSingle(String user) {
    return '$user is typing...';
  }

  @override
  String typingDouble(String user1, String user2) {
    return '$user1 and $user2 are typing...';
  }

  @override
  String typingMultiple(int count) {
    return '$count people are typing...';
  }

  @override
  String reactionsCount(int count) {
    return '$count reactions';
  }

  @override
  String deleteMessagesTitle(int count) {
    return 'Delete $count messages?';
  }

  @override
  String incomingCallFrom(String name) {
    return 'Incoming call from $name';
  }

  @override
  String callTypeLabel(String type) {
    return '$type Call';
  }

  @override
  String get voice => 'Voice';

  @override
  String get chooseFriend => 'Choose Friend';

  @override
  String get noFriendsToSelect => 'No friends to select';

  @override
  String get confirm => 'Confirm';

  @override
  String get pleaseLoginToViewCalls => 'Please login to view calls';

  @override
  String get noCallsMatchSearch => 'No calls match your search';

  @override
  String get searchInHistoryHint => 'Search call history...';

  @override
  String get noCallsYet => 'No calls yet';

  @override
  String get alert => 'Alert';

  @override
  String get profileDataLoadError => 'Failed to load profile data';

  @override
  String get imageSelectionError => 'Image selection failed';

  @override
  String get imageUploadError => 'Image upload failed';

  @override
  String get profileUpdated => 'Profile updated successfully';

  @override
  String get stickerUploading => 'Uploading sticker...';

  @override
  String get starMessagesSuccess => 'Messages starred';

  @override
  String get unstarMessagesSuccess => 'Messages unstarred';

  @override
  String get callingStatus => 'Calling...';

  @override
  String get disconnectedStatus => 'Disconnected';

  @override
  String get failedStatus => 'Failed';

  @override
  String get connectionEnded => 'Connection ended';

  @override
  String get permissions => 'Permissions';

  @override
  String get mediaPermissionRequest => 'Media access required';

  @override
  String get micPermissionDenied => 'Microphone permission denied';

  @override
  String get cameraPermissionDenied => 'Camera permission denied';

  @override
  String get incomingVideoCall => 'Incoming Video Call';

  @override
  String get incomingVoiceCall => 'Incoming Voice Call';

  @override
  String get ringingNow => 'Ringing...';

  @override
  String get closeTooltip => 'Close';

  @override
  String get incomingCall => 'Incoming Call';

  @override
  String get unknown => 'Unknown';

  @override
  String get justNow => 'Just now';

  @override
  String get chooseFriendToCall => 'Choose friend to call';

  @override
  String get webRTC => 'WebRTC';

  @override
  String get recallFailed => 'Call failed';

  @override
  String get sendFailedDetail => 'Failed to send message';

  @override
  String get callFailed => 'Call failed';

  @override
  String get imageUploadDetail => 'Failed to upload image';

  @override
  String get stickerLabel => 'Sticker';

  @override
  String get removeLabel => 'Remove';

  @override
  String get forwardLabel => 'Forward';

  @override
  String get openOrDownload => 'Open or Download';

  @override
  String get starLabelDetailed => 'Star message';

  @override
  String get copyLabelDetailed => 'Copy message';

  @override
  String get forwardLabelDetailed => 'Forward message';

  @override
  String get deleteLabelDetailed => 'Delete message';

  @override
  String get editedLabel => 'Edited';

  @override
  String get saveLabel => 'Save';

  @override
  String get retryLabelDetailed => 'Retry sending';

  @override
  String get removeStarLabelDetailed => 'Unstar message';

  @override
  String get starLabelWithStar => 'Star';

  @override
  String get unpinLabelDetailed => 'Unpin message';

  @override
  String get pinToTopLabelDetailed => 'Pin to top';

  @override
  String get done => 'Done';

  @override
  String get messagesForwardedSuccess => 'Messages forwarded';

  @override
  String get reactLabelDetailed => 'React to message';

  @override
  String get removeMyReactionLabelDetailed => 'Remove reaction';

  @override
  String get deleteForMeLabel => 'Delete for me';

  @override
  String get confirmDelete => 'Confirm delete';

  @override
  String get deleteForMeConfirm => 'Delete for me?';

  @override
  String get select => 'Select';

  @override
  String get deleteForAllLabel => 'Delete for everyone';

  @override
  String get confirmDeleteForAll => 'Delete for everyone';

  @override
  String get deleteForAllConfirm => 'Delete for everyone?';

  @override
  String get confirmLabel => 'Confirm';

  @override
  String get groupRoleAdmin => 'Admin';

  @override
  String get groupRoleModerator => 'Moderator';

  @override
  String get meLabel => 'Me';

  @override
  String get otherPersonLabel => 'Other';

  @override
  String get warning => 'Warning';

  @override
  String get deletedLabel => 'Deleted';

  @override
  String get releaseToCancel => 'Release to cancel';

  @override
  String get swipeToCancel => 'Swipe to cancel';

  @override
  String get sendFailed => 'Send failed';

  @override
  String get groupInfoTitle => 'Group Info';

  @override
  String get groupInfoSoon => 'Group info coming soon';

  @override
  String get audioLabel => 'Audio';

  @override
  String get mediaPermissionDetail => 'Permission required to access media';

  @override
  String get uploadingImage => 'Uploading image...';

  @override
  String get uploadingVideo => 'Uploading video...';

  @override
  String get uploadingFile => 'Uploading file...';

  @override
  String get shareLocation => 'Share Location';

  @override
  String get shareLocationDetail => 'Share your current location';

  @override
  String get myLocationLabel => 'My Location';

  @override
  String get editorLabel => 'Editor';

  @override
  String get messagesCopiedToClipboard => 'Messages copied to clipboard';

  @override
  String get forwardToTitle => 'Forward to';

  @override
  String get deleteMessagesConfirm => 'Delete messages?';

  @override
  String get openLinkLabel => 'Open Link';

  @override
  String get openLinkError => 'Failed to open link';

  @override
  String get openLinkErrorGeneric => 'Error opening link';

  @override
  String get fileLabel => 'File';

  @override
  String get reactionsLabel => 'Reactions';

  @override
  String get userLabel => 'User';

  @override
  String get fetchingPreview => 'Fetching preview...';

  @override
  String get replyLabelDetailed => 'Reply to message';

  @override
  String get webrtcIndividualOnly => 'WebRTC is for individual chats only';

  @override
  String get webrtcFailedToIdentifyOther => 'Failed to identify other user';

  @override
  String get chooseFriendToChat => 'Choose friend to chat';

  @override
  String get changeProfilePhoto => 'Change Profile Photo';

  @override
  String get imageUploadFailed => 'Image upload failed';

  @override
  String minutes(int count) {
    return '$count minutes';
  }

  @override
  String hours(int count) {
    return '$count hours';
  }

  @override
  String get indefinitely => 'Indefinitely';

  @override
  String get connectionGlitch =>
      'A minor glitch in the connection. Stay with us...';

  @override
  String get reconnectingQuietly => 'Reconnecting quietly...';

  @override
  String get exitGracefully =>
      'Ending the session. Thank you for using TalkMate.';

  @override
  String get callEndedPeacefully => 'The call has concluded peacefully.';

  @override
  String get rooms => 'Rooms';

  @override
  String get me => 'Me';

  @override
  String get searchFriendsHint => 'Search by name or email';

  @override
  String get noFriendsYet => 'No friends yet';

  @override
  String get startChat => 'Start Chat';

  @override
  String get removeFromFriends => 'Remove from Friends';

  @override
  String get friendRemoved => 'Friend removed';

  @override
  String get blocked => 'Blocked';

  @override
  String get doneLabel => 'Done';

  @override
  String get pleaseLoginToView => 'Please login to view';

  @override
  String get profilePhoto => 'Profile photo';

  @override
  String get status => 'Status';

  @override
  String get outgoingCall => 'Outgoing Call';

  @override
  String get callStatusDialing => 'Dialing...';

  @override
  String get callStatusRinging => 'Ringing...';

  @override
  String get callStatusConnecting => 'Connecting to other party...';

  @override
  String get callStatusReconnecting => 'Reconnecting...';

  @override
  String get callStatusConnected => 'Connected';

  @override
  String get callStatusFailed => 'Call Failed';

  @override
  String get networkExcellent => 'Excellent';

  @override
  String get networkGood => 'Good';

  @override
  String get networkPoor => 'Poor';

  @override
  String get networkUnstable => 'Unstable';

  @override
  String get fallbackToAudioMsg => 'Switched to audio call for stability';
}
