import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../models/security_models.dart';
import 'secure_storage_service.dart';

final auditLogServiceProvider = Provider((ref) => AuditLogService(ref));

class AuditLogService {
  final Ref _ref;
  File? _logFile;

  AuditLogService(this._ref);

  Future<void> init() async {
    if (_logFile != null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/audit_trail.log');
    } catch (_) {
      // In-memory or test fallback
    }
  }

  Future<void> log(
    String action, {
    String? details,
    String? actor,
    String status = 'Success',
  }) async {
    await init();
    final storage = _ref.read(secureStorageServiceProvider);
    final keyBase64 = await storage.read('master_key_v1');

    final timestamp = DateTime.now().toIso8601String();
    final payload = "$timestamp|$action|${details ?? ''}";

    String signature = 'nosig';
    if (keyBase64 != null) {
      final keyBytes = base64Decode(keyBase64);
      final hmac = Hmac(sha256, keyBytes);
      signature = hmac.convert(utf8.encode(payload)).toString();
    }

    final entry = '$payload|$signature|${actor ?? ''}|$status\n';
    if (_logFile != null) {
      await _logFile!.writeAsString(entry, mode: FileMode.append);
    }
  }

  Future<List<AuditLog>> getRecentLogs(int limit) async {
    await init();
    if (_logFile == null) return const [];

    final lines = await _logFile!.readAsLines();
    final logs = <AuditLog>[];
    for (var i = lines.length - 1; i >= 0 && logs.length < limit; i--) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final parts = line.split('|');
      if (parts.length < 4) continue;

      final timestamp = DateTime.tryParse(parts[0]) ?? DateTime.now();
      final event = parts[1];
      final details = parts[2];
      final signature = parts[3];
      final actor = parts.length >= 5 ? parts[4] : details;
      final status = parts.length >= 6
          ? parts[5]
          : (signature == 'nosig' ? 'Unverified' : 'Success');

      logs.add(AuditLog(
        event: event,
        actor: actor.isEmpty ? details : actor,
        timestamp: timestamp,
        status: status,
      ));
    }
    return logs;
  }
}
