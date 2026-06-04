# 🧪 PKCE Password Recovery - Complete Testing Guide

**Document Version:** 1.0
**Last Updated:** 2026-06-04 20:34
**Status:** Ready for Testing

---

## 🎯 Testing Overview

This guide provides step-by-step instructions to verify that the PKCE password recovery flow is working correctly on all platforms.

### Quick Summary of Changes
- ✅ Recovery code detection from Deep Link (`?code=xxx`)
- ✅ Automatic PKCE code exchange before navigation
- ✅ Duplicate link protection
- ✅ Enhanced error handling and diagnostics
- ✅ Improved user error messages

---

## 🔧 Pre-Testing Setup

### Build Requirements

#### Windows
```powershell
# Clean and rebuild
flutter clean
flutter build windows --release

# Verify build
Get-Item "build\windows\x64\runner\Release\talkmate_ai.exe"
```

#### Android
```bash
# Clean and rebuild
flutter clean
flutter build apk --release

# Verify APK
ls -la build/app/outputs/flutter-apk/app-release.apk
```

#### iOS
```bash
# Clean and rebuild
flutter clean
flutter build ios --release

# Verify archive
open build/ios/archive/Runner.xcarchive
```

#### macOS
```bash
# Clean and rebuild
flutter clean
flutter build macos --release

# Verify app
open build/macos/Build/Products/Release/talkmate_ai.app
```

### Diagnostic Setup

#### Windows - Prepare Log File Location
```powershell
# Create temp directory for logs
New-Item -ItemType Directory -Path "C:\Temp" -Force
Write-Host "Log location: C:\Temp\talkmate_deeplink.log"
```

#### Android - Enable ADB Logging
```bash
# Connect device or emulator
adb devices

# Clear logs
adb logcat --clear

# Start listening (in separate terminal)
adb logcat
```

---

## 📋 Test Scenarios

### Test A: Code Detection in Deep Link

**Objective:** Verify that recovery code is detected in Deep Link parameters

**Procedure (Windows):**
```powershell
# Run app
& "build\windows\x64\runner\Release\talkmate_ai.exe"

# Wait for app to start (5 seconds)
Start-Sleep -Seconds 5

# Send test Deep Link
Start-Process "talkmate://auth/reset-password?code=test-code-12345"

# Wait for processing
Start-Sleep -Seconds 2

# Check logs
Get-Content "C:\Temp\talkmate_deeplink.log" -Tail 20
```

**Expected Logs:**
```
[TIMESTAMP] RECOVERY_CODE_DETECTED
[TIMESTAMP] RECOVERY_CODE (masked) = test-code...
[TIMESTAMP] EXCHANGING_CODE_FOR_SESSION
[TIMESTAMP] ✗ CODE_EXCHANGE_FAILED: ...
```

**Expected UI Behavior:**
- ✅ App opens
- ✅ Error snackbar appears: "This password reset link is invalid or has expired"
- ✅ No crash
- ✅ App remains responsive

**Result:** ✅ PASS / ❌ FAIL

---

### Test B: Real Email-Based Password Recovery (CRITICAL)

**Objective:** End-to-end test with real Supabase recovery email

**Procedure:**

**Step 1: Generate Recovery Email**
1. Open app on Windows/Android/iOS/macOS
2. Go to Login screen
3. Click "Forgot Password?" button
4. Enter test email: `test@example.com`
5. Click "Send Reset Link"
6. Wait for confirmation: "Check your email..."

**Step 2: Receive Email**
1. Check mailbox for recovery email from Supabase
2. Email subject: "Reset your password for TalkMate AI"
3. Email contains recovery link with format:
   ```
   [App URL]?code=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   ```

**Step 3: Test on Windows**

**Cold Start Test:**
```powershell
# Close app completely
Get-Process talkmate_ai -ErrorAction SilentlyContinue | Stop-Process -Force

# Wait 2 seconds
Start-Sleep -Seconds 2

# Click recovery link from email (or paste this command with real code):
Start-Process "talkmate://auth/reset-password?code=REAL_CODE_FROM_EMAIL"

# Wait 3 seconds for app to start and exchange code
Start-Sleep -Seconds 3

# Observe: App should launch directly to ResetPasswordScreen
```

