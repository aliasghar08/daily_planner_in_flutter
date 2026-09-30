import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'; // Added to use kIsWeb
import 'package:daily_planner/services/native_preferences_service.dart';

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

      // Step 1: Ensure Local Persistence is active (Web only)
      if (kIsWeb) {
        try {
          await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
        } catch (e) {
          debugPrint('Auth persistence setting warning: $e');
        }
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

  /// Permanently deletes the current user's account and all associated data.
  ///
  /// Required by Apple App Store Guidelines (5.1.1).
  ///
  /// Deletes in this order:
  ///   1. All Firestore subcollections under the user's document
  ///   2. The user's Firestore profile document
  ///   3. Native preferences (remember-me, theme, etc.)
  ///   4. The Firebase Auth account itself (MUST be last)
  ///
  /// Throws an exception with a user-friendly message on failure.
  Future<void> deleteAccount() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw Exception('No user is currently signed in.');
    }

    try {
      final uid = currentUser.uid;
      debugPrint('🗑️ Starting account deletion for user: ${currentUser.email}');

      // ── Step 1: Delete all Firestore subcollections under the user doc ──
      // Firestore does NOT cascade deletes, so we must delete each doc manually.
      final userDocRef =
          FirebaseFirestore.instance.collection('users').doc(uid);

      const subcollectionsToDelete = [
        'tasks',
        'medications',
        'medication_schedules',
        'schedules',
        'sync_configs',
        'notifications',
        'performance',
        'insights',
      ];

      for (final subName in subcollectionsToDelete) {
        try {
          final snapshot = await userDocRef.collection(subName).get();
          if (snapshot.docs.isEmpty) continue;

          debugPrint('🗑️ Deleting ${snapshot.docs.length} docs from "$subName"');

          // Delete in batches of 500 (Firestore batch limit)
          final batches = <WriteBatch>[];
          WriteBatch batch = FirebaseFirestore.instance.batch();
          int count = 0;

          for (final doc in snapshot.docs) {
            batch.delete(doc.reference);
            count++;
            if (count % 500 == 0) {
              batches.add(batch);
              batch = FirebaseFirestore.instance.batch();
            }
          }
          if (count % 500 != 0) batches.add(batch);

          for (final b in batches) {
            await b.commit();
          }
        } catch (e) {
          debugPrint('⚠️ Could not delete subcollection "$subName": $e');
          // Continue — don't block deletion if one subcollection fails
        }
      }

      // ── Step 2: Delete the user profile document ──
      try {
        await userDocRef.delete();
        debugPrint('🗑️ User profile document deleted');
      } catch (e) {
        debugPrint('⚠️ Could not delete user profile doc: $e');
      }

      // ── Step 3: Clear native preferences ──
      try {
        await NativePreferencesService.getInstance().then(
          (prefs) => prefs.clear(),
        );
        debugPrint('🗑️ Native preferences cleared');
      } catch (e) {
        debugPrint('⚠️ Could not clear native preferences: $e');
      }

      // ── Step 4: Delete the Firebase Auth account (MUST be last) ──
      try {
        await currentUser.delete();
        debugPrint('✅ Firebase Auth account deleted');
      } on FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login') {
          throw Exception(
            'For security, please sign out and sign back in, then try deleting your account again.',
          );
        }
        rethrow;
      }

      // ── Step 5: Reset local state ──
      _user = null;
      _error = null;
      _isLoading = false;
      notifyListeners();

      debugPrint('✅ Account deletion completed successfully');
    } catch (e) {
      debugPrint('❌ Account deletion failed: $e');
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