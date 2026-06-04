import 'dart:io'; // Kept ONLY for FileImage on native usage, but conditional imports preferred.

import 'package:flutter/foundation.dart'; // for kIsWeb if needed
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:talkmate_ai/controllers/auth_controller.dart';
import 'package:talkmate_ai/data/models/user_model.dart';
import 'package:talkmate_ai/data/repositories/contracts/i_user_repository.dart';
import 'package:talkmate_ai/data/services/storage_service.dart';
import 'package:talkmate_ai/localization/app_localizations.dart';
// Better practice: use CrossFileImage or just rely on kIsWeb check.
// Since we are fixing cross-platform, we should avoid dart:io at top level if possible,
// but FileImage requires dart:io File.
// Solution: Use Image.network (for web) or Image.file (native) conditionally.

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _auth = Get.find<AuthController>();
  final _userRepo = Get.find<IUserRepository>();

  final _nameCtrl = TextEditingController();
  final _aboutCtrl = TextEditingController();
  AppLocalizations get l10n => AppLocalizations.of(context);

  bool _loading = true;
  AppUser? _user;
  XFile? _pickedImage; // Changed from File to XFile

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final uid = _auth.userId;
      if (uid.isEmpty) {
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }
      final u =
          await _userRepo.getById(uid).timeout(const Duration(seconds: 6));
      if (!mounted) return;
      setState(() {
        _user = u;
        _nameCtrl.text = u?.displayName ?? _auth.userName;
        _aboutCtrl.text = u?.about ?? '';
        _loading = false;
      });
    } catch (e) {
      // Fallback to AuthController cached values so the screen doesn't hang
      if (!mounted) return;
      setState(() {
        _user = AppUser(
          id: _auth.userId,
          email: _auth.userEmail,
          displayName: _auth.userName.isNotEmpty ? _auth.userName : null,
          photoUrl: _auth.userPhoto.isNotEmpty ? _auth.userPhoto : null,
          status: UserStatus.online,
          createdAt: DateTime.now(),
          lastSeen: DateTime.now(),
        );
        _nameCtrl.text = _auth.userName;
        _aboutCtrl.text = '';
        _loading = false;
      });
      Get.snackbar(
        l10n.alert,
        l10n.profileDataLoadError,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      // ImagePicker supports Web, Android, iOS, Windows (if plugin used)
      // If Windows plugin missing, file_picker fallback might be needed but image_picker usually covers it.
      // If native Windows is not supported by image_picker, we use file_picker fallback logic here.

      XFile? xfile;

      if (!kIsWeb && (GetPlatform.isWindows || GetPlatform.isLinux)) {
        // Fallback for desktop if image_picker doesn't support it yet (though it mostly does in recent versions).
        // But sticking to standard ImagePicker first.
        xfile =
            await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024);
      } else {
        xfile =
            await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024);
      }

      if (xfile != null && mounted) {
        setState(() => _pickedImage = xfile);
      }
    } catch (e) {
      Get.snackbar(l10n.error, '${l10n.imageSelectionError}: $e',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white);
    }
  }

  Future<void> _save() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final uid = _auth.userId;
      if (uid.isEmpty) throw Exception('Not logged in');

      String? photoUrl = _user?.photoUrl;
      if (_pickedImage != null) {
        try {
          final path =
              'users/$uid/profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
          // Use XFile upload method
          final (url, _) = await StorageService.instance.uploadFile(
            file: _pickedImage!,
            path: path,
          );
          photoUrl = url;
        } catch (e) {
          Get.snackbar(
            l10n.alert,
            '${l10n.imageUploadError}\n${e.toString()}',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.orange,
            colorText: Colors.white,
            duration: const Duration(seconds: 4),
          );
        }
      }

      await _userRepo.updateProfile(
        uid,
        displayName:
            _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
        about: _aboutCtrl.text.trim(),
        photoUrl: photoUrl,
      );
      // Also update FirebaseAuth profile and local AuthController cache
      try {
        await _auth.updateProfile(
          displayName:
              _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
          photoUrl: photoUrl,
          about: _aboutCtrl.text.trim(),
        );
      } catch (_) {}
      if (!mounted) return;
      Get.back();
      Get.snackbar(l10n.changesSavedSuccessfully, l10n.profileUpdated,
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      Get.snackbar(l10n.error, e.toString(),
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(
          l10n.editProfile,
          style: theme.appBarTheme.titleTextStyle,
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Get.back(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildAvatarSection(theme, l10n),
                  const SizedBox(height: 40),
                  _buildFormFields(theme, l10n),
                  const SizedBox(height: 48),
                  _buildSaveButton(theme, l10n),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildAvatarSection(ThemeData theme, AppLocalizations l10n) {
    ImageProvider? imageProvider;

    if (_pickedImage != null) {
      if (kIsWeb) {
        imageProvider = NetworkImage(_pickedImage!.path);
      } else {
        imageProvider = FileImage(File(_pickedImage!.path));
      }
    } else if (_user?.photoUrl != null && _user!.photoUrl!.isNotEmpty) {
      imageProvider = NetworkImage(_user!.photoUrl!);
    }

    return Column(
      children: [
        GestureDetector(
          onTap: _pickImage,
          child: Stack(
            alignment: AlignmentDirectional.bottomEnd,
            children: [
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: theme.colorScheme.primary, width: 2),
                ),
                padding: const EdgeInsets.all(4),
                child: CircleAvatar(
                  radius: 60,
                  backgroundColor:
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                  backgroundImage: imageProvider,
                  child: imageProvider == null
                      ? Icon(Icons.person_rounded,
                          size: 80, color: theme.colorScheme.onPrimaryContainer)
                      : null,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: theme.colorScheme.surface, width: 2),
                ),
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.camera_alt_rounded,
                    color: theme.colorScheme.onPrimary, size: 20),
              )
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _pickImage,
          child: Text(
            l10n.changeProfilePhoto,
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w500,
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFormFields(ThemeData theme, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, right: 4, left: 4),
          child: Text(
            l10n.fullName,
            style: TextStyle(
              color: theme.hintColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        TextField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            prefixIcon:
                Icon(Icons.person_outline_rounded, color: theme.hintColor),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.only(bottom: 8, right: 4, left: 4),
          child: Text(
            l10n.bio,
            style: TextStyle(
              color: theme.hintColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        TextField(
          controller: _aboutCtrl,
          maxLines: 4,
          maxLength: 150,
          decoration: InputDecoration(
            prefixIcon: Padding(
              padding: const EdgeInsets.only(bottom: 60),
              child: Icon(Icons.info_outline_rounded, color: theme.hintColor),
            ),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.all(16),
            counterText: '${_aboutCtrl.text.length}/150',
          ),
          onChanged: (val) => setState(() {}),
        ),
      ],
    );
  }

  Widget _buildSaveButton(ThemeData theme, AppLocalizations l10n) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: _save,
        icon: _loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: theme.colorScheme.onPrimary))
            : Icon(Icons.check_rounded, color: theme.colorScheme.onPrimary),
        label: Text(
          l10n.saveChanges,
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onPrimary),
        ),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 0,
        ),
      ),
    );
  }
}
