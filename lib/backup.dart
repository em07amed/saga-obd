import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'trips/trip_db.dart';

/// Whole-app backup as one JSON file: every database table plus settings.
/// The user keeps it wherever they like (Drive, WhatsApp, Files…).
class Backup {
  static const _tables = ['vehicles', 'trips', 'samples', 'maintenance', 'fillups'];

  static Future<void> export(TripDb db) async {
    final data = <String, dynamic>{
      'app': 'car-obd',
      'version': 1,
      'created': DateTime.now().toIso8601String(),
    };
    for (final t in _tables) {
      data[t] = await db.raw.query(t);
    }
    final p = await SharedPreferences.getInstance();
    data['prefs'] = {
      for (final k in p.getKeys())
        if (!k.startsWith('vehicleImage_')) k: p.get(k),
    };
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 10);
    final f = File('${dir.path}/car-obd-backup-$stamp.json');
    await f.writeAsString(jsonEncode(data));
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.path, mimeType: 'application/json')],
      subject: 'Car OBD backup $stamp',
    ));
  }

  /// Replaces all current data with the backup. Returns false if the file
  /// isn't a Car OBD backup.
  static Future<bool?> import(TripDb db) async {
    final pick = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = pick?.files.single.path;
    if (path == null) return null; // cancelled
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return false;
    }
    if (data['app'] != 'car-obd') return false;

    await db.raw.transaction((tx) async {
      for (final t in _tables) {
        await tx.delete(t);
        for (final row in (data[t] as List? ?? const [])) {
          await tx.insert(t, Map<String, Object?>.from(row as Map));
        }
      }
    });
    final p = await SharedPreferences.getInstance();
    final prefs = Map<String, dynamic>.from(data['prefs'] as Map? ?? const {});
    for (final e in prefs.entries) {
      final v = e.value;
      if (v is bool) {
        await p.setBool(e.key, v);
      } else if (v is int) {
        await p.setInt(e.key, v);
      } else if (v is double) {
        await p.setDouble(e.key, v);
      } else if (v is String) {
        await p.setString(e.key, v);
      } else if (v is List) {
        await p.setStringList(e.key, v.map((x) => '$x').toList());
      }
    }
    return true;
  }
}