**Warm Start Test:**
1. Keep app running
2. Click recovery link from email (click again)
3. Observe: ResetPasswordScreen should appear

**Expected Behavior:**
- ✅ App launches or comes to foreground
- ✅ Navigates directly to ResetPasswordScreen
- ✅ ResetPasswordScreen has NO error message
- ✅ Password input fields are visible and enabled
- ✅ Logs show:
  ```
  CODE_EXCHANGE_SUCCESSFUL
  SESSION_CREATED_SUCCESSFULLY
  SESSION_USER_EMAIL = test@***
  ```

**Step 4: Reset Password**
1. In ResetPasswordScreen:
2. New Password: `TestPassword123!`
3. Confirm Password: `TestPassword123!`
4. Click "Reset Password"

**Expected Behavior:**
- ✅ Loading indicator appears
- ✅ After 1-2 seconds: "Your password has been reset successfully"
- ✅ Redirected to Login screen
- ✅ No error messages

**Step 5: Verify New Password Works**
1. On Login screen
2. Enter email: `test@example.com`
3. Enter password: `TestPassword123!`
4. Click "Login"

**Expected Behavior:**
- ✅ Login succeeds
- ✅ Navigated to home screen
- ✅ User is authenticated

**Log Verification:**
```powershell
# Check complete log sequence
Get-Content "C:\Temp\talkmate_deeplink.log" | Select-String "RECOVERY_CODE_DETECTED|CODE_EXCHANGE_SUCCESSFUL|SESSION_CREATED|RESET_PASSWORD_NAVIGATION_EXECUTED"
```

**Result:** ✅ PASS / ❌ FAIL

---

### Test C: Duplicate Link Protection

**Objective:** Verify that opening same link twice processes only once

**Procedure:**

**Step 1: Open Same Link Multiple Times Quickly**
```powershell
# Get a recovery code from email
$code = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Open link first time
Start-Process "talkmate://auth/reset-password?code=$code"
Start-Sleep -Seconds 1

# Open same link immediately again
Start-Process "talkmate://auth/reset-password?code=$code"
Start-Sleep -Seconds 1

# Open third time
Start-Process "talkmate://auth/reset-password?code=$code"
Start-Sleep -Seconds 2

# Check logs
Get-Content "C:\Temp\talkmate_deeplink.log" -Tail 30
```

**Expected Behavior:**
- ✅ ResetPasswordScreen opens only once
- ✅ No duplicate dialogs
- ✅ Logs show:
  - First time: `RECOVERY_CODE_DETECTED` + `CODE_EXCHANGE_SUCCESSFUL`
  - Second time: `DUPLICATE_DEEP_LINK_SKIPPED`
  - Third time: `DUPLICATE_DEEP_LINK_SKIPPED`

**Result:** ✅ PASS / ❌ FAIL

---

### Test D: Expired/Invalid Recovery Code

**Objective:** Verify graceful handling of expired or invalid codes

**Procedure:**

**Part D1: Expired Code (Wait 30+ minutes)**
1. Request password recovery email
2. Extract recovery code from email
3. Wait 30 minutes (exceeds typical 10-15 minute expiry)
4. Click link or run:
   ```powershell
   Start-Process "talkmate://auth/reset-password?code=$oldCode"
   ```

**Part D2: Manually Crafted Invalid Code**
1. Run:
   ```powershell
   Start-Process "talkmate://auth/reset-password?code=invalid-code-123456"
   ```

**Expected Behavior for Both:**
- ✅ App opens
- ✅ Error snackbar appears: "This password reset link is invalid or has expired"
- ✅ ResetPasswordScreen does NOT open
- ✅ No crash or exception
- ✅ Logs show:
  ```
  CODE_EXCHANGE_FAILED
  SESSION_CREATION_FAILED
  ```

**User Should See:**
```
Recovery Link Invalid
This password reset link is invalid or has expired. Please request a new one.
```

**Result:** ✅ PASS / ❌ FAIL

---

### Test E: Regression Testing (Existing Features)

