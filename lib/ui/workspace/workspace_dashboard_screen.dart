import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/workspace_providers.dart';
import '../../services/agent/alexandria_mcp_server.dart';
import '../../services/credits/credit_service.dart';
import '../../services/credits/poch_service.dart';
import '../../services/seed/starter_seed_service.dart';
import '../agent/agent_network_dialog.dart';
import '../common/governance_badge.dart';
import '../credits/credit_wallet_dialog.dart';
import '../credits/sponsorship_card.dart';
import '../onboarding/first_run_wizard_dialog.dart';
import '../plugins/doi_harvester_dialog.dart';
import '../theme/app_theme.dart';
import 'annotations_notes_screen.dart';
import 'ingestion_pipeline_screen.dart';
import 'metadata_editor_screen.dart';

class WorkspaceDashboardScreen extends ConsumerStatefulWidget {
  const WorkspaceDashboardScreen({super.key});

  @override
  ConsumerState<WorkspaceDashboardScreen> createState() =>
      _WorkspaceDashboardScreenState();
}

class _WorkspaceDashboardScreenState
    extends ConsumerState<WorkspaceDashboardScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showQuestCard = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isDoi(String text) {
    final trimmed = text.trim();
    return trimmed.startsWith('10.') ||
        trimmed.toLowerCase().startsWith('doi:10.');
  }

  @override
  Widget build(BuildContext context) {
    final workspacesAsync = ref.watch(activeWorkspacesProvider);
    final activityFeedAsync = ref.watch(activityFeedProvider);
    final creditBalance = ref.watch(creditBalanceProvider);
    final pochMetrics = ref.watch(pochMetricsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(
              'Workspace',
              style: GoogleFonts.newsreader(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textColor,
              ),
            ),
            const SizedBox(width: 12),
            const GovernancePillRow(),
          ],
        ),
        centerTitle: false,
        actions: [
          // Onboarding Tour Action
          IconButton(
            icon: const Icon(Icons.auto_stories_outlined,
                color: AppTheme.primaryAccent),
            tooltip: 'Launch Onboarding & Alexandria Core Team Tour',
            onPressed: () => FirstRunWizardDialog.show(context),
          ),
          // Wallet Quick Balance Action
          InkWell(
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => const CreditWalletDialog(),
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppTheme.primaryAccent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet,
                      size: 15, color: AppTheme.primaryAccent),
                  const SizedBox(width: 6),
                  Text(
                    '${creditBalance.toStringAsFixed(0)} ℭ',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main Content Area
          Expanded(
            flex: 3,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Universal Omnibar
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _isDoi(_searchQuery)
                            ? AppTheme.primaryAccent
                            : theme.dividerColor.withValues(alpha: 0.6),
                        width: _isDoi(_searchQuery) ? 1.5 : 1.0,
                      ),
                    ),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          _isDoi(_searchQuery)
                              ? Icons.science_outlined
                              : Icons.search,
                          color: _isDoi(_searchQuery)
                              ? AppTheme.primaryAccent
                              : AppTheme.secondaryColor,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: (val) =>
                                setState(() => _searchQuery = val),
                            style: GoogleFonts.inter(
                                fontSize: 13, color: AppTheme.textColor),
                            decoration: const InputDecoration(
                              hintText:
                                  'Search library by title, CID, or paste scientific DOI (e.g. 10.1038/s41586-020-2012-7)...',
                              hintStyle: TextStyle(
                                  fontSize: 12, color: AppTheme.secondaryColor),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear,
                                size: 16, color: AppTheme.secondaryColor),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                        if (_isDoi(_searchQuery))
                          FilledButton.icon(
                            onPressed: () {
                              final doi = _searchController.text.trim();
                              showDialog(
                                context: context,
                                builder: (context) =>
                                    DoiHarvesterDialog(initialDoi: doi),
                              );
                            },
                            icon: const Icon(Icons.download, size: 14),
                            label: const Text('Harvest DOI (+20 ℭ)',
                                style: TextStyle(fontSize: 11)),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.primaryAccent,
                              foregroundColor: AppTheme.canvasColor,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Actions & Section Header
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: 12,
                    children: [
                      Text(
                        'Ongoing Tasks',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const IngestionPipelineScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.cloud_upload_outlined,
                                size: 16),
                            label: const Text('New Import',
                                style: TextStyle(fontSize: 12)),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const AnnotationsNotesScreen(),
                                ),
                              );
                            },
                            icon:
                                const Icon(Icons.edit_note_outlined, size: 16),
                            label: const Text('New Note',
                                style: TextStyle(fontSize: 12)),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const MetadataEditorScreen(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.edit_document, size: 16),
                            label: const Text('Metadata',
                                style: TextStyle(fontSize: 12)),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) =>
                                    const DoiHarvesterDialog(),
                              );
                            },
                            icon: const Icon(Icons.science_outlined, size: 16),
                            label: const Text('Harvest DOI',
                                style: TextStyle(fontSize: 12)),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) =>
                                    const CreditWalletDialog(),
                              );
                            },
                            icon: const Icon(
                                Icons.account_balance_wallet_outlined,
                                size: 16),
                            label: const Text('Wallet',
                                style: TextStyle(fontSize: 12)),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => AgentNetworkDialog.show(context),
                            icon:
                                const Icon(Icons.smart_toy_outlined, size: 16),
                            label: const Text('AI Agents',
                                style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // First-Run Preservation Quest Card (dismissible)
                  if (_showQuestCard)
                    _buildQuestChecklistCard(pochMetrics.isCompliant),

                  const SponsorshipCard(
                    category: 'technology',
                    tags: ['preservation', 'open-knowledge'],
                  ),
                  const SizedBox(height: 12),

                  // Workspaces List or Rich Empty State
                  Expanded(
                    child: workspacesAsync.when(
                      data: (workspaces) {
                        final filtered = _searchQuery.isEmpty
                            ? workspaces
                            : workspaces.where((w) {
                                return w.name
                                    .toLowerCase()
                                    .contains(_searchQuery.toLowerCase());
                              }).toList();

                        if (filtered.isEmpty) {
                          return _buildEmptyStateOrNoResults(
                              workspaces.isEmpty);
                        }
                        return ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final workspace = filtered[index];
                            return Card(
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 12.0),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color:
                                      theme.dividerColor.withValues(alpha: 0.5),
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                  vertical: 8.0,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor:
                                      theme.colorScheme.primaryContainer,
                                  foregroundColor:
                                      theme.colorScheme.onPrimaryContainer,
                                  child: const Icon(Icons.work_outline),
                                ),
                                title: Text(
                                  workspace.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    '${workspace.pendingTasks} pending tasks',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.chevron_right),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            AnnotationsNotesScreen(
                                                docId: workspace.id),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                        );
                      },
                      loading: () => const Center(
                        child: CircularProgressIndicator(strokeWidth: 2.0),
                      ),
                      error: (err, stack) => Center(
                        child: Text(
                          'Error loading workspaces: $err',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Contextual Side Panel: Activity Feed & Bounty Telemetry
          Container(
            width: 320,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: theme.dividerColor,
                ),
              ),
              color: theme.colorScheme.surface,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Swarm Telemetry',
                          style: GoogleFonts.newsreader(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.honorColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Online',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.honorColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.canvasColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTelemetryRow(
                            'PoCH Compliance',
                            pochMetrics.isCompliant ? '100% (1.0x)' : 'Pending',
                            AppTheme.honorColor),
                        const SizedBox(height: 6),
                        _buildTelemetryRow(
                            'Cached Storage',
                            '${(pochMetrics.allocatedStorageBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                            AppTheme.textColor),
                        const SizedBox(height: 6),
                        _buildTelemetryRow('Swarm Peers', '12 Connected',
                            AppTheme.primaryAccent),
                        const SizedBox(height: 6),
                        _buildTelemetryRow(
                            'MCP Tools Active',
                            '${ref.watch(alexandriaMcpServerProvider).listTools().length} Registered',
                            const Color(0xFFA78BFA)),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 24, color: Colors.white10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Text(
                    'Activity Feed',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: activityFeedAsync.when(
                    data: (activityFeed) {
                      if (activityFeed.isEmpty) {
                        return const Center(
                            child: Text('No recent activity.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.secondaryColor)));
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        itemCount: activityFeed.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          final activity = activityFeed[index];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      activity.title,
                                      style:
                                          theme.textTheme.titleSmall?.copyWith(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.only(left: 18.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      activity.description,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        fontSize: 11,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${activity.timestamp.hour.toString().padLeft(2, '0')}:${activity.timestamp.minute.toString().padLeft(2, '0')}',
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        fontSize: 10,
                                        color: theme
                                            .colorScheme.onSurfaceVariant
                                            .withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                    loading: () => const Center(
                      child: CircularProgressIndicator(strokeWidth: 2.0),
                    ),
                    error: (err, stack) => Center(
                      child: Text(
                        'Error loading activity: $err',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetryRow(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style:
                GoogleFonts.inter(fontSize: 11, color: AppTheme.secondaryColor),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: GoogleFonts.jetBrainsMono(
              fontSize: 11, fontWeight: FontWeight.bold, color: valueColor),
        ),
      ],
    );
  }

  Widget _buildQuestChecklistCard(bool isCompliant) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppTheme.primaryAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.stars,
                        color: AppTheme.primaryAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'First-Run Preservation Quests',
                        style: GoogleFonts.newsreader(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close,
                    size: 16, color: AppTheme.secondaryColor),
                onPressed: () => setState(() => _showQuestCard = false),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildQuestItem(
              true, 'Claim 100 ℭ Genesis Grant', 'Active in wallet balance'),
          _buildQuestItem(
              isCompliant,
              'Allocate 1GB Storage Baseline',
              isCompliant
                  ? 'PoCH baseline verified'
                  : 'Slide allocation to 1GB in Onboarding'),
          _buildQuestItem(false, 'Harvest a scientific paper via DOI',
              'Earn +20 ℭ verification reward'),
          _buildQuestItem(false, 'Connect an AI Agent or turn on Steward',
              'Earn +25 ℭ autonomous stewardship'),
        ],
      ),
    );
  }

  Widget _buildQuestItem(bool done, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: done ? AppTheme.honorColor : AppTheme.secondaryColor,
            size: 14,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style:
                    GoogleFonts.inter(fontSize: 11, color: AppTheme.textColor),
                children: [
                  TextSpan(
                    text: '$title — ',
                    style: TextStyle(
                      fontWeight: done ? FontWeight.bold : FontWeight.normal,
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  TextSpan(
                    text: subtitle,
                    style: TextStyle(
                        color: done
                            ? AppTheme.secondaryColor
                            : AppTheme.primaryAccent),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyStateOrNoResults(bool isEmptyArchive) {
    if (!isEmptyArchive) {
      return const Center(child: Text('No matching documents found.'));
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: AppTheme.primaryAccent.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_stories,
                    color: AppTheme.primaryAccent, size: 32),
              ),
              const SizedBox(height: 14),
              Text(
                'No workspaces yet.',
                style: GoogleFonts.newsreader(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textColor),
              ),
              const SizedBox(height: 8),
              Text(
                'Welcome to Alexandria Commons. Your node is initialized and ready to preserve human knowledge under US §108 statutory safe harbor.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                    fontSize: 13, height: 1.5, color: AppTheme.secondaryColor),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => FirstRunWizardDialog.show(context),
                    icon: const Icon(Icons.explore, size: 16),
                    label: const Text('Launch Onboarding Tour'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryAccent,
                      foregroundColor: AppTheme.canvasColor,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final seedService = ref.read(starterSeedServiceProvider);
                      await seedService
                          .ingestSeedPack('open-science-landmarks');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Ingested Landmark Open Science collection!'),
                            backgroundColor: AppTheme.honorColor,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.science, size: 16),
                    label: const Text('1-Click Landmark Science Pack'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
