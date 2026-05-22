import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/domains_service.dart';
import '../services/notification_service.dart';
import '../utils/image_utils.dart';

class AuthProvider extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instance;
  final _googleSignIn = GoogleSignIn(scopes: ['email']);

  User? _user;
  String? _displayName;
  String? _photoUrl;
  String? _phone;
  String? _city;
  String? _department;
  String? _bio;
  bool _phonePublic = false;
  bool _cityPublic = false;
  bool _isAdmin = false;
  bool _isLoading = false;
  bool _mustChangePassword = false;
  String? _errorMessage;
  String? _infoMessage;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;
  bool get isAdmin => _isAdmin;
  bool get mustChangePassword => _mustChangePassword;
  String? get errorMessage => _errorMessage;
  String? get infoMessage => _infoMessage;
  String? get photoUrl => _photoUrl;
  String? get phone => _phone;
  String? get city => _city;
  String? get department => _department;
  String? get bio => _bio;
  bool get phonePublic => _phonePublic;
  bool get cityPublic => _cityPublic;

  String get displayName =>
      _displayName ??
      _user?.displayName ??
      (_user?.email?.split('@').first ?? 'Student');

  AuthProvider() {
    _auth.authStateChanges().listen((user) async {
      _user = user;
      if (user != null) {
        await _fetchUserDoc(user.uid);
      } else {
        _displayName = null;
        _photoUrl = null;
        _phone = null;
        _city = null;
        _department = null;
        _bio = null;
        _phonePublic = false;
        _cityPublic = false;
        _isAdmin = false;
        _mustChangePassword = false;
      }
      notifyListeners();
    });
  }

  // ─── Email/password login ──────────────────────────────────────────────────
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    _clearMessages();
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      _user = credential.user;
      if (_user != null) {
        await _fetchUserDoc(_user!.uid);
        // Bind this device's FCM token to the freshly signed-in user.
        await NotificationService().saveTokenForCurrentUser();
      }
      return true;
    } on FirebaseAuthException catch (e) {
      _errorMessage = _parseAuthError(e.code);
      return false;
    } catch (_) {
      _errorMessage = 'Sign in failed. Please try again.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Step 1: Verify with Google + send temporary password email ────────────
  Future<bool> requestTempPasswordViaGoogle() async {
    _setLoading(true);
    _clearMessages();
    try {
      // Sign-out first so user always sees account picker
      await _googleSignIn.signOut();

      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _setLoading(false);
        return false; // user cancelled
      }

      // Domain check on client (UX feedback) — backend re-checks for security.
      // Whitelist is admin-managed in Firestore.
      final email = googleUser.email.toLowerCase();
      final allowed = await DomainsService.fetch();
      if (allowed.isEmpty) {
        _errorMessage =
            'Registration is currently closed. Please contact the administrator.';
        await _googleSignIn.signOut();
        return false;
      }
      final matches = allowed.any((d) => email.endsWith('@$d'));
      if (!matches) {
        _errorMessage =
            'Only emails from these domains are allowed: ${allowed.map((d) => '@$d').join(', ')}';
        await _googleSignIn.signOut();
        return false;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with Google credential (so Cloud Function sees auth)
      await _auth.signInWithCredential(credential);

      // Call backend to generate temp password and email it
      final callable = _functions.httpsCallable('sendTempPassword');
      await callable.call();

      // Sign out the Google session — user must now sign in with email/password
      await _auth.signOut();
      await _googleSignIn.signOut();

      _infoMessage =
          'A temporary password has been sent to $email. Please check your inbox.';
      return true;
    } on FirebaseFunctionsException catch (e) {
      // Make sure we don't leave a Google session lingering
      await _auth.signOut();
      await _googleSignIn.signOut();
      _errorMessage = e.message ?? _parseFunctionError(e.code);
      return false;
    } on FirebaseAuthException catch (e) {
      await _googleSignIn.signOut();
      _errorMessage = _parseAuthError(e.code);
      return false;
    } catch (e) {
      await _googleSignIn.signOut();
      _errorMessage = 'An unexpected error occurred. Please try again.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Step 2: Set a new password after first sign-in ────────────────────────
  Future<bool> setNewPassword(String newPassword) async {
    _setLoading(true);
    _clearMessages();
    try {
      final user = _auth.currentUser;
      if (user == null) {
        _errorMessage = 'You need to sign in first.';
        return false;
      }
      await user.updatePassword(newPassword);
      await _firestore.collection('users').doc(user.uid).set(
        {'mustChangePassword': false},
        SetOptions(merge: true),
      );
      _mustChangePassword = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        _errorMessage =
            'For security, please sign out and sign back in, then change your password.';
      } else if (e.code == 'weak-password') {
        _errorMessage = 'Password is too weak. Use at least 8 characters.';
      } else {
        _errorMessage = _parseAuthError(e.code);
      }
      return false;
    } catch (_) {
      _errorMessage = 'Could not set password. Please try again.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Change password from profile (current + new password) ─────────────────
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _setLoading(true);
    _clearMessages();
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) {
        _errorMessage = 'You must be signed in.';
        return false;
      }
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(cred);
      await user.updatePassword(newPassword);
      await _firestore.collection('users').doc(user.uid).set(
        {'mustChangePassword': false},
        SetOptions(merge: true),
      );
      _mustChangePassword = false;
      _infoMessage = 'Your password has been updated.';
      return true;
    } on FirebaseAuthException catch (e) {
      _errorMessage = _parseAuthError(e.code);
      return false;
    } catch (_) {
      _errorMessage = 'Could not change password. Please try again.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ─── Forgot password (uses custom Cloud Function + Gmail SMTP) ─────────────
  Future<bool> sendPasswordResetEmail(String email) async {
    _setLoading(true);
    _clearMessages();
    try {
      final normalized = email.trim().toLowerCase();
      // Client-side hint — backend re-checks against the admin whitelist.
      final allowed = await DomainsService.fetch();
      if (allowed.isEmpty) {
        _errorMessage =
            'Password reset is currently disabled. Please contact the administrator.';
        return false;
      }
      final matches = allowed.any((d) => normalized.endsWith('@$d'));
      if (!matches) {
        _errorMessage =
            'Only emails from these domains are allowed: ${allowed.map((d) => '@$d').join(', ')}';
        return false;
      }
      final callable = _functions.httpsCallable('sendPasswordResetMail');
      await callable.call({'email': normalized});
      _infoMessage = 'A reset link has been sent to $normalized.';
      return true;
    } on FirebaseFunctionsException catch (e) {
      _errorMessage = e.message ?? _parseFunctionError(e.code);
      return false;
    } catch (_) {
      _errorMessage = 'Could not send request. Please try again.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    // Clear FCM token first so the next user on this device does not
    // receive notifications addressed to the user signing out.
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      await NotificationService().clearTokenForUser(uid);
    }
    await _googleSignIn.signOut();
    await _auth.signOut();
    _user = null;
    _displayName = null;
    _isAdmin = false;
    _mustChangePassword = false;
    notifyListeners();
  }

  Future<void> refreshUserDoc() async {
    if (_user != null) await _fetchUserDoc(_user!.uid);
  }

  Future<void> _fetchUserDoc(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        _displayName = (data['displayName'] as String?) ??
            _user?.displayName ??
            _user?.email?.split('@').first;
        _photoUrl = data['photoUrl'] as String?;
        _phone = data['phone'] as String?;
        _city = data['city'] as String?;
        _department = data['department'] as String?;
        _bio = data['bio'] as String?;
        _phonePublic = data['phonePublic'] == true;
        _cityPublic = data['cityPublic'] == true;
        _isAdmin = data['isAdmin'] == true;
        _mustChangePassword = data['mustChangePassword'] == true;
      } else {
        _displayName = _user?.displayName ?? _user?.email?.split('@').first;
        _photoUrl = null;
        _phone = null;
        _city = null;
        _department = null;
        _bio = null;
        _phonePublic = false;
        _cityPublic = false;
        _isAdmin = false;
        _mustChangePassword = false;
        await _firestore.collection('users').doc(uid).set({
          'uid': uid,
          'email': _user?.email ?? '',
          'displayName': _displayName ?? 'Student',
          'createdAt': FieldValue.serverTimestamp(),
          'isAdmin': false,
          'mustChangePassword': false,
        }, SetOptions(merge: true));
      }
    } catch (_) {
      _displayName =
          _user?.displayName ?? _user?.email?.split('@').first ?? 'Student';
      _photoUrl = null;
      _isAdmin = false;
      _mustChangePassword = false;
    }
  }

  /// Update profile fields. Pass only the fields you want to change.
  /// To upload a new photo, pass [newPhotoFile]. To remove the existing
  /// photo, pass [removePhoto] = true.
  Future<bool> updateProfile({
    String? displayName,
    String? phone,
    String? city,
    String? department,
    String? bio,
    bool? phonePublic,
    bool? cityPublic,
    File? newPhotoFile,
    bool removePhoto = false,
  }) async {
    final uid = _user?.uid;
    if (uid == null) {
      _errorMessage = 'You must be signed in.';
      notifyListeners();
      return false;
    }
    _setLoading(true);
    _clearMessages();
    try {
      String? newPhotoUrl = _photoUrl;

      if (removePhoto) {
        newPhotoUrl = null;
        try {
          await FirebaseStorage.instance
              .ref('profile_images/$uid.jpg')
              .delete();
        } catch (_) {
          // Photo may not exist — ignore.
        }
      } else if (newPhotoFile != null) {
        final compressed = await ImageUtils.compress(
          newPhotoFile,
          maxWidth: 720,
          quality: 85,
        );
        final ref = FirebaseStorage.instance.ref('profile_images/$uid.jpg');
        await ref.putFile(compressed);
        newPhotoUrl = await ref.getDownloadURL();
      }

      final updates = <String, dynamic>{
        if (displayName != null) 'displayName': displayName.trim(),
        if (phone != null) 'phone': phone.trim().isEmpty ? null : phone.trim(),
        if (city != null) 'city': city.trim().isEmpty ? null : city.trim(),
        if (department != null)
          'department': department.trim().isEmpty ? null : department.trim(),
        if (bio != null) 'bio': bio.trim().isEmpty ? null : bio.trim(),
        if (phonePublic != null) 'phonePublic': phonePublic,
        if (cityPublic != null) 'cityPublic': cityPublic,
        if (newPhotoFile != null || removePhoto) 'photoUrl': newPhotoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _firestore.collection('users').doc(uid).set(
            updates,
            SetOptions(merge: true),
          );

      await _fetchUserDoc(uid);
      _infoMessage = 'Profile updated.';
      notifyListeners();
      return true;
    } catch (_) {
      _errorMessage = 'Failed to update profile. Please try again.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool val) {
    _isLoading = val;
    notifyListeners();
  }

  void _clearMessages() {
    _errorMessage = null;
    _infoMessage = null;
  }

  void clearMessages() {
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();
  }

  String _parseAuthError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email address.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled. Contact your administrator.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later.';
      case 'network-request-failed':
        return 'No internet connection. Check your network.';
      case 'weak-password':
        return 'Password is too weak. Use at least 8 characters.';
      default:
        return 'Sign in failed. Please try again.';
    }
  }

  String _parseFunctionError(String code) {
    switch (code) {
      case 'permission-denied':
        return 'Your email domain is not allowed.';
      case 'unauthenticated':
        return 'Google verification failed.';
      case 'resource-exhausted':
        return 'Too many requests. Please wait a moment.';
      default:
        return 'Server error. Please try again.';
    }
  }
}
