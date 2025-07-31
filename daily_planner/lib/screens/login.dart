import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/screens/forgotPass.dart';
import 'package:daily_planner/screens/home.dart';
import 'package:daily_planner/screens/signup.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;

  Future<void> loginUser() async {
    if (!_formKey.currentState!.validate()) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logging in...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userCredential.user!.uid)
              .get();

      String fullName = userDoc.data()?['fullName'] ?? 'User';

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Welcome, $fullName!')));

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MyHome()),
      );
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      String message = 'Login failed.';
      if (e.code == 'user-not-found') {
        message = 'No user found for that email.';
      } else if (e.code == 'wrong-password') {
        message = 'Incorrect password. Please try again.';
      } else if (e.code == 'invalid-email') {
        message = 'The email address is not valid.';
      } else if (e.code == 'invalid-credential') {
        message =
            'Invalid login credentials. Please check your email and password.';
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An unexpected error occurred. Please try again.'),
        ),
      );
      print('Unexpected error during login: $e');
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final uid = userCredential.user!.uid;

      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (!userDoc.exists) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'fullName': googleUser.displayName,
          'email': googleUser.email,
          'createdAt': Timestamp.now(),
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Welcome, ${googleUser.displayName ?? "User"}!'),
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MyHome()),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Google sign-in failed.')));
      print("Google sign-in error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 100,
                  color: Colors.blueAccent,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Welcome Back!',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 30),

                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator:
                      (value) =>
                          value != null &&
                                  value.contains('@') &&
                                  value.endsWith('.com')
                              ? null
                              : 'Enter a valid email (e.g., example@domain.com)',
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _passwordController,
                  obscureText: !_isPasswordVisible,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _isPasswordVisible = !_isPasswordVisible;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator:
                      (value) =>
                          value != null && value.length >= 6
                              ? null
                              : 'Password must be at least 6 characters long',
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    
                    TextButton(

                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ForgotPasswordScreen(),
                          ),
                        );
                      },
                      child: Text("Forgot Password?"),
                    ),
                  ],
                ),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      FocusScope.of(context).unfocus();
                      await loginUser();
                    },
                    child: const Text('Login', style: TextStyle(fontSize: 16)),
                  ),
                ),

                const SizedBox(height: 12),

                Center(
                  child: SizedBox(
                    ////// width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        side: const BorderSide(color: Colors.grey),
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () async {
                        await signInWithGoogle();
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset('assets/google.png', height: 24),
                          const SizedBox(width: 12),
                          const Text(
                            'Continue with Google',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Don't have an account?"),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SignupPage(),
                          ),
                        );
                      },
                      child: const Text("Sign Up"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
