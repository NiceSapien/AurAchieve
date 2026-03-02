import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DraftMemory {
  final String id;
  final String title;
  final String description;
  final String? tag;
  final String? tagColor;
  final String? mood;
  final int timestamp;
  final List<String> mediaPaths;
  final List<String> mediaTypes;

  DraftMemory({
    required this.id,
    required this.title,
    required this.description,
    this.tag,
    this.tagColor,
    this.mood,
    required this.timestamp,
    this.mediaPaths = const [],
    this.mediaTypes = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'tag': tag,
    'tagColor': tagColor,
    'mood': mood,
    'timestamp': timestamp,
    'mediaPaths': mediaPaths,
    'mediaTypes': mediaTypes,
  };

  factory DraftMemory.fromJson(Map<String, dynamic> json) => DraftMemory(
    id: json['id'],
    title: json['title'],
    description: json['description'],
    tag: json['tag'],
    tagColor: json['tagColor'],
    mood: json['mood'],
    timestamp: json['timestamp'],
    mediaPaths: (json['mediaPaths'] as List<dynamic>?)?.cast<String>() ?? [],
    mediaTypes: (json['mediaTypes'] as List<dynamic>?)?.cast<String>() ?? [],
  );
}

class DraftManager {
  static const String _storageKey = 'memory_drafts_list';
  static const Duration _retention = Duration(days: 14);

  static Future<List<DraftMemory>> getDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> list = prefs.getStringList(_storageKey) ?? [];

    final drafts = list
        .map((e) {
          try {
            return DraftMemory.fromJson(jsonDecode(e));
          } catch (_) {
            return null;
          }
        })
        .whereType<DraftMemory>()
        .toList();

    
    final now = DateTime.now();
    final validDrafts = drafts.where((d) {
      final date = DateTime.fromMillisecondsSinceEpoch(d.timestamp);
      return now.difference(date) <= _retention;
    }).toList();

    
    if (validDrafts.length < drafts.length) {
      await saveAllDrafts(validDrafts);
    }

    debugPrint('DraftManager: Loaded ${validDrafts.length} drafts'); 
    return validDrafts..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  static Future<void> saveDraft(DraftMemory draft) async {
    final drafts = await getDrafts();
    final index = drafts.indexWhere((d) => d.id == draft.id);

    if (index >= 0) {
      drafts[index] = draft;
    } else {
      drafts.add(draft);
    }

    await saveAllDrafts(drafts);
    debugPrint(
      'DraftManager: Saved draft ${draft.id} (${draft.title})',
    ); 
  }

  static Future<void> deleteDraft(String id) async {
    final drafts = await getDrafts();
    drafts.removeWhere((d) => d.id == id);
    await saveAllDrafts(drafts);
  }

  static Future<void> saveAllDrafts(List<DraftMemory> drafts) async {
    final prefs = await SharedPreferences.getInstance();
    final list = drafts.map((d) => jsonEncode(d.toJson())).toList();
    await prefs.setStringList(_storageKey, list);
  }
}
