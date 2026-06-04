# Password Reset Deep Link Implementation Guide

## Overview
This document provides a complete guide to the password reset Deep Link implementation using the scheme `talkmate://auth/reset-password`.

## Implementation Status

### ✅ Completed
1. **Reset Password Screen** (`lib/screens/auth/reset_password_screen.dart`)
   - Production-ready UI with password strength indicator
   - Password requirements validation
   - Comprehensive error handling
   - Success state with automatic navigation

2. **Deep Link Handler** (`lib/services/platform/platform_service.dart`)
   - URI parsing for `talkmate://auth/reset-password`
   - Safe navigation to Reset Password screen
   - No assumptions about app state

3. **Authentication Service** (`lib/services/auth/supabase_auth_service.dart`)
   - `updatePassword()` method for secure password updates
   - `getPasswordRecoveryRedirectUrl()` for email template configuration

4. **Navigation Routing** (`lib/main.dart`)
   - Route: `/auth/reset-password` → `ResetPasswordScreen`
   - Proper integration with GetX navigation

5. **Platform Configuration**

   **Android** (`android/app/src/main/AndroidManifest.xml`)
   - Intent Filter for `talkmate://auth/reset-password`
   - `android:host="auth"` 
   - `android:pathPrefix="/reset-password"`
   - Coexists with existing chat deep links

   **iOS** (`ios/Runner/Info.plist`)
   - `CFBundleURLTypes` registration
   - URL scheme: `talkmate`

   **macOS** (`macos/Runner/Info.plist`)
   - `CFBundleURLTypes` registration
   - URL scheme: `talkmate`

   **Windows**
   - Supported via `app_links` plugin
   - No manual registry configuration needed (handled by plugin)

---

## Supabase Dashboard Configuration (MANUAL STEPS REQUIRED)

### Step 1: Configure Password Recovery Email Template

Navigate to **Supabase Dashboard** → **Authentication** → **Email Templates** → **Reset Password**

**Current state:** Points to `http://localhost:3000/`

**Required change:** Update the password recovery redirect URL

1. Open the **Reset Password** email template
2. Find the password recovery link (usually in format):
   ```
   {{ .ConfirmationURL }}
   ```
   Or similar template variable

3. The template should generate URLs like:
   ```
   talkmate://auth/reset-password?token=<recovery_token>&type=recovery
   ```

### Step 2: Alternative - Use Email Template Raw Editor

If your Supabase version allows:
1. Use the **Raw Email Editor**
2. Ensure the recovery link is formatted as:
   ```html
   <a href="talkmate://auth/reset-password?token={{ .Token }}&type=recovery">
     Reset Your Password
   </a>
   ```

---

## How It Works

### User Flow

```
1. User clicks "Forgot Password" on Login Screen
2. Enters email and clicks "Send"
3. AuthController.resetPassword(email) triggers
4. Supabase sends recovery email with Deep Link:
   talkmate://auth/reset-password?token=...
5. User clicks link in email
6. OS routes to TalkMate AI app
7. PlatformService._handleUri() receives URI
8. Deep Link handler navigates to /auth/reset-password
9. ResetPasswordScreen loads with active session
10. User enters new password + confirmation
11. ResetPasswordScreen calls Supabase.auth.updateUser()
12. Password updated successfully
13. User redirected to /login
```

### Session Management

The Deep Link click **automatically creates a recovery session** in Supabase. The `ResetPasswordScreen`:
1. Checks for active session via `Supabase.instance.client.auth.currentSession`
2. If session exists → user can update password
3. If session null/expired → show error and request new reset link

**No manual token handling required** - Supabase manages the recovery session.

---

## Error Handling

The implementation handles:

| Error | Handling |
|-------|----------|
| Expired recovery link | User gets message: "Session expired. Please request a new password reset link." |
| Invalid/tampered token | Supabase rejects update → AuthException caught |
| Network failure | Try/catch block with user-friendly error message |
| Already-used link | Session automatically invalidated after first use |
| Missing session | Validation on screen load |

---

## Testing

### Android Testing

```bash
# 1. Build debug APK
flutter build apk --debug

# 2. Install on device
adb install -r build/app/outputs/apk/debug/app-debug.apk

# 3. Test deep link directly
adb shell am start -a android.intent.action.VIEW \
  -d "talkmate://auth/reset-password?token=test123&type=recovery"

# 4. Or simulate email click (via adb or Firebase Console)
```

### iOS Testing

```bash
# 1. Build and run
flutter run

# 2. Simulate deep link in Xcode debugger
# Open scheme URL in Safari on simulator:
# - Device → Launch Xcode
# - Navigate to: talkmate://auth/reset-password

# 3. Or use xcrun to test:
xcrun simctl openurl booted "talkmate://auth/reset-password"
```

### Web Testing (PWA Fallback)

Web **cannot** use custom URI schemes. Recommended approach:

**Option A: Separate Web URL**
- Supabase detects web client
- Sends: `https://yourdomain.com/auth/reset-password?token=xxx`
- Implement web-specific reset page

**Option B: Use Supabase Redirect URL**
- Configure in Supabase Dashboard
- Set redirect to your PWA origin
- Supabase handles the rest

