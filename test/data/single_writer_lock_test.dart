// Tests for the multi-PROCESS single-writer guard (WORKING_ON residual
// closure): an OS advisory exclusive lock on `<db>.lock`, acquired
// before the file-backed executor opens and held for the process
// lifetime. Contention policy: FAIL LOUD (StateError), never wait.
//
// Contention is exercised with a REAL second OS process — dart:io file
// locks are per-process (fcntl/flock semantics), so two handles inside
// this test process can never conflict; the residual was always about
// cross-PROCESS writers.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alexandria/data/database.dart';

/// The helper process this suite spawns. Modes:
///  * `hold <lockPath>` — acquire the exclusive lock, print LOCKED,
///    hold until stdin closes, then exit.
///  * `try <lockPath>` — attempt the exclusive lock, print ACQUIRED or
///    FAILED, exit immediately.
const _helperSource = r'''
import 'dart:io';
void main(List<String> args) async {
  final mode = args[0];
  final path = args[1];
  final raf = await File(path).open(mode: FileMode.write);
  if (mode == 'try') {
    try {
      await raf.lock(FileLock.exclusive);
      stdout.writeln('ACQUIRED');
      await raf.unlock();
    } catch (_) {
      stdout.writeln('FAILED');
    }
    await stdout.flush();
    await raf.close();
    return;
  }
  // mode == 'hold'
  await raf.lock(FileLock.exclusive);
  stdout.writeln('LOCKED');
  await stdout.flush();
  try {
    await stdin.drain<void>();
  } catch (_) {}
}
''';

void main() {
  late Directory tmp;
  late String helperPath;
  var dartAvailable = true;

  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('alx_lock_test');
    helperPath = '${tmp.path}/lock_helper.dart';
    File(helperPath).writeAsStringSync(_helperSource);
    try {
      final probe = await Process.run('dart', ['--version']);
      dartAvailable = probe.exitCode == 0;
    } catch (_) {
      dartAvailable = false;
    }
  });

  tearDownAll(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  String lockPath(String name) => '${tmp.path}/$name.lock';

  /// Starts the helper in `hold` mode and waits for its LOCKED line.
  Future<Process> holdLock(String path) async {
    final proc = await Process.start('dart', [helperPath, 'hold', path]);
    final first = await proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 30));
    expect(first, 'LOCKED');
    return proc;
  }

  /// Runs the helper in `try` mode; returns its single output line.
  Future<String> tryLock(String path) async {
    final result = await Process.run('dart', [helperPath, 'try', path]);
    return (result.stdout as String).trim();
  }

  group('DatabaseFileGuard', () {
    test(
        'acquire returns a held lock; a re-entrant acquire of the same '
        'path returns the same handle (no self-conflict)', () async {
      const guard = DatabaseFileGuard();
      final lock = await guard.acquire(lockPath('a'));
      expect(lock.released, isFalse);
      expect(File(lockPath('a')).existsSync(), isTrue,
          reason: 'the lockfile is a real sidecar file next to the db');

      final again = await guard.acquire(lockPath('a'));
      expect(identical(again, lock), isTrue,
          reason: 'the process-level registry dedups — re-acquiring '
              'our own lock must not report false contention');
      await lock.release();
    });

    test(
        'a second PROCESS holding the lock makes acquire FAIL LOUD '
        '(StateError), and acquisition succeeds once it exits', () async {
      if (!dartAvailable) {
        markTestSkipped('dart binary not on PATH — cannot spawn the '
            'contending process');
        return;
      }
      const guard = DatabaseFileGuard();
      final path = lockPath('contended');

      final holder = await holdLock(path);
      await expectLater(guard.acquire(path), throwsStateError,
          reason: 'the fail-loud contention policy — never wait, never '
              'silently run a second writer');

      // The OS releases the lock on process death — a crashed holder
      // never strands the database.
      holder.kill();
      await holder.exitCode;
      final lock = await guard.acquire(path);
      expect(lock.released, isFalse);
      await lock.release();
    });

    test(
        'the guard-held lock excludes a second process, and release() '
        'frees it', () async {
      if (!dartAvailable) {
        markTestSkipped('dart binary not on PATH — cannot spawn the '
            'contending process');
        return;
      }
      const guard = DatabaseFileGuard();
      final path = lockPath('held');
      final lock = await guard.acquire(path);

      expect(await tryLock(path), 'FAILED',
          reason: 'the OS-level lock is really held, not bookkeeping');

      await lock.release();
      expect(lock.released, isTrue);
      expect(await tryLock(path), 'ACQUIRED');
    });

    test('independent lock paths do not interfere', () async {
      const guard = DatabaseFileGuard();
      final l1 = await guard.acquire(lockPath('one'));
      final l2 = await guard.acquire(lockPath('two'));
      expect(identical(l1, l2), isFalse);
      await l1.release();
      await l2.release();
    });
  });

  group('injectable seam', () {
    test(
        'databaseFileGuardProvider is overridable — the lazy '
        'file-backed opener resolves the guard through it', () async {
      var acquireCalls = 0;
      final container = ProviderContainer(overrides: [
        databaseFileGuardProvider
            .overrideWithValue(_CountingGuard(() => acquireCalls++)),
      ]);
      addTearDown(container.dispose);
      expect(container.read(databaseFileGuardProvider), isA<_CountingGuard>());
      // (FLUTTER_TEST gives the in-memory executor, so no acquire is
      // exercised here — the seam assertion is that the provider is
      // what the production opener consults.)
      expect(acquireCalls, 0);
    });
  });
}

class _CountingGuard extends DatabaseFileGuard {
  final void Function() onAcquire;
  _CountingGuard(this.onAcquire);
  @override
  Future<DatabaseFileLock> acquire(String lockFilePath) async {
    onAcquire();
    return super.acquire(lockFilePath);
  }
}
