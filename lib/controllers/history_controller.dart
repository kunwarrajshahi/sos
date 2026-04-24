import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryEntry {
  HistoryEntry({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    this.metadata = const {},
  });

  final String type;
  final String title;
  final String subtitle;
  final DateTime timestamp;
  final Map<String, dynamic> metadata;

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      type: json['type'] as String? ?? 'event',
      title: json['title'] as String? ?? 'Event',
      subtitle: json['subtitle'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      metadata: Map<String, dynamic>.from(json['metadata'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'title': title,
        'subtitle': subtitle,
        'timestamp': timestamp.toIso8601String(),
        'metadata': metadata,
      };
}

class HistoryController extends GetxController {
  static HistoryController instanceOrCreate() {
    if (Get.isRegistered<HistoryController>()) {
      return Get.find<HistoryController>();
    }
    return Get.put(HistoryController());
  }

  static const String _prefsKeyPrefix = 'safe_route_history_events';

  final RxList<HistoryEntry> entries = <HistoryEntry>[].obs;
  final RxString query = ''.obs;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  StreamSubscription<User?>? _authSubscription;

  @override
  void onInit() {
    super.onInit();
    loadHistory();
    _authSubscription = _auth.userChanges().listen((_) {
      loadHistory();
    });
  }

  @override
  void onClose() {
    _authSubscription?.cancel();
    super.onClose();
  }

  Future<void> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_resolvedPrefsKey()) ?? [];
    final parsed = raw
        .map(
          (item) =>
              HistoryEntry.fromJson(jsonDecode(item) as Map<String, dynamic>),
        )
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    entries.assignAll(parsed);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final capped = entries.take(50).toList();
    await prefs.setStringList(
      _resolvedPrefsKey(),
      capped.map((entry) => jsonEncode(entry.toJson())).toList(),
    );
  }

  Future<void> addEntry(HistoryEntry entry) async {
    entries.insert(0, entry);
    while (entries.length > 50) {
      entries.removeLast();
    }
    await _save();
  }

  Future<void> recordSos({
    required String status,
    String? locationLabel,
  }) async {
    await addEntry(
      HistoryEntry(
        type: 'sos',
        title: 'SOS $status',
        subtitle: locationLabel ?? 'Emergency alert recorded',
        timestamp: DateTime.now(),
      ),
    );
  }

  Future<void> recordUnsafeZone({
    String? reason,
    String? areaName,
    String? timeStart,
    String? timeEnd,
  }) async {
    final parts = <String>[
      if (reason != null && reason.trim().isNotEmpty) reason,
      if (timeStart != null && timeEnd != null)
        'Unsafe from $timeStart to $timeEnd',
    ];

    await addEntry(
      HistoryEntry(
        type: 'unsafe',
        title: areaName?.trim().isNotEmpty == true
            ? areaName!.trim()
            : 'Unsafe area reported',
        subtitle: parts.isEmpty ? 'Unsafe zone saved' : parts.join(' - '),
        timestamp: DateTime.now(),
        metadata: {
          'reason': reason,
          'areaName': areaName,
          'timeStart': timeStart,
          'timeEnd': timeEnd,
        },
      ),
    );
  }

  Future<void> recordRoute({
    required String destinationName,
    required String distanceLabel,
    required String durationLabel,
  }) async {
    await addEntry(
      HistoryEntry(
        type: 'route',
        title: 'Route to $destinationName',
        subtitle: '$distanceLabel - $durationLabel',
        timestamp: DateTime.now(),
      ),
    );
  }

  Future<void> clearHistory() async {
    entries.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_resolvedPrefsKey());
  }

  String _resolvedPrefsKey() {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return '${_prefsKeyPrefix}_anonymous';
    }
    return '${_prefsKeyPrefix}_$uid';
  }
}
