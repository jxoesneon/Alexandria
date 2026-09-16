import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/models/library_models.dart';
import 'package:alexandria/providers/library_providers.dart';
import 'package:alexandria/services/biometric_service.dart';
import 'package:alexandria/services/governance_service.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/ledger_service.dart';
import 'package:alexandria/services/mnemonic_service.dart';
import 'package:alexandria/services/sync_service.dart';
import 'package:alexandria/ui/agent/mcp_config_export_dialog.dart';
import 'package:alexandria/ui/governance_screen.dart';
import 'package:alexandria/ui/library/library_overview_screen.dart';
import 'package:alexandria/ui/onboarding_screen.dart';
import 'package:alexandria/ui/profile_screen.dart';
import 'package:alexandria/ui/scriptorium/creation_wizard.dart';
import 'package:alexandria/ui/theme/app_theme.dart';

/// Mock for SystemChannels.platform so Clipboard.setData/getData
/// complete — the test binding never replies to platform messages, so
/// any lib path that awaits Clipboard.setData before showing feedback
/// would otherwise hang forever.
void installClipboardMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.getData') {
      return <String, dynamic>{'text': ''};
    }
    return null;
  });
}

/// Stateful in-memory handler for flutter_secure_storage.
Map<String, String> installSecureStore() {
  final store = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      final key = call.arguments['key'] as String?;
      switch (call.method) {
        case 'read':
          return store[key];
        case 'write':
          store[key!] = call.arguments['value'] as String;
          return null;
        case 'delete':
          store.remove(key);
          return null;
        case 'containsKey':
          return store.containsKey(key);
        default:
          return null;
      }
    },
  );
  return store;
}

class _FakeIdentityService implements IdentityService {
  _FakeIdentityService({this.throwOnGenerate = false});

  bool throwOnGenerate;

  @override
  Future<AlexandriaIdentity?> getIdentity() async => null;

  @override
  Future<bool> hasIdentity() async => false;

