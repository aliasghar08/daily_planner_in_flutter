import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:daily_planner/screens/forgotPass.dart';
import 'package:daily_planner/screens/home.dart';
import 'package:daily_planner/screens/signup.dart';
import 'package:daily_planner/services/native_google_sign_in.dart';
import 'package:daily_planner/utils/passkey_auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:daily_planner/services/native_preferences_service.dart';

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
  bool _rememberMe = false;
  bool _isPasskeyAvailable = false;
  bool _isPasskeyLoading = false;

  final PasskeyAuthService _passkeyAuthService = PasskeyAuthService();

  @override
  void initState() {
    super.initState();
    _loadRememberMePreference();
    _checkPasskeyAvailability();
  }

  // ✅ Check if Passkeys/Biometrics are supported and enabled
  Future<void> _checkPasskeyAvailability() async {
    try {
      final isSupported = await _passkeyAuthService.isDeviceSupported();
      final hasCreds = (await _passkeyAuthService.getSavedPasskeyCredential()) != null;
      final isEnabled = await _passkeyAuthService.isPasskeyEnabled();
      if (mounted) {
        setState(() {
          _isPasskeyAvailable = isSupported && (hasCreds || isEnabled);
        });
      }
    } catch (e) {
      debugPrint('Error checking passkey availability: $e');
    }
  }

  // ✅ Sign in with Passkey / Biometrics
  Future<void> signInWithPasskey() async {
    setState(() => _isPasskeyLoading = true);
    try {
      final authenticated = await _passkeyAuthService.verifyWithPasskey(
        reason: 'Verify with Passkey to sign in to Daily Planner',
      );

      if (!authenticated) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Passkey verification cancelled or not recognized.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      final savedCreds = await _passkeyAuthService.getSavedPasskeyCredential();
      if (savedCreds != null) {
        final email = savedCreds['email']!;
        final password = savedCreds['password']!;

        final userCredential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);

        TextInput.finishAutofillContext(shouldSave: true);

        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .get();

        String fullName = userDoc.data()?['fullName'] ?? 'User';

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Welcome back, $fullName! (Verified with Passkey)')),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const MyHome()),
          );
        }
      } else if (FirebaseAuth.instance.currentUser != null) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const MyHome()),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please sign in with email and password once to register your Passkey.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Passkey login error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPasskeyLoading = false);
    }
  }

  // ✅ Load saved "Remember Me" preference
  Future<void> _loadRememberMePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rememberMe = prefs.getBool('rememberMe') ?? false;
      final savedEmail = prefs.getString('savedEmail') ?? '';

      if (mounted) {
        setState(() {
          _rememberMe = rememberMe;
          if (_rememberMe && savedEmail.isNotEmpty) {
            _emailController.text = savedEmail;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading Remember Me preference: $e');
    }
  }

  // ✅ Save "Remember Me" preference
  Future<void> _saveRememberMePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('rememberMe', _rememberMe);
      if (_rememberMe) {
        await prefs.setString('savedEmail', _emailController.text.trim());
      } else {
        await prefs.remove('savedEmail');
      }
    } catch (e) {
      debugPrint('Error saving Remember Me preference: $e');
    }
  }

  Future<void> loginUser() async {
    if (!_formKey.currentState!.validate()) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Logging in...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: email,
            password: password,
          );

      // ✅ Trigger Google Password Manager and Apple Passwords save dialog
      TextInput.finishAutofillContext(shouldSave: true);

      // ✅ Store passkey credential for future one-tap passkey login
      await _passkeyAuthService.savePasskeyCredential(
        email: email,
        password: password,
      );

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .get();

      String fullName = userDoc.data()?['fullName'] ?? 'User';

      // ✅ Save Remember Me preference after successful login
      await _saveRememberMePreference();

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Welcome, $fullName!')));

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MyHome()),
        );
      }
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
        message = 'Invalid login credentials. Please check your email and password.';
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
      final googleAccount = await NativeGoogleSignIn.signIn();
      if (googleAccount == null || googleAccount.idToken == null) {
        return;
      }

      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAccount.idToken,
        accessToken: googleAccount.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );

      final uid = userCredential.user!.uid;

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (!userDoc.exists) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'fullName': googleAccount.displayName ?? userCredential.user?.displayName,
          'email': googleAccount.email ?? userCredential.user?.email,
          'createdAt': Timestamp.now(),
        });
      }

      // ✅ Save Remember Me preference for Google sign-in
      if (_rememberMe && googleAccount.email != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('rememberMe', true);
        await prefs.setString('savedEmail', googleAccount.email!);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Welcome, ${googleAccount.displayName ?? userCredential.user?.displayName ?? "User"}!'),
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MyHome()),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Google sign-in failed.')));
      }
      debugPrint("Google sign-in error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  const Icon(
                    Icons.lock_outline,
                    size: 90,
                    color: Colors.blueAccent,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Welcome Back!',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),

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
                    autofillHints: const [
                      AutofillHints.email,
                      AutofillHints.username,
                    ],
                    textInputAction: TextInputAction.next,
                    validator: (value) =>
                        value != null && value.contains('@') && value.endsWith('.com')
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
                          _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
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
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) async {
                      FocusScope.of(context).unfocus();
                      await loginUser();
                    },
                    validator: (value) =>
                        value != null && value.length >= 6
                            ? null
                            : 'Password must be at least 6 characters long',
                  ),
                  
                  // ✅ Remember Me Checkbox
                  Row(
                    children: [
                      Checkbox(
                        value: _rememberMe,
                        onChanged: (value) {
                          setState(() {
                            _rememberMe = value ?? false;
                          });
                        },
                        activeColor: Colors.blueAccent,
                      ),
                      const Text(
                        'Remember Me',
                        style: TextStyle(fontSize: 14),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ForgotPasswordScreen(),
                            ),
                          );
                        },
                        child: const Text("Forgot Password?"),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

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

                  if (_isPasskeyAvailable) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: _isPasskeyLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.fingerprint, size: 22),
                        label: const Text(
                          'Sign in with Passkey / Biometrics',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: Colors.indigo.shade600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _isPasskeyLoading ? null : signInWithPasskey,
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),

                  Center(
                    child: SizedBox(
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
      ),
    );
  }
}