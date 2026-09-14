import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/ledger_service.dart';
import 'package:alexandria/services/mnemonic_service.dart';
import 'package:alexandria/ui/profile_screen.dart';

class _FakeIdentityService implements IdentityService {
  AlexandriaIdentity? currentIdentity;

  /// Simulates keys present in storage while [currentIdentity] is null
  /// — the stale-cache case where the UI shows "no identity" but a
  /// stored keypair would still be overwritten by a recovery.
  bool identityStored = false;

  _FakeIdentityService({this.currentIdentity});

  final StreamController<int> _revisionController =
      StreamController<int>.broadcast(sync: true);
  int _revision = 0;

  @override
  Stream<int> get revisionStream => _revisionController.stream;

  @override
  int get revision => _revision;

  @override
  Future<bool> hasIdentity() async =>
      identityStored || currentIdentity != null;

  @override
  Future<AlexandriaIdentity?> getIdentity() async => currentIdentity;

  @override
  Future<AlexandriaIdentity> generateIdentity() async {
    final ident = AlexandriaIdentity(
      publicKey: Uint8List.fromList(List.filled(32, 99)),
      privateKey: Uint8List.fromList(List.filled(32, 100)),
      createdAt: DateTime(2026, 1, 1),
    );
    currentIdentity = ident;
    _revision++;
    _revisionController.add(_revision);
    return ident;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLedgerService implements LedgerService {
  @override
  double get totalReputation => 75.0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeIpfsService implements IpfsService {
  @override
  Set<String> get pinnedCids => {'bafy_pin1', 'bafy_pin2'};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMnemonicService implements MnemonicService {
  bool recovered = false;
  bool backupConfirmed = false;
  String? confirmedPhrase;
  int recoverCalls = 0;

  /// When set, [recoverFromMnemonic] throws it — simulates a recovery
  /// failure (e.g. post-write verification StateError).
  Object? recoverError;

  @override
  Future<bool> hasBackup() async => true;

  @override
  Future<void> markBackupConfirmed(String phrase) async {
    backupConfirmed = true;
    confirmedPhrase = phrase;
  }

  @override
  Future<MnemonicResult?> backupCurrentIdentity() async => MnemonicResult(
        words: List.filled(24, 'abandon'),
        entropy: Uint8List(32),
        seed: Uint8List(64),
      );

  @override
  Future<AlexandriaIdentity?> recoverFromMnemonic(List<String> words) async {
    recoverCalls++;
    final error = recoverError;
    if (error != null) throw error;
    recovered = true;
    return AlexandriaIdentity(
      publicKey: Uint8List.fromList(List.filled(32, 77)),
      privateKey: Uint8List.fromList(List.filled(32, 88)),
      createdAt: DateTime(2026, 1, 1),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProfileScreen Tests', () {
    testWidgets('renders identity, reputation, and activity graph', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final identity = AlexandriaIdentity(
        publicKey: Uint8List.fromList(List.filled(32, 42)),
        privateKey: Uint8List.fromList(List.filled(32, 43)),
        createdAt: DateTime(2025, 1, 1),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            identityServiceProvider.overrideWithValue(_FakeIdentityService(currentIdentity: identity)),
            ledgerServiceProvider.overrideWithValue(_FakeLedgerService()),
            ipfsServiceProvider.overrideWithValue(_FakeIpfsService()),
            mnemonicServiceProvider.overrideWithValue(_FakeMnemonicService()),
            reputationProvider.overrideWithValue(75.0),
            pinnedCountProvider.overrideWithValue(2),
            userActivityProvider.overrideWith((ref, key) async => {
                  DateTime.now(): 5,
                }),
          ],
          child: const MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );

      expect(find.text('DIGITAL IDENTITY'), findsOneWidget);
      await tester.pumpAndSettle();

      expect(find.text('75'), findsWidgets);
      expect(find.text('REPUTATION'), findsWidgets);
      expect(find.text('PRESERVATION ACTIVITY'), findsOneWidget);
      expect(find.text('EARNED BADGES'), findsOneWidget);
      expect(find.text('Guardian'), findsOneWidget);

      // Open Backup Dialog
      final backupBtn = find.byIcon(Icons.backup);
      expect(backupBtn, findsOneWidget);
      await tester.tap(backupBtn);
      await tester.pumpAndSettle();

      expect(find.text('Backup Identity'), findsOneWidget);
      expect(find.text("I've saved it"), findsOneWidget);
      await tester.tap(find.text("I've saved it"));
      await tester.pumpAndSettle();
    });

    testWidgets('unverified mode enables generating and recovering identity', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeIdentity = _FakeIdentityService(currentIdentity: null);
      final fakeMnemonic = _FakeMnemonicService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            identityServiceProvider.overrideWithValue(fakeIdentity),
            ledgerServiceProvider.overrideWithValue(_FakeLedgerService()),
            ipfsServiceProvider.overrideWithValue(_FakeIpfsService()),
            mnemonicServiceProvider.overrideWithValue(fakeMnemonic),
            reputationProvider.overrideWithValue(0.0),
            pinnedCountProvider.overrideWithValue(0),
          ],
          child: const MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('UNVERIFIED'), findsOneWidget);
      expect(find.text('Generate Identity'), findsOneWidget);
      expect(find.text('Recover from Mnemonic'), findsOneWidget);

      // Tap Recover from Mnemonic
      await tester.tap(find.text('Recover from Mnemonic'));
      await tester.pumpAndSettle();

      expect(find.text('Recover Identity'), findsOneWidget);
      final phrase = List.filled(24, 'abandon').join(' ');
      await tester.enterText(find.byType(TextField), phrase);
      await tester.pump();

      await tester.tap(find.text('Recover'));
      await tester.pumpAndSettle();

      expect(fakeMnemonic.recovered, isTrue);
    });

    testWidgets('recovery failure shows a SnackBar instead of an '
        'unhandled error', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeIdentity = _FakeIdentityService(currentIdentity: null);
      final fakeMnemonic = _FakeMnemonicService()
        ..recoverError = StateError('identity write failed verification');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            identityServiceProvider.overrideWithValue(fakeIdentity),
            ledgerServiceProvider.overrideWithValue(_FakeLedgerService()),
            ipfsServiceProvider.overrideWithValue(_FakeIpfsService()),
            mnemonicServiceProvider.overrideWithValue(fakeMnemonic),
            reputationProvider.overrideWithValue(0.0),
            pinnedCountProvider.overrideWithValue(0),
          ],
          child: const MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recover from Mnemonic'));
      await tester.pumpAndSettle();

      final phrase = List.filled(24, 'abandon').join(' ');
      await tester.enterText(find.byType(TextField), phrase);
      await tester.pump();
      await tester.tap(find.text('Recover'));
      await tester.pumpAndSettle();

      // An uncaught async error would fail this test on its own.
      expect(find.textContaining('Recovery failed'), findsOneWidget);
      expect(fakeMnemonic.recoverCalls, 1);
    });

    testWidgets('recover warns before replacing a stored identity the '
        'UI cannot see', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Storage still holds an identity even though the provider
      // serves null — recovery must confirm before overwriting it.
      final fakeIdentity = _FakeIdentityService(currentIdentity: null)
        ..identityStored = true;
      final fakeMnemonic = _FakeMnemonicService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            identityServiceProvider.overrideWithValue(fakeIdentity),
            ledgerServiceProvider.overrideWithValue(_FakeLedgerService()),
            ipfsServiceProvider.overrideWithValue(_FakeIpfsService()),
            mnemonicServiceProvider.overrideWithValue(fakeMnemonic),
            reputationProvider.overrideWithValue(0.0),
            pinnedCountProvider.overrideWithValue(0),
          ],
          child: const MaterialApp(
            home: ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recover from Mnemonic'));
      await tester.pumpAndSettle();

      // The replace warning gates the phrase input dialog.
      expect(find.text('Replace existing identity?'), findsOneWidget);
      expect(find.text('Recover Identity'), findsNothing);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fakeMnemonic.recoverCalls, 0);

      // Confirming proceeds to the phrase entry dialog.
      await tester.tap(find.text('Recover from Mnemonic'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace identity'));
      await tester.pumpAndSettle();

      expect(find.text('Recover Identity'), findsOneWidget);
      final phrase = List.filled(24, 'abandon').join(' ');
      await tester.enterText(find.byType(TextField), phrase);
      await tester.pump();
      await tester.tap(find.text('Recover'));
      await tester.pumpAndSettle();

      expect(fakeMnemonic.recoverCalls, 1);
    });
  });
}