**Objective:** Verify no regression in existing functionality

#### Test E1: Chat Deep Links Still Work
**Procedure:**
1. Get chat ID from app
2. Send Deep Link: `talkmate://chat/chat-id-12345`
3. Verify: Chat opens without error

**Result:** ✅ PASS / ❌ FAIL

#### Test E2: Normal Login Still Works
**Procedure:**
1. App login screen
2. Enter credentials
3. Click Login
4. Verify: Login succeeds

**Result:** ✅ PASS / ❌ FAIL

#### Test E3: Normal Registration Still Works
**Procedure:**
1. App login screen
2. Click Register
3. Fill form
4. Submit
5. Verify: Registration succeeds, verification email sent

**Result:** ✅ PASS / ❌ FAIL

#### Test E4: Logout Still Works
**Procedure:**
1. Login to app
2. Go to settings/profile
3. Click Logout
4. Verify: Redirected to login screen

**Result:** ✅ PASS / ❌ FAIL

---

### Test F: Platform-Specific Tests

#### Test F1: Android
**Requirements:**
- Android emulator or real device
- adb installed

**Procedure:**
```bash
# Build and install
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk

# Get recovery code from email

# Send Deep Link
adb shell am start -a android.intent.action.VIEW \
  -d "talkmate://auth/reset-password?code=YOUR_CODE"

# Observe: App should launch and navigate to ResetPasswordScreen

# Check logs
adb logcat | grep -i "recovery\|exchange\|session"
```

**Expected Behavior:**
- ✅ App launches
- ✅ ResetPasswordScreen opens
- ✅ No error messages

**Result:** ✅ PASS / ❌ FAIL

---

#### Test F2: iOS
**Requirements:**
- Mac with Xcode
- iOS device or simulator

**Procedure:**
```bash
# Build
flutter build ios --release

# Run on simulator or device
flutter run -d <device_id> --release

# Generate recovery email using on-device login

# Click recovery link in email
# Safari will prompt to open in app

# Verify: App launches and shows ResetPasswordScreen
```

**Expected Behavior:**
- ✅ App launches from Deep Link
- ✅ ResetPasswordScreen appears
- ✅ Can enter new password

**Result:** ✅ PASS / ❌ FAIL

---

#### Test F3: macOS
**Requirements:**
- macOS device
- Xcode installed

**Procedure:**
```bash
# Build
flutter build macos --release

# Launch app
open build/macos/Build/Products/Release/talkmate_ai.app

# Send Deep Link via terminal
open "talkmate://auth/reset-password?code=YOUR_CODE"

# Verify: App navigates to ResetPasswordScreen
```

**Expected Behavior:**
- ✅ App receives Deep Link
- ✅ ResetPasswordScreen opens
- ✅ No macOS-specific errors

**Result:** ✅ PASS / ❌ FAIL

---

## 📊 Testing Results Summary

### Test Results Template

```markdown
## 🧪 Testing Results - [DATE]

### Platform: [Windows/Android/iOS/macOS]
### Build Type: [Debug/Release]
### Date: [YYYY-MM-DD]

| Test | Result | Notes |
|------|--------|-------|
| A - Code Detection | ✅ PASS / ❌ FAIL | |
| B - Real Email Flow | ✅ PASS / ❌ FAIL | |
| C - Duplicate Protection | ✅ PASS / ❌ FAIL | |
| D - Expired Code | ✅ PASS / ❌ FAIL | |
| E1 - Chat Deep Links | ✅ PASS / ❌ FAIL | |
| E2 - Login | ✅ PASS / ❌ FAIL | |
| E3 - Register | ✅ PASS / ❌ FAIL | |
| E4 - Logout | ✅ PASS / ❌ FAIL | |
| Overall | ✅ PASS / ❌ FAIL | |

### Key Observations
- [Observation 1]
- [Observation 2]
- [Observation 3]

### Issues Found
- [Issue 1 - Description - Severity]
- [Issue 2 - Description - Severity]

### Performance Metrics
- Deep Link to ResetPasswordScreen: [X]ms
- Code Exchange Duration: [X]ms
- Total Flow Time: [X]ms

### Tester Name: [Name]
### Signed Off: [YES/NO]
```

