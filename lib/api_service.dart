import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:appwrite/appwrite.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';

dynamic _parseJson(String jsonString) {
  return jsonDecode(jsonString);
}

class ApiService {
  final String _baseUrl =
      'https://ubiquitous-waddle-557rj9965pwh7q7g-3000.app.github.dev';
  final Account account;
  final _storage = const FlutterSecureStorage();

  ApiService({required this.account});

  Future<String?> getJwtToken({bool forceRefresh = false}) async {
    return await _storage.read(key: 'jwt_token');
  }

  Future<http.Response> _authedGet(String url, {int retryCount = 0}) async {
    String? token = await getJwtToken();
    final headers = {
      'Authorization': token != null ? 'Bearer $token' : '',
      'Content-Type': 'application/json',
    };
    final resp = await http.get(Uri.parse(url), headers: headers);

    // If JWT expired, try refreshing once
    if (resp.statusCode == 401 && retryCount == 0) {
      token = await getJwtToken(forceRefresh: true);
      final newHeaders = {
        'Authorization': token != null ? 'Bearer $token' : '',
        'Content-Type': 'application/json',
      };
      return await http.get(Uri.parse(url), headers: newHeaders);
    }
    return resp;
  }

  List<dynamic> _asList(dynamic v) {
    if (v is List) return v;
    if (v is Map) {
      final inner = v['data'] ?? v['items'] ?? v['documents'] ?? v['list'];
      if (inner is List) return inner;
      if (inner is String) {
        try {
          final decoded = jsonDecode(inner);
          if (decoded is List) return decoded;
        } catch (_) {}
      }
    }
    if (v is String) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is List) return decoded;
        if (decoded is Map) {
          final inner =
              decoded['data'] ??
              decoded['items'] ??
              decoded['documents'] ??
              decoded['list'];
          if (inner is List) return inner;
        }
      } catch (_) {}
    }
    return const [];
  }

  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map) {
      final inner = v['data'];
      if (inner is Map) return Map<String, dynamic>.from(inner);
      return Map<String, dynamic>.from(v);
    }
    if (v is String && v.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return null;
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
      return (await compute(_parseJson, response.body)) as List<dynamic>;
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
      return (await compute(_parseJson, response.body)) as Map<String, dynamic>;
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
      return (await compute(_parseJson, response.body)) as Map<String, dynamic>;
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
      return (await compute(_parseJson, response.body)) as Map<String, dynamic>;
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
      return (await compute(_parseJson, response.body)) as Map<String, dynamic>;
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
      return (await compute(_parseJson, response.body)) as Map<String, dynamic>;
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
      return (await compute(_parseJson, response.body)) as Map<String, dynamic>;
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
      final data = await compute(_parseJson, response.body);
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
      return (await compute(_parseJson, response.body)) as Map<String, dynamic>;
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
      if (response.body.isEmpty ||
          response.body == "null" ||
          response.body == "{}") {
        return null;
      }
      return (await compute(_parseJson, response.body)) as Map<String, dynamic>;
    } else if (response.statusCode == 404) {
      return null;
    } else {
      final body = response.body.toLowerCase();
      if (body.contains('not found') || body.contains('no study plan')) {
        return null;
      }
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
      Uri.parse('$_baseUrl/api/study-plan/generate'),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return (await compute(_parseJson, response.body)) as List<dynamic>;
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
      return (await compute(_parseJson, response.body)) as Map<String, dynamic>;
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
      return (await compute(_parseJson, response.body)) as Map<String, dynamic>;
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

  Future<Map<String, dynamic>> createHabit({
    required String habitName,
    required String habitGoal,
    required String habitLocation,
    DateTime? createdAt,
    List<String>? completedDays,
  }) async {
    final headers = await _getHeaders();
    final cdJson = jsonEncode(completedDays ?? <String>[]);
    final response = await http.post(
      Uri.parse('$_baseUrl/api/habit'),
      headers: headers,
      body: jsonEncode({
        'habitName': habitName,
        'habitGoal': habitGoal,
        'habitLocation': habitLocation,
        'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
        'completedDays': cdJson,
      }),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return (await compute(_parseJson, response.body)) as Map<String, dynamic>;
    }
    throw Exception('Failed to add habit: ${response.body}');
  }

  Future<List<dynamic>> getHabits() async {
    final headers = await _getHeaders();
    final res = await http.get(
      Uri.parse('$_baseUrl/api/habit'),
      headers: headers,
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to load habits: ${res.body}');
    }
    final data = await compute(_parseJson, res.body);
    List habits;
    if (data is List) {
      habits = data;
    } else if (data is Map) {
      habits =
          (data['habits'] ??
                  data['documents'] ??
                  data['items'] ??
                  data['data'] ??
                  [])
              as List;
    } else {
      habits = [];
    }
    for (final h in habits) {
      if (h is Map && h['completedDays'] is String) {
        final s = h['completedDays'] as String;
        if (s.trim().isEmpty) {
          h['completedDays'] = <String>[];
        } else {
          try {
            final parsed = jsonDecode(s);
            if (parsed is List) {
              h['completedDays'] = List<String>.from(
                parsed.map((e) => e.toString()),
              );
              continue;
            }
          } catch (_) {}
          h['completedDays'] = s
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      }
    }
    return habits;
  }

  Future<List<String>> incrementHabitCompletedTimes(
    String habitId, {
    required List<String> completedDays,
  }) async {
    final headers = await _getHeaders();
    final cdJson = jsonEncode(completedDays);
    final response = await http.put(
      Uri.parse('$_baseUrl/api/habit'),
      headers: headers,
      body: jsonEncode({
        'habitId': habitId,
        'completedDays': cdJson,
        'incrementCompletedTimes': 1,
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to update habit: ${response.body}');
    }
    final data = await compute(_parseJson, response.body);
    if (data is Map) {
      final raw = data['completedDays'];
      if (raw is String && raw.isNotEmpty) {
        try {
          final parsed = jsonDecode(raw);
          if (parsed is List) {
            return List<String>.from(parsed.map((e) => e.toString()));
          }
        } catch (_) {}

        return raw
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } else if (raw is List) {
        return List<String>.from(raw.map((e) => e.toString()));
      }
    }
    return completedDays;
  }

  Future<void> saveHabitReminderLocal(
    String habitId,
    List<String> reminders,
  ) async {
    final existing = await _storage.read(key: 'habit_reminders');
    Map<String, dynamic> map = {};
    if (existing != null && existing.isNotEmpty) {
      try {
        map = jsonDecode(existing);
      } catch (_) {
        map = {};
      }
    }
    map[habitId] = reminders;
    await _storage.write(key: 'habit_reminders', value: jsonEncode(map));
  }

  Future<List<String>?> getHabitReminderLocal(String habitId) async {
    final existing = await _storage.read(key: 'habit_reminders');
    if (existing == null) return null;
    try {
      final map = jsonDecode(existing);
      final v = map[habitId];
      if (v is List) return List<String>.from(v.map((e) => e.toString()));
    } catch (_) {}
    return null;
  }

  Future<void> deleteHabit(String habitId) async {
    final headers = await _getHeaders();
    final res = await http.delete(
      Uri.parse('$_baseUrl/api/habit'),
      headers: headers,
      body: jsonEncode({'habitId': habitId}),
    );
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('Failed to delete habit: ${res.body}');
    }
  }

  Future<Map<String, dynamic>> getTasksAndHabits() async {
    final resp = await _authedGet('$_baseUrl/api/tasks');
    print('Server response for /api/tasks: ${resp.body}'); // Debug log
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      if (resp.statusCode == 404) {
        return {'tasks': [], 'habits': []};
      }
      throw Exception('Failed to fetch tasks: ${resp.statusCode} ${resp.body}');
    }
    final root = await compute(_parseJson, resp.body);

    // FIX: Directly extract lists, fallback to [] if missing
    final tasks = (root['tasks'] as List?) ?? [];
    final habits = (root['habits'] as List?) ?? [];

    return {
      'tasks': tasks,
      'habits': habits,
    };
  }

  Future<Map<String, String>> _getHeaders({bool forceRefresh = false}) async {
    final token = await getJwtToken(forceRefresh: forceRefresh);
    return {
      'Authorization': token != null ? 'Bearer $token' : '',
      'Content-Type': 'application/json',
    };
  }

  List<dynamic> _extractList(dynamic value) {
    if (value == null) return [];
    if (value is List) return value;
    if (value is Map) {
      final inner =
          value['data'] ??
          value['items'] ??
          value['documents'] ??
          value['list'];
      if (inner is List) return inner;
      if (inner is String) {
        try {
          final decoded = jsonDecode(inner);
          if (decoded is List) return decoded;
        } catch (_) {}
      }
    }
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) return decoded;
        if (decoded is Map) {
          final inner =
              decoded['data'] ??
              decoded['items'] ??
              decoded['documents'] ??
              decoded['list'];
          if (inner is List) return inner;
        }
      } catch (_) {}
    }
    return [];
  }

  Future<void> createProfile(Map<String, dynamic> profileData) async {
    final headers = await _getHeaders();
    final resp = await http.get(
      Uri.parse('$_baseUrl/api/user/profile'),
      headers: headers,
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
        'Failed to create profile: ${resp.statusCode} ${resp.body}',
      );
    }
  }
}
