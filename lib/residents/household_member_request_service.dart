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

  Future<List<HouseholdMemberRequest>> getMyRequests() async {
    try {
      final response =
          await _apiClient.dio.get('/household-member-requests/my');
      final data = response.data;
      if (data is List) {
        return data
            .map((item) => HouseholdMemberRequest.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ))
            .toList();
      }
      return const [];
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

  Future<HouseholdMemberRequest> cancelRequest(String requestId) async {
    try {
      final response =
          await _apiClient.dio.patch('/household-member-requests/$requestId/cancel');
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
      throw Exception('Không thể hủy yêu cầu. Vui lòng thử lại.');
    }
  }

  Future<HouseholdMemberRequest> resendRequest({
    required String requestId,
    String? residentFullName,
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
      if (residentFullName != null && residentFullName.isNotEmpty) 'residentFullName': residentFullName,
      if (residentPhone != null && residentPhone.isNotEmpty) 'residentPhone': residentPhone,
      if (residentEmail != null && residentEmail.isNotEmpty) 'residentEmail': residentEmail,
      if (residentNationalId != null && residentNationalId.isNotEmpty) 'residentNationalId': residentNationalId,
      if (residentDob != null) 'residentDob': formatter.format(residentDob),
      if (relation != null && relation.isNotEmpty) 'relation': relation,
      if (proofOfRelationImageUrl != null && proofOfRelationImageUrl.isNotEmpty) 'proofOfRelationImageUrl': proofOfRelationImageUrl,
      if (note != null && note.isNotEmpty) 'note': note,
    };

    try {
      final response = await _apiClient.dio.post(
        '/household-member-requests/$requestId/resend',
        data: payload.isEmpty ? null : payload,
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
      throw Exception('Không thể gửi lại yêu cầu. Vui lòng thử lại.');
    }
  }
}

