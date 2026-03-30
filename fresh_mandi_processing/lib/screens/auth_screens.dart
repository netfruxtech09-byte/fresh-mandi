import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/auth_state.dart';
import '../widgets/shared_widgets.dart';
import 'home_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneCtrl = TextEditingController();

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final phoneDigits = _phoneCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    final canSubmit = phoneDigits.length == 10 && !auth.loading;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: [
                  const AuthTopBanner(),
                  const SizedBox(height: 16),
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Login to continue',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Use your admin-created processing account. No customer or delivery login works here.',
                            style: TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            maxLength: 10,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Mobile Number',
                              prefixText: '+91 ',
                              counterText: '',
                              hintText: '9876543210',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: canSubmit
                                  ? () async {
                                      FocusScope.of(context).unfocus();
                                      final ok = await auth.requestOtp(
                                        _phoneCtrl.text,
                                      );
                                      if (!context.mounted) return;
                                      if (ok) {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => const OtpScreen(),
                                          ),
                                        );
                                      }
                                    }
                                  : null,
                              child: auth.loading
                                  ? const BtnLoader()
                                  : const Text('Send OTP'),
                            ),
                          ),
                          if ((auth.error ?? '').isNotEmpty) ...[
                            const SizedBox(height: 10),
                            ErrorBox(text: auth.error!),
                          ],
                        ],
                      ),
                    ),
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

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  int _seconds = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(6, (_) => TextEditingController());
    _focusNodes = List.generate(6, (_) => FocusNode());
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _focusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _seconds = 30;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_seconds == 0) {
        t.cancel();
        return;
      }
      setState(() => _seconds -= 1);
    });
  }

  String _otp() => _controllers.map((e) => e.text).join();

  void _onOtpChanged(int index, String value) {
    final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length > 1) {
      for (var i = 0; i < 6; i++) {
        _controllers[i].text = i < digitsOnly.length ? digitsOnly[i] : '';
      }
      _focusNodes[(digitsOnly.length.clamp(1, 6)) - 1].requestFocus();
      return;
    }
    if (digitsOnly.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    if (digitsOnly.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final canResend = _seconds == 0 && !auth.loading;
    final canVerify = _otp().length == 6 && !auth.loading;

    return Scaffold(
      appBar: AppBar(title: const Text('Verify OTP')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Enter 6-digit OTP',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Sent to ${auth.pendingPhone ?? ''}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(6, (index) {
                          return SizedBox(
                            width: 48,
                            child: TextField(
                              controller: _controllers[index],
                              focusNode: _focusNodes[index],
                              keyboardType: TextInputType.number,
                              textInputAction: index == 5
                                  ? TextInputAction.done
                                  : TextInputAction.next,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                              decoration: const InputDecoration(
                                counterText: '',
                              ),
                              onChanged: (v) {
                                _onOtpChanged(index, v);
                                setState(() {});
                              },
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: canResend
                              ? () async {
                                  final ok = await auth.requestOtp(
                                    auth.pendingPhone ?? '',
                                  );
                                  if (!mounted) return;
                                  if (ok) {
                                    for (final c in _controllers) {
                                      c.clear();
                                    }
                                    _focusNodes.first.requestFocus();
                                    setState(_startTimer);
                                  }
                                }
                              : null,
                          child: Text(
                            canResend ? 'Resend OTP' : 'Resend in ${_seconds}s',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: canVerify
                              ? () async {
                                  FocusScope.of(context).unfocus();
                                  final ok = await auth.verifyOtp(_otp());
                                  if (!context.mounted) return;
                                  if (ok) {
                                    Navigator.pushAndRemoveUntil(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const ProcessingHomeShell(),
                                      ),
                                      (_) => false,
                                    );
                                  }
                                }
                              : null,
                          child: auth.loading
                              ? const BtnLoader()
                              : const Text('Verify & Continue'),
                        ),
                      ),
                      if ((auth.error ?? '').isNotEmpty) ...[
                        const SizedBox(height: 10),
                        ErrorBox(text: auth.error!),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