  @override
  Future<AlexandriaIdentity> generateIdentity() async {
    if (throwOnGenerate) throw StateError('keygen exploded');
    throw UnimplementedError('unexpected success path');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMnemonicService implements MnemonicService {
  _FakeMnemonicService(
      {this.throwOnBackup = false, this.throwOnRecover = false});

  bool throwOnBackup;
  bool throwOnRecover;
  AlexandriaIdentity? recoverResult;
  bool returnNullBackup = false;

  @override
  Future<MnemonicResult?> backupCurrentIdentity() async {
    if (throwOnBackup) throw StateError('backup exploded');
    if (returnNullBackup) return null;
    return MnemonicResult(
      words: List.filled(24, 'anchor'),
      entropy: Uint8List(32),
      seed: Uint8List(64),
    );
  }

  @override
  Future<AlexandriaIdentity?> recoverFromMnemonic(
      List<String> words) async {
    if (throwOnRecover) throw StateError('recover exploded');
    return recoverResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBiometricService implements BiometricService {
  _FakeBiometricService({this.throwOnAuth = false});

  bool throwOnAuth;
  bool result = true;

  @override
  Future<bool> authenticate({String reason = ''}) async {
    if (throwOnAuth) throw StateError('no biometric hardware');
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLedgerService implements LedgerService {
  @override
  double get totalReputation => 50.0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGovernanceService implements GovernanceService {
  _FakeGovernanceService(this._proposals, {this.canVoteResult = true});

  final List<Proposal> _proposals;
  bool canVoteResult;
  bool canCreateResult = true;
  bool? lastApprove;

  @override
  List<Proposal> get proposals => _proposals;

  @override
  List<Proposal> get activeProposals =>
      _proposals.where((p) => p.status == ProposalStatus.active).toList();

  @override
  Future<bool> canVote() async => canVoteResult;

  @override
  Future<bool> canCreateProposal() async => canCreateResult;

  @override
  Future<bool> vote({required String proposalId, required bool approve}) async {
    lastApprove = approve;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Proposal _prop(String id, ProposalStatus status,
        {Duration deadlineOffset = const Duration(days: 7)}) =>
    Proposal(
      id: id,
      type: ProposalType.gatewayAddition,
      title: 'Prop $id',
      description: 'desc',
      payload: const {},
      proposerId: 'proposer',
      created: DateTime.now().subtract(const Duration(days: 2)),
      deadline: DateTime.now().add(deadlineOffset),
      status: status,
      signature: 'sig',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> bigSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  group('CreationWizard', () {
    testWidgets('stepper completes at last step and cancels at first',
        (tester) async {
      await bigSurface(tester);
      await tester.pumpWidget(const ProviderScope(
          child: MaterialApp(home: CreationWizard())));
      await tester.pumpAndSettle();

      // Drive the stepper via its callbacks: tapping the controls row
      // misses the hit test once later (taller) steps shift the layout.
      Stepper stepper() => tester.widget<Stepper>(find.byType(Stepper));

      // Step 0 → Continue → step 1 → Continue → step 2.
      for (var i = 0; i < 2; i++) {
        stepper().onStepContinue!();
        await tester.pumpAndSettle();
      }

      // Toggle the encrypt switch.
      final toggle = find.byType(SwitchListTile);
      if (toggle.evaluate().isNotEmpty) {
        tester.widget<SwitchListTile>(toggle.first).onChanged!(true);
        await tester.pumpAndSettle();
      }

      // Continue on the last step → snackbar + pop.
      stepper().onStepContinue!();
      await tester.pumpAndSettle();
      expect(find.text('Add Document to Library'), findsNothing);
    });

    testWidgets('cancel on step 0 pops the wizard', (tester) async {
      await bigSurface(tester);
      await tester.pumpWidget(const ProviderScope(
          child: MaterialApp(home: CreationWizard())));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel').first);
      await tester.pumpAndSettle();
      expect(find.byType(Stepper), findsNothing);
    });
  });

  group('McpConfigExportDialog', () {
    final tools = [
      {'name': 'tool_a', 'description': 'first tool'},
      {'name': 'tool_b', 'description': 'second tool'},
    ];

    Future<void> pumpDialog(WidgetTester tester) async {
      await bigSurface(tester);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(body: McpConfigExportDialog(tools: tools)),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('copy button works on every tab and resets', (tester) async {
      await pumpDialog(tester);

      for (final tab in [
        'Gemini CLI',
        'Cursor / Windsurf',
        'Tool Schemas',
        'Claude Desktop'
      ]) {
        await tester.tap(find.textContaining(tab));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Copy Active Config'));
        await tester.pump();
        expect(find.textContaining('copied to clipboard'), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('code block InkWell copies and close button pops',
        (tester) async {
      await pumpDialog(tester);
      // InkWell wrapping the per-tab 'Copy' affordance next to filename.
      await tester.tap(find.widgetWithText(InkWell, 'Copy').first);
      await tester.pump();
      expect(find.textContaining('copied to clipboard'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();
    });

    testWidgets('static show() helper opens the dialog', (tester) async {
      await bigSurface(tester);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => McpConfigExportDialog.show(context, tools),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Connect External AI Agents (ALX-006)'),
          findsOneWidget);
    });
  });

  group('LibraryOverviewScreen', () {
    Widget subject({
      SyncStatus sync = SyncStatus.idle,
      Object? statsError,
      Object? recentError,
      Object? arrivalsError,
      List<LibraryItem> recent = const [
        LibraryItem(cid: 'c1', title: 'R1', author: 'a'),
        LibraryItem(cid: 'c2', title: 'R2', author: 'b'),
      ],
      List<LibraryItem> arrivals = const [],
    }) {
      return ProviderScope(
        // Keyed by status: ProviderScope freezes its overrides at
        // container creation, so re-pumping the same scope type would
        // silently keep the FIRST status forever.
        key: ValueKey('library-scope-${sync.name}'),
        overrides: [
          syncStatusProvider.overrideWith((ref) => sync),
          libraryDashboardProvider.overrideWith((ref) async {
            if (statsError != null) throw statsError;
            return const LibraryStats(
              totalItems: 1,
              totalSize: '1 KB',
              networkStatus: 'ok',
            );
          }),
          recentItemsProvider.overrideWith((ref) async {
            if (recentError != null) throw recentError;
            return recent;
          }),
          newArrivalsProvider.overrideWith((ref) async {
            if (arrivalsError != null) throw arrivalsError;
            return arrivals;
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const LibraryOverviewScreen(),
        ),
      );
    }

    testWidgets('sync status variants render', (tester) async {
      await bigSurface(tester);
      const labels = {
        SyncStatus.idle: 'Synced',
        SyncStatus.syncing: 'Syncing',
        SyncStatus.offline: 'Offline',
        SyncStatus.error: 'Sync failed',
      };
      for (final status in SyncStatus.values) {
        await tester.pumpWidget(subject(sync: status));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text(labels[status]!), findsOneWidget);
      }
    });

    testWidgets('async error branches render failure text', (tester) async {
      await bigSurface(tester);
      await tester.pumpWidget(subject(
        statsError: 'boom',
        recentError: 'boom',
        arrivalsError: 'boom',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Failed to load stats'), findsOneWidget);
      expect(find.textContaining('Failed to load recent items'),
          findsOneWidget);
      expect(find.textContaining('Failed to load new arrivals'),
          findsOneWidget);
    });

    testWidgets('carousel separator renders with multiple items',
        (tester) async {
      await bigSurface(tester);
      await tester.pumpWidget(subject());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('R1'), findsOneWidget);
      expect(find.text('R2'), findsOneWidget);
    });

    testWidgets('search action navigates to discovery', (tester) async {
      await bigSurface(tester);
      await tester.pumpWidget(subject());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(LibraryOverviewScreen), findsNothing);
    });

    testWidgets('collections action navigates to collections shelves',
        (tester) async {
      await bigSurface(tester);
      await tester.pumpWidget(subject());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester
          .tap(find.byIcon(Icons.collections_bookmark_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(LibraryOverviewScreen), findsNothing);
    });
  });

  group('GovernanceScreen', () {
    Future<void> pumpGov(
      WidgetTester tester, {
      required _FakeGovernanceService gov,
      Object? canVoteError,
      Object? canCreateError,
      bool canVoteLoading = false,
    }) async {
      await bigSurface(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          identityServiceProvider
              .overrideWithValue(_FakeIdentityService()),
          ledgerServiceProvider.overrideWithValue(_FakeLedgerService()),
          governanceServiceProvider.overrideWithValue(gov),
          canVoteProvider.overrideWith((ref) async {
            if (canVoteLoading) {
              await Future.delayed(const Duration(seconds: 30));
            }
            if (canVoteError != null) throw canVoteError;
            return gov.canVoteResult;
          }),
          canCreateProposalProvider.overrideWith((ref) async {
            if (canCreateError != null) throw canCreateError;
            return gov.canCreateResult;
          }),
        ],
        child: MaterialApp(
            theme: AppTheme.darkTheme, home: const GovernanceScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('empty state and provider error branches', (tester) async {
      final gov = _FakeGovernanceService([]);
      await pumpGov(tester,
          gov: gov, canVoteError: 'x', canCreateError: 'y');
      expect(find.text('No proposals yet'), findsOneWidget);
      expect(find.text('Be the first to create a governance proposal'),
          findsOneWidget);
    });

    testWidgets('proposal cards render status colors and date formats',
        (tester) async {
      final gov = _FakeGovernanceService([
        _prop('p_active', ProposalStatus.active,
            deadlineOffset: const Duration(days: 3)),
        _prop('p_approved', ProposalStatus.approved,
            deadlineOffset: const Duration(hours: 5)),
        _prop('p_executed', ProposalStatus.executed,
            deadlineOffset: const Duration(minutes: 30)),
        _prop('p_rejected', ProposalStatus.rejected,
            deadlineOffset: const Duration(days: -1)),
        _prop('p_expired', ProposalStatus.expired,
            deadlineOffset: const Duration(days: -2)),
        _prop('p_draft', ProposalStatus.draft),
      ]);
      await pumpGov(tester, gov: gov);
      expect(find.text('Prop p_active'), findsOneWidget);
      expect(find.text('Prop p_rejected'), findsOneWidget);
      expect(find.textContaining('Ended'), findsWidgets);
    });

    testWidgets('proposal detail sheet: REJECT votes and canVote container',
        (tester) async {
      final gov = _FakeGovernanceService(
          [_prop('p_vote', ProposalStatus.active)]);
      await pumpGov(tester, gov: gov);

      // Open the detail bottom sheet.
      await tester.tap(find.text('Prop p_vote'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('REJECT'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(gov.lastApprove, isFalse);
    });

    testWidgets('canVote false shows eligibility notice', (tester) async {
      final gov = _FakeGovernanceService(
          [_prop('p_nv', ProposalStatus.active)],
          canVoteResult: false);
      await pumpGov(tester, gov: gov);
      await tester.tap(find.text('Prop p_nv'));
      await tester.pumpAndSettle();
      expect(
          find.textContaining('need at least 10 reputation'),
          findsOneWidget);
    });

    testWidgets('create proposal dialog: dropdown change and cancel',
        (tester) async {
      final gov = _FakeGovernanceService([]);
      await pumpGov(tester, gov: gov);

      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pumpAndSettle();
      expect(find.text('Create Proposal'), findsOneWidget);

      // Exercise the dropdown onChanged.
      await tester.tap(find.byType(DropdownButtonFormField<ProposalType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Schema Change').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Create Proposal'), findsNothing);
    });
  });

  group('OnboardingScreen error branches', () {
    Future<void> pumpStep(WidgetTester tester, OnboardingStep step,
        {List<Override> overrides = const []}) async {
      await bigSurface(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          onboardingStepProvider.overrideWith((ref) => step),
          ...overrides,
        ],
        child: const MaterialApp(home: OnboardingScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('identity creation failure shows error snackbar',
        (tester) async {
      installSecureStore();
      await pumpStep(tester, OnboardingStep.identity, overrides: [
        identityServiceProvider.overrideWithValue(
            _FakeIdentityService(throwOnGenerate: true)),
      ]);
      await tester.tap(find.text('Create New Identity'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Error:'), findsOneWidget);
    });

    testWidgets('backup phrase failure shows error snackbar',
        (tester) async {
      installSecureStore();
      await pumpStep(tester, OnboardingStep.mnemonic, overrides: [
        mnemonicServiceProvider.overrideWithValue(
            _FakeMnemonicService(throwOnBackup: true)),
      ]);
      await tester.tap(find.text('Generate Backup Phrase'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Error:'), findsOneWidget);
    });

    testWidgets('biometric failure shows unavailable snackbar',
        (tester) async {
      installSecureStore();
      await pumpStep(tester, OnboardingStep.biometric, overrides: [
        biometricServiceProvider.overrideWithValue(
            _FakeBiometricService(throwOnAuth: true)),
      ]);
      await tester.tap(find.text('Enable Biometrics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Biometric not available'),
          findsOneWidget);
    });

    testWidgets('mnemonic import failure shows error snackbar',
        (tester) async {
      installSecureStore();
      await pumpStep(tester, OnboardingStep.identity, overrides: [
        mnemonicServiceProvider.overrideWithValue(
            _FakeMnemonicService(throwOnRecover: true)),
      ]);
      await tester.tap(find.text('Import Existing Identity'));
      await tester.pumpAndSettle();

      // Enter a plausible 24-word phrase into the recovery field.
      final field = find.byType(TextField);
      expect(field, findsWidgets);
      await tester.enterText(
          field.first, List.filled(24, 'anchor').join(' '));
      await tester.pump();
      await tester.tap(find.text('Import'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Error:'), findsWidgets);
    });
  });

  group('ProfileScreen error branches', () {
    Future<void> pumpProfile(WidgetTester tester,
        {List<Override> overrides = const []}) async {
      await bigSurface(tester);
      await tester.pumpWidget(ProviderScope(
        overrides: overrides,
        child: const MaterialApp(home: ProfileScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('identity creation error shows snackbar', (tester) async {
      installSecureStore();
      await pumpProfile(tester, overrides: [
        identityServiceProvider.overrideWithValue(
            _FakeIdentityService(throwOnGenerate: true)),
      ]);
      await tester.tap(find.text('Generate Identity'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Error:'), findsOneWidget);
    });

    testWidgets('recover dialog cancel pops without recovering',
        (tester) async {
      installSecureStore();
      await pumpProfile(tester, overrides: [
        identityServiceProvider
            .overrideWithValue(_FakeIdentityService()),
        mnemonicServiceProvider
            .overrideWithValue(_FakeMnemonicService()),
      ]);
      await tester.tap(find.text('Recover from Mnemonic'));
      await tester.pumpAndSettle();
      expect(find.text('Recover Identity'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Recover Identity'), findsNothing);
    });

    testWidgets('invalid mnemonic shows invalid-phrase snackbar',
        (tester) async {
      installSecureStore();
      await pumpProfile(tester, overrides: [
        identityServiceProvider
            .overrideWithValue(_FakeIdentityService()),
        mnemonicServiceProvider
            .overrideWithValue(_FakeMnemonicService()),
      ]);
      await tester.tap(find.text('Recover from Mnemonic'));
      await tester.pumpAndSettle();

      final field = find.byType(TextField);
      expect(field, findsWidgets);
      await tester.enterText(
          field.first, List.filled(24, 'anchor').join(' '));
      await tester.pump();
      await tester.tap(find.text('Recover'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Invalid mnemonic phrase'), findsOneWidget);
    });

    testWidgets('backup dialog error and copy-to-clipboard paths',
        (tester) async {
      installSecureStore();
      installClipboardMock();
      await pumpProfile(tester, overrides: [
        identityServiceProvider
            .overrideWithValue(_FakeIdentityService()),
        mnemonicServiceProvider
            .overrideWithValue(_FakeMnemonicService()),
      ]);
      await tester.tap(find.byTooltip('Backup Identity'));
      await tester.pumpAndSettle();
      // _mnemonic loaded from the fake — copy button visible.
      await tester.tap(find.widgetWithText(TextButton, 'Copy'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Phrase copied to clipboard'), findsOneWidget);
    });
  });
}
