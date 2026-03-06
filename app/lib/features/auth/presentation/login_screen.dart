import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/utils/app_feedback.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/fresh_ui.dart';
import '../data/auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      AppFeedback.error(context, 'Please enter a valid Indian mobile number.');
      return;
    }

    setState(() => _loading = true);
    final phone = _phoneController.text.trim();

    try {
      await ref.read(authRepositoryProvider).requestOtp(phone);
      if (!mounted) return;
      AppFeedback.success(context, 'OTP sent successfully to +91 $phone');
      context.push('/otp?phone=$phone');
    } on AppException catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, e.message);
    } catch (_) {
      if (!mounted) return;
      AppFeedback.error(context, 'Unable to send OTP right now. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final compact = width < 380;

    return Scaffold(
      backgroundColor: DT.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: compact ? 22 : 34),
                Center(
                  child: Container(
                    width: compact ? 102 : 112,
                    height: compact ? 102 : 112,
                    decoration: BoxDecoration(
                      color: DT.primary,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: const [
                        BoxShadow(color: Color(0x24000000), blurRadius: 30, offset: Offset(0, 18)),
                      ],
                    ),
                    child: Icon(Icons.smartphone_outlined, size: compact ? 50 : 56, color: Colors.white),
                  ),
                ),
                SizedBox(height: compact ? 26 : 34),
                Center(
                  child: Text(
                    'Welcome!',
                    style: TextStyle(fontSize: compact ? 50 / 1.45 : 50 / 1.35, fontWeight: FontWeight.w700, color: DT.text),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Enter your mobile number to get started',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: DT.sub, fontWeight: FontWeight.w500),
                  ),
                ),
                SizedBox(height: compact ? 34 : 42),
                const Text(
                  'Mobile Number',
                  style: TextStyle(fontSize: 15, color: Color(0xFF374151), fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  maxLength: 10,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: Validators.indianPhone,
                  onFieldSubmitted: (_) => _requestOtp(),
                  style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280), fontWeight: FontWeight.w500),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: DT.field,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                    prefixText: '+91  ',
                    prefixStyle: const TextStyle(fontSize: 14, color: Color(0xFF6B7280), fontWeight: FontWeight.w500),
                    hintText: 'Enter 10 digit mobile number',
                    hintStyle: const TextStyle(fontSize: 14, color: Color(0xFF8B93A6), fontWeight: FontWeight.w400),
                  ),
                ),
                const SizedBox(height: 16),
                FreshPrimaryButton(
                  text: 'Send OTP  ›',
                  loading: _loading,
                  height: 56,
                  onPressed: _requestOtp,
                ),
                SizedBox(height: compact ? 20 : 26),
                const Center(
                  child: Text(
                    'By continuing, you agree to our Terms & Conditions',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Color(0xFF6B7280), fontWeight: FontWeight.w500),
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
