import 'package:dio/dio.dart';
import 'package:intl/intl.dart';

import '../auth/api_client.dart';
import '../models/household.dart';
import '../models/household_member_request.dart';

class HouseholdMemberRequestService {
  HouseholdMemberRequestService(this._apiClient);

  final ApiClient _apiClient;

  Future<Household?> getCurrentHousehold(String unitId) async {
    try {
      final response =
          await _apiClient.dio.get('/households/units/$unitId/current');
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return Household.fromJson(data);
      }
      if (data is Map) {
        return Household.fromJson(Map<String, dynamic>.from(data));
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Future<HouseholdMemberRequest> createRequest({
    required String householdId,
    required String residentFullName,
    String? residentPhone,
    String? residentEmail,
    String? residentNationalId,
    DateTime? residentDob,
    String? relation,
    String? proofOfRelationImageUrl,
    String? note,
  }) async {
    final formatter = DateFormat('yyyy-MM-dd');

    final payload = <String, dynamic>{
      'householdId': householdId,
      'residentFullName': residentFullName,
      'residentPhone': residentPhone,
      'residentEmail': residentEmail,
      'residentNationalId': residentNationalId,
      'residentDob': residentDob != null ? formatter.format(residentDob) : null,
      'relation': relation,
      'proofOfRelationImageUrl': proofOfRelationImageUrl,
      'note': note,
    }..removeWhere((key, value) =>
        value == null || (value is String && value.trim().isEmpty));

    try {
      final response = await _apiClient.dio.post(
        '/household-member-requests',
        data: payload,
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return HouseholdMemberRequest.fromJson(data);
      }
      if (data is Map) {
        return HouseholdMemberRequest.fromJson(Map<String, dynamic>.from(data));
      }
      throw Exception('Không thể đọc dữ liệu phản hồi.');
    } on DioException catch (e) {
      final responseData = e.response?.data;
      if (responseData is Map &&
          responseData['message'] is String &&
          (responseData['message'] as String).isNotEmpty) {
        throw Exception(responseData['message']);
      }
      rethrow;
    }
  }
}
