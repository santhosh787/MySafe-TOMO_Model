import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _googleInitialized = false;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<UserCredential> registerWithEmail(String name, String email, String password) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await credential.user?.updateDisplayName(name.trim());
    await ProfileService.instance.ensureProfile(credential.user!, displayName: name.trim());
    return credential;
  }

  Future<UserCredential> signInWithEmail(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await ProfileService.instance.ensureProfile(credential.user!);
    return credential;
  }

  Future<UserCredential> signInWithGoogle() async {
    if (!_googleInitialized) {
      await GoogleSignIn.instance.initialize();
      _googleInitialized = true;
    }
    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw StateError('Google sign-in is not supported on this platform build.');
    }
    final account = await GoogleSignIn.instance.authenticate();
    final googleAuth = account.authentication;
    final credential = GoogleAuthProvider.credential(idToken: googleAuth.idToken);
    final result = await _auth.signInWithCredential(credential);
    await ProfileService.instance.ensureProfile(result.user!);
    return result;
  }

  Future<void> signOut() async {
    await _auth.signOut();
    if (_googleInitialized) {
      await GoogleSignIn.instance.signOut();
    }
  }

  Future<void> signInWithPhoneCredential(PhoneAuthCredential credential) async {
    final result = await _auth.signInWithCredential(credential);
    await ProfileService.instance.ensureProfile(result.user!);
  }

  Future<void> sendPhoneVerification({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) codeSent,
    required void Function(FirebaseAuthException error) failed,
    required void Function(PhoneAuthCredential credential) completed,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber.trim(),
      timeout: const Duration(seconds: 60),
      verificationCompleted: completed,
      verificationFailed: failed,
      codeSent: codeSent,
      codeAutoRetrievalTimeout: (verificationId) {},
    );
  }
}

class ProfileService {
  ProfileService._();
  static final ProfileService instance = ProfileService._();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> ensureProfile(User user, {String? displayName}) async {
    final ref = _db.collection('users').doc(user.uid);
    final existing = await ref.get();
    final profile = <String, dynamic>{
      'displayName': displayName ?? user.displayName ?? '',
      'email': user.email ?? '',
      'phoneNumber': user.phoneNumber ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (!existing.exists) profile['createdAt'] = FieldValue.serverTimestamp();
    await ref.set(profile, SetOptions(merge: true));
  }

  Future<void> saveDeviceToken(String token) async {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null) return;
    final tokenId = sha256.convert(utf8.encode(token)).toString();
    await _db.collection('users').doc(uid).collection('devices').doc(tokenId).set({
      'token': token,
      'updatedAt': FieldValue.serverTimestamp(),
      'platform': defaultTargetPlatform.name,
    }, SetOptions(merge: true));
  }
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  Future<void> initialize() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    await syncCurrentToken();
    messaging.onTokenRefresh.listen((token) {
      ProfileService.instance.saveDeviceToken(token);
    });
  }

  Future<void> syncCurrentToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await ProfileService.instance.saveDeviceToken(token);
    } catch (_) {
      // FCM can be unavailable on simulators until platform push setup is complete.
    }
  }
}

class SafetyService {
  SafetyService._();
  static final SafetyService instance = SafetyService._();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<Position?> _getPermittedLocation() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 12),
      ),
    );
  }

  Future<String> createSosIncident() async {
    final user = AuthService.instance.currentUser;
    if (user == null) throw StateError('You must be signed in to send an SOS.');

    Position? position;
    try {
      position = await _getPermittedLocation();
    } catch (_) {
      // The SOS is still recorded when GPS is unavailable or times out.
    }

    final doc = _db.collection('users').doc(user.uid).collection('incidents').doc();
    await doc.set({
      'type': 'sos',
      'message': 'The user requested emergency assistance.',
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
      'location': position == null
          ? null
          : {
              'latitude': position.latitude,
              'longitude': position.longitude,
              'accuracyMeters': position.accuracy,
              'capturedAt': Timestamp.fromDate(position.timestamp),
            },
    });
    return doc.id;
  }

  Future<void> checkIn() async {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null) throw StateError('You must be signed in.');
    await _db.collection('users').doc(uid).update({
      'lastCheckInAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

class GuardianService {
  GuardianService._();
  static final GuardianService instance = GuardianService._();
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  Future<String> createInvite() async {
    final result = await _functions.httpsCallable('createGuardianInvite').call();
    final data = Map<String, dynamic>.from(result.data as Map);
    final code = data['code'] as String?;
    if (code == null || code.isEmpty) throw StateError('The server did not return an invite code.');
    return 'mysafetomo://pair?code=$code';
  }

  Future<void> acceptInvite(String scannedValue) async {
    final uri = Uri.tryParse(scannedValue);
    final code = uri?.queryParameters['code'] ?? scannedValue.trim();
    if (code.isEmpty) throw ArgumentError('The QR code does not contain an invitation.');
    await _functions.httpsCallable('acceptGuardianInvite').call({'code': code});
  }
}
