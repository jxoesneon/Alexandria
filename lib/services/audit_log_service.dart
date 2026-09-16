import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../models/security_models.dart';
import 'secure_storage_service.dart';

final auditLogServiceProvider = Provider((ref) => AuditLogService(ref));

class AuditLogService {
  final Ref _ref;
  File? _logFile;

  /// How often a MAC'd checkpoint line is written into the log itself
  /// (see the chain-integrity comment block). Injectable so tests can
  /// exercise checkpoints with small entry counts; clamped >= 1.
  final int checkpointEvery;

  AuditLogService(this._ref, {int checkpointEvery = 16})
      : checkpointEvery = checkpointEvery < 1 ? 1 : checkpointEvery;

  // ─── (round-4 red finding) chain-integrity state ───────────────────
  //
  // Signed lines are written as
  //   ts|event|details|v2:<seq>:<prevDigestHex>:<hmacHex>|actor|status
  // where <seq> is the entry's line index, <prevDigestHex> is the
  // SHA-256 of the PREVIOUS raw log line ('genesis' for the first), and
  // the HMAC covers EVERY column - the round-3 MAC only covered
  // timestamp|event|details, leaving actor/status freely rewritable by
  // anyone with file-append access (a denied 'attacker' line could be
  // relabelled 'victim|Success' and still verify). The seq+prev digest
  // chain additionally makes deletion detectable: removing a middle
  // line breaks the next line's prev link, and removing the tail is
  // caught by comparing the file's last line against the remembered
  // head (in-memory, plus a copy persisted in secure storage under
  // 'audit_chain_head_v1' so truncation survives restarts).

  /// Secure-storage key holding the persisted chain head
  /// (`<seq>:<sha256-of-last-line>`).
  static const String _chainHeadKey = 'audit_chain_head_v1';

  static const String _genesisDigest = 'genesis';

  /// Bound on synthesized gap-marker entries so a huge missing tail
  /// cannot flood the reader.
  static const int _maxGapMarkers = 32;

  // ─── (campaign-2 hardening) redundant head anchors ─────────────────
  //
  // The secure-storage chain head alone cannot bind truncation: an
  // attacker with secure-storage WRITE deletes 'audit_chain_head_v1'
  // AND truncates the file, and the surviving prefix verifies
  // perfectly. Two redundant anchors shrink what that adversary can do
  // silently:
  //
  //   * SIDECAR HEAD FILE (`<log>.head`, beside audit_trail.log): a
  //     second-domain artifact rewritten on every signed write,
  //     carrying 'v1|<seq>|<digest>|<hmac>' where the HMAC covers
  //     'audit-head:v1|<seq>|<digest>'. The reader takes the HIGHER-seq
  //     anchor of {secure storage, sidecar} as the expected head - a
  //     rolled-back single anchor can never LOWER the expectation -
  //     and flags a same-seq/different-digest disagreement as
  //     'audit_log_anchor_conflict'.
  //   * IN-FILE CHECKPOINT LINES every [checkpointEvery] signed
  //     entries: a normal chained v2-MAC'd line whose event is
  //     'audit_chain_checkpoint' and whose details record
  //     '<headSeq>:<headDigest>' of the entry just written. They are
  //     chain members (deleting one breaks the next line's prev link),
  //     MAC'd (forging one needs the key), and verified on read against
  //     the recorded predecessor digest - a tampered checkpoint is
  //     flagged like any tampered line.
  //
  // The detection guarantee this adds: deleting the secure-storage
  // head no longer blinds the reader (the sidecar still exposes
  // truncation), and deleting EVERY anchor while signed lines remain
  // is itself surfaced as 'audit_log_head_anchor_missing' - so a
  // single-shot attacker with file+secure-storage write cannot
  // silently truncate: they must either leave an anchor (→ gap
  // markers), forge one (→ impossible without the key), or delete all
  // anchors (→ the missing-anchor marker).
  //
  // WHAT THIS CANNOT CLOSE (documented residual): an attacker who
  // holds BOTH domains persistently and previously CAPTURED an older
  // anchor pair can roll storage+sidecar back to a consistent earlier
  // head and truncate to it - no purely-local mechanism distinguishes
  // a rolled-back anchor from a fresh one. Likewise, erasing the log
  // file, the sidecar AND the storage head atomically leaves nothing
  // to check. Closing tail-rollback entirely needs an external anchor:
  // remote notarization of the head digest, an append-only remote
  // log, or a hardware monotonic counter. Until that exists the
  // bound above is the honest ceiling.
  //
  // ─────────────────────────────────────────────────────────────────

