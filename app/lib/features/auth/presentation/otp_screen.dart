import 'dart:async';

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

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.phone});
  final String phone;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();
  final _focusNode = FocusNode();
  bool _loading = false;
  int _secondsLeft = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsLeft == 0) {
        t.cancel();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _focusNode.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      AppFeedback.error(context, 'Please enter a valid 6-digit OTP.');
      return;
    }

    setState(() => _loading = true);
    try {
      final result = await ref
          .read(authRepositoryProvider)
          .verifyOtp(widget.phone, _otpController.text.trim());
      if (!mounted) return;
      AppFeedback.success(context, 'Phone verified successfully.');
      context.go(result.hasAddress ? '/home' : '/address?onboarding=1');
    } on AppException catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, e.message);
    } catch (_) {
      if (!mounted) return;
      AppFeedback.error(context, 'OTP verification failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (_secondsLeft != 0) return;
    try {
      await ref.read(authRepositoryProvider).requestOtp(widget.phone);
      if (!mounted) return;
      AppFeedback.success(context, 'OTP resent successfully.');
      _startTimer();
    } on AppException catch (e) {
      if (!mounted) return;
      AppFeedback.error(context, e.message);
    } catch (_) {
      if (!mounted) return;
      AppFeedback.error(context, 'Unable to resend OTP.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final otp = _otpController.text;
    final width = MediaQuery.of(context).size.width;
    final compact = width < 380;
    final horizontalPadding = width < 340 ? 12.0 : (compact ? 16.0 : 22.0);

    return Scaffold(
      backgroundColor: DT.bg,
      body: GestureDetector(
        onTap: () => _focusNode.requestFocus(),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                horizontalPadding, 16, horizontalPadding, 18),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                children: [
                  SizedBox(height: compact ? 22 : 34),
                  Container(
                    width: compact ? 102 : 112,
                    height: compact ? 102 : 112,
                    decoration: BoxDecoration(
                      color: DT.primary,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x24000000),
                            blurRadius: 30,
                            offset: Offset(0, 18)),
                      ],
                    ),
                    child: Icon(Icons.shield_outlined,
                        size: compact ? 50 : 56, color: Colors.white),
                  ),
                  SizedBox(height: compact ? 26 : 34),
                  Text(
                    'Verify OTP',
                    style: TextStyle(
                        fontSize: compact ? 50 / 1.45 : 50 / 1.35,
                        fontWeight: FontWeight.w700,
                        color: DT.text),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter the 6-digit code sent to',
                    style: TextStyle(
                        fontSize: 14,
                        color: DT.sub,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '+91 ${widget.phone}',
                    style: const TextStyle(
                        fontSize: 14,
                        color: DT.primary,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 1,
                    width: 1,
                    child: TextFormField(
                      controller: _otpController,
                      focusNode: _focusNode,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: Validators.otp6,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const count = 6;
                      final spacing = constraints.maxWidth < 340 ? 2.0 : 4.0;
                      final totalSpacing = spacing * (count - 1);
                      final boxWidth =
                          ((constraints.maxWidth - totalSpacing) / count)
                              .clamp(34.0, 54.0);
                      final boxHeight = (boxWidth * 1.2).clamp(44.0, 68.0);
                      final fontSize = boxWidth * 0.42;

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(count, (i) {
                          final char = i < otp.length ? otp[i] : '';
                          return Padding(
                            padding: EdgeInsets.only(
                                right: i == count - 1 ? 0 : spacing),
                            child: Container(
                              width: boxWidth,
                              height: boxHeight,
                              decoration: BoxDecoration(
                                color: DT.field,
                                borderRadius: BorderRadius.circular(14),
                                border:
                                    Border.all(color: DT.border, width: 1.5),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                char,
                                style: TextStyle(
                                  fontSize: fontSize,
                                  fontWeight: FontWeight.w600,
                                  color: DT.text,
                                ),
                              ),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                  const SizedBox(height: 26),
                  GestureDetector(
                    onTap: _resend,
                    child: Text(
                      _secondsLeft == 0
                          ? 'Resend OTP'
                          : 'Resend OTP in ${_secondsLeft}s',
                      style: TextStyle(
                        fontSize: 14,
                        color: _secondsLeft == 0 ? DT.primary : DT.sub,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Didn\'t receive the code? Check your SMS or resend',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12,
                        color: DT.muted,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 30),
                  FreshPrimaryButton(
                    text: 'Verify OTP  ›',
                    loading: _loading,
                    height: 56,
                    onPressed: _verify,
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
