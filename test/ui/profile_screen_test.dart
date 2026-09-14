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

  _FakeIdentityService({this.currentIdentity});

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

  @override
  Future<bool> hasBackup() async => true;

  @override
  Future<MnemonicResult?> backupCurrentIdentity() async => MnemonicResult(
        words: List.filled(24, 'abandon'),
        entropy: Uint8List(32),
        seed: Uint8List(64),
      );

  @override
  Future<AlexandriaIdentity?> recoverFromMnemonic(List<String> words) async {
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
  });
}
