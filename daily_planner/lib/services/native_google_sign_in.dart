import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Represents a signed-in Google account from the native Android Google Sign-In SDK.
class NativeGoogleSignInAccount {
  final String? id;
  final String? idToken;
  final String? email;
  final String? displayName;
  final String? givenName;
  final String? familyName;
  final String? photoUrl;
  final String? serverAuthCode;

  const NativeGoogleSignInAccount({
    this.id,
    this.idToken,
    this.email,
    this.displayName,
    this.givenName,
    this.familyName,
    this.photoUrl,
    this.serverAuthCode,
  });

  factory NativeGoogleSignInAccount.fromMap(Map<dynamic, dynamic> map) {
    return NativeGoogleSignInAccount(
      id: map['id'] as String?,
      idToken: map['idToken'] as String?,
      email: map['email'] as String?,
      displayName: map['displayName'] as String?,
      givenName: map['givenName'] as String?,
      familyName: map['familyName'] as String?,
      photoUrl: map['photoUrl'] as String?,
      serverAuthCode: map['serverAuthCode'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'idToken': idToken,
      'email': email,
      'displayName': displayName,
      'givenName': givenName,
      'familyName': familyName,
      'photoUrl': photoUrl,
      'serverAuthCode': serverAuthCode,
    };
  }

  @override
  String toString() =>
      'NativeGoogleSignInAccount(email: $email, displayName: $displayName, hasToken: ${idToken != null})';
}

/// Custom in-house Google Sign-In Service replacing third-party package:google_sign_in.
class NativeGoogleSignIn {
  static const MethodChannel _channel =
      MethodChannel('daily_planner/native_google_signin');

  /// Start native Google Sign-In flow
  static Future<NativeGoogleSignInAccount?> signIn({
    String? serverClientId,
  }) async {
    try {
      final dynamic result = await _channel.invokeMethod('signIn', {
        if (serverClientId != null) 'serverClientId': serverClientId,
      });

      if (result is Map) {
        return NativeGoogleSignInAccount.fromMap(result);
      }
      return null;
    } on PlatformException catch (e) {
      debugPrint('Native Google Sign-In PlatformException: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      debugPrint('Native Google Sign-In error: $e');
      return null;
    }
  }

  /// Sign out the current Google user natively
  static Future<bool> signOut() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('signOut');
      return result ?? true;
    } catch (e) {
      debugPrint('Native Google Sign-Out error: $e');
      return false;
    }
  }

  /// Revoke Google access
  static Future<bool> disconnect() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>('disconnect');
      return result ?? true;
    } catch (e) {
      debugPrint('Native Google Disconnect error: $e');
      return false;
    }
  }

  /// Get the currently signed-in Google account without showing UI
  static Future<NativeGoogleSignInAccount?> getCurrentUser() async {
    try {
      final dynamic result = await _channel.invokeMethod('getCurrentUser');
      if (result is Map) {
        return NativeGoogleSignInAccount.fromMap(result);
      }
      return null;
    } catch (e) {
      debugPrint('Native Google getCurrentUser error: $e');
      return null;
    }
  }

  /// Complete end-to-end Google sign in and Firebase authentication
  static Future<UserCredential?> signInWithFirebase({
    String? serverClientId,
  }) async {
    final account = await signIn(serverClientId: serverClientId);
    if (account == null || account.idToken == null) {
      debugPrint('Native Google Sign-In failed or cancelled by user');
      return null;
    }

    final credential = GoogleAuthProvider.credential(
      idToken: account.idToken,
      accessToken: account.idToken,
    );

    return await FirebaseAuth.instance.signInWithCredential(credential);
  }
}
