import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../models/listing_model.dart';
import '../utils/image_utils.dart';

class PostFormProvider extends ChangeNotifier {
  final _picker = ImagePicker();

  String _title = '';
  String _description = '';
  String _type = 'lost';
  String? _location;
  String? _category;
  File? _imageFile;
  String? _existingPhotoUrl;
  bool _isSubmitting = false;
  bool _chatEnabled = true;
  String _pickupNote = '';

  String get title => _title;
  String get description => _description;
  String get type => _type;
  String? get location => _location;
  String? get category => _category;
  File? get imageFile => _imageFile;
  String? get existingPhotoUrl => _existingPhotoUrl;
  bool get isSubmitting => _isSubmitting;
  bool get hasImage => _imageFile != null || _existingPhotoUrl != null;
  bool get chatEnabled => _chatEnabled;
  String get pickupNote => _pickupNote;

  void loadFromListing(ListingModel listing) {
    _title = listing.title;
    _description = listing.description;
    _type = listing.type;
    _location = listing.location;
    _category = listing.category;
    _existingPhotoUrl = listing.photoUrl;
    _imageFile = null;
    _chatEnabled = listing.chatEnabled;
    _pickupNote = listing.pickupNote ?? '';
    notifyListeners();
  }

  void setTitle(String val) { _title = val; notifyListeners(); }
  void setDescription(String val) { _description = val; notifyListeners(); }
  void setType(String val) { _type = val; notifyListeners(); }
  void setLocation(String? val) { _location = val; notifyListeners(); }
  void setCategory(String? val) { _category = val; notifyListeners(); }
  void setSubmitting(bool val) { _isSubmitting = val; notifyListeners(); }
  void setChatEnabled(bool val) { _chatEnabled = val; notifyListeners(); }
  void setPickupNote(String val) { _pickupNote = val; notifyListeners(); }

  Future<void> pickFromGallery() async {
    // Let image_picker do an initial rough resize (faster decoding),
    // then compress with the dedicated package for tighter size.
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (picked != null) {
      _imageFile = await ImageUtils.compress(File(picked.path));
      notifyListeners();
    }
  }

  Future<void> pickFromCamera() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (picked != null) {
      _imageFile = await ImageUtils.compress(File(picked.path));
      notifyListeners();
    }
  }

  void removeImage() { _imageFile = null; _existingPhotoUrl = null; notifyListeners(); }

  String? validateTitle() {
    if (_title.trim().isEmpty) return 'Title is required';
    if (_title.trim().length < 3) return 'Title must be at least 3 characters';
    return null;
  }

  String? validateDescription() {
    if (_description.trim().isEmpty) return 'Description is required';
    if (_description.trim().length < 10) return 'Please provide more detail';
    return null;
  }

  String? validateLocation() {
    if (_location == null) return 'Please select a campus location';
    return null;
  }

  String? validateCategory() {
    if (_category == null) return 'Please select a category';
    return null;
  }

  String? validatePickupNote() {
    // Pickup note is only required when chat is disabled — the user
    // must explain where to retrieve the item.
    if (_chatEnabled) return null;
    if (_pickupNote.trim().isEmpty) {
      return 'Add pickup instructions since chat is disabled';
    }
    if (_pickupNote.trim().length < 5) return 'Please provide more detail';
    return null;
  }

  bool get isValid =>
      validateTitle() == null &&
      validateDescription() == null &&
      validateLocation() == null &&
      validateCategory() == null &&
      validatePickupNote() == null;

  void reset() {
    _title = '';
    _description = '';
    _type = 'lost';
    _location = null;
    _category = null;
    _imageFile = null;
    _existingPhotoUrl = null;
    _isSubmitting = false;
    _chatEnabled = true;
    _pickupNote = '';
    notifyListeners();
  }
}