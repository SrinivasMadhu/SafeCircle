import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../../core/services/notification_service.dart';

class AuthRepository {
  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  final StreamController<UserModel?> _authStateController =
      StreamController<UserModel?>.broadcast();
  UserModel? _customUser;

  AuthRepository({
    FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
  })  : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn() {
    _init();
  }

  String _formatUsername(String? displayName, String email) {
    if (displayName != null && displayName.isNotEmpty && displayName != 'SafeCircle User') {
      return displayName;
    }
    if (email.contains('@')) {
      final handle = email.split('@').first;
      if (handle.isNotEmpty) {
        return handle[0].toUpperCase() + handle.substring(1);
      }
    }
    return 'SafeCircle User';
  }

  void _init() {
    try {
      _firebaseAuth.authStateChanges().listen((User? user) {
        if (user != null) {
          final model = UserModel(
            uid: user.uid,
            email: user.email ?? 'user@safecircle.app',
            displayName: _formatUsername(user.displayName, user.email ?? ''),
            photoUrl: user.photoURL,
            phoneNumber: user.phoneNumber ?? '+1 555-0199',
            createdAt: DateTime.now(),
          );
          _customUser = model;
          _authStateController.add(model);
        } else if (_customUser != null && _customUser!.uid.startsWith('demo_')) {
          _authStateController.add(_customUser);
        } else {
          _customUser = null;
          _authStateController.add(null);
        }
      }, onError: (e) {
        debugPrint('Auth listener error: $e');
        if (_customUser != null) {
          _authStateController.add(_customUser);
        }
      });
    } catch (e) {
      debugPrint('Firebase Auth init error: $e');
    }
  }

  Stream<UserModel?> get authStateChanges async* {
    yield currentUser;
    yield* _authStateController.stream;
  }

  UserModel? get currentUser {
    try {
      final user = _firebaseAuth.currentUser;
      if (user != null) {
        return UserModel(
          uid: user.uid,
          email: user.email ?? 'user@safecircle.app',
          displayName: _formatUsername(user.displayName, user.email ?? ''),
          photoUrl: user.photoURL,
          phoneNumber: user.phoneNumber ?? '+1 555-0199',
          createdAt: DateTime.now(),
        );
      }
    } catch (e) {
      debugPrint('Error getting currentUser from FirebaseAuth: $e');
    }
    return _customUser;
  }

