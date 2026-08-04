import 'package:daily_planner/screens/home.dart';
import 'package:daily_planner/screens/login.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  User? _user;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initAuth();
  }

  Future<void> _initAuth() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Step 1: Use cached currentUser first (works offline & across restarts)
      _user = FirebaseAuth.instance.currentUser;
      debugPrint('🔐 Cached user session: ${_user?.email ?? 'No active session'}');

      // Step 2: Listen for auth state changes in background
      FirebaseAuth.instance.authStateChanges().listen((User? newUser) {
        if (mounted) {
          debugPrint('🔄 Auth state changed: ${newUser?.email ?? 'Signed out'}');
          setState(() {
            _user = newUser;
            _isLoading = false;
          });
        }
      });

      // Step 3: Ensure Firestore profile exists without logging out
      if (_user != null) {
        _syncUserDocument(_user!);
      }
    } catch (e) {
      debugPrint('❌ Auth initialization error: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _syncUserDocument(User user) async {
    try {
      final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final doc = await docRef.get();
      if (!doc.exists) {
        await docRef.set({
          'fullName': user.displayName ?? (user.email?.split('@').first ?? 'User'),
          'email': user.email ?? '',
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('⚠️ Firestore sync note: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading spinner while checking auth
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Checking session...',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // Show error if any
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red.shade400,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Authentication Error',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _isLoading = true;
                    });
                    _initAuth();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Navigate based on auth state
    return _user != null ? const MyHome() : const LoginPage();
  }
}