import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final addressRepositoryProvider = Provider<AddressRepository>((ref) {
  return AddressRepository(ref.watch(dioProvider));
});

class AddressRepository {
  AddressRepository(this._dio);
  final Dio _dio;

  Future<List<Map<String, dynamic>>> fetchAddresses() async {
    final res = await _dio.get('/addresses');
    return ((res.data['data'] as List<dynamic>?) ?? [])
        .cast<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<void> createAddress({
    required String label,
    required String line1,
    required String city,
    required String state,
    required String pincode,
    required bool isDefault,
  }) async {
    await _dio.post('/addresses', data: {
      'label': label,
      'line1': line1,
      'city': city,
      'state': state,
      'pincode': pincode,
      'is_default': isDefault,
    });
  }

  Future<void> updateAddress({
    required int id,
    String? label,
    required String line1,
    required String city,
    required String state,
    required String pincode,
    required bool isDefault,
  }) async {
    await _dio.put('/addresses/$id', data: {
      'label': label ?? 'Home',
      'line1': line1,
      'city': city,
      'state': state,
      'pincode': pincode,
      'is_default': isDefault,
    });
  }

  Future<void> deleteAddress(int id) async {
    await _dio.delete('/addresses/$id');
  }

  Future<void> setDefaultAddress(int id) async {
    final addresses = await fetchAddresses();
    for (final a in addresses) {
      final currentId =
          (a['id'] as num?)?.toInt() ?? int.tryParse('${a['id']}');
      if (currentId == null) continue;
      final currentDefault = a['is_default'] == true;
      final nextDefault = currentId == id;
      if (currentDefault != nextDefault) {
        await _dio
            .put('/addresses/$currentId', data: {'is_default': nextDefault});
      }
    }
  }
}
