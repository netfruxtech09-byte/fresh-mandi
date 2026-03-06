import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

class FreshPageScaffold extends StatelessWidget {
  const FreshPageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.bottomNavigationBar,
    this.centerTitle = false,
    this.showDivider = true,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;
  final bool centerTitle;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DT.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: centerTitle,
        titleSpacing: centerTitle ? null : 0,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded, size: 24, color: DT.text),
              )
            : null,
        title: Text(
          title,
          style: const TextStyle(
            color: DT.text,
            fontSize: 26 / 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: actions,
        bottom: showDivider
            ? PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(height: 1, color: const Color(0xFFE6ECE8)),
              )
            : null,
      ),
      body: SafeArea(child: body),
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

class FreshCard extends StatelessWidget {
  const FreshCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.margin = EdgeInsets.zero,
    this.color = Colors.white,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color color;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: borderRadius,
        boxShadow: DT.softShadow,
      ),
      child: child,
    );
  }
}

class FreshPrimaryButton extends StatelessWidget {
  const FreshPrimaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.loading = false,
    this.height = 48,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool loading;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: DT.primary,
          disabledBackgroundColor: DT.primary.withValues(alpha: 0.6),
          minimumSize: Size.fromHeight(height),
          shape: RoundedRectangleBorder(borderRadius: DT.r16),
        ),
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(
                text,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
      ),
    );
  }
}

class FreshSectionTitle extends StatelessWidget {
  const FreshSectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          text,
          style: const TextStyle(
            color: DT.text,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

int gridCountForWidth(double width) {
  if (width >= 980) return 4;
  if (width >= 700) return 3;
  return 2;
}
