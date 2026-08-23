import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
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

  Future<void> log(String action, {String? details}) async {
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

    final entry = '$payload|$signature\n';
    if (_logFile != null) {
      await _logFile!.writeAsString(entry, mode: FileMode.append);
    }
  }
}
