import 'package:flutter/material.dart';

class AppLockScreen extends StatelessWidget {
  final VoidCallback onUnlock;
  
  const AppLockScreen({super.key, required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline, 
              size: 100, 
              color: Theme.of(context).primaryColor,
            ),
            const SizedBox(height: 32),
            const Text(
              'App Locked', 
              style: TextStyle(
                fontSize: 28, 
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Please authenticate to access the app',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 48),
            ElevatedButton.icon(
              icon: const Icon(Icons.fingerprint, size: 28),
              label: const Text(
                'Unlock',
                style: TextStyle(fontSize: 18),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: onUnlock,
            ),
          ],
        ),
      ),
    );
  }
}
