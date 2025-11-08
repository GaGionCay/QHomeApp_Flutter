import 'package:dio/dio.dart';

import '../auth/api_client.dart';
import '../models/account_creation_request.dart';
import '../models/resident_without_account.dart';

class ResidentAccountService {
  ResidentAccountService(this._apiClient);

  final ApiClient _apiClient;

  Future<List<ResidentWithoutAccount>> getResidentsWithoutAccount(
      String unitId) async {
    final response = await _apiClient.dio
        .get('/residents/units/$unitId/household/members/without-account');

    if (response.data is! List) {
      return [];
    }

    return (response.data as List)
        .map((item) => ResidentWithoutAccount.fromJson(
            Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<AccountCreationRequest> createAccountRequest({
    required String residentId,
    bool autoGenerate = true,
    String? username,
    String? password,
    List<String>? proofOfRelationImages,
  }) async {
    final payload = <String, dynamic>{
      'residentId': residentId,
      'autoGenerate': autoGenerate,
      'username': autoGenerate ? null : username,
      'password': autoGenerate ? null : password,
      'proofOfRelationImageUrls': proofOfRelationImages,
    }..removeWhere((key, value) => value == null);

    try {
      final response = await _apiClient.dio
          .post('/residents/create-account-request', data: payload);

      return AccountCreationRequest.fromJson(
          Map<String, dynamic>.from(response.data as Map));
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map &&
          data['message'] is String &&
          data['message'].toString().isNotEmpty) {
        throw Exception(data['message']);
      }
      rethrow;
    }
  }

  Future<List<AccountCreationRequest>> getMyAccountRequests() async {
    final response =
        await _apiClient.dio.get('/residents/my-account-requests');

    if (response.data is! List) {
      return [];
    }

    return (response.data as List)
        .map((item) => AccountCreationRequest.fromJson(
            Map<String, dynamic>.from(item as Map)))
        .toList();
  }
}

