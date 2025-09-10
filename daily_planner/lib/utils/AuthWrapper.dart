import 'package:daily_planner/screens/home.dart';
import 'package:daily_planner/screens/login.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  User? user;
  bool checkedAuth = false;

  @override
  void initState() {
    super.initState();
    _initAuth();
  }

  Future<void> _initAuth() async {
    try {
      // 1️⃣ Use cached currentUser first (no server call, instant)
      user = FirebaseAuth.instance.currentUser;

      // 2️⃣ Listen for auth state changes in background
      FirebaseAuth.instance.authStateChanges().listen((u) {
        if (mounted) setState(() => user = u);
      });
    } finally {
      // 3️⃣ Mark auth check as done
      if (mounted) setState(() => checkedAuth = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!checkedAuth) {
      // Show loading spinner only while checking cached auth
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Navigate based on cached auth
    return user != null ? const MyHome() : const LoginPage();
  }
}
