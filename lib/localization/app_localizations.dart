import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart' deferred as app_localizations_ar;
import 'app_localizations_en.dart' deferred as app_localizations_en;

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'localization/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'TalkMate AI'**
  String get appName;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @chats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chats;

  /// No description provided for @calls.
  ///
  /// In en, this message translates to:
  /// **'Calls'**
  String get calls;

  /// No description provided for @groups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get groups;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get register;

  /// No description provided for @continueAsGuest.
  ///
  /// In en, this message translates to:
  /// **'Continue as Guest'**
  String get continueAsGuest;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to TalkMate AI'**
  String get welcome;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'This feature will be added soon'**
  String get comingSoon;

  /// No description provided for @tooltipChangeTheme.
  ///
  /// In en, this message translates to:
  /// **'Change theme'**
  String get tooltipChangeTheme;

  /// No description provided for @tooltipChangeLanguage.
  ///
  /// In en, this message translates to:
  /// **'Change language'**
  String get tooltipChangeLanguage;

  /// No description provided for @snackTestTitle.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get snackTestTitle;

  /// No description provided for @snackTestMessage.
  ///
  /// In en, this message translates to:
  /// **'Tapped {count} times! 🎉'**
  String snackTestMessage(int count);

  /// No description provided for @guest.
  ///
  /// In en, this message translates to:
  /// **'Guest'**
  String get guest;

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Smart chat and calls app'**
  String get appTagline;

  /// No description provided for @runningOk.
  ///
  /// In en, this message translates to:
  /// **'✅ Running successfully!'**
  String get runningOk;

  /// No description provided for @appStatus.
  ///
  /// In en, this message translates to:
  /// **'App status:'**
  String get appStatus;

  /// No description provided for @platform.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get platform;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @user.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get user;

  /// No description provided for @loggedIn.
  ///
  /// In en, this message translates to:
  /// **'Logged in'**
  String get loggedIn;

  /// No description provided for @clickCount.
  ///
  /// In en, this message translates to:
  /// **'Click count'**
  String get clickCount;

  /// No description provided for @availableFeatures.
  ///
  /// In en, this message translates to:
  /// **'Available features:'**
  String get availableFeatures;

  /// No description provided for @instantMessaging.
  ///
  /// In en, this message translates to:
  /// **'Instant messaging'**
  String get instantMessaging;

  /// No description provided for @voiceCalls.
  ///
  /// In en, this message translates to:
  /// **'Voice calls'**
  String get voiceCalls;

  /// No description provided for @videoCalls.
  ///
  /// In en, this message translates to:
  /// **'Video calls'**
  String get videoCalls;

  /// No description provided for @groupsFeature.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get groupsFeature;

  /// No description provided for @securityPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Security and privacy'**
  String get securityPrivacy;

  /// No description provided for @settingsHeader.
  ///
  /// In en, this message translates to:
  /// **'Settings:'**
  String get settingsHeader;

  /// No description provided for @deleteMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete message'**
  String get deleteMessageTitle;

  /// No description provided for @deleteMessageConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this message?'**
  String get deleteMessageConfirm;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get online;

  /// No description provided for @statusInCall.
  ///
  /// In en, this message translates to:
  /// **'In a call'**
  String get statusInCall;

  /// No description provided for @statusInRoomVoice.
  ///
  /// In en, this message translates to:
  /// **'In voice room'**
  String get statusInRoomVoice;

  /// No description provided for @statusInRoomVideo.
  ///
  /// In en, this message translates to:
  /// **'In video room'**
  String get statusInRoomVideo;

  /// No description provided for @appearanceLanguage.
  ///
  /// In en, this message translates to:
  /// **'Appearance & Language'**
  String get appearanceLanguage;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark mode'**
  String get darkMode;

  /// No description provided for @darkModeHint.
  ///
  /// In en, this message translates to:
  /// **'Enable the app\'s dark theme'**
  String get darkModeHint;

  /// No description provided for @arabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get arabic;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @enableNotifications.
  ///
  /// In en, this message translates to:
  /// **'Enable notifications'**
  String get enableNotifications;

  /// No description provided for @newMessagesNotifications.
  ///
  /// In en, this message translates to:
  /// **'Receive new message notifications'**
  String get newMessagesNotifications;

  /// No description provided for @notificationSound.
  ///
  /// In en, this message translates to:
  /// **'Notification sound'**
  String get notificationSound;

  /// No description provided for @playSoundOnNotifications.
  ///
  /// In en, this message translates to:
  /// **'Play sound when notifications arrive'**
  String get playSoundOnNotifications;

  /// No description provided for @notificationVibration.
  ///
  /// In en, this message translates to:
  /// **'Notification vibration'**
  String get notificationVibration;

  /// No description provided for @vibrateOnNotifications.
  ///
  /// In en, this message translates to:
  /// **'Vibrate the device on notifications'**
  String get vibrateOnNotifications;

  /// No description provided for @testNotifications.
  ///
  /// In en, this message translates to:
  /// **'Test notifications'**
  String get testNotifications;

  /// No description provided for @sendTestNotification.
  ///
  /// In en, this message translates to:
  /// **'Send a test notification'**
  String get sendTestNotification;

  /// No description provided for @privacySecurity.
  ///
  /// In en, this message translates to:
  /// **'Privacy & Security'**
  String get privacySecurity;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePassword;

  /// No description provided for @blockedUsers.
  ///
  /// In en, this message translates to:
  /// **'Blocked users'**
  String get blockedUsers;

  /// No description provided for @manageBlockedUsers.
  ///
  /// In en, this message translates to:
  /// **'Manage blocked list'**
  String get manageBlockedUsers;

  /// No description provided for @privacySettings.
  ///
  /// In en, this message translates to:
  /// **'Privacy settings'**
  String get privacySettings;

  /// No description provided for @whoCanSeeInfo.
  ///
  /// In en, this message translates to:
  /// **'Who can see your info'**
  String get whoCanSeeInfo;

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'About the app'**
  String get aboutApp;

  /// No description provided for @appInfo.
  ///
  /// In en, this message translates to:
  /// **'App info'**
  String get appInfo;

  /// No description provided for @appVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String appVersionLabel(String version);

  /// No description provided for @developerLabel.
  ///
  /// In en, this message translates to:
  /// **'Developer: {name}'**
  String developerLabel(String name);

  /// No description provided for @helpSupport.
  ///
  /// In en, this message translates to:
  /// **'Help & support'**
  String get helpSupport;

  /// No description provided for @faqSupport.
  ///
  /// In en, this message translates to:
  /// **'FAQs and support'**
  String get faqSupport;

  /// No description provided for @termsOfUse.
  ///
  /// In en, this message translates to:
  /// **'Terms of use'**
  String get termsOfUse;

  /// No description provided for @readTerms.
  ///
  /// In en, this message translates to:
  /// **'Read terms and conditions'**
  String get readTerms;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get privacyPolicy;

  /// No description provided for @howWeProtectData.
  ///
  /// In en, this message translates to:
  /// **'How we protect your data'**
  String get howWeProtectData;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @logoutHint.
  ///
  /// In en, this message translates to:
  /// **'Sign out from the current account'**
  String get logoutHint;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountPermanently.
  ///
  /// In en, this message translates to:
  /// **'Delete the account permanently'**
  String get deleteAccountPermanently;

  /// No description provided for @chooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose language'**
  String get chooseLanguage;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @confirmLogout.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to log out?'**
  String get confirmLogout;

  /// No description provided for @confirmDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete the account? This action cannot be undone.'**
  String get confirmDeleteAccount;

  /// No description provided for @newChat.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get newChat;

  /// No description provided for @searchChatsHint.
  ///
  /// In en, this message translates to:
  /// **'Search chats...'**
  String get searchChatsHint;

  /// No description provided for @noChatsYet.
  ///
  /// In en, this message translates to:
  /// **'No chats yet'**
  String get noChatsYet;

  /// No description provided for @startNewChatWithFriends.
  ///
  /// In en, this message translates to:
  /// **'Start a new chat with your friends'**
  String get startNewChatWithFriends;

  /// No description provided for @startNewChat.
  ///
  /// In en, this message translates to:
  /// **'Start a new chat'**
  String get startNewChat;

  /// No description provided for @archive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archive;

  /// No description provided for @unarchive.
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get unarchive;

  /// No description provided for @mute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get mute;

  /// No description provided for @unmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmute;

  /// No description provided for @pin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pin;

  /// No description provided for @unpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpin;

  /// No description provided for @newChatTitle.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get newChatTitle;

  /// No description provided for @chooseChatType.
  ///
  /// In en, this message translates to:
  /// **'Choose the type of chat you want to create'**
  String get chooseChatType;

  /// No description provided for @individualChat.
  ///
  /// In en, this message translates to:
  /// **'Individual chat'**
  String get individualChat;

  /// No description provided for @group.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get group;

  /// No description provided for @createIndividualChat.
  ///
  /// In en, this message translates to:
  /// **'Create individual chat'**
  String get createIndividualChat;

  /// No description provided for @personNameHint.
  ///
  /// In en, this message translates to:
  /// **'Person name'**
  String get personNameHint;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @createGroup.
  ///
  /// In en, this message translates to:
  /// **'Create group'**
  String get createGroup;

  /// No description provided for @groupNameHint.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupNameHint;

  /// No description provided for @deleteChat.
  ///
  /// In en, this message translates to:
  /// **'Delete chat'**
  String get deleteChat;

  /// No description provided for @deleteChatTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete chat'**
  String get deleteChatTitle;

  /// No description provided for @deleteChatConfirmWithName.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete the chat with {name}?'**
  String deleteChatConfirmWithName(Object name);

  /// No description provided for @confirmDeleteChatWithName.
  ///
  /// In en, this message translates to:
  /// **'Delete chat with {name}'**
  String confirmDeleteChatWithName(Object name);

  /// No description provided for @searchInChatHint.
  ///
  /// In en, this message translates to:
  /// **'Search in chat...'**
  String get searchInChatHint;

  /// No description provided for @typing.
  ///
  /// In en, this message translates to:
  /// **'typing...'**
  String get typing;

  /// No description provided for @searchOptions.
  ///
  /// In en, this message translates to:
  /// **'Search options'**
  String get searchOptions;

  /// No description provided for @matchCase.
  ///
  /// In en, this message translates to:
  /// **'Match case'**
  String get matchCase;

  /// No description provided for @wholeWord.
  ///
  /// In en, this message translates to:
  /// **'Whole word'**
  String get wholeWord;

  /// No description provided for @useRegex.
  ///
  /// In en, this message translates to:
  /// **'Use Regex'**
  String get useRegex;

  /// No description provided for @previous.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @closeSearch.
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get closeSearch;

  /// No description provided for @notificationsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Notifications enabled'**
  String get notificationsEnabled;

  /// No description provided for @notificationsDisabled.
  ///
  /// In en, this message translates to:
  /// **'Notifications disabled'**
  String get notificationsDisabled;

  /// No description provided for @notificationSoundEnabled.
  ///
  /// In en, this message translates to:
  /// **'Notification sound enabled'**
  String get notificationSoundEnabled;

  /// No description provided for @notificationSoundDisabled.
  ///
  /// In en, this message translates to:
  /// **'Notification sound disabled'**
  String get notificationSoundDisabled;

  /// No description provided for @notificationVibrationEnabled.
  ///
  /// In en, this message translates to:
  /// **'Notification vibration enabled'**
  String get notificationVibrationEnabled;

  /// No description provided for @notificationVibrationDisabled.
  ///
  /// In en, this message translates to:
  /// **'Notification vibration disabled'**
  String get notificationVibrationDisabled;

  /// No description provided for @notificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification'**
  String get notificationTitle;

  /// No description provided for @openChatFromNotificationWithId.
  ///
  /// In en, this message translates to:
  /// **'Open chat from notification: {chatId}'**
  String openChatFromNotificationWithId(Object chatId);

  /// No description provided for @messageTypeImage.
  ///
  /// In en, this message translates to:
  /// **'📷 Image'**
  String get messageTypeImage;

  /// No description provided for @messageTypeVideo.
  ///
  /// In en, this message translates to:
  /// **'🎥 Video'**
  String get messageTypeVideo;

  /// No description provided for @messageTypeAudio.
  ///
  /// In en, this message translates to:
  /// **'🎵 Voice message'**
  String get messageTypeAudio;

  /// No description provided for @messageTypeFile.
  ///
  /// In en, this message translates to:
  /// **'📎 File'**
  String get messageTypeFile;

  /// No description provided for @messageTypeLocation.
  ///
  /// In en, this message translates to:
  /// **'📍 Location'**
  String get messageTypeLocation;

  /// No description provided for @messageTypeContact.
  ///
  /// In en, this message translates to:
  /// **'👤 Contact'**
  String get messageTypeContact;

  /// No description provided for @incomingCallTitleWithType.
  ///
  /// In en, this message translates to:
  /// **'Incoming {callType} call'**
  String incomingCallTitleWithType(Object callType);

  /// No description provided for @fromCallerName.
  ///
  /// In en, this message translates to:
  /// **'From {callerName}'**
  String fromCallerName(Object callerName);

  /// No description provided for @callsChannelName.
  ///
  /// In en, this message translates to:
  /// **'TalkMate Calls'**
  String get callsChannelName;

  /// No description provided for @callsChannelDescription.
  ///
  /// In en, this message translates to:
  /// **'Incoming call notifications'**
  String get callsChannelDescription;

  /// No description provided for @answer.
  ///
  /// In en, this message translates to:
  /// **'Answer'**
  String get answer;

  /// No description provided for @decline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get decline;

  /// No description provided for @testChannelName.
  ///
  /// In en, this message translates to:
  /// **'Notifications Test'**
  String get testChannelName;

  /// No description provided for @testChannelDescription.
  ///
  /// In en, this message translates to:
  /// **'Notifications test channel'**
  String get testChannelDescription;

  /// No description provided for @notificationsTestTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications Test'**
  String get notificationsTestTitle;

  /// No description provided for @notificationsTestBody.
  ///
  /// In en, this message translates to:
  /// **'This is a test notification from TalkMate AI 🚀'**
  String get notificationsTestBody;

  /// No description provided for @sent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get sent;

  /// No description provided for @testNotificationSent.
  ///
  /// In en, this message translates to:
  /// **'Test notification sent successfully'**
  String get testNotificationSent;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @testNotificationFailedWithError.
  ///
  /// In en, this message translates to:
  /// **'Failed to send test notification: {error}'**
  String testNotificationFailedWithError(Object error);

  /// No description provided for @testNotificationDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Test Notification'**
  String get testNotificationDialogTitle;

  /// No description provided for @testNotificationDialogBody.
  ///
  /// In en, this message translates to:
  /// **'Notifications system works properly!'**
  String get testNotificationDialogBody;

  /// No description provided for @testNotificationShown.
  ///
  /// In en, this message translates to:
  /// **'Test notification displayed successfully'**
  String get testNotificationShown;

  /// No description provided for @updated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get updated;

  /// No description provided for @chatsUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Chats updated successfully'**
  String get chatsUpdatedSuccessfully;

  /// No description provided for @updateChatsError.
  ///
  /// In en, this message translates to:
  /// **'An error occurred while updating chats'**
  String get updateChatsError;

  /// No description provided for @chatCreatedWithName.
  ///
  /// In en, this message translates to:
  /// **'Chat created with {name}'**
  String chatCreatedWithName(Object name);

  /// No description provided for @newGroup.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get newGroup;

  /// No description provided for @groupCreatedWithName.
  ///
  /// In en, this message translates to:
  /// **'Group {name} created'**
  String groupCreatedWithName(Object name);

  /// No description provided for @deleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get deleted;

  /// No description provided for @chatDeleted.
  ///
  /// In en, this message translates to:
  /// **'Chat deleted'**
  String get chatDeleted;

  /// No description provided for @archived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get archived;

  /// No description provided for @unarchived.
  ///
  /// In en, this message translates to:
  /// **'Unarchived'**
  String get unarchived;

  /// No description provided for @chatArchived.
  ///
  /// In en, this message translates to:
  /// **'Chat archived'**
  String get chatArchived;

  /// No description provided for @chatUnarchived.
  ///
  /// In en, this message translates to:
  /// **'Chat unarchived'**
  String get chatUnarchived;

  /// No description provided for @muted.
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get muted;

  /// No description provided for @unmuted.
  ///
  /// In en, this message translates to:
  /// **'Unmuted'**
  String get unmuted;

  /// No description provided for @chatMuted.
  ///
  /// In en, this message translates to:
  /// **'Notifications for this chat have been muted'**
  String get chatMuted;

  /// No description provided for @chatUnmuted.
  ///
  /// In en, this message translates to:
  /// **'Chat notifications unmuted'**
  String get chatUnmuted;

  /// No description provided for @cleared.
  ///
  /// In en, this message translates to:
  /// **'Cleared'**
  String get cleared;

  /// No description provided for @allChatMessagesCleared.
  ///
  /// In en, this message translates to:
  /// **'All chat messages cleared'**
  String get allChatMessagesCleared;

  /// No description provided for @messageDeleted.
  ///
  /// In en, this message translates to:
  /// **'This message was deleted'**
  String get messageDeleted;

  /// No description provided for @videoCall.
  ///
  /// In en, this message translates to:
  /// **'Video call'**
  String get videoCall;

  /// No description provided for @voiceCall.
  ///
  /// In en, this message translates to:
  /// **'Voice call'**
  String get voiceCall;

  /// No description provided for @viewProfile.
  ///
  /// In en, this message translates to:
  /// **'View Profile'**
  String get viewProfile;

  /// No description provided for @searchInChat.
  ///
  /// In en, this message translates to:
  /// **'Search in chat'**
  String get searchInChat;

  /// No description provided for @muteNotifications.
  ///
  /// In en, this message translates to:
  /// **'Mute notifications'**
  String get muteNotifications;

  /// No description provided for @clearChat.
  ///
  /// In en, this message translates to:
  /// **'Clear chat'**
  String get clearChat;

  /// No description provided for @startConversation.
  ///
  /// In en, this message translates to:
  /// **'Start the conversation'**
  String get startConversation;

  /// No description provided for @writeFirstMessage.
  ///
  /// In en, this message translates to:
  /// **'Write your first message to start the conversation'**
  String get writeFirstMessage;

  /// No description provided for @chatToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get chatToday;

  /// No description provided for @chatYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get chatYesterday;

  /// No description provided for @attachFile.
  ///
  /// In en, this message translates to:
  /// **'Attach file'**
  String get attachFile;

  /// No description provided for @emoji.
  ///
  /// In en, this message translates to:
  /// **'Emoji'**
  String get emoji;

  /// No description provided for @typeMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get typeMessageHint;

  /// No description provided for @messageSentTitle.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get messageSentTitle;

  /// No description provided for @messageSentSuccess.
  ///
  /// In en, this message translates to:
  /// **'Message sent successfully'**
  String get messageSentSuccess;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @profileViewComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Profile view will be added soon'**
  String get profileViewComingSoon;

  /// No description provided for @attachFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Attach file'**
  String get attachFileTitle;

  /// No description provided for @photo.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get photo;

  /// No description provided for @video.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get video;

  /// No description provided for @file.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get file;

  /// No description provided for @location.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get location;

  /// No description provided for @attachImageTitle.
  ///
  /// In en, this message translates to:
  /// **'Attach photo'**
  String get attachImageTitle;

  /// No description provided for @attachVideoTitle.
  ///
  /// In en, this message translates to:
  /// **'Attach video'**
  String get attachVideoTitle;

  /// No description provided for @attachFileActionTitle.
  ///
  /// In en, this message translates to:
  /// **'Attach file'**
  String get attachFileActionTitle;

  /// No description provided for @attachLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Attach location'**
  String get attachLocationTitle;

  /// No description provided for @attachImageComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Photo attachment feature will be added soon'**
  String get attachImageComingSoon;

  /// No description provided for @attachVideoComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Video attachment feature will be added soon'**
  String get attachVideoComingSoon;

  /// No description provided for @attachFileComingSoon.
  ///
  /// In en, this message translates to:
  /// **'File attachment feature will be added soon'**
  String get attachFileComingSoon;

  /// No description provided for @attachLocationComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Location attachment feature will be added soon'**
  String get attachLocationComingSoon;

  /// No description provided for @clearChatTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear chat'**
  String get clearChatTitle;

  /// No description provided for @clearChatConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to clear all messages in this chat?'**
  String get clearChatConfirm;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @clearedTitle.
  ///
  /// In en, this message translates to:
  /// **'Cleared'**
  String get clearedTitle;

  /// No description provided for @chatCleared.
  ///
  /// In en, this message translates to:
  /// **'All chat messages have been cleared'**
  String get chatCleared;

  /// No description provided for @messageOptions.
  ///
  /// In en, this message translates to:
  /// **'Message options'**
  String get messageOptions;

  /// No description provided for @reply.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get reply;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copiedTitle.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copiedTitle;

  /// No description provided for @messageCopied.
  ///
  /// In en, this message translates to:
  /// **'Message copied'**
  String get messageCopied;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @editMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit message'**
  String get editMessageTitle;

  /// No description provided for @featureComingSoon.
  ///
  /// In en, this message translates to:
  /// **'This feature will be added soon'**
  String get featureComingSoon;

  /// No description provided for @deletedMessagePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Deleted message'**
  String get deletedMessagePlaceholder;

  /// No description provided for @loginSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Login successful'**
  String get loginSuccessTitle;

  /// No description provided for @loginErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Login error'**
  String get loginErrorTitle;

  /// No description provided for @loginErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'An error occurred during login. Please try again.'**
  String get loginErrorMessage;

  /// No description provided for @registrationSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Account created successfully'**
  String get registrationSuccessTitle;

  /// No description provided for @registrationErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Registration error'**
  String get registrationErrorTitle;

  /// No description provided for @registrationErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'An error occurred during registration. Please try again.'**
  String get registrationErrorMessage;

  /// No description provided for @loggedOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Logged out'**
  String get loggedOutTitle;

  /// No description provided for @loggedOutMessage.
  ///
  /// In en, this message translates to:
  /// **'You have been logged out successfully'**
  String get loggedOutMessage;

  /// No description provided for @profileUpdatedTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile updated'**
  String get profileUpdatedTitle;

  /// No description provided for @changesSavedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Changes saved successfully'**
  String get changesSavedSuccessfully;

  /// No description provided for @updateErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get updateErrorTitle;

  /// No description provided for @updateProfileErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'An error occurred while updating the profile'**
  String get updateProfileErrorMessage;

  /// No description provided for @guestLoginTitle.
  ///
  /// In en, this message translates to:
  /// **'Guest login'**
  String get guestLoginTitle;

  /// No description provided for @guestWelcomeMessage.
  ///
  /// In en, this message translates to:
  /// **'Welcome as a guest to TalkMate AI'**
  String get guestWelcomeMessage;

  /// No description provided for @searchHistoryCleared.
  ///
  /// In en, this message translates to:
  /// **'Search history cleared'**
  String get searchHistoryCleared;

  /// No description provided for @openChatTitle.
  ///
  /// In en, this message translates to:
  /// **'Open chat'**
  String get openChatTitle;

  /// No description provided for @openChatWithName.
  ///
  /// In en, this message translates to:
  /// **'Open chat with {name}'**
  String openChatWithName(Object name);

  /// No description provided for @goToMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'Go to message'**
  String get goToMessageTitle;

  /// No description provided for @goToMessageBody.
  ///
  /// In en, this message translates to:
  /// **'Go to message: {content}'**
  String goToMessageBody(Object content);

  /// No description provided for @viewUserTitle.
  ///
  /// In en, this message translates to:
  /// **'View user'**
  String get viewUserTitle;

  /// No description provided for @viewUserProfileWithName.
  ///
  /// In en, this message translates to:
  /// **'View {name}\'s profile'**
  String viewUserProfileWithName(Object name);

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @chatsLabel.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chatsLabel;

  /// No description provided for @messagesLabel.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get messagesLabel;

  /// No description provided for @usersLabel.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get usersLabel;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @pleaseEnterEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter your email'**
  String get pleaseEnterEmail;

  /// No description provided for @invalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Invalid email address'**
  String get invalidEmail;

  /// No description provided for @pleaseEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Please enter password'**
  String get pleaseEnterPassword;

  /// No description provided for @pleaseEnterName.
  ///
  /// In en, this message translates to:
  /// **'Please enter your name'**
  String get pleaseEnterName;

  /// No description provided for @minChars.
  ///
  /// In en, this message translates to:
  /// **'At least {count} characters required'**
  String minChars(int count);

  /// No description provided for @searchInAppHint.
  ///
  /// In en, this message translates to:
  /// **'Search in {appName}...'**
  String searchInAppHint(String appName);

  /// No description provided for @recentSearches.
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get recentSearches;

  /// No description provided for @clearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get clearAll;

  /// No description provided for @noSearchHistory.
  ///
  /// In en, this message translates to:
  /// **'No search history'**
  String get noSearchHistory;

  /// No description provided for @startSearchingToSave.
  ///
  /// In en, this message translates to:
  /// **'Start searching to save your queries'**
  String get startSearchingToSave;

  /// No description provided for @searching.
  ///
  /// In en, this message translates to:
  /// **'Searching...'**
  String get searching;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get noResults;

  /// No description provided for @tryDifferentKeywordsOrType.
  ///
  /// In en, this message translates to:
  /// **'Try different keywords or change the search type'**
  String get tryDifferentKeywordsOrType;

  /// No description provided for @now.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get now;

  /// No description provided for @minutesAbbrev.
  ///
  /// In en, this message translates to:
  /// **'{count}m'**
  String minutesAbbrev(int count);

  /// No description provided for @hoursAbbrev.
  ///
  /// In en, this message translates to:
  /// **'{count}h'**
  String hoursAbbrev(int count);

  /// No description provided for @daysAbbrev.
  ///
  /// In en, this message translates to:
  /// **'{count}d'**
  String daysAbbrev(int count);

  /// No description provided for @endCall.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get endCall;

  /// No description provided for @turnCameraOn.
  ///
  /// In en, this message translates to:
  /// **'Turn camera on'**
  String get turnCameraOn;

  /// No description provided for @turnCameraOff.
  ///
  /// In en, this message translates to:
  /// **'Turn camera off'**
  String get turnCameraOff;

  /// No description provided for @speaker.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get speaker;

  /// No description provided for @addParticipant.
  ///
  /// In en, this message translates to:
  /// **'Add participant'**
  String get addParticipant;

  /// No description provided for @dialPad.
  ///
  /// In en, this message translates to:
  /// **'Dial pad'**
  String get dialPad;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get connecting;

  /// No description provided for @live.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get live;

  /// No description provided for @ended.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get ended;

  /// No description provided for @missed.
  ///
  /// In en, this message translates to:
  /// **'Missed call'**
  String get missed;

  /// No description provided for @rejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get rejected;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @noBlockedUsers.
  ///
  /// In en, this message translates to:
  /// **'No blocked users'**
  String get noBlockedUsers;

  /// No description provided for @block.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get block;

  /// No description provided for @unblock.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get unblock;

  /// No description provided for @enterUserIdToBlock.
  ///
  /// In en, this message translates to:
  /// **'Enter userId to block'**
  String get enterUserIdToBlock;

  /// No description provided for @flipCamera.
  ///
  /// In en, this message translates to:
  /// **'Flip camera'**
  String get flipCamera;

  /// No description provided for @shareScreen.
  ///
  /// In en, this message translates to:
  /// **'Share screen'**
  String get shareScreen;

  /// No description provided for @authErrorInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Invalid email or password. Please check your credentials and try again.'**
  String get authErrorInvalidCredentials;

  /// No description provided for @authErrorEmailNotConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Your email is not confirmed yet. Please check your inbox for the confirmation link.'**
  String get authErrorEmailNotConfirmed;

  /// No description provided for @authErrorUserAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'An account with this email already exists. Try logging in instead.'**
  String get authErrorUserAlreadyExists;

  /// No description provided for @authErrorTooManyRequests.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait a few seconds and try again.'**
  String get authErrorTooManyRequests;

  /// No description provided for @authErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error. Please check your internet connection.'**
  String get authErrorNetwork;

  /// No description provided for @authErrorUnknown.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred. Please try again later.'**
  String get authErrorUnknown;

  /// No description provided for @onboardingTitle1.
  ///
  /// In en, this message translates to:
  /// **'Ultra Secure & Fast'**
  String get onboardingTitle1;

  /// No description provided for @onboardingDesc1.
  ///
  /// In en, this message translates to:
  /// **'We use the latest Supabase tech to ensure your messages arrive instantly with top-tier encryption.'**
  String get onboardingDesc1;

  /// No description provided for @onboardingTitle2.
  ///
  /// In en, this message translates to:
  /// **'Works Even Offline'**
  String get onboardingTitle2;

  /// No description provided for @onboardingDesc2.
  ///
  /// In en, this message translates to:
  /// **'Smart sync system saves messages locally and sends them automatically when connection returns.'**
  String get onboardingDesc2;

  /// No description provided for @onboardingTitle3.
  ///
  /// In en, this message translates to:
  /// **'Your Privacy is Our Priority'**
  String get onboardingTitle3;

  /// No description provided for @onboardingDesc3.
  ///
  /// In en, this message translates to:
  /// **'Full control over your data and visibility settings. Your chats belong to you only.'**
  String get onboardingDesc3;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get getStarted;

  /// No description provided for @onboardingNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @successMomentTitle.
  ///
  /// In en, this message translates to:
  /// **'Congratulations! 🎉'**
  String get successMomentTitle;

  /// No description provided for @successMomentMessage.
  ///
  /// In en, this message translates to:
  /// **'You successfully sent your first message. Enjoy a unique chat experience with TalkMate AI.'**
  String get successMomentMessage;

  /// No description provided for @resumeChatWith.
  ///
  /// In en, this message translates to:
  /// **'Resume chat with {name}'**
  String resumeChatWith(String name);

  /// No description provided for @welcomeToAdvancedMessaging.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Advanced Messaging'**
  String get welcomeToAdvancedMessaging;

  /// No description provided for @startFirstChatHint.
  ///
  /// In en, this message translates to:
  /// **'Start your first chat now and experience instant sync and privacy.'**
  String get startFirstChatHint;

  /// No description provided for @startNewChatAction.
  ///
  /// In en, this message translates to:
  /// **'Start New Chat'**
  String get startNewChatAction;

  /// No description provided for @accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// No description provided for @friendRequests.
  ///
  /// In en, this message translates to:
  /// **'Friend Requests'**
  String get friendRequests;

  /// No description provided for @incoming.
  ///
  /// In en, this message translates to:
  /// **'Incoming'**
  String get incoming;

  /// No description provided for @outgoing.
  ///
  /// In en, this message translates to:
  /// **'Outgoing'**
  String get outgoing;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @noIncomingRequests.
  ///
  /// In en, this message translates to:
  /// **'No incoming requests'**
  String get noIncomingRequests;

  /// No description provided for @noOutgoingRequests.
  ///
  /// In en, this message translates to:
  /// **'No outgoing requests'**
  String get noOutgoingRequests;

  /// No description provided for @noRequestHistory.
  ///
  /// In en, this message translates to:
  /// **'No request history'**
  String get noRequestHistory;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// No description provided for @friends.
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get friends;

  /// No description provided for @noGroupsYet.
  ///
  /// In en, this message translates to:
  /// **'No groups yet'**
  String get noGroupsYet;

  /// No description provided for @createYourFirstGroup.
  ///
  /// In en, this message translates to:
  /// **'Create your first group'**
  String get createYourFirstGroup;

  /// No description provided for @bio.
  ///
  /// In en, this message translates to:
  /// **'Bio'**
  String get bio;

  /// No description provided for @joinDate.
  ///
  /// In en, this message translates to:
  /// **'Join Date'**
  String get joinDate;

  /// No description provided for @noBio.
  ///
  /// In en, this message translates to:
  /// **'No bio yet'**
  String get noBio;

  /// No description provided for @member.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get member;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fullName;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get saveChanges;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get welcomeBack;

  /// No description provided for @loginToContinue.
  ///
  /// In en, this message translates to:
  /// **'Login to continue'**
  String get loginToContinue;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @or.
  ///
  /// In en, this message translates to:
  /// **'Or'**
  String get or;

  /// No description provided for @dontHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get dontHaveAccount;

  /// No description provided for @verificationSent.
  ///
  /// In en, this message translates to:
  /// **'Verification link sent. Wait {seconds}s.'**
  String verificationSent(int seconds);

  /// No description provided for @resendVerification.
  ///
  /// In en, this message translates to:
  /// **'Resend verification link'**
  String get resendVerification;

  /// No description provided for @createAccountHeader.
  ///
  /// In en, this message translates to:
  /// **'Create new account'**
  String get createAccountHeader;

  /// No description provided for @joinUs.
  ///
  /// In en, this message translates to:
  /// **'Join us and start chatting'**
  String get joinUs;

  /// No description provided for @statusOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get statusOnline;

  /// No description provided for @statusOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get statusOffline;

  /// No description provided for @statusAway.
  ///
  /// In en, this message translates to:
  /// **'Away'**
  String get statusAway;

  /// No description provided for @statusBusy.
  ///
  /// In en, this message translates to:
  /// **'Busy'**
  String get statusBusy;

  /// No description provided for @msgTypeText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get msgTypeText;

  /// No description provided for @msgTypeImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get msgTypeImage;

  /// No description provided for @msgTypeVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get msgTypeVideo;

  /// No description provided for @msgTypeAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get msgTypeAudio;

  /// No description provided for @msgTypeFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get msgTypeFile;

  /// No description provided for @msgTypeLocation.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get msgTypeLocation;

  /// No description provided for @msgTypeContact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get msgTypeContact;

  /// No description provided for @msgTypeChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get msgTypeChat;

  /// No description provided for @msgTypeCall.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get msgTypeCall;

  /// No description provided for @msgStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Sending...'**
  String get msgStatusPending;

  /// No description provided for @msgStatusSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get msgStatusSent;

  /// No description provided for @msgStatusDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get msgStatusDelivered;

  /// No description provided for @msgStatusRead.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get msgStatusRead;

  /// No description provided for @msgStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get msgStatusFailed;

  /// No description provided for @chatTypeIndividual.
  ///
  /// In en, this message translates to:
  /// **'Individual Chat'**
  String get chatTypeIndividual;

  /// No description provided for @chatTypeGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get chatTypeGroup;

  /// No description provided for @chatTypeChannel.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get chatTypeChannel;

  /// No description provided for @chatTypeChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chatTypeChat;

  /// No description provided for @noMessages.
  ///
  /// In en, this message translates to:
  /// **'No messages'**
  String get noMessages;

  /// No description provided for @timeNow.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get timeNow;

  /// No description provided for @timeMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String timeMinutes(int count);

  /// No description provided for @timeHours.
  ///
  /// In en, this message translates to:
  /// **'{count} h'**
  String timeHours(int count);

  /// No description provided for @timeDays.
  ///
  /// In en, this message translates to:
  /// **'{count} d'**
  String timeDays(int count);

  /// No description provided for @timeWeeks.
  ///
  /// In en, this message translates to:
  /// **'{count} w'**
  String timeWeeks(int count);

  /// No description provided for @youDeletedMessage.
  ///
  /// In en, this message translates to:
  /// **'You deleted this message'**
  String get youDeletedMessage;

  /// No description provided for @deletedBy.
  ///
  /// In en, this message translates to:
  /// **'Deleted by {name}'**
  String deletedBy(String name);

  /// No description provided for @imageLoadError.
  ///
  /// In en, this message translates to:
  /// **'Failed to load image'**
  String get imageLoadError;

  /// No description provided for @stickerUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Sticker upload failed'**
  String get stickerUploadFailed;

  /// No description provided for @stickerUploadError.
  ///
  /// In en, this message translates to:
  /// **'Failed to upload sticker'**
  String get stickerUploadError;

  /// No description provided for @lastSeen.
  ///
  /// In en, this message translates to:
  /// **'Last seen'**
  String get lastSeen;

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min ago'**
  String minutesAgo(int minutes);

  /// No description provided for @todayAt.
  ///
  /// In en, this message translates to:
  /// **'Today at {time}'**
  String todayAt(String time);

  /// No description provided for @yesterdayAt.
  ///
  /// In en, this message translates to:
  /// **'Yesterday at {time}'**
  String yesterdayAt(String time);

  /// No description provided for @dateTimeAt.
  ///
  /// In en, this message translates to:
  /// **'{date} at {time}'**
  String dateTimeAt(String date, String time);

  /// No description provided for @throttledMessagesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} messages'**
  String throttledMessagesCount(int count);

  /// No description provided for @selectedCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCountLabel(int count);

  /// No description provided for @typingSingle.
  ///
  /// In en, this message translates to:
  /// **'{user} is typing...'**
  String typingSingle(String user);

  /// No description provided for @typingDouble.
  ///
  /// In en, this message translates to:
  /// **'{user1} and {user2} are typing...'**
  String typingDouble(String user1, String user2);

  /// No description provided for @typingMultiple.
  ///
  /// In en, this message translates to:
  /// **'{count} people are typing...'**
  String typingMultiple(int count);

  /// No description provided for @reactionsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} reactions'**
  String reactionsCount(int count);

  /// No description provided for @deleteMessagesTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} messages?'**
  String deleteMessagesTitle(int count);

  /// No description provided for @incomingCallFrom.
  ///
  /// In en, this message translates to:
  /// **'Incoming call from {name}'**
  String incomingCallFrom(String name);

  /// No description provided for @callTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'{type} Call'**
  String callTypeLabel(String type);

  /// No description provided for @voice.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get voice;

  /// No description provided for @chooseFriend.
  ///
  /// In en, this message translates to:
  /// **'Choose Friend'**
  String get chooseFriend;

  /// No description provided for @noFriendsToSelect.
  ///
  /// In en, this message translates to:
  /// **'No friends to select'**
  String get noFriendsToSelect;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @pleaseLoginToViewCalls.
  ///
  /// In en, this message translates to:
  /// **'Please login to view calls'**
  String get pleaseLoginToViewCalls;

  /// No description provided for @noCallsMatchSearch.
  ///
  /// In en, this message translates to:
  /// **'No calls match your search'**
  String get noCallsMatchSearch;

  /// No description provided for @searchInHistoryHint.
  ///
  /// In en, this message translates to:
  /// **'Search call history...'**
  String get searchInHistoryHint;

  /// No description provided for @noCallsYet.
  ///
  /// In en, this message translates to:
  /// **'No calls yet'**
  String get noCallsYet;

  /// No description provided for @alert.
  ///
  /// In en, this message translates to:
  /// **'Alert'**
  String get alert;

  /// No description provided for @profileDataLoadError.
  ///
  /// In en, this message translates to:
  /// **'Failed to load profile data'**
  String get profileDataLoadError;

  /// No description provided for @imageSelectionError.
  ///
  /// In en, this message translates to:
  /// **'Image selection failed'**
  String get imageSelectionError;

  /// No description provided for @imageUploadError.
  ///
  /// In en, this message translates to:
  /// **'Image upload failed'**
  String get imageUploadError;

  /// No description provided for @profileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile updated successfully'**
  String get profileUpdated;

  /// No description provided for @stickerUploading.
  ///
  /// In en, this message translates to:
  /// **'Uploading sticker...'**
  String get stickerUploading;

  /// No description provided for @starMessagesSuccess.
  ///
  /// In en, this message translates to:
  /// **'Messages starred'**
  String get starMessagesSuccess;

  /// No description provided for @unstarMessagesSuccess.
  ///
  /// In en, this message translates to:
  /// **'Messages unstarred'**
  String get unstarMessagesSuccess;

  /// No description provided for @callingStatus.
  ///
  /// In en, this message translates to:
  /// **'Calling...'**
  String get callingStatus;

  /// No description provided for @disconnectedStatus.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get disconnectedStatus;

  /// No description provided for @failedStatus.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failedStatus;

  /// No description provided for @connectionEnded.
  ///
  /// In en, this message translates to:
  /// **'Connection ended'**
  String get connectionEnded;

  /// No description provided for @permissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get permissions;

  /// No description provided for @mediaPermissionRequest.
  ///
  /// In en, this message translates to:
  /// **'Media access required'**
  String get mediaPermissionRequest;

  /// No description provided for @micPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission denied'**
  String get micPermissionDenied;

  /// No description provided for @cameraPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Camera permission denied'**
  String get cameraPermissionDenied;

  /// No description provided for @incomingVideoCall.
  ///
  /// In en, this message translates to:
  /// **'Incoming Video Call'**
  String get incomingVideoCall;

  /// No description provided for @incomingVoiceCall.
  ///
  /// In en, this message translates to:
  /// **'Incoming Voice Call'**
  String get incomingVoiceCall;

  /// No description provided for @ringingNow.
  ///
  /// In en, this message translates to:
  /// **'Ringing...'**
  String get ringingNow;

  /// No description provided for @closeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeTooltip;

  /// No description provided for @incomingCall.
  ///
  /// In en, this message translates to:
  /// **'Incoming Call'**
  String get incomingCall;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get justNow;

  /// No description provided for @chooseFriendToCall.
  ///
  /// In en, this message translates to:
  /// **'Choose friend to call'**
  String get chooseFriendToCall;

  /// No description provided for @webRTC.
  ///
  /// In en, this message translates to:
  /// **'WebRTC'**
  String get webRTC;

  /// No description provided for @recallFailed.
  ///
  /// In en, this message translates to:
  /// **'Call failed'**
  String get recallFailed;

  /// No description provided for @sendFailedDetail.
  ///
  /// In en, this message translates to:
  /// **'Failed to send message'**
  String get sendFailedDetail;

  /// No description provided for @callFailed.
  ///
  /// In en, this message translates to:
  /// **'Call failed'**
  String get callFailed;

  /// No description provided for @imageUploadDetail.
  ///
  /// In en, this message translates to:
  /// **'Failed to upload image'**
  String get imageUploadDetail;

  /// No description provided for @stickerLabel.
  ///
  /// In en, this message translates to:
  /// **'Sticker'**
  String get stickerLabel;

  /// No description provided for @removeLabel.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeLabel;

  /// No description provided for @forwardLabel.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get forwardLabel;

  /// No description provided for @openOrDownload.
  ///
  /// In en, this message translates to:
  /// **'Open or Download'**
  String get openOrDownload;

  /// No description provided for @starLabelDetailed.
  ///
  /// In en, this message translates to:
  /// **'Star message'**
  String get starLabelDetailed;

  /// No description provided for @copyLabelDetailed.
  ///
  /// In en, this message translates to:
  /// **'Copy message'**
  String get copyLabelDetailed;

  /// No description provided for @forwardLabelDetailed.
  ///
  /// In en, this message translates to:
  /// **'Forward message'**
  String get forwardLabelDetailed;

  /// No description provided for @deleteLabelDetailed.
  ///
  /// In en, this message translates to:
  /// **'Delete message'**
  String get deleteLabelDetailed;

  /// No description provided for @editedLabel.
  ///
  /// In en, this message translates to:
  /// **'Edited'**
  String get editedLabel;

  /// No description provided for @saveLabel.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveLabel;

  /// No description provided for @retryLabelDetailed.
  ///
  /// In en, this message translates to:
  /// **'Retry sending'**
  String get retryLabelDetailed;

  /// No description provided for @removeStarLabelDetailed.
  ///
  /// In en, this message translates to:
  /// **'Unstar message'**
  String get removeStarLabelDetailed;

  /// No description provided for @starLabelWithStar.
  ///
  /// In en, this message translates to:
  /// **'Star'**
  String get starLabelWithStar;

  /// No description provided for @unpinLabelDetailed.
  ///
  /// In en, this message translates to:
  /// **'Unpin message'**
  String get unpinLabelDetailed;

  /// No description provided for @pinToTopLabelDetailed.
  ///
  /// In en, this message translates to:
  /// **'Pin to top'**
  String get pinToTopLabelDetailed;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @messagesForwardedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Messages forwarded'**
  String get messagesForwardedSuccess;

  /// No description provided for @reactLabelDetailed.
  ///
  /// In en, this message translates to:
  /// **'React to message'**
  String get reactLabelDetailed;

  /// No description provided for @removeMyReactionLabelDetailed.
  ///
  /// In en, this message translates to:
  /// **'Remove reaction'**
  String get removeMyReactionLabelDetailed;

  /// No description provided for @deleteForMeLabel.
  ///
  /// In en, this message translates to:
  /// **'Delete for me'**
  String get deleteForMeLabel;

  /// No description provided for @confirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Confirm delete'**
  String get confirmDelete;

  /// No description provided for @deleteForMeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete for me?'**
  String get deleteForMeConfirm;

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @deleteForAllLabel.
  ///
  /// In en, this message translates to:
  /// **'Delete for everyone'**
  String get deleteForAllLabel;

  /// No description provided for @confirmDeleteForAll.
  ///
  /// In en, this message translates to:
  /// **'Delete for everyone'**
  String get confirmDeleteForAll;

  /// No description provided for @deleteForAllConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete for everyone?'**
  String get deleteForAllConfirm;

  /// No description provided for @confirmLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirmLabel;

  /// No description provided for @groupRoleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get groupRoleAdmin;

  /// No description provided for @groupRoleModerator.
  ///
  /// In en, this message translates to:
  /// **'Moderator'**
  String get groupRoleModerator;

  /// No description provided for @meLabel.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get meLabel;

  /// No description provided for @otherPersonLabel.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get otherPersonLabel;

  /// No description provided for @warning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get warning;

  /// No description provided for @deletedLabel.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get deletedLabel;

  /// No description provided for @releaseToCancel.
  ///
  /// In en, this message translates to:
  /// **'Release to cancel'**
  String get releaseToCancel;

  /// No description provided for @swipeToCancel.
  ///
  /// In en, this message translates to:
  /// **'Swipe to cancel'**
  String get swipeToCancel;

  /// No description provided for @sendFailed.
  ///
  /// In en, this message translates to:
  /// **'Send failed'**
  String get sendFailed;

  /// No description provided for @groupInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Group Info'**
  String get groupInfoTitle;

  /// No description provided for @groupInfoSoon.
  ///
  /// In en, this message translates to:
  /// **'Group info coming soon'**
  String get groupInfoSoon;

  /// No description provided for @audioLabel.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get audioLabel;

  /// No description provided for @mediaPermissionDetail.
  ///
  /// In en, this message translates to:
  /// **'Permission required to access media'**
  String get mediaPermissionDetail;

  /// No description provided for @uploadingImage.
  ///
  /// In en, this message translates to:
  /// **'Uploading image...'**
  String get uploadingImage;

  /// No description provided for @uploadingVideo.
  ///
  /// In en, this message translates to:
  /// **'Uploading video...'**
  String get uploadingVideo;

  /// No description provided for @uploadingFile.
  ///
  /// In en, this message translates to:
  /// **'Uploading file...'**
  String get uploadingFile;

  /// No description provided for @shareLocation.
  ///
  /// In en, this message translates to:
  /// **'Share Location'**
  String get shareLocation;

  /// No description provided for @shareLocationDetail.
  ///
  /// In en, this message translates to:
  /// **'Share your current location'**
  String get shareLocationDetail;

  /// No description provided for @myLocationLabel.
  ///
  /// In en, this message translates to:
  /// **'My Location'**
  String get myLocationLabel;

  /// No description provided for @editorLabel.
  ///
  /// In en, this message translates to:
  /// **'Editor'**
  String get editorLabel;

  /// No description provided for @messagesCopiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Messages copied to clipboard'**
  String get messagesCopiedToClipboard;

  /// No description provided for @forwardToTitle.
  ///
  /// In en, this message translates to:
  /// **'Forward to'**
  String get forwardToTitle;

  /// No description provided for @deleteMessagesConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete messages?'**
  String get deleteMessagesConfirm;

  /// No description provided for @openLinkLabel.
  ///
  /// In en, this message translates to:
  /// **'Open Link'**
  String get openLinkLabel;

  /// No description provided for @openLinkError.
  ///
  /// In en, this message translates to:
  /// **'Failed to open link'**
  String get openLinkError;

  /// No description provided for @openLinkErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Error opening link'**
  String get openLinkErrorGeneric;

  /// No description provided for @fileLabel.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get fileLabel;

  /// No description provided for @reactionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Reactions'**
  String get reactionsLabel;

  /// No description provided for @userLabel.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get userLabel;

  /// No description provided for @fetchingPreview.
  ///
  /// In en, this message translates to:
  /// **'Fetching preview...'**
  String get fetchingPreview;

  /// No description provided for @replyLabelDetailed.
  ///
  /// In en, this message translates to:
  /// **'Reply to message'**
  String get replyLabelDetailed;

  /// No description provided for @webrtcIndividualOnly.
  ///
  /// In en, this message translates to:
  /// **'WebRTC is for individual chats only'**
  String get webrtcIndividualOnly;

  /// No description provided for @webrtcFailedToIdentifyOther.
  ///
  /// In en, this message translates to:
  /// **'Failed to identify other user'**
  String get webrtcFailedToIdentifyOther;

  /// No description provided for @chooseFriendToChat.
  ///
  /// In en, this message translates to:
  /// **'Choose friend to chat'**
  String get chooseFriendToChat;

  /// No description provided for @changeProfilePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change Profile Photo'**
  String get changeProfilePhoto;

  /// No description provided for @imageUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Image upload failed'**
  String get imageUploadFailed;

  /// No description provided for @minutes.
  ///
  /// In en, this message translates to:
  /// **'{count} minutes'**
  String minutes(int count);

  /// No description provided for @hours.
  ///
  /// In en, this message translates to:
  /// **'{count} hours'**
  String hours(int count);

  /// No description provided for @indefinitely.
  ///
  /// In en, this message translates to:
  /// **'Indefinitely'**
  String get indefinitely;

  /// No description provided for @connectionGlitch.
  ///
  /// In en, this message translates to:
  /// **'A minor glitch in the connection. Stay with us...'**
  String get connectionGlitch;

  /// No description provided for @reconnectingQuietly.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting quietly...'**
  String get reconnectingQuietly;

  /// No description provided for @exitGracefully.
  ///
  /// In en, this message translates to:
  /// **'Ending the session. Thank you for using TalkMate.'**
  String get exitGracefully;

  /// No description provided for @callEndedPeacefully.
  ///
  /// In en, this message translates to:
  /// **'The call has concluded peacefully.'**
  String get callEndedPeacefully;

  /// No description provided for @rooms.
  ///
  /// In en, this message translates to:
  /// **'Rooms'**
  String get rooms;

  /// No description provided for @me.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get me;

  /// No description provided for @searchFriendsHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name or email'**
  String get searchFriendsHint;

  /// No description provided for @noFriendsYet.
  ///
  /// In en, this message translates to:
  /// **'No friends yet'**
  String get noFriendsYet;

  /// No description provided for @startChat.
  ///
  /// In en, this message translates to:
  /// **'Start Chat'**
  String get startChat;

  /// No description provided for @removeFromFriends.
  ///
  /// In en, this message translates to:
  /// **'Remove from Friends'**
  String get removeFromFriends;

  /// No description provided for @friendRemoved.
  ///
  /// In en, this message translates to:
  /// **'Friend removed'**
  String get friendRemoved;

  /// No description provided for @blocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get blocked;

  /// No description provided for @doneLabel.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get doneLabel;

  /// No description provided for @pleaseLoginToView.
  ///
  /// In en, this message translates to:
  /// **'Please login to view'**
  String get pleaseLoginToView;

  /// No description provided for @profilePhoto.
  ///
  /// In en, this message translates to:
  /// **'Profile photo'**
  String get profilePhoto;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @outgoingCall.
  ///
  /// In en, this message translates to:
  /// **'Outgoing Call'**
  String get outgoingCall;

  /// No description provided for @callStatusDialing.
  ///
  /// In en, this message translates to:
  /// **'Dialing...'**
  String get callStatusDialing;

  /// No description provided for @callStatusRinging.
  ///
  /// In en, this message translates to:
  /// **'Ringing...'**
  String get callStatusRinging;

  /// No description provided for @callStatusConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to other party...'**
  String get callStatusConnecting;

  /// No description provided for @callStatusReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting...'**
  String get callStatusReconnecting;

  /// No description provided for @callStatusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get callStatusConnected;

  /// No description provided for @callStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Call Failed'**
  String get callStatusFailed;

  /// No description provided for @networkExcellent.
  ///
  /// In en, this message translates to:
  /// **'Excellent'**
  String get networkExcellent;

  /// No description provided for @networkGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get networkGood;

  /// No description provided for @networkPoor.
  ///
  /// In en, this message translates to:
  /// **'Poor'**
  String get networkPoor;

  /// No description provided for @networkUnstable.
  ///
  /// In en, this message translates to:
  /// **'Unstable'**
  String get networkUnstable;

  /// No description provided for @fallbackToAudioMsg.
  ///
  /// In en, this message translates to:
  /// **'Switched to audio call for stability'**
  String get fallbackToAudioMsg;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return lookupAppLocalizations(locale);
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

Future<AppLocalizations> lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return app_localizations_ar
          .loadLibrary()
          .then((dynamic _) => app_localizations_ar.AppLocalizationsAr());
    case 'en':
      return app_localizations_en
          .loadLibrary()
          .then((dynamic _) => app_localizations_en.AppLocalizationsEn());
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
