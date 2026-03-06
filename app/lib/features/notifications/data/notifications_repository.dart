import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  return NotificationsRepository(ref.watch(dioProvider));
});

class NotificationsRepository {
  NotificationsRepository(this._dio);
  final Dio _dio;

  Future<List<Map<String, dynamic>>> fetchNotifications() async {
    final res = await _dio.get('/notifications');
    return ((res.data['data'] as List<dynamic>?) ?? []).cast<Map<String, dynamic>>();
  }
}
