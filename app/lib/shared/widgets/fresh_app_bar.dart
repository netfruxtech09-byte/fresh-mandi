import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

class FreshAppBar extends StatelessWidget implements PreferredSizeWidget {
  const FreshAppBar({
    super.key,
    required this.title,
    this.showBack = true,
    this.onBack,
  });

  final String title;
  final bool showBack;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      leading: showBack
          ? IconButton(
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_rounded, color: DT.text),
            )
          : null,
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          color: DT.text,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: const Color(0xFFE6ECE8)),
      ),
    );
  }
}
