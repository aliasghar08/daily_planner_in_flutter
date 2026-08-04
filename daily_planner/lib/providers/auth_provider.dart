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

      // Step 1: Get cached user immediately (works offline)
      _user = FirebaseAuth.instance.currentUser;
      debugPrint('🔐 Cached user: ${_user?.email ?? 'null'}');

      // Step 2: Listen for auth state changes (handles token refresh, logout, etc.)
      FirebaseAuth.instance.authStateChanges().listen((User? newUser) {
        debugPrint('🔄 Auth state changed: ${newUser?.email ?? 'null'}');
        _user = newUser;
        _isLoading = false;
        notifyListeners();
      });

      // Step 3: If user exists, verify their data in Firestore
      if (_user != null) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(_user!.uid)
              .get();

          if (!doc.exists) {
            // User data doesn't exist - force logout
            debugPrint('⚠️ User data not found in Firestore, logging out');
            await FirebaseAuth.instance.signOut();
            _user = null;
            _error = 'User data not found';
            notifyListeners();
          } else {
            debugPrint('✅ User data verified in Firestore');
          }
        } catch (e) {
          // Network error - keep user logged in if cached data exists
          debugPrint('⚠️ Could not verify user data (network error): $e');
        }
      }

      // Step 4: Small delay to ensure everything is loaded
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      debugPrint('❌ Auth check error: $e');
      _error = e.toString();
      _user = null;
    } finally {
      _isLoading = false;
      notifyListeners();
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

  Future<void> signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      _user = null;
      notifyListeners();
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
