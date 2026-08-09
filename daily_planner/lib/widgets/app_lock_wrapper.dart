import 'package:flutter/material.dart';
import 'package:daily_planner/services/custom_state_management.dart';
import 'package:daily_planner/providers/auth_provider.dart' as app_auth;
import 'package:daily_planner/utils/passkey_auth_service.dart';
import 'package:daily_planner/screens/app_lock_screen.dart';

class AppLockWrapper extends StatefulWidget {
  final Widget child;
  const AppLockWrapper({super.key, required this.child});

  @override
  State<AppLockWrapper> createState() => _AppLockWrapperState();
}

class _AppLockWrapperState extends State<AppLockWrapper> with WidgetsBindingObserver {
  bool _isLocked = false;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLockOnStartup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkLockOnStartup() async {
    // Check if biometric is enabled
    final isEnabled = await PasskeyAuthService().isPasskeyEnabled();
    if (!mounted) return;
    
    final authProvider = context.read<app_auth.AuthProvider>();
    
    // Wait for authProvider to finish initial loading
    while (authProvider.isLoading && mounted) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    if (mounted) {
      if (isEnabled && authProvider.isLoggedIn) {
        setState(() => _isLocked = true);
        _authenticate();
      }
      setState(() => _isChecking = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Lock when the app goes to background
      _lockAppIfNeeded();
    } else if (state == AppLifecycleState.resumed) {
      // When resuming, check if we are locked, or if we need to lock
      if (_isLocked) {
        _authenticate();
      } else {
        _lockAppIfNeeded().then((locked) {
           if (locked) _authenticate();
        });
      }
    }
  }

  Future<bool> _lockAppIfNeeded() async {
    final authProvider = context.read<app_auth.AuthProvider>();
    final isEnabled = await PasskeyAuthService().isPasskeyEnabled();
    
    if (isEnabled && authProvider.isLoggedIn) {
      if (!_isLocked && mounted) {
        setState(() => _isLocked = true);
      }
      return true;
    }
    return false;
  }

  Future<void> _authenticate() async {
    // Only attempt to authenticate if we are locked
    if (!_isLocked) return;
    
    final success = await PasskeyAuthService().verifyWithPasskey(
      reason: 'Please authenticate to unlock the app',
    );
    
    if (success && mounted) {
      setState(() => _isLocked = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // While checking initial state, we just show a blank screen or loading
    // Since this wraps the whole app, returning child is fine, but we might want 
    // to hide it if we suspect it will lock. Let's return empty container to prevent flicker of sensitive data.
    if (_isChecking) {
      return Container(color: Theme.of(context).scaffoldBackgroundColor);
    }

    return Stack(
      children: [
        widget.child,
        if (_isLocked)
          Positioned.fill(
            child: AppLockScreen(
              onUnlock: _authenticate,
            ),
          ),
      ],
    );
  }
}
