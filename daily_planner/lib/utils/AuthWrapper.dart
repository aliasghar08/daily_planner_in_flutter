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

      // ✅ Step 1: Use cached currentUser first (works offline)
      _user = FirebaseAuth.instance.currentUser;
      debugPrint('🔐 Cached user: ${_user?.email ?? 'null'}');

      // ✅ Step 2: Listen for auth state changes in background
      FirebaseAuth.instance.authStateChanges().listen((User? newUser) {
        if (mounted) {
          debugPrint('🔄 Auth state changed: ${newUser?.email ?? 'null'}');
          setState(() {
            _user = newUser;
            _isLoading = false;
          });
        }
      });

      // ✅ Step 3: If user exists, verify their data in Firestore
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
            if (mounted) {
              setState(() {
                _user = null;
                _error = 'User data not found';
              });
            }
          } else {
            debugPrint('✅ User data verified in Firestore');
          }
        } catch (e) {
          // Network error - keep user logged in if cached data exists
          debugPrint('⚠️ Could not verify user data (network error): $e');
        }
      }

      // ✅ Step 4: Small delay to ensure everything is loaded
      await Future.delayed(const Duration(milliseconds: 300));
      
    } catch (e) {
      debugPrint('❌ Auth initialization error: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _user = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
                Text(
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