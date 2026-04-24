import 'dart:convert';

import 'package:http/http.dart' as http;

class SosCallBackendService {
  SosCallBackendService({http.Client? client})
    : _client = client ?? http.Client();

  static const String _baseUrl = String.fromEnvironment(
    'SOS_BACKEND_BASE_URL',
    defaultValue: '',
  );

  final http.Client _client;

  bool get isConfigured => _baseUrl.trim().isNotEmpty;

  Uri _uri(String path, [Map<String, String>? queryParameters]) {
    final normalizedBase = _baseUrl.endsWith('/')
        ? _baseUrl.substring(0, _baseUrl.length - 1)
        : _baseUrl;
    return Uri.parse(
      '$normalizedBase$path',
    ).replace(queryParameters: queryParameters);
  }

  Future<SosCallStatusPayload> startCall({
    required String sessionId,
    required String userId,
    required String victimName,
    required String? victimPhone,
    required List<String> emergencyContacts,
    required double latitude,
    required double longitude,
  }) async {
    final response = await _client.post(
      _uri('/sos/$sessionId/start-call'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': sessionId,
        'userId': userId,
        'victimName': victimName,
        'victimPhone': victimPhone,
        'emergencyContacts': emergencyContacts,
        'location': {'lat': latitude, 'lng': longitude},
      }),
    );
    return _parseStatusResponse(response);
  }

  Future<SosCallStatusPayload?> getActiveCall({required String userId}) async {
    final response = await _client.get(_uri('/sos/active', {'userId': userId}));
    if (response.statusCode == 404) {
      return null;
    }
    return _parseStatusResponse(response);
  }

  Future<SosCallStatusPayload> getCallStatus({
    required String sessionId,
  }) async {
    final response = await _client.get(_uri('/sos/$sessionId/call-status'));
    return _parseStatusResponse(response);
  }

  Future<SosCallStatusPayload> markSafe({required String sessionId}) async {
    final response = await _client.post(_uri('/sos/$sessionId/safe'));
    return _parseStatusResponse(response);
  }

  Future<SosCallStatusPayload> endCall({required String sessionId}) async {
    final response = await _client.post(_uri('/sos/$sessionId/end-call'));
    return _parseStatusResponse(response);
  }

  Future<void> syncLocation({
    required String sessionId,
    required double latitude,
    required double longitude,
  }) async {
    final response = await _client.post(
      _uri('/sos/$sessionId/location'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'location': {'lat': latitude, 'lng': longitude},
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Location sync failed with status ${response.statusCode}: ${response.body}',
      );
    }
  }

  SosCallStatusPayload _parseStatusResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Voice backend request failed with status ${response.statusCode}: ${response.body}',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return SosCallStatusPayload.fromJson(data);
  }
}

class SosCallStatusPayload {
  const SosCallStatusPayload({
    required this.sessionId,
    required this.status,
    required this.statusText,
    required this.isCallActive,
    required this.isSafe,
    required this.canShowPostSafeActions,
    this.providerCallId,
    this.currentContact,
  });

  factory SosCallStatusPayload.fromJson(Map<String, dynamic> json) {
    return SosCallStatusPayload(
      sessionId: json['sessionId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'idle',
      statusText: json['statusText']?.toString() ?? 'Voice idle',
      isCallActive: json['isCallActive'] == true,
      isSafe: json['isSafe'] == true,
      canShowPostSafeActions: json['canShowPostSafeActions'] == true,
      providerCallId: json['providerCallId']?.toString(),
      currentContact: json['currentContact']?.toString(),
    );
  }

  final String sessionId;
  final String status;
  final String statusText;
  final bool isCallActive;
  final bool isSafe;
  final bool canShowPostSafeActions;
  final String? providerCallId;
  final String? currentContact;
}