  /// Sidecar anchor file suffix - `<log path>.head`.
  static const String _headFileSuffix = '.head';

  /// Event name carried by in-file checkpoint lines.
  static const String _checkpointEvent = 'audit_chain_checkpoint';

  /// True when the two head anchors disagree at the same seq - an
  /// impossible state for honest writes, so it means one anchor was
  /// rewritten. Surfaced as a Tampered marker on the next read.
  bool _anchorConflict = false;

  bool _chainLoaded = false;
  int _nextSeq = 0;
  String _prevDigest = _genesisDigest;

  /// The head this service knows was written - either from a write it
  /// performed itself or from the persisted secure-storage checkpoint.
  /// Never re-derived from the log file itself (that would mask a
  /// truncation).
  int? _expectedHeadSeq;
  String? _expectedHeadDigest;

  Future<void> init() async {
    if (_logFile != null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/audit_trail.log');
    } catch (_) {
      // In-memory or test fallback
    }
  }

  /// One-time recovery of chain state: the file tail supplies the
  /// write-side continuation (next seq + prev link), and the persisted
  /// checkpoint supplies the expected head for truncation detection.
  Future<void> _ensureChainState() async {
    if (_chainLoaded) return;
    _chainLoaded = true;
    try {
      final file = _logFile;
      if (file != null && await file.exists()) {
        final lines = (await file.readAsLines())
            .where((l) => l.trim().isNotEmpty)
            .toList();
        _nextSeq = lines.length;
        _prevDigest = lines.isEmpty ? _genesisDigest : _lineDigest(lines.last);
      }
    } catch (_) {
      // Unreadable file - start a fresh chain.
    }
    // Resolve the redundant head anchors (secure storage + sidecar
    // file); the higher-seq anchor wins so a single rolled-back anchor
    // cannot lower the expectation (campaign-2 hardening).
    final keyBytes = await _masterKeyBytes();
    final anchors = await _resolveHeadAnchors(keyBytes);
    if (anchors.conflict) _anchorConflict = true;
    var seq = anchors.seq;
    var digest = anchors.digest;
    if (seq == null) {
      // No external anchor: recover the last VERIFIED in-file
      // checkpoint as a conservative head - a MAC'd watermark that
      // still constrains the chain when secure storage was wiped but
      // the log file survived.
      final recovered = await _recoverCheckpointHead(keyBytes);
      if (recovered != null) {
        seq = recovered.$1;
        digest = recovered.$2;
      }
    }
    if (seq != null) {
      _expectedHeadSeq = seq;
      _expectedHeadDigest = digest;
      // Never reopen a sequence window the checkpoint already
      // closed - a truncated file must not mint lower seqs.
      if (_nextSeq <= seq) _nextSeq = seq + 1;
    }
  }

  /// Reads the audit HMAC key once per resolution.
  Future<Uint8List?> _masterKeyBytes() async {
    try {
      final storage = _ref.read(secureStorageServiceProvider);
      final keyBase64 = await storage.read('master_key_v1');
      return keyBase64 != null ? base64Decode(keyBase64) : null;
    } catch (_) {
      return null;
    }
  }

  /// Resolves both head anchors - secure storage `_chainHeadKey` and
  /// the MAC'd sidecar `<log>.head` - returning the higher-seq
  /// candidate plus a conflict flag when they claim the same seq with
  /// different digests (impossible for honest writes ⇒ one anchor was
  /// rewritten). The returned `any` flag reports whether at least one
  /// anchor exists at all; its absence while signed lines remain is
  /// itself tamper evidence (campaign-2 hardening).
  Future<({int? seq, String? digest, bool any, bool conflict})>
      _resolveHeadAnchors(Uint8List? keyBytes) async {
    int? aSeq;
    String? aDigest;
    try {
      final storage = _ref.read(secureStorageServiceProvider);
      final head = await storage.read(_chainHeadKey);
      if (head != null) {
        final sep = head.indexOf(':');
        if (sep > 0) {
          final s = int.tryParse(head.substring(0, sep));
          if (s != null) {
            aSeq = s;
            aDigest = head.substring(sep + 1);
          }
        }
      }
    } catch (_) {}

    int? bSeq;
    String? bDigest;
    try {
      final file = _logFile;
      if (file != null) {
        final headFile = File('${file.path}$_headFileSuffix');
        if (await headFile.exists()) {
          final raw = (await headFile.readAsString()).trim();
          final parts = raw.split('|');
          if (parts.length == 4 && parts[0] == 'v1' && keyBytes != null) {
            final s = int.tryParse(parts[1]);
            final mac = Hmac(sha256, keyBytes)
                .convert(utf8.encode('audit-head:v1|${parts[1]}|${parts[2]}'))
                .toString();
            if (s != null && mac == parts[3]) {
              bSeq = s;
              bDigest = parts[2];
            }
          }
        }
      }
    } catch (_) {}

    var conflict = false;
    int? seq;
    String? digest;
    if (aSeq != null && bSeq != null) {
      if (aSeq == bSeq && aDigest != bDigest) conflict = true;
      if (aSeq >= bSeq) {
        seq = aSeq;
        digest = aDigest;
      } else {
        seq = bSeq;
        digest = bDigest;
      }
    } else if (aSeq != null) {
      seq = aSeq;
      digest = aDigest;
    } else if (bSeq != null) {
      seq = bSeq;
      digest = bDigest;
    }
    return (
      seq: seq,
      digest: digest,
      any: aSeq != null || bSeq != null,
      conflict: conflict,
    );
  }

