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

  static const int _pageSize = 10;

  // All listings (for All tab)
  List<ListingModel> _allListings = [];
  DocumentSnapshot? _lastAllDoc;
  bool _hasMoreAll = true;
  bool _isLoadingMoreAll = false;
  StreamSubscription? _allSub;

  // Lost listings
  List<ListingModel> _lostListings = [];
  DocumentSnapshot? _lastLostDoc;
  bool _hasMoreLost = true;
  bool _isLoadingMoreLost = false;
  StreamSubscription? _lostSub;

  // Found listings
  List<ListingModel> _foundListings = [];
  DocumentSnapshot? _lastFoundDoc;
  bool _hasMoreFound = true;
  bool _isLoadingMoreFound = false;
  StreamSubscription? _foundSub;

  List<ListingModel> _cachedListings = [];

  bool _isLoading = false;
  bool _isOffline = false;
  String? _errorMessage;
  String _searchQuery = '';
  String? _selectedLocation;
  String? _selectedCategory;

  // Getters
  List<ListingModel> get allListings => _filterListings(_allListings);
  List<ListingModel> get lostListings => _filterListings(_lostListings);
  List<ListingModel> get foundListings => _filterListings(_foundListings);
  List<ListingModel> get cachedListings => _cachedListings;

  bool get isLoading => _isLoading;
  bool get isOffline => _isOffline;
  bool get isLoadingMoreAll => _isLoadingMoreAll;
  bool get isLoadingMoreLost => _isLoadingMoreLost;
  bool get isLoadingMoreFound => _isLoadingMoreFound;
  bool get hasMoreAll => _hasMoreAll;
  bool get hasMoreLost => _hasMoreLost;
  bool get hasMoreFound => _hasMoreFound;

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
    Future.wait([
      _loadInitialAll(),
      _loadInitialLost(),
      _loadInitialFound(),
    ]).then((_) => _setLoading(false));
  }

  // ── All listings ─────────────────────────────────────────────────────────────
  Future<void> _loadInitialAll() async {
    try {
      final snap = await _firestore
          .collection('listings')
          .where('isResolved', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(_pageSize)
          .get();

      _allListings = snap.docs.map(ListingModel.fromFirestore).toList();
      _lastAllDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
      _hasMoreAll = snap.docs.length == _pageSize;
      _isOffline = false;
      _cacheListings(_allListings);

      _allSub?.cancel();
      _allSub = _firestore
          .collection('listings')
          .where('isResolved', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(_pageSize)
          .snapshots()
          .listen((snapshot) {
        _allListings = snapshot.docs.map(ListingModel.fromFirestore).toList();
        _isOffline = false;
        notifyListeners();
      }, onError: (e) => _handleStreamError(e));
    } catch (e) {
      _handleStreamError(e);
    }
  }

  Future<void> loadMoreAll() async {
    if (!_hasMoreAll || _isLoadingMoreAll || _lastAllDoc == null) return;
    _isLoadingMoreAll = true;
    notifyListeners();

    try {
      final snap = await _firestore
          .collection('listings')
          .where('isResolved', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastAllDoc!)
          .limit(_pageSize)
          .get();

      final newListings = snap.docs.map(ListingModel.fromFirestore).toList();
      _allListings.addAll(newListings);
      _lastAllDoc = snap.docs.isNotEmpty ? snap.docs.last : _lastAllDoc;
      _hasMoreAll = snap.docs.length == _pageSize;
    } catch (e) {
      _errorMessage = 'Failed to load more listings.';
    }

    _isLoadingMoreAll = false;
    notifyListeners();
  }

  // ── Lost listings ─────────────────────────────────────────────────────────────
  Future<void> _loadInitialLost() async {
    try {
      final snap = await _firestore
          .collection('listings')
          .where('type', isEqualTo: 'lost')
          .where('isResolved', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(_pageSize)
          .get();

      _lostListings = snap.docs.map(ListingModel.fromFirestore).toList();
      _lastLostDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
      _hasMoreLost = snap.docs.length == _pageSize;

      _lostSub?.cancel();
      _lostSub = _firestore
          .collection('listings')
          .where('type', isEqualTo: 'lost')
          .where('isResolved', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(_pageSize)
          .snapshots()
          .listen((snapshot) {
        _lostListings = snapshot.docs.map(ListingModel.fromFirestore).toList();
        notifyListeners();
      }, onError: (e) => _handleStreamError(e));
    } catch (e) {
      _handleStreamError(e);
    }
  }

  Future<void> loadMoreLost() async {
    if (!_hasMoreLost || _isLoadingMoreLost || _lastLostDoc == null) return;
    _isLoadingMoreLost = true;
    notifyListeners();

    try {
      final snap = await _firestore
          .collection('listings')
          .where('type', isEqualTo: 'lost')
          .where('isResolved', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastLostDoc!)
          .limit(_pageSize)
          .get();

      _lostListings.addAll(snap.docs.map(ListingModel.fromFirestore));
      _lastLostDoc = snap.docs.isNotEmpty ? snap.docs.last : _lastLostDoc;
      _hasMoreLost = snap.docs.length == _pageSize;
    } catch (e) {
      _errorMessage = 'Failed to load more listings.';
    }

    _isLoadingMoreLost = false;
    notifyListeners();
  }

  // ── Found listings ────────────────────────────────────────────────────────────
  Future<void> _loadInitialFound() async {
    try {
      final snap = await _firestore
          .collection('listings')
          .where('type', isEqualTo: 'found')
          .where('isResolved', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(_pageSize)
          .get();

      _foundListings = snap.docs.map(ListingModel.fromFirestore).toList();
      _lastFoundDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
      _hasMoreFound = snap.docs.length == _pageSize;

      _foundSub?.cancel();
      _foundSub = _firestore
          .collection('listings')
          .where('type', isEqualTo: 'found')
          .where('isResolved', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(_pageSize)
          .snapshots()
          .listen((snapshot) {
        _foundListings = snapshot.docs.map(ListingModel.fromFirestore).toList();
        notifyListeners();
      }, onError: (e) => _handleStreamError(e));
    } catch (e) {
      _handleStreamError(e);
    }
  }

  Future<void> loadMoreFound() async {
    if (!_hasMoreFound || _isLoadingMoreFound || _lastFoundDoc == null) return;
    _isLoadingMoreFound = true;
    notifyListeners();

    try {
      final snap = await _firestore
          .collection('listings')
          .where('type', isEqualTo: 'found')
          .where('isResolved', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .startAfterDocument(_lastFoundDoc!)
          .limit(_pageSize)
          .get();

      _foundListings.addAll(snap.docs.map(ListingModel.fromFirestore));
      _lastFoundDoc = snap.docs.isNotEmpty ? snap.docs.last : _lastFoundDoc;
      _hasMoreFound = snap.docs.length == _pageSize;
    } catch (e) {
      _errorMessage = 'Failed to load more listings.';
    }

    _isLoadingMoreFound = false;
    notifyListeners();
  }

  void stopListening() {
    _allSub?.cancel();
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
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 60)),
        ),
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

  Future<bool> extendListing(String listingId) async {
    try {
      await _firestore.collection('listings').doc(listingId).update({
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 60)),
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      _errorMessage = 'Failed to extend listing.';
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
      _allListings = _cachedListings.where((l) => !l.isResolved).toList();
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