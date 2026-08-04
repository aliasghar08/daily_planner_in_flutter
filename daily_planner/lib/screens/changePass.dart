import 'package:daily_planner/utils/passkey_auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _currentPassController = TextEditingController();
  final TextEditingController _newPassController = TextEditingController();
  final TextEditingController _confirmPassController = TextEditingController();

  bool isLoading = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email;

    try {
      if (user == null || email == null) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'User is not logged in.',
        );
      }

      final cred = EmailAuthProvider.credential(
        email: email,
        password: _currentPassController.text.trim(),
      );
      await user.reauthenticateWithCredential(cred);

      final newPassword = _newPassController.text.trim();
      await user.updatePassword(newPassword);

      // ✅ Signal Google Password Manager and Apple Passwords to update stored password
      TextInput.finishAutofillContext(shouldSave: true);

      // ✅ Update saved Passkey credentials with new password
      await PasskeyAuthService().savePasskeyCredential(
        email: email,
        password: newPassword,
      );

      _currentPassController.clear();
      _newPassController.clear();
      _confirmPassController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Password changed successfully. Stored passwords updated."),
          ),
        );

        await FirebaseAuth.instance.signOut();
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.message}")),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Change Password")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: AutofillGroup(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _currentPassController,
                  obscureText: _obscureCurrent,
                  decoration: InputDecoration(
                    labelText: "Current Password",
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureCurrent ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() => _obscureCurrent = !_obscureCurrent);
                      },
                    ),
                  ),
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.next,
                  validator: (value) =>
                      value == null || value.isEmpty ? "Enter current password" : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _newPassController,
                  obscureText: _obscureNew,
                  decoration: InputDecoration(
                    labelText: "New Password",
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureNew ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() => _obscureNew = !_obscureNew);
                      },
                    ),
                  ),
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                  validator: (value) =>
                      value != null && value.length >= 6
                          ? null
                          : "Password must be at least 6 characters",
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPassController,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    labelText: "Confirm New Password",
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() => _obscureConfirm = !_obscureConfirm);
                      },
                    ),
                  ),
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _changePassword(),
                  validator: (value) =>
                      value == _newPassController.text
                          ? null
                          : "Passwords do not match",
                ),
                const SizedBox(height: 24),
                isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton.icon(
                        onPressed: _changePassword,
                        icon: const Icon(Icons.lock_reset),
                        label: const Text("Change Password"),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
