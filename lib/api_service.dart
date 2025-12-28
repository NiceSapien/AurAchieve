import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:appwrite/appwrite.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

dynamic _parseJson(String jsonString) {
  return jsonDecode(jsonString);
}

class AppConfig {
  static const String defaultBaseUrl =
      'https://auraascend-fgf4aqf5gubgacb3.centralindia-01.azurewebsites.net';
  static String baseUrl = defaultBaseUrl;

  static const String defaultAppwriteEndpoint =
      'https://fra.cloud.appwrite.io/v1';
  static String appwriteEndpoint = defaultAppwriteEndpoint;

  static const String defaultAppwriteProjectId = '6800a2680008a268a6a3';
  static String appwriteProjectId = defaultAppwriteProjectId;

  static void setBaseUrl(String newUrl) {
    if (newUrl.isNotEmpty &&
        (newUrl.startsWith('http://') || newUrl.startsWith('https://'))) {
      baseUrl = newUrl.endsWith('/')
          ? newUrl.substring(0, newUrl.length - 1)
          : newUrl;
    }
  }

  static void setAppwriteConfig(String endpoint, String projectId) {
    if (endpoint.isNotEmpty) appwriteEndpoint = endpoint;
    if (projectId.isNotEmpty) appwriteProjectId = projectId;
  }

  static const String _prefKey = 'api_base_url';
  static const String _prefKeyAppwriteEndpoint = 'appwrite_endpoint';
  static const String _prefKeyAppwriteProject = 'appwrite_project_id';

  static void resetToDefault() {
    baseUrl = defaultBaseUrl;
    appwriteEndpoint = defaultAppwriteEndpoint;
    appwriteProjectId = defaultAppwriteProjectId;
  }

  static Future<void> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    if (saved != null && saved.isNotEmpty) {
      setBaseUrl(saved);
    } else {
      baseUrl = defaultBaseUrl;
    }

    final savedEndpoint = prefs.getString(_prefKeyAppwriteEndpoint);
    if (savedEndpoint != null && savedEndpoint.isNotEmpty) {
      appwriteEndpoint = savedEndpoint;
    } else {
      appwriteEndpoint = defaultAppwriteEndpoint;
    }

    final savedProject = prefs.getString(_prefKeyAppwriteProject);
    if (savedProject != null && savedProject.isNotEmpty) {
      appwriteProjectId = savedProject;
    } else {
      appwriteProjectId = defaultAppwriteProjectId;
    }
  }

  static Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, baseUrl);
    await prefs.setString(_prefKeyAppwriteEndpoint, appwriteEndpoint);
    await prefs.setString(_prefKeyAppwriteProject, appwriteProjectId);
  }
}

class ApiService {
  final Account account;
  final _storage = const FlutterSecureStorage();

  ApiService({required this.account});

  Future<String?> getJwtToken({bool forceRefresh = false}) async {
    if (forceRefresh) {
      try {
        final jwt = await account.createJWT();
        await _storage.write(key: 'jwt_token', value: jwt.jwt);
        return jwt.jwt;
      } catch (e) {
        print("Failed to refresh JWT: $e");
        await _storage.delete(key: 'jwt_token');
        return null;
      }
    }
    return await _storage.read(key: 'jwt_token');
  }

