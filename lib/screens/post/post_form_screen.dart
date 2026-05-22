import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/listing_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/listings_provider.dart';
import '../../providers/post_form_provider.dart';
import '../../services/notification_service.dart';

class PostFormScreen extends StatefulWidget {
  final ListingModel? existingListing;
  const PostFormScreen({super.key, this.existingListing});

  @override
  State<PostFormScreen> createState() => _PostFormScreenState();
}

class _PostFormScreenState extends State<PostFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;

  bool get _isEditMode => widget.existingListing != null;

  @override
  void initState() {
    super.initState();
    final form = context.read<PostFormProvider>();
    if (_isEditMode) {
      form.loadFromListing(widget.existingListing!);
      _titleCtrl = TextEditingController(text: widget.existingListing!.title);
      _descCtrl = TextEditingController(text: widget.existingListing!.description);
    } else {
      _titleCtrl = TextEditingController();
      _descCtrl = TextEditingController();
      Future.microtask(() => form.reset());
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final form = context.read<PostFormProvider>();
    final auth = context.read<AuthProvider>();
    final listings = context.read<ListingsProvider>();
    final user = auth.user!;

    form.setSubmitting(true);
    bool success;

    if (_isEditMode) {
      success = await listings.updateListing(
        listingId: widget.existingListing!.id,
        title: form.title,
        description: form.description,
        type: form.type,
        location: form.location!,
        category: form.category,
        existingPhotoUrl: form.existingPhotoUrl,
        newImageFile: form.imageFile,
        ownerId: user.uid,
        chatEnabled: form.chatEnabled,
        pickupNote: form.chatEnabled ? null : form.pickupNote.trim(),
      );
    } else {
      final ownerName = auth.displayName;
      success = await listings.createListing(
        title: form.title,
        description: form.description,
        type: form.type,
        location: form.location!,
        category: form.category,
        ownerId: user.uid,
        ownerEmail: user.email ?? '',
        ownerName: ownerName,
        imageFile: form.imageFile,
        chatEnabled: form.chatEnabled,
        pickupNote: form.chatEnabled ? null : form.pickupNote.trim(),
      );

      if (success) {
        // Fire-and-forget: this writes to a top-level `notifications`
        // queue intended for a fan-out Cloud Function. Don't block the
        // submit on it — and don't crash the UI if the rules deny it.
        // ignore: discarded_futures
        NotificationService.sendNewListingNotification(
          type: form.type,
          itemTitle: form.title,
          location: form.location!,
        ).catchError((_) {
          // Non-fatal — the listing itself was created successfully.
        });
      }
    }

    form.setSubmitting(false);
    if (!mounted) return;

    if (success) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isEditMode ? 'Listing updated!' : 'Listing posted successfully!')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(bottom: BorderSide(color: scheme.outline, width: 1)),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.arrow_back_rounded, color: scheme.onSurface),
                  ),
                  const SizedBox(width: 12),
                  Text(_isEditMode ? 'Edit listing' : 'Post Item', style: textTheme.titleSmall),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Consumer<PostFormProvider>(
                    builder: (_, form, __) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        _Label('What kind of post is this?'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _TypeCard(
                                isSelected: form.type == 'lost',
                                color: const Color(0xFFFF6B6B),
                                icon: Icons.search_rounded,
                                title: 'I LOST IT',
                                subtitle: 'Looking for my missing item',
                                onTap: () => form.setType('lost'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _TypeCard(
                                isSelected: form.type == 'found',
                                color: const Color(0xFF4CAF50),
                                icon: Icons.emoji_objects_outlined,
                                title: 'I FOUND IT',
                                subtitle: 'Looking for the owner',
                                onTap: () => form.setType('found'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _Label('Title *'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _titleCtrl,
                          onChanged: form.setTitle,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(hintText: 'e.g. Black backpack with laptop'),
                          validator: (_) => form.validateTitle(),
                        ),
                        const SizedBox(height: 16),
                        _Label('Description *'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _descCtrl,
                          onChanged: form.setDescription,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText: 'Provide details about the item, where and when it was lost/found...',
                            alignLabelWithHint: true,
                          ),
                          validator: (_) => form.validateDescription(),
                        ),
                        const SizedBox(height: 16),
                        _Label('Category *'),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: form.category,
                          decoration: const InputDecoration(hintText: 'Select a category'),
                          items: itemCategories.map((cat) {
                            return DropdownMenuItem(value: cat, child: Text(cat));
                          }).toList(),
                          onChanged: form.setCategory,
                          validator: (_) => form.validateCategory(),
                          dropdownColor: scheme.surfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        _Label('Campus Location *'),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: form.location,
                          decoration: const InputDecoration(hintText: 'Select a location'),
                          items: campusLocations.map((loc) {
                            return DropdownMenuItem(value: loc, child: Text(loc));
                          }).toList(),
                          onChanged: form.setLocation,
                          validator: (_) => form.validateLocation(),
                          dropdownColor: scheme.surfaceVariant,
                        ),
                        const SizedBox(height: 20),
                        _Label('Photo (optional)'),
                        const SizedBox(height: 8),
                        _PhotoPicker(form: form),
                        const SizedBox(height: 24),

                        // Chat toggle + pickup note (when chat disabled)
                        _ChatToggleSection(form: form),
                        const SizedBox(height: 32),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Consumer<PostFormProvider>(
                                builder: (_, f, __) => ElevatedButton(
                                  onPressed: f.isSubmitting ? null : _submit,
                                  child: f.isSubmitting
                                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                      : Text(_isEditMode ? 'Update' : 'Post Item'),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
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
  Widget build(BuildContext context) => Text(text, style: Theme.of(context).textTheme.labelLarge);
}

class _ChatToggleSection extends StatelessWidget {
  final PostFormProvider form;
  const _ChatToggleSection({required this.form});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              children: [
                Icon(
                  form.chatEnabled
                      ? Icons.chat_bubble_outline_rounded
                      : Icons.chat_bubble_outline_rounded,
                  size: 20,
                  color: form.chatEnabled
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Allow chat',
                        style: textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        form.chatEnabled
                            ? 'People can message you about this item.'
                            : 'Chat disabled — add pickup instructions below.',
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: form.chatEnabled,
                  onChanged: form.setChatEnabled,
                  activeColor: scheme.primary,
                ),
              ],
            ),
          ),
          // Pickup note appears only when chat is disabled
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: form.chatEnabled
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(color: scheme.outline, height: 12),
                        const SizedBox(height: 8),
                        Text(
                          'Pickup instructions *',
                          style: textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: form.pickupNote,
                          onChanged: form.setPickupNote,
                          maxLines: 2,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            hintText:
                                'e.g. Find it at the Information Desk (Danışma)',
                          ),
                          validator: (_) => form.validatePickupNote(),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final bool isSelected;
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _TypeCard({
    required this.isSelected,
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.12) : scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : scheme.outline,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.18),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isSelected ? color : scheme.onSurface,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoPicker extends StatelessWidget {
  final PostFormProvider form;
  const _PhotoPicker({required this.form});

  @override
  Widget build(BuildContext context) {
    if (form.hasImage) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: form.imageFile != null
                ? Image.file(form.imageFile!, height: 200, width: double.infinity, fit: BoxFit.cover)
                : Image.network(form.existingPhotoUrl!, height: 200, width: double.infinity, fit: BoxFit.cover),
          ),
          Positioned(
            top: 8, right: 8,
            child: GestureDetector(
              onTap: form.removeImage,
              child: Container(
                width: 30, height: 30,
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: form.pickFromGallery,
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: const Text('Gallery'),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: form.pickFromCamera,
            icon: const Icon(Icons.camera_alt_outlined, size: 18),
            label: const Text('Camera'),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
          ),
        ),
      ],
    );
  }
}