import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:appwrite/appwrite.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';

class ApiService {
  final String _baseUrl =
      'https://redesigned-robot-j9p7vgg64gp2r75-4000.app.github.dev';
  final Account account;
  final _storage = const FlutterSecureStorage();

  ApiService({required this.account});

  Future<String?> _getJwtToken() async {
    return await _storage.read(key: 'jwt_token');
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await _getJwtToken();
    if (token == null) {
      print('JWT token not found for API request.');
      throw Exception('Authentication token not found.');
    }
    return {
      'Content-Type': 'application/json; charset=UTF-8',
      'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> getUserProfile() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$_baseUrl/api/user/profile'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      print(
        'Failed to load user profile: ${response.statusCode} ${response.body}',
      );
      throw Exception('Failed to load user profile: ${response.body}');
    }
  }

  Future<List<dynamic>> getTasks() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$_baseUrl/api/tasks'),
      headers: headers,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load tasks: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> createTask({
    required String name,
    String intensity = 'easy',
    String type = 'good',
    String taskCategory = 'normal',
    int? durationMinutes,
    bool isImageVerifiable = false,
  }) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$_baseUrl/api/tasks'),
      headers: headers,
      body: jsonEncode({
        'name': name,
        'intensity': intensity,
        'type': type,
        'taskCategory': taskCategory,
        if (durationMinutes != null) 'durationMinutes': durationMinutes,
        'isImageVerifiable': isImageVerifiable,
      }),
    );
    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to create task: ${response.body}');
    }
  }

  Future<void> deleteTask(String taskId) async {
    final headers = await _getHeaders();
    final response = await http.delete(
      Uri.parse('$_baseUrl/api/tasks/$taskId'),
      headers: headers,
    );
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Failed to delete task: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> completeNormalNonVerifiableTask(
    String taskId,
  ) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$_baseUrl/api/tasks/$taskId/complete-normal-non-verifiable'),
      headers: headers,
      body: jsonEncode({'verificationType': 'honor'}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(
        'Failed to complete normal non-verifiable task: ${response.body}',
      );
    }
  }

  Future<Map<String, dynamic>> completeNormalImageVerifiableTask(
    String taskId,
    String imageBase64,
  ) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$_baseUrl/api/tasks/$taskId/complete'),
      headers: headers,
      body: jsonEncode({
        'verificationType': 'image',
        'imageBase64': imageBase64,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(
        'Failed to complete normal image verifiable task: ${response.body}',
      );
    }
  }

  Future<Map<String, dynamic>> completeBadTask(String taskId) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$_baseUrl/api/tasks/$taskId/complete-bad'),
      headers: headers,
      body: jsonEncode({'verificationType': 'bad_task_completion'}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to complete bad task: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> completeTimedTask(
    String taskId, {
    int? durationSpentMinutes,
  }) async {
    final headers = await _getHeaders();

    final body = <String, dynamic>{'verificationType': 'timed_completion'};
    if (durationSpentMinutes != null) {
      body['durationSpentMinutes'] = durationSpentMinutes;
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/api/tasks/$taskId/complete-timed'),
      headers: headers,
      body: jsonEncode(body),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to complete timed task: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> markTaskAsBad(String taskId) async {
    final headers = await _getHeaders();
    final response = await http.put(
      Uri.parse('$_baseUrl/api/tasks/$taskId/mark-bad'),
      headers: headers,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to mark task as bad: ${response.body}');
    }
  }

  Future<Map<String, dynamic>?> getSocialBlockerData() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$_baseUrl/api/social-blocker/get'),
      headers: headers,
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic> && data.isNotEmpty) {
        return data;
      }
      return {};
    } else if (response.statusCode == 404) {
      return null;
    } else {
      throw Exception('Failed to get social blocker data: ${response.body}');
    }
  }

  Future<void> setupSocialBlocker({
    required int socialEndDays,
    required String socialPassword,
  }) async {
    final headers = await _getHeaders();
    final user = await account.get();
    final response = await http.post(
      Uri.parse('$_baseUrl/api/social-blocker'),
      headers: headers,
      body: jsonEncode({
        'userId': user.$id,
        'socialEnd': socialEndDays,
        'socialPassword': socialPassword,
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to set up social blocker: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> completeSocialBlocker() async {
    final headers = await _getHeaders();
    final user = await account.get();
    final response = await http.post(
      Uri.parse('$_baseUrl/api/social-blocker/end'),
      headers: headers,
      body: jsonEncode({
        'hasEnded': true,
        'userId': user.$id,
        'email': user.email,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to complete social blocker: ${response.body}');
    }
  }

  Future<Map<String, dynamic>?> getStudyPlan() async {
    final headers = await _getHeaders();
    final clientDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final response = await http.get(
      Uri.parse('$_baseUrl/api/study-plan?clientDate=$clientDate'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      // Handle cases where the server returns 200 but with an empty body
      if (response.body.isEmpty ||
          response.body == "null" ||
          response.body == "{}") {
        return null;
      }
      return jsonDecode(response.body);
    } else if (response.statusCode == 404) {
      // Handle explicit "Not Found"
      return null;
    } else {
      // For other errors (like 500), check if the body implies "not found"
      // before throwing an exception, making the client more resilient.
      final body = response.body.toLowerCase();
      if (body.contains('not found') || body.contains('no study plan')) {
        return null;
      }
      // Otherwise, it's a real error we should report.
      throw Exception('Failed to get study plan: ${response.body}');
    }
  }

  Future<List<dynamic>> generateTimetablePreview({
    required Map<String, List<Map<String, String>>> chapters,
    required DateTime deadline,
  }) async {
    final headers = await _getHeaders();
    final clientDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final body = {
      'chapters': chapters,
      'deadline': DateFormat('yyyy-MM-dd').format(deadline),
      'clientDate': clientDate,
    };

    final response = await http.post(
      Uri.parse('$_baseUrl/api/timetable'),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to generate timetable preview: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> saveStudyPlan({
    required List<Map<String, dynamic>> subjects,
    required Map<String, List<Map<String, String>>> chapters,
    required DateTime deadline,
    required List<Map<String, dynamic>> timetable,
  }) async {
    final headers = await _getHeaders();

    final body = {
      'subjects': subjects,
      'chapters': chapters,
      'deadline': DateFormat('yyyy-MM-dd').format(deadline),
      'timetable': timetable,
    };

    final response = await http.post(
      Uri.parse('$_baseUrl/api/study-plan'),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to save study plan: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> completeStudyPlanTask(
    String taskId,
    String dateOfTask,
  ) async {
    final headers = await _getHeaders();
    final clientDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final response = await http.post(
      Uri.parse('$_baseUrl/api/study-plan/tasks/$taskId/complete'),
      headers: headers,
      body: jsonEncode({'clientDate': clientDate, 'dateOfTask': dateOfTask}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to complete task: ${response.body}');
    }
  }

  Future<void> deleteStudyPlan() async {
    final headers = await _getHeaders();
    final response = await http.delete(
      Uri.parse('$_baseUrl/api/study-plan'),
      headers: headers,
    );
    if (response.statusCode != 204) {
      throw Exception('Failed to delete study plan: ${response.body}');
    }
  }
}