### Windows Testing

```bash
# 1. Build Windows app
flutter build windows

# 2. Test deep link via command line (PowerShell):
Start-Process "talkmate://auth/reset-password?token=test123&type=recovery"

# 3. Verify app launches and navigates to reset screen
```

---

## Files Modified

| File | Changes |
|------|---------|
| `lib/screens/auth/reset_password_screen.dart` | ✨ **NEW** - Production reset screen |
| `lib/services/auth/supabase_auth_service.dart` | Added `updatePassword()`, `getPasswordRecoveryRedirectUrl()` |
| `lib/services/platform/platform_service.dart` | Added `talkmate://auth/reset-password` handler |
| `lib/main.dart` | Added `/auth/reset-password` route |
| `android/app/src/main/AndroidManifest.xml` | Added auth reset-password intent filter |
| `ios/Runner/Info.plist` | Added CFBundleURLTypes |
| `macos/Runner/Info.plist` | Added CFBundleURLTypes |

## Files NOT Modified (Existing Architecture Preserved)

- `lib/controllers/auth_controller.dart` - Still works via `resetPassword(email)`
- `lib/screens/change_password_screen.dart` - For logged-in users (different flow)
- `lib/screens/auth/login_screen.dart` - Existing "Forgot Password" button

---

## Security Considerations

### ✅ Secure by Design

1. **Session-based** - Token not exposed in app code
2. **One-time use** - Supabase invalidates after first use
3. **Expiration** - Recovery links expire (default 24 hours)
4. **HTTPS only** - Email link must use HTTPS or custom scheme
5. **Password validation** - 8+ chars, uppercase, lowercase, number
6. **No logging** - Password never logged or printed
7. **State validation** - Checks session on screen load

### ⚠️ Important

- Ensure Supabase has **"Confirm email before signing in"** disabled (or handle in UI)
- Recovery links work only on **first click** (session auto-invalidated after password update)
- User must use the **exact email** they registered with

---

## Troubleshooting

### Deep Link Not Opening App

**Android:**
- Verify intent filter in `AndroidManifest.xml`
- Check scheme: `android:scheme="talkmate"`
- Check host: `android:host="auth"`
- Run: `adb shell am start -a android.intent.action.VIEW -d "talkmate://auth/reset-password"`

**iOS:**
- Verify `CFBundleURLSchemes` in `Info.plist`
- Run: `xcrun simctl openurl booted "talkmate://auth/reset-password"`

**Windows:**
- Verify app_links plugin is built
- Check Windows firewall/antivirus blocking URL protocol
- Test via PowerShell: `Start-Process "talkmate://auth/reset-password"`

### Session Expired Error

- Recovery link is single-use
- User must click the link in the original email
- If expired, user must request new password reset
- Default expiration: 24 hours (Supabase setting)

### Password Update Fails

- Verify active session: Check `_checkSession()` in ResetPasswordScreen
- Verify Supabase connection
- Check Supabase auth configuration
- Ensure password meets requirements (8+ chars, upper, lower, number)

---

## Next Steps

### 1. Manual Supabase Configuration (Required)

Update your Supabase email template:

```bash
# Via Supabase CLI:
supabase link
supabase functions deploy --update-templates
```

Or manually in dashboard:
- Auth → Email Templates → Reset Password
- Update recovery link to use `talkmate://auth/reset-password`

### 2. Testing

- [ ] Test on Android device
- [ ] Test on iOS device/simulator
- [ ] Test on Windows desktop
- [ ] Test on macOS
- [ ] Test web fallback (if applicable)

### 3. Deployment

- [ ] Build signed APK for Android
- [ ] Build signed IPA for iOS
- [ ] Verify email templates in production Supabase project
- [ ] Test full flow end-to-end with real recovery email

---

## Architecture Decisions

### Why Deep Link Instead of Web Redirect?

| Aspect | Deep Link | Web Redirect |
|--------|-----------|-------------|
| User Experience | Native app opens seamlessly | Web view, copy/paste required |
| Session Management | Automatic (Supabase) | Manual handling needed |
| Platform Coverage | Mobile + Desktop (Windows/Mac) | Web only |
| Notifications | Can trigger app notification | Limited |
| Offline Capable | App can handle offline | Not applicable |

### Why Not Use Firebase Dynamic Links?

- Project uses Supabase (not Firebase)
- Direct Supabase support is simpler
- Custom scheme gives complete control

### Design Pattern: Single Responsibility

- `ResetPasswordScreen` → UI + validation only
- `SupabaseAuthService` → Auth API calls only
- `PlatformService` → Deep Link routing only
- `AuthController` → High-level auth state

---

## References

- [Supabase Auth Deep Links](https://supabase.com/docs/guides/auth/managing-user-data#password-reset)
- [Flutter App Links Plugin](https://pub.dev/packages/app_links)
- [Android Deep Links Documentation](https://developer.android.com/training/app-links/deep-linking)
- [iOS Universal Links](https://developer.apple.com/ios/universal-links/)

---

## Support

For issues, check:
1. Supabase email template configuration
2. App logs: `flutter run` with verbose output
3. Platform-specific logs: Xcode, Android Studio, or Windows debugger
