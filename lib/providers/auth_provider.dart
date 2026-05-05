import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
class AuthProvider extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _googleSignIn = GoogleSignIn(scopes: ['email']);

  User? _user;
  String? _displayName;
  bool _isAdmin = false;
  bool _isLoading = false;
  String? _errorMessage;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;
  bool get isAdmin => _isAdmin;
  String? get errorMessage => _errorMessage;

  String get displayName =>
      _displayName ??
      _user?.displayName ??
      (_user?.email?.split('@').first ?? 'Student');

  AuthProvider() {
    _auth.authStateChanges().listen((user) async {
      _user = user;
      if (user != null) {
        await _fetchDisplayName(user.uid);
      } else {
        _displayName = null;
        _isAdmin = false;
      }
      notifyListeners();
    });
  }

  Future<bool> login({
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    _clearError();
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      _user = credential.user;
      if (_user != null) await _fetchDisplayName(_user!.uid);
      return true;
    } on FirebaseAuthException catch (e) {
      _errorMessage = _parseAuthError(e.code);
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> signInWithGoogle() async {
    _setLoading(true);
    _clearError();
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _setLoading(false);
        return false;
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      _user = userCredential.user;
      if (_user != null) await _fetchDisplayName(_user!.uid);
      return true;
    } on FirebaseAuthException catch (e) {
      _errorMessage = _parseAuthError(e.code);
      return false;
    } catch (e) {
      _errorMessage = 'Google sign-in failed. Please try again.';
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
    _user = null;
    _displayName = null;
    _isAdmin = false;
    notifyListeners();
  }

  Future<void> _fetchDisplayName(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data()?['displayName'] != null) {
        _displayName = doc.data()?['displayName'] as String?;
        _isAdmin = doc.data()?['isAdmin'] == true;
      } else {
        _displayName = _user?.displayName ?? _user?.email?.split('@').first;
        _isAdmin = false;
        await _firestore.collection('users').doc(uid).set({
          'uid': uid,
          'email': _user?.email ?? '',
          'displayName': _displayName ?? 'Student',
          'createdAt': DateTime.now(),
          'isAdmin': false,
        }, SetOptions(merge: true));
      }
    } catch (_) {
      _displayName = _user?.displayName ?? _user?.email?.split('@').first ?? 'Student';
      _isAdmin = false;
    }
  }

  void _setLoading(bool val) {
    _isLoading = val;
    notifyListeners();
  }

  void _clearError() => _errorMessage = null;

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  String _parseAuthError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.';
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
      default:
        return 'Sign in failed. Please try again.';
    }
  }
}