  /// Scans the log file tail-to-head for the most recent checkpoint
  /// line that FULLY verifies - MAC, own seq position, and the
  /// recorded predecessor head - returning `(seq, lineDigest)` of the
  /// checkpoint itself. Used only when both external anchors are
  /// absent (campaign-2 hardening).
  Future<(int, String)?> _recoverCheckpointHead(Uint8List? keyBytes) async {
    if (keyBytes == null) return null;
    try {
      final file = _logFile;
      if (file == null || !await file.exists()) return null;
      final lines =
          (await file.readAsLines()).where((l) => l.trim().isNotEmpty).toList();
      for (var i = lines.length - 1; i >= 0; i--) {
        final parts = _splitEscaped(lines[i]);
        if (parts.length < 6 || _unesc(parts[1]) != _checkpointEvent) {
          continue;
        }
        final sig = parts[3];
        if (!sig.startsWith('v2:')) continue;
        final f = sig.split(':');
        if (f.length != 4) continue;
        final seq = int.tryParse(f[1]);
        if (seq == null || seq != i) continue;
        final mac = Hmac(sha256, keyBytes)
            .convert(utf8.encode(_v2MacInput(
                seq, f[2], parts[0], parts[1], parts[2], parts[4], parts[5])))
            .toString();
        if (mac != f[3]) continue;
        // Recorded-head consistency: '<S>:<D>' must name the line
        // directly before the checkpoint and hash to it.
        final rec = _unesc(parts[2]);
        final sep = rec.indexOf(':');
        if (sep <= 0) continue;
        final rs = int.tryParse(rec.substring(0, sep));
        if (rs == null ||
            rs != i - 1 ||
            _lineDigest(lines[rs]) != rec.substring(sep + 1)) {
          continue;
        }
        return (i, _lineDigest(lines[i]));
      }
    } catch (_) {}
    return null;
  }

  /// Persists the chain head to BOTH anchors: secure storage and the
  /// MAC'd sidecar file. Best-effort - an unwritable anchor degrades
  /// to the other, never to no anchor silently (the missing-anchor
  /// read marker covers total absence).
  Future<void> _writeHeadAnchors(SecureStorageService storage,
      Uint8List keyBytes, int seq, String digest) async {
    try {
      await storage.write(_chainHeadKey, '$seq:$digest');
    } catch (_) {}
    final file = _logFile;
    if (file == null) return;
    try {
      final mac = Hmac(sha256, keyBytes)
          .convert(utf8.encode('audit-head:v1|$seq|$digest'))
          .toString();
      await File('${file.path}$_headFileSuffix')
          .writeAsString('v1|$seq|$digest|$mac\n');
    } catch (_) {}
  }

  static String _lineDigest(String rawLine) =>
      sha256.convert(utf8.encode(rawLine)).toString();

  /// The MAC input for a v2 line: EVERY stored column plus the chain
  /// fields - nothing on the line is outside the signature.
  static String _v2MacInput(int seq, String prev, String p0, String p1,
      String p2, String p4, String p5) {
    return 'v2|$seq|$prev|$p0|$p1|$p2|$p4|$p5';
  }

