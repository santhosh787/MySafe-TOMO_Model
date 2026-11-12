import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/app_services.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  bool _register = false;
  bool _phoneMode = false;
  bool _loading = false;
  bool _obscure = true;
  String? _verificationId;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _loading = true);
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      _message(e.message ?? e.code);
    } catch (e) {
      _message(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _emailSubmit() => _run(() async {
        if (_email.text.trim().isEmpty || _password.text.isEmpty) {
          _message('Enter your email and password.');
          return;
        }
        if (_register) {
          if (_name.text.trim().isEmpty) {
            _message('Enter your name.');
            return;
          }
          if (_password.text.length < 6) {
            _message('Use a password with at least 6 characters.');
            return;
          }
          await AuthService.instance.registerWithEmail(
            _name.text,
            _email.text,
            _password.text,
          );
        } else {
          await AuthService.instance.signInWithEmail(_email.text, _password.text);
        }
      });

  Future<void> _googleSubmit() => _run(() async {
        await AuthService.instance.signInWithGoogle();
      });

  Future<void> _sendOtp() => _run(() async {
        if (_phone.text.trim().isEmpty) {
          _message('Enter your phone number with country code, for example +91.');
          return;
        }
        await AuthService.instance.sendPhoneVerification(
          phoneNumber: _phone.text,
          codeSent: (id, _) {
            if (!mounted) return;
            setState(() => _verificationId = id);
            _message('Verification code sent.');
          },
          failed: (error) => _message(error.message ?? error.code),
          completed: (credential) async {
            try {
              await AuthService.instance.signInWithPhoneCredential(credential);
            } catch (e) {
              _message(e.toString());
            }
          },
        );
      });

  Future<void> _verifyOtp() => _run(() async {
        final id = _verificationId;
        if (id == null || _otp.text.trim().length < 6) {
          _message('Enter the six-digit code sent to your phone.');
          return;
        }
        final credential = PhoneAuthProvider.credential(
          verificationId: id,
          smsCode: _otp.text.trim(),
        );
        await AuthService.instance.signInWithPhoneCredential(credential);
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 74,
                    width: 74,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(Icons.shield_moon_rounded,
                        color: theme.colorScheme.primary, size: 40),
                  ),
                  const SizedBox(height: 22),
                  Text('My Safe Tomo', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('A trusted circle for everyday safety.',
                      style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 28),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Sign in')),
                      ButtonSegment(value: true, label: Text('Create account')),
                    ],
                    selected: {_register},
                    onSelectionChanged: _loading
                        ? null
                        : (value) => setState(() {
                              _register = value.first;
                              _phoneMode = false;
                            }),
                  ),
                  const SizedBox(height: 20),
                  if (_phoneMode) ...[
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                        hintText: '+91 98765 43210',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_verificationId != null)
                      TextField(
                        controller: _otp,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: 'SMS verification code',
                          prefixIcon: Icon(Icons.verified_outlined),
                          counterText: '',
                        ),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _loading ? null : (_verificationId == null ? _sendOtp : _verifyOtp),
                      child: _loading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(_verificationId == null ? 'Send OTP' : 'Verify and sign in'),
                    ),
                    TextButton(
                      onPressed: _loading ? null : () => setState(() { _phoneMode = false; _verificationId = null; }),
                      child: const Text('Back to email sign-in'),
                    ),
                  ] else ...[
                    if (_register) ...[
                      TextField(
                        controller: _name,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: _register ? const [AutofillHints.newPassword] : const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _loading ? null : _emailSubmit,
                      child: _loading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(_register ? 'Create secure account' : 'Sign in'),
                    ),
                    const SizedBox(height: 14),
                    const Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('OR')), Expanded(child: Divider())]),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _googleSubmit,
                      icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                      label: const Text('Continue with Google'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _loading ? null : () => setState(() { _phoneMode = true; _verificationId = null; }),
                      icon: const Icon(Icons.sms_outlined),
                      label: const Text('Continue with phone OTP'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'Emergency support depends on device permissions, network coverage and configured notification services. This app does not replace local emergency services.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF65777D)),
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
