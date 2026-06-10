import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:talkmate_ai/utils/error_messages.dart';

/// Reset password screen accessible via Deep Link: talkmate://auth/reset-password
/// This screen handles the password recovery flow after user clicks the email link.
class ResetPasswordScreen extends StatefulWidget {
  /// The recovery token from Supabase (optional - can be extracted from Deep Link)
  final String? recoveryToken;

  const ResetPasswordScreen({
    super.key,
    this.recoveryToken,
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  late final SupabaseClient _supabase; // ✅ Lazy init - prevents crash on instantiation

  bool _isLoading = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  String? _errorMessage;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    _initializeSupabase();
    _handleRecoveryFlow();
  }

  /// Initialize Supabase client safely (called after State is constructed)
  void _initializeSupabase() {
    try {
      _supabase = Supabase.instance.client;
      debugPrint('✅ ResetPasswordScreen: Supabase client initialized successfully');
    } catch (e) {
      setState(() {
        _errorMessage = 'System error: Cannot initialize authentication. Please try again.';
      });
      debugPrint('❌ ResetPasswordScreen: Failed to initialize Supabase: $e');
    }
  }

  /// Handle complete recovery flow: code exchange (if needed) then session check
  Future<void> _handleRecoveryFlow() async {
    try {
      // Check if recovery code was passed via Deep Link
      final recoveryCode = Get.arguments?['recoveryCode'] as String?;
      
      if (recoveryCode != null && recoveryCode.isNotEmpty) {
        debugPrint('🔄 ResetPasswordScreen: Recovery code received, performing PKCE exchange');
        await _performCodeExchange(recoveryCode);
      }
      
      // After code exchange (if any), check session
      await _checkSession();
    } catch (e) {
      debugPrint('❌ ResetPasswordScreen: Recovery flow error: $e');
      final friendlyMessage = ErrorMessages.getPasswordRecoveryErrorMessage(e);
      setState(() {
        _errorMessage = friendlyMessage;
      });
    }
  }

  /// Exchange PKCE recovery code for session
  Future<void> _performCodeExchange(String code) async {
    try {
      debugPrint('🔄 Attempting PKCE code exchange with code: ${code.substring(0, 8)}...');
      
      // Exchange code for session
      await _supabase.auth.exchangeCodeForSession(code);
      debugPrint('✅ PKCE code exchange successful');
      
      // Verify session was created
      final session = _supabase.auth.currentSession;
      if (session == null) {
        throw Exception('Recovery session was not created after code exchange');
      }
      
      debugPrint('✅ Recovery session created for user: ${session.user.email}');
    } catch (e) {
      debugPrint('❌ Code exchange failed: $e');
      // Use user-friendly error message
      final friendlyMessage = ErrorMessages.getPasswordRecoveryErrorMessage(e);
      throw Exception(friendlyMessage);
    }
  }

  /// Verify that user has an active recovery session
  Future<void> _checkSession() async {
    try {
      final session = _supabase.auth.currentSession;
      if (session == null) {
        // Create a fake AuthApiException-like error for message mapping
        setState(() {
          _errorMessage = ErrorMessages.getUserFriendlyMessage(
            Exception('invalid_recovery_token'),
          );
        });
        debugPrint('ResetPasswordScreen: No active session found');
      } else {
        debugPrint('✅ ResetPasswordScreen: Active session verified for user ${session.user.email}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to verify session: $e';
      });
      debugPrint('ResetPasswordScreen: Session verification error: $e');
    }
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  /// Validate password strength
  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Password must contain at least one uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'Password must contain at least one lowercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Password must contain at least one number';
    }
    return null;
  }