  Future<void> log(
    String action, {
    String? details,
    String? actor,
    String status = 'Success',
  }) async {
    await init();
    await _ensureChainState();
    final storage = _ref.read(secureStorageServiceProvider);
    final keyBase64 = await storage.read('master_key_v1');

    final timestamp = DateTime.now().toIso8601String();
    // Fields are '|'-delimited, so every remote-controllable value is
    // backslash-escaped before joining - otherwise a `|` or newline in
    // details/actor would forge extra columns or fake log lines (red
    // minor-observation hardening).
    final p1 = _esc(action);
    final p2 = _esc(details ?? '');
    final p4 = _esc(actor ?? '');
    final p5 = _esc(status);

    String signature = 'nosig';
    final seq = _nextSeq;
    if (keyBase64 != null) {
      final keyBytes = base64Decode(keyBase64);
      final mac = Hmac(sha256, keyBytes)
          .convert(utf8
              .encode(_v2MacInput(seq, _prevDigest, timestamp, p1, p2, p4, p5)))
          .toString();
      signature = 'v2:$seq:$_prevDigest:$mac';
    }

    final entry = '$timestamp|$p1|$p2|$signature|$p4|$p5\n';
    final file = _logFile;
    if (file != null) {
      await file.writeAsString(entry, mode: FileMode.append);
    }

    // Advance the chain: even unsigned ('nosig') lines occupy a
    // sequence position, so a later signed line links over them.
    final digest = _lineDigest(entry.trim());
    _prevDigest = digest;
    _nextSeq = seq + 1;
    _expectedHeadSeq = seq;
    _expectedHeadDigest = digest;
    if (keyBase64 != null) {
      final keyBytes = base64Decode(keyBase64);
      // (campaign-2 hardening) persist the head to BOTH anchors -
      // deleting only the secure-storage copy can no longer blind
      // truncation detection.
      await _writeHeadAnchors(storage, keyBytes, seq, digest);
      // Periodic in-file checkpoint: a MAC'd, chain-linked line
      // recording the head just written - a second redundant anchor
      // embedded in the log stream itself.
      if (file != null && _nextSeq % checkpointEvery == 0) {
        await _writeCheckpoint(file, keyBytes);
      }
    }
  }

  /// Appends a checkpoint line: a normal v2-chained, HMAC'd entry
  /// whose details record `headSeq:headDigest` of the entry just
  /// written. It occupies its own sequence position (so deleting it
  /// breaks the next line's chain link) and becomes the new head
  /// (campaign-2 hardening).
  Future<void> _writeCheckpoint(File file, Uint8List keyBytes) async {
    final timestamp = DateTime.now().toIso8601String();
    final recorded = '$_expectedHeadSeq:$_expectedHeadDigest';
    final seq = _nextSeq;
    final mac = Hmac(sha256, keyBytes)
        .convert(utf8.encode(_v2MacInput(seq, _prevDigest, timestamp,
            _checkpointEvent, recorded, 'system', 'Checkpoint')))
        .toString();
    final line =
        '$timestamp|$_checkpointEvent|$recorded|v2:$seq:$_prevDigest:$mac'
        '|system|Checkpoint\n';
    await file.writeAsString(line, mode: FileMode.append);
    final digest = _lineDigest(line.trim());
    _prevDigest = digest;
    _nextSeq = seq + 1;
    _expectedHeadSeq = seq;
    _expectedHeadDigest = digest;
    final storage = _ref.read(secureStorageServiceProvider);
    await _writeHeadAnchors(storage, keyBytes, seq, digest);
  }

