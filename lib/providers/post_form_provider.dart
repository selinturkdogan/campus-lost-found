import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../models/listing_model.dart';

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

  String get title => _title;
  String get description => _description;
  String get type => _type;
  String? get location => _location;
  String? get category => _category;
  File? get imageFile => _imageFile;
  String? get existingPhotoUrl => _existingPhotoUrl;
  bool get isSubmitting => _isSubmitting;
  bool get hasImage => _imageFile != null || _existingPhotoUrl != null;

  void loadFromListing(ListingModel listing) {
    _title = listing.title;
    _description = listing.description;
    _type = listing.type;
    _location = listing.location;
    _category = listing.category;
    _existingPhotoUrl = listing.photoUrl;
    _imageFile = null;
    notifyListeners();
  }

  void setTitle(String val) { _title = val; notifyListeners(); }
  void setDescription(String val) { _description = val; notifyListeners(); }
  void setType(String val) { _type = val; notifyListeners(); }
  void setLocation(String? val) { _location = val; notifyListeners(); }
  void setCategory(String? val) { _category = val; notifyListeners(); }
  void setSubmitting(bool val) { _isSubmitting = val; notifyListeners(); }

  Future<void> pickFromGallery() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1080, maxHeight: 1080, imageQuality: 85);
    if (picked != null) { _imageFile = File(picked.path); notifyListeners(); }
  }

  Future<void> pickFromCamera() async {
    final picked = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1080, maxHeight: 1080, imageQuality: 85);
    if (picked != null) { _imageFile = File(picked.path); notifyListeners(); }
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

  bool get isValid =>
      validateTitle() == null &&
      validateDescription() == null &&
      validateLocation() == null &&
      validateCategory() == null;

  void reset() {
    _title = '';
    _description = '';
    _type = 'lost';
    _location = null;
    _category = null;
    _imageFile = null;
    _existingPhotoUrl = null;
    _isSubmitting = false;
    notifyListeners();
  }
}