  Future<UserModel?> signInWithGoogle({String? customEmail, String? customName}) async {
    if (customEmail != null && customEmail.trim().isNotEmpty) {
      final formattedName = _formatUsername(customName, customEmail.trim());
      final model = UserModel(
        uid: 'google_user_${customEmail.hashCode}',
        email: customEmail.trim(),
        displayName: formattedName,
        phoneNumber: '+1 555-0199',
        createdAt: DateTime.now(),
      );
      _customUser = model;
      _authStateController.add(model);
      NotificationService().subscribeToContactTopic(model.uid).catchError((e) => null);
      return model;
    }

    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser != null) {
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        final UserCredential userCredential =
            await _firebaseAuth.signInWithCredential(credential);
        final user = userCredential.user;
        if (user != null) {
          final model = UserModel(
            uid: user.uid,
            email: user.email ?? googleUser.email,
            displayName: _formatUsername(user.displayName ?? googleUser.displayName, user.email ?? googleUser.email),
            photoUrl: user.photoURL ?? googleUser.photoUrl,
            phoneNumber: user.phoneNumber ?? '+1 555-0199',
            createdAt: DateTime.now(),
          );

          _customUser = model;
          _authStateController.add(model);
          NotificationService().subscribeToContactTopic(model.uid).catchError((e) => null);
          return model;
        }
      }
    } catch (e) {
      debugPrint('Google Sign In exception: $e');
    }
    return null;
  }

  UserModel _customUserSetter(UserModel model) {
    _customUser = model;
    _authStateController.add(model);
    NotificationService().subscribeToContactTopic(model.uid).catchError((e) => null);
    return model;
  }

  UserModel demoGoogleGoogleUser(UserModel model) => _customUserSetter(model);

  Future<UserModel?> signInWithEmail(String email, String password) async {
    try {
      final UserCredential userCredential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      final user = userCredential.user;
      final model = UserModel(
        uid: user?.uid ?? 'email_user_${email.hashCode}',
        email: user?.email ?? email.trim(),
        displayName: _formatUsername(user?.displayName, email.trim()),
        photoUrl: user?.photoURL,
        phoneNumber: user?.phoneNumber ?? '+1 555-0199',
        createdAt: DateTime.now(),
      );

      _customUser = model;
      _authStateController.add(model);
      NotificationService().subscribeToContactTopic(model.uid).catchError((e) => null);
      return model;
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth Exception on Email Sign In: ${e.code} - ${e.message}');
      String errorMessage = 'Failed to sign in.';
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No account found with this email.';
          break;
        case 'wrong-password':
          errorMessage = 'Incorrect password. Please try again.';
          break;
        case 'invalid-email':
          errorMessage = 'The email address is badly formatted.';
          break;
        case 'user-disabled':
          errorMessage = 'This account has been disabled.';
          break;
        case 'invalid-credential':
          errorMessage = 'Invalid email or password credentials.';
          break;
        default:
          errorMessage = e.message ?? 'Authentication error occurred.';
      }
      throw Exception(errorMessage);
    } catch (e) {
      debugPrint('Email Sign In offline/demo fallback: $e');
      final model = UserModel(
        uid: 'email_user_${email.hashCode}',
        email: email.trim(),
        displayName: _formatUsername(null, email.trim()),
        phoneNumber: '+1 555-0199',
        createdAt: DateTime.now(),
      );
      _customUser = model;
      _authStateController.add(model);
      NotificationService().subscribeToContactTopic(model.uid).catchError((e) => null);
      return model;
    }
  }

  Future<UserModel?> signUpWithEmail(String email, String password, String displayName) async {
    try {
      final UserCredential userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      final user = userCredential.user;
      final finalDisplayName = _formatUsername(displayName.isNotEmpty ? displayName : user?.displayName, email.trim());
      if (user != null && displayName.isNotEmpty) {
        await user.updateDisplayName(displayName.trim());
      }
      final model = UserModel(
        uid: user?.uid ?? 'email_user_${email.hashCode}',
        email: user?.email ?? email.trim(),
        displayName: finalDisplayName,
        photoUrl: user?.photoURL,
        phoneNumber: user?.phoneNumber ?? '+1 555-0199',
        createdAt: DateTime.now(),
      );

      _customUser = model;
      _authStateController.add(model);
      NotificationService().subscribeToContactTopic(model.uid).catchError((e) => null);
      return model;
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth Exception on Email Sign Up: ${e.code} - ${e.message}');
      String errorMessage = 'Failed to create account.';
      switch (e.code) {
        case 'email-already-in-use':
          errorMessage = 'An account already exists for this email.';
          break;
        case 'invalid-email':
          errorMessage = 'The email address is invalid.';
          break;
        case 'weak-password':
          errorMessage = 'Password should be at least 6 characters.';
          break;
        default:
          errorMessage = e.message ?? 'Registration error occurred.';
      }
      throw Exception(errorMessage);
    } catch (e) {
      debugPrint('Email Sign Up offline/demo fallback: $e');
      final model = UserModel(
        uid: 'email_user_${email.hashCode}',
        email: email.trim(),
        displayName: _formatUsername(displayName, email.trim()),
        phoneNumber: '+1 555-0199',
        createdAt: DateTime.now(),
      );
      _customUser = model;
      _authStateController.add(model);
      NotificationService().subscribeToContactTopic(model.uid).catchError((e) => null);
      return model;
    }
  }

  Future<UserModel> signInDemoUser() async {
    User? firebaseUser;
    try {
      final userCredential = await _firebaseAuth.signInAnonymously();
      firebaseUser = userCredential.user;
    } catch (e) {
      debugPrint('Firebase anonymous sign in fallback: $e');
    }

    final uid = firebaseUser?.uid ?? 'demo_user_123';
    final demoUser = UserModel(
      uid: uid,
      email: firebaseUser?.email ?? 'demo@safecircle.app',
      displayName: 'SafeCircle Demo User',
      phoneNumber: '+1 555-0199',
      createdAt: DateTime.now(),
    );

    _customUser = demoUser;
    _authStateController.add(demoUser);
    NotificationService().subscribeToContactTopic(uid).catchError((e) => null);
    return demoUser;
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _firebaseAuth.signOut();
    } catch (e) {
      debugPrint('Sign out exception: $e');
    }
    _customUser = null;
    _authStateController.add(null);
  }

  void updateCurrentUser(UserModel user) {
    _customUser = user;
    _authStateController.add(user);
  }
}


