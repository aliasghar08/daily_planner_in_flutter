import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthProvider extends ChangeNotifier {
  User? _user;
  bool _isLoading = true;
  String? _error;

  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _user != null;

  AuthProvider() {
    _checkAuthState();
  }

  Future<void> _checkAuthState() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Step 1: Ensure Local Persistence is active
      try {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      } catch (e) {
        debugPrint('Auth persistence setting warning: $e');
      }

      // Step 2: Read current authenticated user session
      _user = FirebaseAuth.instance.currentUser;
      debugPrint('🔐 Current active user session: ${_user?.email ?? "No session"}');

      // Step 3: Listen for auth state changes continuously
      FirebaseAuth.instance.authStateChanges().listen((User? newUser) {
        debugPrint('🔄 Auth state changed: ${newUser?.email ?? "Signed out"}');
        _user = newUser;
        _isLoading = false;
        notifyListeners();
      });

      // Step 4: Ensure Firestore user document exists without ever logging the user out
      if (_user != null) {
        _syncUserDocument(_user!);
      }
    } catch (e) {
      debugPrint('❌ Auth check error: $e');
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _syncUserDocument(User currentUser) async {
    try {
      final docRef = FirebaseFirestore.instance.collection('users').doc(currentUser.uid);
      final doc = await docRef.get();
      if (!doc.exists) {
        await docRef.set({
          'fullName': currentUser.displayName ?? (currentUser.email?.split('@').first ?? 'User'),
          'email': currentUser.email ?? '',
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('✅ Synced user profile document to Firestore');
      }
    } catch (e) {
      debugPrint('⚠️ Non-fatal Firestore profile sync note: $e');
    }
  }

  Future<void> refreshToken() async {
    try {
      if (_user != null) {
        await _user!.getIdToken(true);
        debugPrint('✅ Token refreshed for user: ${_user!.email}');
      }
    } catch (e) {
      debugPrint('❌ Token refresh error: $e');
    }
  }

  /// Explicit sign out - ONLY called when user explicitly taps Logout
  Future<void> signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      _user = null;
      _error = null;
      notifyListeners();
      debugPrint('👋 User successfully logged out');
    } catch (e) {
      debugPrint('❌ Sign out error: $e');
      rethrow;
    }
  }

  void retry() {
    _error = null;
    _isLoading = true;
    notifyListeners();
    _checkAuthState();
  }
}
