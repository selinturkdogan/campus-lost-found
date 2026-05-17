import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/notification_service.dart';

class AuthProvider extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instance;
  final _googleSignIn = GoogleSignIn(scopes: ['email']);

  // Domain restriction for the Lost & Found app — keep in sync with backend.
  static const String allowedDomain = 'final.edu.tr';

  User? _user;
  String? _displayName;
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

      // Domain check on client (UX feedback) — backend re-checks for security
      final email = googleUser.email.toLowerCase();
      if (!email.endsWith('@$allowedDomain')) {
        _errorMessage =
            'Only @$allowedDomain email addresses are allowed.';
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
      if (!normalized.endsWith('@$allowedDomain')) {
        _errorMessage =
            'Password reset is only available for @$allowedDomain emails.';
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
        _isAdmin = data['isAdmin'] == true;
        _mustChangePassword = data['mustChangePassword'] == true;
      } else {
        _displayName = _user?.displayName ?? _user?.email?.split('@').first;
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
      _isAdmin = false;
      _mustChangePassword = false;
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
        return 'Only @$allowedDomain emails are allowed.';
      case 'unauthenticated':
        return 'Google verification failed.';
      case 'resource-exhausted':
        return 'Too many requests. Please wait a moment.';
      default:
        return 'Server error. Please try again.';
    }
  }
}
