import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/app_feedback.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_text_form_field.dart';
import '../../../shared/widgets/fresh_ui.dart';
import '../../auth/data/auth_repository.dart';

class EditPhoneScreen extends ConsumerStatefulWidget {
  const EditPhoneScreen({super.key});

  @override
  ConsumerState<EditPhoneScreen> createState() => _EditPhoneScreenState();
}

class _EditPhoneScreenState extends ConsumerState<EditPhoneScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
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
      AppFeedback.success(context, 'OTP sent to +91 $phone');
      context.push('/otp?phone=$phone');
    } on AppException catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, e.message);
    } catch (_) {
      if (!mounted) return;
      AppFeedback.error(context, 'Could not send OTP. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FreshPageScaffold(
      title: 'Edit Phone',
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: Column(
            children: [
              FreshCard(
                borderRadius: BorderRadius.circular(12),
                child: AppTextFormField(
                  controller: _phoneController,
                  label: 'New phone number',
                  hint: '10-digit mobile number',
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: Validators.indianPhone,
                  onFieldSubmitted: (_) => _sendOtp(),
                ),
              ),
              const SizedBox(height: 12),
              FreshPrimaryButton(text: 'Send OTP', loading: _loading, onPressed: _sendOtp),
            ],
          ),
        ),
      ),
    );
  }
}
