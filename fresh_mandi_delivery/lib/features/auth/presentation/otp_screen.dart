import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/validators.dart';
import '../../../shared/providers/auth_provider.dart';
import '../../dashboard/presentation/home_screen.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.phone, required this.deviceId});

  final String phone;
  final String deviceId;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpCtrl = TextEditingController();

  @override
  void dispose() {
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.verifyOtp(
      phone: widget.phone,
      otp: _otpCtrl.text.trim(),
      deviceId: widget.deviceId,
    );
    if (!mounted || !ok) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Verify OTP')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            children: [
              Text('OTP sent to +91 ${widget.phone}'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _otpCtrl,
                maxLength: 6,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: Validators.otp6,
                decoration: const InputDecoration(
                  counterText: '',
                  labelText: 'Enter 6-digit OTP',
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: auth.loading ? null : _verify,
                child: Text(auth.loading ? 'Verifying...' : 'Verify & Login'),
              ),
              if (auth.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(auth.error!, style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
