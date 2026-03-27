import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/device_identity.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/providers/auth_provider.dart';
import 'otp_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  String? _deviceId;
  bool _resolvingDevice = true;

  @override
  void initState() {
    super.initState();
    _initDevice();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _initDevice() async {
    try {
      final id = await DeviceIdentity.getOrCreate();
      if (!mounted) return;
      setState(() {
        _deviceId = id;
        _resolvingDevice = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _resolvingDevice = false);
    }
  }

  Future<void> _onContinue() async {
    final phone = _phoneCtrl.text.trim();
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) return;
    if (_deviceId == null || _deviceId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Device setup failed. Please restart app.'),
        ),
      );
      return;
    }
    final auth = context.read<AuthProvider>();
    final deviceId = _deviceId!;
    await auth.requestOtp(phone: phone, deviceId: deviceId);
    if (!mounted || auth.error != null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OtpScreen(phone: phone, deviceId: deviceId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 36),
                const Text(
                  'Fresh Mandi Delivery',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF127A45),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Delivery Executive Login',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text('Use your assigned delivery number to receive OTP'),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: Validators.indianPhone,
                      decoration: const InputDecoration(
                        counterText: '',
                        labelText: 'Mobile Number',
                        hintText: 'Enter 10-digit number',
                        prefixText: '+91 ',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: auth.loading || _resolvingDevice
                      ? null
                      : _onContinue,
                  child: Text(
                    _resolvingDevice
                        ? 'Preparing...'
                        : (auth.loading ? 'Sending OTP...' : 'Send OTP'),
                  ),
                ),
                if (auth.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      auth.error!,
                      style: const TextStyle(color: Colors.red),
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
