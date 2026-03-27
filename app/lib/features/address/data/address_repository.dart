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
    required int sectorId,
    int? buildingId,
    required bool isDefault,
  }) async {
    await _dio.post('/addresses', data: {
      'label': label,
      'line1': line1,
      'city': city,
      'state': state,
      'pincode': pincode,
      'sector_id': sectorId,
      'building_id': buildingId,
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
    required int sectorId,
    int? buildingId,
    required bool isDefault,
  }) async {
    await _dio.put('/addresses/$id', data: {
      'label': label ?? 'Home',
      'line1': line1,
      'city': city,
      'state': state,
      'pincode': pincode,
      'sector_id': sectorId,
      'building_id': buildingId,
      'is_default': isDefault,
    });
  }

  Future<List<Map<String, dynamic>>> fetchSectors() async {
    final res = await _dio.get('/catalog/sectors');
    return ((res.data['data'] as List<dynamic>?) ?? [])
        .cast<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchBuildings(
      {required int sectorId}) async {
    final res = await _dio
        .get('/catalog/buildings', queryParameters: {'sector_id': sectorId});
    return ((res.data['data'] as List<dynamic>?) ?? [])
        .cast<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<Map<String, dynamic>> fetchServiceability() async {
    final res = await _dio.get('/catalog/serviceability');
    final data = res.data['data'];
    if (data is Map) {
      return data.cast<String, dynamic>();
    }
    return const {
      'city': 'Mohali',
      'state': 'Punjab',
      'cities': ['Mohali'],
      'pincodes': <String>[],
    };
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
