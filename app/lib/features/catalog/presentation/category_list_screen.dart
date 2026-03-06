import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/fresh_ui.dart';

class CategoryListScreen extends StatelessWidget {
  const CategoryListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FreshPageScaffold(
      title: 'Categories',
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          FreshCard(
            child: ListTile(
              title: const Text('Fruit', style: TextStyle(fontWeight: FontWeight.w700)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/products?type=fruit'),
            ),
          ),
          const SizedBox(height: 10),
          FreshCard(
            child: ListTile(
              title: const Text('Vegetable', style: TextStyle(fontWeight: FontWeight.w700)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/products?type=vegetable'),
            ),
          ),
        ],
      ),
    );
  }
}
