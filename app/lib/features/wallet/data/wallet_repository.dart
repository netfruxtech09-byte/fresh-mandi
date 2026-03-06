import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  return WalletRepository(ref.watch(dioProvider));
});

class WalletRepository {
  WalletRepository(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> fetchWallet() async {
    final res = await _dio.get('/wallet');
    return (res.data['data'] as Map).cast<String, dynamic>();
  }
}
