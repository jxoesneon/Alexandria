import 'dart:convert';
import 'dart:io';
import 'package:alexandria/services/secure_storage_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final auditLogServiceProvider = Provider((ref) => AuditLogService(ref));

class AuditLogService {
  final Ref _ref;
  File? _logFile;

  AuditLogService(this._ref);

  Future<void> _init() async {
    if (_logFile != null) return;
    final dir = await getApplicationDocumentsDirectory();
    _logFile = File('${dir.path}/audit_trail.log');
  }

  Future<void> log(String action, {String? details}) async {
    await _init();

    // Get Master Key for signing (hmac)
    // We access secure storage directly to retrieve the raw key string if needed,
    // or rely on ContentRepos helper if exposed.
    // To avoid circular dependency with ContentRepo, we re-read storage.
    final storage = _ref.read(secureStorageServiceProvider);
    final keyBase64 = await storage.read('master_key_v1');

    final timestamp = DateTime.now().toIso8601String();
    final payload = "$timestamp|$action|${details ?? ''}";

    String signature = 'nosig';
    if (keyBase64 != null) {
      final keyBytes = base64Decode(keyBase64);
      final hmac = Hmac(sha256, keyBytes);
      final digest = hmac.convert(utf8.encode(payload));
      signature = digest.toString();
    }

    final entry = '$payload|$signature\n';
    await _logFile!.writeAsString(entry, mode: FileMode.append);
  }
}