  Future<List<AuditLog>> getRecentLogs(int limit) async {
    // A non-positive limit is a caller bug - clamp it rather than let
    // `sublist(0, negative)` throw RangeError at the tail of the read.
    if (limit <= 0) return const [];
    await init();
    await _ensureChainState();
    if (_logFile == null) return const [];

    // (round-3 red finding) the write-side HMAC is VERIFIED on read -
    // a forged line appended to the log file must never surface as a
    // trusted entry. (round-4 red finding) the v2 MAC covers the WHOLE
    // line (actor/status included) and each line chains to its
    // predecessor, so tampering with ANY column - or deleting middle or
    // tail lines - is detectable. Rules:
    //   * 'nosig' line → surfaced flagged 'Unverified' (legacy unsigned).
    //   * signed line, no verifier key → dropped (cannot be checked).
    //   * MAC or chain mismatch → surfaced flagged 'Tampered' with the
    //     claimed actor stripped - flagged, never trusted, never silent.
    //   * missing tail (file's last line != remembered head) → gap
    //     marker entries are synthesized so the absence is visible.
    final storage = _ref.read(secureStorageServiceProvider);
    final keyBase64 = await storage.read('master_key_v1');
    final keyBytes = keyBase64 != null ? base64Decode(keyBase64) : null;

    // (campaign-2 hardening) re-resolve the head anchors FRESH on every
    // read - a mid-session anchor deletion must not hide behind the
    // state loaded once at init. The higher-seq anchor feeds the
    // expected head below; `anchors.any` drives the missing-anchor
    // marker, and a same-seq/different-digest disagreement is flagged.
    final anchors = await _resolveHeadAnchors(keyBytes);
    if (anchors.conflict) _anchorConflict = true;

    List<String> lines;
    try {
      lines = await _logFile!.readAsLines();
    } catch (_) {
      lines = const [];
    }
    final nonEmpty =
        lines.where((l) => l.trim().isNotEmpty).map((l) => l.trim()).toList();

    // Parse & verify every line (oldest → newest for chain checks).
    final verified = <AuditLog>[];
    var prevDigest = _genesisDigest;
    for (var i = 0; i < nonEmpty.length; i++) {
      final line = nonEmpty[i];
      final parts = _splitEscaped(line);
      if (parts.length < 4) {
        prevDigest = _lineDigest(line);
        continue;
      }

      final timestamp = DateTime.tryParse(parts[0]) ?? DateTime.now();
      final event = _unesc(parts[1]);
      final details = _unesc(parts[2]);
      final signature = parts[3];
      final claimedActor = parts.length >= 5 ? _unesc(parts[4]) : '';
      final claimedStatus = parts.length >= 6 ? _unesc(parts[5]) : 'Success';
      final lineDigest = _lineDigest(line);

      AuditLog? entry;
      if (signature == 'nosig') {
        entry = AuditLog(
          event: event,
          actor: claimedActor.isEmpty ? details : claimedActor,
          timestamp: timestamp,
          status: 'Unverified',
        );
      } else if (keyBytes == null) {
        // Signed entry but no verifier key - cannot check → drop.
        entry = null;
      } else if (signature.startsWith('v2:')) {
        final fields = signature.split(':');
        final wellFormed = fields.length == 4 && parts.length >= 6;
        final seq = wellFormed ? int.tryParse(fields[1]) : null;
        final claimedPrev = wellFormed ? fields[2] : '';
        final claimedMac = wellFormed ? fields[3] : '';
        final expectedMac = seq == null
            ? null
            : Hmac(sha256, keyBytes)
                .convert(utf8.encode(_v2MacInput(
                    seq,
                    claimedPrev,
                    parts[0],
                    parts[1],
                    parts[2],
                    parts.length >= 5 ? parts[4] : '',
                    parts[5])))
                .toString();
        final macOk = expectedMac != null && expectedMac == claimedMac;
        var chainOk = seq == i && claimedPrev == prevDigest;
        // (campaign-2 hardening) checkpoint lines carry a recorded head
        // '<S>:<D>' that must name the line directly before them and
        // hash to it - a MAC-valid line whose watermark lies is still
        // tampered.
        if (chainOk && event == _checkpointEvent) {
          chainOk = _checkpointConsistent(details, i, nonEmpty);
        }
        entry = macOk && chainOk
            ? AuditLog(
                event: event,
                actor: claimedActor.isEmpty ? details : claimedActor,
                timestamp: timestamp,
                status: claimedStatus,
              )
            : _tampered(event, timestamp);
      } else {
        // Legacy signed line (round-3 format): MAC covered only
        // parts[0..2] - verify it for backward compatibility; a failure
        // is still surfaced flagged rather than trusted.
        final payload = '${parts[0]}|${parts[1]}|${parts[2]}';
        final expected =
            Hmac(sha256, keyBytes).convert(utf8.encode(payload)).toString();
        entry = expected == signature
            ? AuditLog(
                event: event,
                actor: claimedActor.isEmpty ? details : claimedActor,
                timestamp: timestamp,
                status: claimedStatus,
              )
            : _tampered(event, timestamp);
      }

      if (entry != null) verified.add(entry);
      prevDigest = lineDigest;
    }

    // Tail-truncation detection (round-4 red finding): the remembered
    // head says how many entries SHOULD exist; if the file ends earlier
    // the missing tail is reported as gap markers instead of vanishing.
    // (campaign-2 hardening) the expectation is the HIGHER-seq source
    // of {in-memory head, secure-storage anchor, sidecar anchor} - a
    // single rolled-back or deleted anchor can no longer lower it.
    final gapMarkers = <AuditLog>[];
    var expectedSeq = _expectedHeadSeq;
    var expectedDigest = _expectedHeadDigest;
    if (anchors.seq != null &&
        (expectedSeq == null || anchors.seq! > expectedSeq)) {
      expectedSeq = anchors.seq;
      expectedDigest = anchors.digest;
    }
    if (expectedSeq != null) {
      final lastIndex = nonEmpty.isEmpty ? -1 : nonEmpty.length - 1;
      final lastDigest =
          nonEmpty.isEmpty ? _genesisDigest : _lineDigest(nonEmpty.last);
      final missing = expectedSeq - lastIndex;
      if (missing > 0 && lastDigest != expectedDigest) {
        final count = missing > _maxGapMarkers ? _maxGapMarkers : missing;
        final markerTs =
            verified.isEmpty ? DateTime.now() : verified.last.timestamp;
        for (var k = 0; k < count; k++) {
          gapMarkers.add(AuditLog(
            event: 'audit_log_tail_gap',
            actor: 'system',
            timestamp: markerTs,
            status: 'Tampered',
          ));
        }
      }
    }

    // (campaign-2 hardening) anchor-anomaly markers - surfaced like
    // gap markers so anchor tampering is visible, never silent:
    //   * 'audit_log_anchor_conflict': the two anchors claim the same
    //     seq with different digests - one of them was rewritten.
    //   * 'audit_log_head_anchor_missing': the file still carries
    //     v2-signed lines but NO head anchor exists anywhere - the
    //     only way signed lines lose every anchor is deletion.
    final anomalyTs =
        verified.isEmpty ? DateTime.now() : verified.last.timestamp;
    if (_anchorConflict) {
      gapMarkers.add(AuditLog(
        event: 'audit_log_anchor_conflict',
        actor: 'system',
        timestamp: anomalyTs,
        status: 'Tampered',
      ));
    }
    final hasSignedLines = nonEmpty.any((l) {
      final p = _splitEscaped(l);
      return p.length >= 4 && p[3].startsWith('v2:');
    });
    if (hasSignedLines && !anchors.any) {
      gapMarkers.add(AuditLog(
        event: 'audit_log_head_anchor_missing',
        actor: 'system',
        timestamp: anomalyTs,
        status: 'Tampered',
      ));
    }

    // Newest-first result, gap markers (representing the most recent,
    // absent entries) first.
    final logs = <AuditLog>[
      ...gapMarkers,
      ...verified.reversed,
    ];
    return logs.length > limit ? logs.sublist(0, limit) : logs;
  }

