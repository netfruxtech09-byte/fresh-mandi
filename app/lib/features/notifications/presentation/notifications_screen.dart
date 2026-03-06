import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/design_tokens.dart';
import '../../../shared/widgets/fresh_ui.dart';
import '../data/notifications_repository.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  late Future<List<Map<String, dynamic>>> _notificationsFuture;

  @override
  void initState() {
    super.initState();
    _notificationsFuture = _load();
  }

  Future<List<Map<String, dynamic>>> _load() => ref.read(notificationsRepositoryProvider).fetchNotifications();

  Future<void> _retry() async {
    final next = _load();
    setState(() => _notificationsFuture = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return FreshPageScaffold(
      title: 'Notifications',
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _notificationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Unable to load notifications'),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: _retry, child: const Text('Retry')),
                ],
              ),
            );
          }

          final notifications = snapshot.data ?? const <Map<String, dynamic>>[];
          if (notifications.isEmpty) {
            return RefreshIndicator(
              onRefresh: _retry,
              child: ListView(
                children: const [
                  SizedBox(height: 140),
                  Center(child: Text('No notifications yet.')),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _retry,
            child: ListView.separated(
              padding: const EdgeInsets.all(14),
              itemBuilder: (_, i) {
                final n = notifications[i];
                return FreshCard(
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.notifications_active_outlined, color: DT.primaryDark),
                    title: Text('${n['title']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                    subtitle: Text('${n['body']}', style: const TextStyle(fontSize: 11.5, color: DT.sub)),
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemCount: notifications.length,
            ),
          );
        },
      ),
    );
  }
}
