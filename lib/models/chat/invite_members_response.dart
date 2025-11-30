import 'invitation.dart';

class InviteMembersResponse {
  final List<GroupInvitationResponse> successfulInvitations;
  final List<String> invalidPhones;
  final List<String> skippedPhones;

  InviteMembersResponse({
    required this.successfulInvitations,
    required this.invalidPhones,
    required this.skippedPhones,
  });

  factory InviteMembersResponse.fromJson(Map<String, dynamic> json) {
    return InviteMembersResponse(
      successfulInvitations: (json['successfulInvitations'] as List<dynamic>?)
              ?.map((e) => GroupInvitationResponse.fromJson(e))
              .toList() ??
          [],
      invalidPhones: (json['invalidPhones'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      skippedPhones: (json['skippedPhones'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

