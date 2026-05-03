import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/listing_model.dart';

class ListingsProvider extends ChangeNotifier {
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;

  List<ListingModel> _lostListings = [];
  List<ListingModel> _foundListings = [];
  List<ListingModel> _cachedListings = [];

  bool _isLoading = false;
  bool _isOffline = false;
  String? _errorMessage;
  String _searchQuery = '';
  String? _selectedLocation;
  String? _selectedCategory;

  StreamSubscription? _lostSub;
  StreamSubscription? _foundSub;

  List<ListingModel> get lostListings => _filterListings(_lostListings);
  List<ListingModel> get foundListings => _filterListings(_foundListings);
  List<ListingModel> get allListings => [..._lostListings, ..._foundListings];
  List<ListingModel> get cachedListings => _cachedListings;
  bool get isLoading => _isLoading;
  bool get isOffline => _isOffline;
  String? get errorMessage => _errorMessage;
  String get searchQuery => _searchQuery;
  String? get selectedLocation => _selectedLocation;
  String? get selectedCategory => _selectedCategory;

  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void startListening() {
    _setLoading(true);

    _lostSub = _firestore
        .collection('listings')
        .where('type', isEqualTo: 'lost')
        .where('isResolved', isEqualTo: false)
        .snapshots()
        .listen(
      (snapshot) {
        _lostListings = snapshot.docs.map(ListingModel.fromFirestore).toList();
        _isOffline = false;
        _cacheListings(_lostListings);
        _setLoading(false);
      },
      onError: (e) => _handleStreamError(e),
    );

    _foundSub = _firestore
        .collection('listings')
        .where('type', isEqualTo: 'found')
        .where('isResolved', isEqualTo: false)
        .snapshots()
        .listen(
      (snapshot) {
        _foundListings = snapshot.docs.map(ListingModel.fromFirestore).toList();
        _isOffline = false;
        _cacheListings(_foundListings);
        _setLoading(false);
      },
      onError: (e) => _handleStreamError(e),
    );
  }

  void stopListening() {
    _lostSub?.cancel();
    _foundSub?.cancel();
  }

  Future<bool> createListing({
    required String title,
    required String description,
    required String type,
    required String location,
    String? category,
    required String ownerId,
    required String ownerEmail,
    required String ownerName,
    File? imageFile,
  }) async {
    try {
      final docRef = _firestore.collection('listings').doc();
      String? photoUrl;
      if (imageFile != null) {
        photoUrl = await _uploadPhoto(imageFile, ownerId, docRef.id);
      }
      await docRef.set({
        'title': title,
        'description': description,
        'type': type,
        'location': location,
        'category': category,
        'photoUrl': photoUrl,
        'ownerId': ownerId,
        'ownerEmail': ownerEmail,
        'ownerName': ownerName,
        'isResolved': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      _errorMessage = 'Failed to create listing. Please try again.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateListing({
    required String listingId,
    required String title,
    required String description,
    required String type,
    required String location,
    String? category,
    String? existingPhotoUrl,
    File? newImageFile,
    required String ownerId,
  }) async {
    try {
      String? photoUrl = existingPhotoUrl;
      if (newImageFile != null) {
        photoUrl = await _uploadPhoto(newImageFile, ownerId, listingId);
      }
      await _firestore.collection('listings').doc(listingId).update({
        'title': title,
        'description': description,
        'type': type,
        'location': location,
        'category': category,
        'photoUrl': photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      _errorMessage = 'Failed to update listing.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteListing(String listingId, String ownerId) async {
    try {
      try {
        await _storage.ref('listing_images/$ownerId/$listingId.jpg').delete();
      } catch (_) {}
      await _firestore.collection('listings').doc(listingId).delete();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to delete listing.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> markResolved(String listingId) async {
    try {
      await _firestore.collection('listings').doc(listingId).update({
        'isResolved': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      _errorMessage = 'Failed to mark as resolved.';
      notifyListeners();
      return false;
    }
  }

  Stream<List<ListingModel>> myPostsStream(String uid) {
    return _firestore
        .collection('listings')
        .where('ownerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(ListingModel.fromFirestore).toList());
  }

  // ── Search & filter ──────────────────────────────────────────────────────────
  void setSearchQuery(String query) {
    _searchQuery = query.toLowerCase();
    notifyListeners();
  }

  void setLocationFilter(String? location) {
    _selectedLocation = location;
    notifyListeners();
  }

  void setCategoryFilter(String? category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void clearFilters() {
    _searchQuery = '';
    _selectedLocation = null;
    _selectedCategory = null;
    notifyListeners();
  }

  List<ListingModel> _filterListings(List<ListingModel> listings) {
    return listings.where((l) {
      final matchesSearch = _searchQuery.isEmpty ||
          l.title.toLowerCase().contains(_searchQuery) ||
          l.description.toLowerCase().contains(_searchQuery);
      final matchesLocation =
          _selectedLocation == null || l.location == _selectedLocation;
      final matchesCategory =
          _selectedCategory == null || l.category == _selectedCategory;
      return matchesSearch && matchesLocation && matchesCategory;
    }).toList();
  }

  Future<void> _cacheListings(List<ListingModel> listings) async {
    try {
      final box = Hive.box<ListingModel>('recentListings');
      for (final listing in listings.take(20)) {
        await box.put(listing.id, listing);
      }
    } catch (_) {}
  }

  void loadFromCache() {
    try {
      final box = Hive.box<ListingModel>('recentListings');
      _cachedListings = box.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _lostListings = _cachedListings.where((l) => l.type == 'lost').toList();
      _foundListings = _cachedListings.where((l) => l.type == 'found').toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<String?> _uploadPhoto(File file, String uid, String listingId) async {
    final ref = _storage.ref('listing_images/$uid/$listingId.jpg');
    final task = await ref.putFile(file);
    return await task.ref.getDownloadURL();
  }

  void _handleStreamError(dynamic e) async {
    final online = await _hasInternet();
    if (!online) {
      _isOffline = true;
      loadFromCache();
    }
    _setLoading(false);
  }

  void _setLoading(bool val) {
    _isLoading = val;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}