---

## 🔍 Troubleshooting During Testing

### Problem: Deep Link Not Opening App

**Diagnosis:**
```powershell
# Check Windows registry
Get-ItemProperty 'HKCU:\Software\Classes\talkmate'
```

**Solution:**
1. Rebuild Windows app
2. Reinstall the app (protocol registration happens during install)
3. Check firewall/security settings

---

### Problem: "Session expired" Error Still Shows

**Diagnosis:**
```powershell
# Check logs for:
Get-Content "C:\Temp\talkmate_deeplink.log" | Select-String "CODE_EXCHANGE_FAILED"
```

**Solutions:**
1. **If CODE_EXCHANGE_FAILED:** Code is invalid or expired
   - Request new recovery email
   - Verify Supabase dashboard settings
   
2. **If no exchange logs:** Code wasn't detected
   - Check Deep Link format in email
   - Verify `?code=` parameter exists
   - Check browser/email client didn't modify URL

3. **If exchange succeeded but session null:** Supabase issue
   - Check Supabase status page
   - Verify auth configuration in Supabase dashboard

---

### Problem: Duplicate Navigation Occurs

**Diagnosis:**
```powershell
# Check logs for:
Get-Content "C:\Temp\talkmate_deeplink.log" | Select-String "DUPLICATE|STREAM_URI|INITIAL_URI"
```

**Solution:**
- This is normal if same Deep Link received twice
- Duplicate protection should prevent double navigation
- If navigation still duplicates, check DeepLinkQueue implementation

---

### Problem: ResetPasswordScreen Never Appears

**Diagnosis:**
1. Check logs: `Get-Content "C:\Temp\talkmate_deeplink.log" -Tail 50`
2. Look for: `DEFERRED_DEEP_LINK_EXECUTED` vs `NO_MATCHING_ROUTE`

**Solutions:**
1. **If NO_MATCHING_ROUTE:** URI format incorrect
   - Verify: `talkmate://auth/reset-password`
   - Not: `talkmate://reset-password`
   
2. **If DEFERRED_DEEP_LINK_EXECUTED:** Navigation queued but screen not showing
   - Check main.dart route definitions
   - Verify `/auth/reset-password` route exists
   - Check if app is in background (bring to foreground)

---

### Problem: Logs Not Appearing

**Windows:**
```powershell
# Verify log file exists and app can write to it
Get-Item "C:\Temp\talkmate_deeplink.log" -ErrorAction SilentlyContinue

# If missing, create directory
New-Item -ItemType Directory -Path "C:\Temp" -Force

# Run app again and check
```

**Android:**
```bash
# Use adb to check logs
adb logcat | grep -i "deeplink\|exchangeCodeForSession"
```

---

## ✅ Sign-Off Criteria

Testing is COMPLETE when:

- ✅ Test A passed (Code detection works)
- ✅ Test B passed (Real email recovery works)
- ✅ Test C passed (Duplicate protection works)
- ✅ Test D passed (Expired code handled gracefully)
- ✅ Test E (all 4 passed - no regressions)
- ✅ Test F passed on all available platforms
- ✅ Performance acceptable (< 3 seconds total)
- ✅ Error messages are clear and helpful
- ✅ No crashes or exceptions
- ✅ Logs are comprehensive and helpful

---

## 🚀 After Testing

### If All Tests Pass ✅
1. Merge code to main branch
2. Create release notes
3. Deploy to production
4. Monitor diagnostic logs for 2-4 weeks
5. Gather user feedback

### If Any Test Fails ❌
1. Identify specific failure point from logs
2. Debug using diagnostic logs
3. Implement fix
4. Re-test the specific test case
5. If multiple failures, retry full test suite

---

## 📞 Support Contacts

- **Development:** [Team Lead]
- **QA:** [QA Lead]
- **DevOps:** [DevOps Lead]
- **On-Call:** [On-Call Engineer]

---

**Document Version:** 1.0
**Last Updated:** 2026-06-04
**Status:** READY FOR TESTING
