import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/governance_service.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/ledger_service.dart';
import 'package:alexandria/ui/governance_screen.dart';

class _FakeIdentityService implements IdentityService {
  @override
  Future<AlexandriaIdentity?> getIdentity() async => AlexandriaIdentity(
        publicKey: Uint8List(32),
        privateKey: Uint8List(32),
        createdAt: DateTime(2025, 1, 1),
      );

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
  bool voteCalled = false;
  bool? lastApprove;
  bool createProposalCalled = false;

  final List<Proposal> _proposals = [
    Proposal(
      id: 'prop_test_1',
      type: ProposalType.gatewayAddition,
      title: 'Add Gateway Node EU-1',
      description: 'Deploy new gateway for European researchers',
      payload: {},
      proposerId: 'proposer_hex',
      created: DateTime(2026, 1, 1),
      deadline: DateTime(2026, 1, 15),
      status: ProposalStatus.active,
      signature: 'sig',
    ),
  ];

  @override
  List<Proposal> get proposals => _proposals;

  @override
  List<Proposal> get activeProposals => _proposals;

  @override
  Future<bool> canVote() async => true;

  @override
  Future<bool> canCreateProposal() async => true;

  @override
  Future<bool> vote({required String proposalId, required bool approve}) async {
    voteCalled = true;
    lastApprove = approve;
    return true;
  }

  @override
  Future<Proposal> createProposal({
    required ProposalType type,
    required String title,
    required String description,
    required Map<String, dynamic> payload,
    Duration? votingPeriod,
  }) async {
    createProposalCalled = true;
    final prop = Proposal(
      id: 'prop_new',
      type: type,
      title: title,
      description: description,
      payload: payload,
      proposerId: 'proposer_hex',
      created: DateTime.now(),
      deadline: DateTime.now().add(const Duration(days: 7)),
      status: ProposalStatus.active,
      signature: 'sig',
    );
    _proposals.add(prop);
    return prop;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GovernanceScreen Tests', () {
    testWidgets(
        'renders Parliament header, proposals, creates proposal, and votes',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeGov = _FakeGovernanceService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            identityServiceProvider.overrideWithValue(_FakeIdentityService()),
            ledgerServiceProvider.overrideWithValue(_FakeLedgerService()),
            governanceServiceProvider.overrideWithValue(fakeGov),
            canVoteProvider.overrideWith((ref) => true),
            canCreateProposalProvider.overrideWith((ref) => true),
          ],
          child: const MaterialApp(
            home: GovernanceScreen(),
          ),
        ),
      );

      expect(find.text('THE PARLIAMENT'), findsOneWidget);
      await tester.pumpAndSettle();

      expect(find.text('Add Gateway Node EU-1'), findsOneWidget);
      expect(find.text('ACTIVE'), findsWidgets);

      // Tap on proposal card to open detail sheet
      await tester.tap(find.text('Add Gateway Node EU-1'));
      await tester.pumpAndSettle();

      expect(find.text('APPROVE'), findsOneWidget);
      expect(find.text('REJECT'), findsOneWidget);

      // Vote APPROVE
      await tester.tap(find.text('APPROVE'));
      await tester.pumpAndSettle();

      expect(fakeGov.voteCalled, isTrue);
      expect(fakeGov.lastApprove, isTrue);
      expect(find.text('Vote recorded!'), findsOneWidget);

      // Open Create Proposal Dialog
      await tester.tap(find.byIcon(Icons.add_circle));
      await tester.pumpAndSettle();

      expect(find.text('Create Proposal'), findsOneWidget);
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'Emergency Cache Replication');
      await tester.enterText(
          textFields.at(1), 'Immediate replication of rare texts');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(fakeGov.createProposalCalled, isTrue);
    });
  });
}