  /// Verifies a checkpoint line's recorded head: details must be
  /// `S:D` where S is the index of the line directly before the
  /// checkpoint in [lines] and D is that line's digest (campaign-2
  /// hardening).
  static bool _checkpointConsistent(
      String details, int index, List<String> lines) {
    final sep = details.indexOf(':');
    if (sep <= 0) return false;
    final s = int.tryParse(details.substring(0, sep));
    if (s == null || s != index - 1 || s < 0 || s >= lines.length) {
      return false;
    }
    return _lineDigest(lines[s]) == details.substring(sep + 1);
  }

  /// A line that parses but fails MAC/chain verification: surfaced so
  /// the tamper attempt is visible, but flagged and stripped of its
  /// claimed actor/status so it can never masquerade as trusted.
  static AuditLog _tampered(String claimedEvent, DateTime timestamp) =>
      AuditLog(
        event: claimedEvent,
        actor: 'unknown',
        timestamp: timestamp,
        status: 'Tampered',
      );

  /// Escapes `|` and newlines in a single log field so remote-controlled
  /// values can neither forge columns nor splice fake lines.
  static String _esc(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll('|', '\\p')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r');

  /// Splits a log line on UNESCAPED `|` separators.
  static List<String> _splitEscaped(String line) {
    final parts = <String>[];
    final buf = StringBuffer();
    var escaped = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (escaped) {
        buf.write(ch);
        escaped = false;
      } else if (ch == '\\') {
        buf.write(ch);
        escaped = true;
      } else if (ch == '|') {
        parts.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    parts.add(buf.toString());
    return parts;
  }

  /// Inverse of [_esc].
  static String _unesc(String s) {
    final buf = StringBuffer();
    var escaped = false;
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (!escaped && ch == '\\') {
        escaped = true;
        continue;
      }
      if (escaped) {
        buf.write(switch (ch) {
          'p' => '|',
          'n' => '\n',
          'r' => '\r',
          _ => ch,
        });
        escaped = false;
      } else {
        buf.write(ch);
      }
    }
    return buf.toString();
  }
}