  /// Validate password confirmation
  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please confirm your password';
    }
    if (value != _passwordCtrl.text) {
      return 'Passwords do not match';
    }
    return null;
  }

  /// Submit the new password using Supabase updateUser
  Future<void> _submitPasswordReset() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get current session
      final session = _supabase.auth.currentSession;
      if (session == null) {
        throw Exception('No active session. Please use the password reset link from your email.');
      }

      // Update user password using Supabase
      await _supabase.auth.updateUser(
        UserAttributes(password: _passwordCtrl.text),
      );

      // Success
      setState(() {
        _isSuccess = true;
        _isLoading = false;
      });

      // Show success message
      if (mounted) {
        final locale = Get.locale?.languageCode ?? 'en';
        final isArabic = locale == 'ar';
        
        Get.snackbar(
          isArabic ? 'نجاح' : 'Success',
          isArabic 
              ? 'تم تغيير كلمة المرور بنجاح.' 
              : 'Your password has been reset successfully.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.green,
          colorText: Colors.white,
          duration: const Duration(seconds: 3),
        );

        // Navigate to login after a short delay
        Future.delayed(const Duration(seconds: 2), () {
          Get.offAllNamed('/login');
        });
      }
    } on AuthException catch (e) {
      final friendlyMessage = ErrorMessages.getPasswordUpdateErrorMessage(e);
      setState(() {
        _errorMessage = friendlyMessage;
        _isLoading = false;
      });
      if (mounted) {
        final locale = Get.locale?.languageCode ?? 'en';
        final isArabic = locale == 'ar';
        
        Get.snackbar(
          isArabic ? 'خطأ في المصادقة' : 'Authentication Error',
          friendlyMessage,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      final friendlyMessage = ErrorMessages.getPasswordUpdateErrorMessage(e);
      setState(() {
        _errorMessage = friendlyMessage;
        _isLoading = false;
      });
      if (mounted) {
        final locale = Get.locale?.languageCode ?? 'en';
        final isArabic = locale == 'ar';
        
        Get.snackbar(
          isArabic ? 'خطأ' : 'Error',
          friendlyMessage,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset Password'),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isSuccess
          ? _buildSuccessState(context)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Text(
                    'Set New Password',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please enter a strong password for your account.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
                  const SizedBox(height: 24),

                  // Error message if any
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        border: Border.all(color: Colors.red),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.red, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_errorMessage != null) const SizedBox(height: 16),

                  // Form
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Password field
                        TextFormField(
                          controller: _passwordCtrl,
                          obscureText: !_showPassword,
                          enabled: !_isLoading,
                          decoration: InputDecoration(
                            labelText: 'New Password',
                            hintText: 'Enter a strong password',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(
                                    () => _showPassword = !_showPassword);
                              },
                            ),
                          ),
                          validator: _validatePassword,
                          onChanged: (_) {
                            _formKey.currentState?.validate();
                          },
                        ),
                        const SizedBox(height: 16),

                        // Password strength indicator
                        _buildPasswordStrengthIndicator(_passwordCtrl.text),
                        const SizedBox(height: 16),

                        // Confirm password field
                        TextFormField(
                          controller: _confirmPasswordCtrl,
                          obscureText: !_showConfirmPassword,
                          enabled: !_isLoading,
                          decoration: InputDecoration(
                            labelText: 'Confirm Password',
                            hintText: 'Re-enter your password',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showConfirmPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(() =>
                                    _showConfirmPassword =
                                        !_showConfirmPassword);
                              },
                            ),
                          ),
                          validator: _validateConfirmPassword,
                        ),
                        const SizedBox(height: 24),

                        // Password requirements
                        _buildPasswordRequirements(),
                        const SizedBox(height: 24),

                        // Submit button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _submitPasswordReset,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check),
                            label: Text(
                              _isLoading
                                  ? 'Resetting Password...'
                                  : 'Reset Password',
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),

                        // Back to login link
                        const SizedBox(height: 16),
                        Center(
                          child: TextButton(
                            onPressed: _isLoading ? null : () => Get.back(),
                            child: const Text('Back to Login'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// Build success state UI
  Widget _buildSuccessState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle,
              size: 80,
              color: Colors.green,
            ),
            const SizedBox(height: 24),
            Text(
              'Password Reset Successful',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Your password has been updated. You will be redirected to the login screen.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }

  /// Build password strength indicator
  Widget _buildPasswordStrengthIndicator(String password) {
    double strength = 0;
    String label = '';
    Color color = Colors.grey;

    if (password.isEmpty) {
      label = 'No password';
    } else {
      int checks = 0;
      if (password.length >= 8) checks++;
      if (password.length >= 12) checks++;
      if (RegExp(r'[A-Z]').hasMatch(password)) checks++;
      if (RegExp(r'[a-z]').hasMatch(password)) checks++;
      if (RegExp(r'[0-9]').hasMatch(password)) checks++;
      if (RegExp(r'[!@#$%^&*]').hasMatch(password)) checks++;

      strength = (checks / 6).clamp(0, 1);

      if (strength < 0.3) {
        label = 'Weak';
        color = Colors.red;
      } else if (strength < 0.6) {
        label = 'Fair';
        color = Colors.orange;
      } else if (strength < 0.8) {
        label = 'Good';
        color = Colors.amber;
      } else {
        label = 'Strong';
        color = Colors.green;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Password Strength',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: strength,
            minHeight: 6,
            backgroundColor: Colors.grey.withValues(alpha: 0.3),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  /// Build password requirements checklist
  Widget _buildPasswordRequirements() {
    final password = _passwordCtrl.text;
    final requirements = [
      ('At least 8 characters', password.length >= 8),
      ('At least one uppercase letter', RegExp(r'[A-Z]').hasMatch(password)),
      ('At least one lowercase letter', RegExp(r'[a-z]').hasMatch(password)),
      ('At least one number', RegExp(r'[0-9]').hasMatch(password)),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: Theme.of(context).dividerColor,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Password Requirements',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          ...requirements.map((req) {
            final (label, met) = req;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    met ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 16,
                    color: met ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: met ? Colors.green : Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
