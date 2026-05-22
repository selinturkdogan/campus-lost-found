import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/user_avatar.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _deptCtrl;
  late final TextEditingController _bioCtrl;

  bool _phonePublic = false;
  bool _cityPublic = false;
  File? _pickedPhoto;
  bool _removeExistingPhoto = false;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _nameCtrl = TextEditingController(text: auth.displayName);
    _phoneCtrl = TextEditingController(text: auth.phone ?? '');
    _cityCtrl = TextEditingController(text: auth.city ?? '');
    _deptCtrl = TextEditingController(text: auth.department ?? '');
    _bioCtrl = TextEditingController(text: auth.bio ?? '');
    _phonePublic = auth.phonePublic;
    _cityPublic = auth.cityPublic;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _cityCtrl.dispose();
    _deptCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            if (context.read<AuthProvider>().photoUrl != null ||
                _pickedPhoto != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: Colors.red),
                title: const Text('Remove photo',
                    style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(context, null),
              ),
          ],
        ),
      ),
    );

    if (!mounted) return;

    if (source == null) {
      // Remove was selected (or sheet dismissed). If a photo exists, treat
      // as remove.
      if (context.read<AuthProvider>().photoUrl != null ||
          _pickedPhoto != null) {
        setState(() {
          _pickedPhoto = null;
          _removeExistingPhoto = true;
        });
      }
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _pickedPhoto = File(picked.path);
      _removeExistingPhoto = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.updateProfile(
      displayName: _nameCtrl.text,
      phone: _phoneCtrl.text,
      city: _cityCtrl.text,
      department: _deptCtrl.text,
      bio: _bioCtrl.text,
      phonePublic: _phonePublic,
      cityPublic: _cityPublic,
      newPhotoFile: _pickedPhoto,
      removePhoto: _removeExistingPhoto,
    );
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated.')),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(auth.errorMessage ?? 'Failed to update profile.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final auth = context.watch<AuthProvider>();

    final showExistingPhoto =
        _pickedPhoto == null && !_removeExistingPhoto && auth.photoUrl != null;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(
                    bottom: BorderSide(color: scheme.outline, width: 1)),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: scheme.surfaceVariant,
                          shape: BoxShape.circle),
                      child: Icon(Icons.arrow_back_rounded,
                          size: 18, color: scheme.onSurface),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('Edit profile', style: textTheme.titleMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: auth.isLoading ? null : _save,
                    child: auth.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : Text('Save',
                            style: TextStyle(
                                color: scheme.primary,
                                fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar with edit
                      Center(
                        child: GestureDetector(
                          onTap: _pickPhoto,
                          child: Stack(
                            children: [
                              if (_pickedPhoto != null)
                                ClipOval(
                                  child: Image.file(
                                    _pickedPhoto!,
                                    width: 100,
                                    height: 100,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              else
                                UserAvatar(
                                  photoUrl:
                                      showExistingPhoto ? auth.photoUrl : null,
                                  fallbackName: auth.displayName,
                                  size: 100,
                                ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: scheme.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: scheme.surface, width: 2),
                                  ),
                                  child: const Icon(Icons.camera_alt_rounded,
                                      size: 16, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: _pickPhoto,
                          child: Text(
                              auth.photoUrl != null || _pickedPhoto != null
                                  ? 'Change photo'
                                  : 'Add photo'),
                        ),
                      ),
                      const SizedBox(height: 24),

                      _Label('Display name *'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                            hintText: 'Your name'),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Name is required';
                          }
                          if (v.trim().length < 2) {
                            return 'Name is too short';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      _Label('Phone (optional)'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                            hintText: '+90 5xx xxx xx xx'),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Show phone on my listings',
                            style: textTheme.bodyMedium),
                        subtitle: Text(
                          'Others will see your phone on listing details.',
                          style: textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        value: _phonePublic,
                        onChanged: (v) => setState(() => _phonePublic = v),
                      ),
                      const SizedBox(height: 12),

                      _Label('City (optional)'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _cityCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                            hintText: 'e.g. Lefkoşa'),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text('Show city on my listings',
                            style: textTheme.bodyMedium),
                        subtitle: Text(
                          'Others will see your city on listing details.',
                          style: textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        value: _cityPublic,
                        onChanged: (v) => setState(() => _cityPublic = v),
                      ),
                      const SizedBox(height: 12),

                      _Label('Department (optional)'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _deptCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                            hintText: 'e.g. Computer Engineering'),
                      ),
                      const SizedBox(height: 20),

                      _Label('Bio (optional)'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _bioCtrl,
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'A few words about you',
                        ),
                      ),
                      const SizedBox(height: 32),

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: auth.isLoading ? null : _save,
                          child: auth.isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Text('Save changes'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.labelLarge);
}