  Future<http.Response> _performRequest(
    String method,
    String endpoint, {
    Object? body,
    int retryCount = 0,
    String? overrideUrl,
  }) async {
    final url = overrideUrl != null
        ? Uri.parse(overrideUrl)
        : Uri.parse('${AppConfig.baseUrl}$endpoint');
    final headers = await _getHeaders();

    http.Response response;
    switch (method) {
      case 'GET':
        response = await http.get(url, headers: headers);
        break;
      case 'POST':
        response = await http.post(url, headers: headers, body: body);
        break;
      case 'PUT':
        response = await http.put(url, headers: headers, body: body);
        break;
      case 'DELETE':
        response = await http.delete(url, headers: headers, body: body);
        break;
      case 'PATCH':
        response = await http.patch(url, headers: headers, body: body);
        break;
      default:
        throw Exception('Unsupported method: $method');
    }

    if ((response.statusCode == 401 ||
            response.body.contains("Invalid or Expired token")) &&
        retryCount == 0) {
      await getJwtToken(forceRefresh: true);
      return _performRequest(
        method,
        endpoint,
        body: body,
        retryCount: retryCount + 1,
        overrideUrl: overrideUrl,
      );
    }

    return response;
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
    final response = await _performRequest('GET', '/api/user/profile');

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
    final response = await _performRequest('GET', '/api/tasks');
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
    final response = await _performRequest(
      'POST',
      '/api/tasks',
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
    final response = await _performRequest('DELETE', '/api/tasks/$taskId');
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Failed to delete task: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> completeNormalNonVerifiableTask(
    String taskId,
  ) async {
    final response = await _performRequest(
      'POST',
      '/api/tasks/$taskId/complete-normal-non-verifiable',
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
    final response = await _performRequest(
      'POST',
      '/api/tasks/$taskId/complete',
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
    final response = await _performRequest(
      'POST',
      '/api/tasks/$taskId/complete-bad',
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
    final body = <String, dynamic>{'verificationType': 'timed_completion'};
    if (durationSpentMinutes != null) {
      body['durationSpentMinutes'] = durationSpentMinutes;
    }

    final response = await _performRequest(
      'POST',
      '/api/tasks/$taskId/complete-timed',
      body: jsonEncode(body),
    );
    if (response.statusCode == 200) {
      return (await compute(_parseJson, response.body)) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to complete timed task: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> markTaskAsBad(String taskId) async {
    final response = await _performRequest(
      'PUT',
      '/api/tasks/$taskId/mark-bad',
    );
    if (response.statusCode == 200) {
      return (await compute(_parseJson, response.body)) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to mark task as bad: ${response.body}');
    }
  }

  Future<Map<String, dynamic>?> getSocialBlockerData() async {
    final response = await _performRequest('GET', '/api/social-blocker/get');
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
    final user = await account.get();
    final response = await _performRequest(
      'POST',
      '/api/social-blocker',
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
    final user = await account.get();
    final response = await _performRequest(
      'POST',
      '/api/social-blocker/end',
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

  Future<Map<String, dynamic>> giveUpSocialBlocker() async {
    final response = await _performRequest(
      'DELETE',
      '/api/social-blocker/giveup',
    );
    if (response.statusCode == 200) {
      return (await compute(_parseJson, response.body)) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to give up on social blocker: ${response.body}');
    }
  }

  Future<Map<String, dynamic>?> getStudyPlan() async {
    final clientDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final response = await _performRequest(
      'GET',
      '/api/study-plan?clientDate=$clientDate',
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
    final clientDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final body = {
      'chapters': chapters,
      'deadline': DateFormat('yyyy-MM-dd').format(deadline),
      'clientDate': clientDate,
    };

    final response = await _performRequest(
      'POST',
      '/api/study-plan/generate',
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
    final body = {
      'subjects': subjects,
      'chapters': chapters,
      'deadline': DateFormat('yyyy-MM-dd').format(deadline),
      'timetable': timetable,
    };

    final response = await _performRequest(
      'POST',
      '/api/study-plan',
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
    final clientDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final response = await _performRequest(
      'POST',
      '/api/study-plan/tasks/$taskId/complete',
      body: jsonEncode({'clientDate': clientDate, 'dateOfTask': dateOfTask}),
    );
    if (response.statusCode == 200) {
      return (await compute(_parseJson, response.body)) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to complete task: ${response.body}');
    }
  }

  Future<void> deleteStudyPlan() async {
    final response = await _performRequest('DELETE', '/api/study-plan');
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
    final cdJson = jsonEncode(completedDays ?? <String>[]);
    final response = await _performRequest(
      'POST',
      '/api/habit',
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
    final res = await _performRequest('GET', '/api/habit');
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

  Future<Map<String, dynamic>> incrementHabitCompletedTimes(
    String habitId, {
    required List<String> completedDays,
  }) async {
    final cdJson = jsonEncode(completedDays);
    final response = await _performRequest(
      'PUT',
      '/api/habit',
      body: jsonEncode({
        'habitId': habitId,
        'completedDays': cdJson,
        'incrementCompletedTimes': 1,
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to update habit: ${response.body}');
    }
    return (await compute(_parseJson, response.body)) as Map<String, dynamic>;
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
    final res = await _performRequest(
      'DELETE',
      '/api/habit',
      body: jsonEncode({'habitId': habitId}),
    );
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('Failed to delete habit: ${res.body}');
    }
  }

  Future<Map<String, dynamic>> editHabit({
    required String habitId,
    String? habitName,
    String? habitLocation,
    String? habitGoal,
    List<String>? completedDays,
  }) async {
    final body = <String, dynamic>{'habitId': habitId};
    if (habitName != null) body['habitName'] = habitName;
    if (habitLocation != null) body['habitLocation'] = habitLocation;
    if (habitGoal != null) body['habitGoal'] = habitGoal;
    if (completedDays != null) body['completedDays'] = completedDays;

    final response = await _performRequest(
      'PATCH',
      '/api/habit',
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return (await compute(_parseJson, response.body)) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to edit habit: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> editBadHabit({
    required String habitId,
    String? habitName,
    String? habitGoal,
    String? severity,
    List<String>? completedDays,
  }) async {
    final body = <String, dynamic>{'habitId': habitId};
    if (habitName != null) body['habitName'] = habitName;
    if (habitGoal != null) body['habitGoal'] = habitGoal;
    if (severity != null) body['severity'] = severity;
    if (completedDays != null) body['completedDays'] = completedDays;

    final response = await _performRequest(
      'PATCH',
      '/api/bad-habit',
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      return (await compute(_parseJson, response.body)) as Map<String, dynamic>;
    } else {
      throw Exception('Failed to edit bad habit: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> createBadHabit({
    required String habitName,
    required String severity,
    String? habitGoal,
    List<String>? completedDays,
  }) async {
    final payload = {
      'habitName': habitName,
      'severity': severity,
      'habitGoal': habitGoal,
      'completedDays': completedDays ?? <String>[],
    };
    print('DEBUG: createBadHabit payload: ${jsonEncode(payload)}');
    final response = await _performRequest(
      'POST',
      '/api/bad-habit',
      body: jsonEncode(payload),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return (await compute(_parseJson, response.body)) as Map<String, dynamic>;
    }
    throw Exception('Failed to add bad habit: ${response.body}');
  }

  Future<List<dynamic>> getBadHabits() async {
    final res = await _performRequest('GET', '/api/bad-habit');
    if (res.statusCode != 200) {
      throw Exception('Failed to load bad habits: ${res.body}');
    }
    final data = await compute(_parseJson, res.body);
    if (data is List) return data;
    if (data is Map) {
      return (data['data'] ?? data['items'] ?? []) as List;
    }
    return [];
  }

  Future<Map<String, dynamic>> incrementBadHabit(
    String habitId, {
    int incrementBy = 1,
    List<String>? completedDays,
  }) async {
    final payload = <String, dynamic>{
      'habitId': habitId,
      'incrementBy': incrementBy,
    };
    if (completedDays != null) {
      payload['completedDays'] = completedDays;
    }
    final response = await _performRequest(
      'PUT',
      '/api/bad-habit',
      body: jsonEncode(payload),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to update bad habit: ${response.body}');
    }
    return (await compute(_parseJson, response.body)) as Map<String, dynamic>;
  }

  Future<void> deleteBadHabit(String habitId) async {
    final res = await _performRequest(
      'DELETE',
      '/api/bad-habit',
      body: jsonEncode({'habitId': habitId}),
    );
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception('Failed to delete bad habit: ${res.body}');
    }
  }

  Future<Map<String, dynamic>> getTasksAndHabits() async {
    if (AppConfig.baseUrl != AppConfig.defaultBaseUrl) {
      final resp = await _performRequest('GET', '/api/tasks');
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception(
          'Failed to fetch tasks: ${resp.statusCode} ${resp.body}',
        );
      }
      final data = await compute(_parseJson, resp.body);

      if (data is Map<String, dynamic> &&
          (data.containsKey('tasks') ||
              data.containsKey('habits') ||
              data.containsKey('badHabits'))) {
        return {
          'tasks': (data['tasks'] as List?) ?? [],
          'habits': (data['habits'] as List?) ?? [],
          'badHabits': (data['badHabits'] as List?) ?? [],
          'studyPlan': data['studyPlan'],
          'userId': data['userId'],
          'name': data['name'],
          'email': data['email'],
          'aura': data['aura'],
          'validationCount': data['validationCount'],
          'lastValidationResetDate': data['lastValidationResetDate'],
          'quote': data['quote'],
        };
      }

      final tasks = data is List ? data : _extractList(data);
      return {
        'tasks': tasks,
        'habits': const [],
        'badHabits': const [],
        'studyPlan': null,
        'userId': null,
        'name': null,
        'email': null,
        'aura': null,
        'validationCount': null,
        'lastValidationResetDate': null,
        'quote': null,
      };
    }

    final resp = await _performRequest(
      'GET',
      '',
      overrideUrl: AppConfig.baseUrl + '/api/tasks',
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      if (resp.statusCode == 404) {
        return {
          'tasks': [],
          'habits': [],
          'badHabits': [],
          'studyPlan': null,
          'userId': null,
          'name': null,
          'email': null,
          'aura': null,
          'validationCount': null,
          'lastValidationResetDate': null,
          'quote': null,
        };
      }
      throw Exception('Failed to fetch tasks: ${resp.statusCode} ${resp.body}');
    }
    final root = await compute(_parseJson, resp.body);
    return {
      'tasks': (root['tasks'] as List?) ?? const [],
      'habits': (root['habits'] as List?) ?? const [],
      'badHabits': (root['badHabits'] as List?) ?? const [],
      'studyPlan': root['studyPlan'],
      'userId': root['userId'],
      'name': root['name'],
      'email': root['email'],
      'aura': root['aura'],
      'validationCount': root['validationCount'],
      'lastValidationResetDate': root['lastValidationResetDate'],
      'quote': root['quote'],
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

  Future<void> createProfile(String name, String email) async {
    final resp = await _performRequest(
      'POST',
      '/api/users',
      body: {'name': name, 'email': email},
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(
        'Failed to create profile: ${resp.statusCode} ${resp.body}',
      );
    }
  }
}
