import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/agent/agent_steward_service.dart';
import '../../services/agent/alexandria_mcp_server.dart';
import '../../services/agent/moltbook_service.dart';
import '../common/governance_badge.dart';
import '../theme/app_theme.dart';
import 'mcp_config_export_dialog.dart';

/// Interactive modal for inspecting the Autonomous Agent Network, Moltbook feeds, and MCP tools (ALX-006)
class AgentNetworkDialog extends ConsumerStatefulWidget {
  const AgentNetworkDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => const AgentNetworkDialog(),
    );
  }

  @override
  ConsumerState<AgentNetworkDialog> createState() => _AgentNetworkDialogState();
}

class _AgentNetworkDialogState extends ConsumerState<AgentNetworkDialog> {
  String _selectedSubmolt = 'alexandria-bounties';
  final _bountyCidController = TextEditingController();
  final _bountyTitleController = TextEditingController();
  final _bountyCreditsController = TextEditingController(text: '20.0');

  @override
  void dispose() {
    _bountyCidController.dispose();
    _bountyTitleController.dispose();
    _bountyCreditsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final moltbookService = ref.watch(moltbookServiceProvider);
    final stewardService = ref.watch(agentStewardServiceProvider);
    final mcpServer = ref.watch(alexandriaMcpServerProvider);

    final posts = moltbookService.getPostsForSubmolt(_selectedSubmolt);
    final width = MediaQuery.of(context).size.width.clamp(400.0, 750.0);
    final height = MediaQuery.of(context).size.height * 0.88;

    return Dialog(
      backgroundColor: AppTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.white12),
      ),
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purpleAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.smart_toy, color: Colors.purpleAccent, size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Autonomous Agent Network (ALX-006)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Moltbook Social Transport • Beacon v2 Envelopes • MCP Server',
                        style: TextStyle(fontSize: 11, color: AppTheme.secondaryColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const GovernancePillRow(),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 20, color: AppTheme.secondaryColor),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Colors.white10),
            const SizedBox(height: 14),

            // Scrollable Body
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section 1: Autonomous Steward Status Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: stewardService.isRunning
                              ? Colors.greenAccent.withValues(alpha: 0.3)
                              : Colors.white10,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 18,
                                color: stewardService.isRunning
                                    ? Colors.greenAccent
                                    : AppTheme.secondaryColor,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Autonomous Preservation Steward',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Material(
                                type: MaterialType.transparency,
                                child: Switch(
                                  value: stewardService.isRunning,
                                  activeThumbColor: Colors.greenAccent,
                                  activeTrackColor: Colors.greenAccent.withValues(alpha: 0.4),
                                  onChanged: (val) {
                                    if (val) {
                                      stewardService.startSteward();
                                    } else {
                                      stewardService.stopSteward();
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Self-governed agent loop: monitors node health, restores PoCH score, performs Cauchy RS compute, and fulfills endangered preservation bounties.',
                            style: TextStyle(fontSize: 11, color: AppTheme.secondaryColor),
                          ),
                          const SizedBox(height: 12),

                          // Steward Metrics Row
                          Row(
                            children: [
                              _buildMetricPill(
                                label: 'Bounties Fulfilled',
                                value: '${stewardService.totalBountiesClaimed}',
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 8),
                              _buildMetricPill(
                                label: 'Compute Cycles',
                                value: '${stewardService.totalComputeCyclesExecuted}',
                                color: Colors.cyanAccent,
                              ),
                              const SizedBox(width: 8),
                              _buildMetricPill(
                                label: 'Credits Earned',
                                value: '+${stewardService.totalCreditsEarned.toStringAsFixed(1)} ℭ',
                                color: Colors.greenAccent,
                              ),
                            ],
                          ),

                          if (stewardService.activityLog.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Text(
                              'Recent Agent Activity:',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textColor),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black26,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final log in stewardService.activityLog.take(3))
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 2),
                                      child: Text(
                                        log,
                                        style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppTheme.secondaryColor),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Section 2: Beacon v2 Cryptographic Identity
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.verified_user_outlined, size: 20, color: Colors.cyanAccent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Beacon v2 Agent Identity (Ed25519)',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textColor),
                                ),
                                Text(
                                  'Agent ID: ${moltbookService.agentId.isEmpty ? "Initializing..." : moltbookService.agentId}',
                                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.cyanAccent),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: moltbookService.agentId));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Agent ID copied to clipboard')),
                              );
                            },
                            icon: const Icon(Icons.copy, size: 14),
                            label: const Text('Copy', style: TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Section 3: Moltbook Social Feed Header & Submolts
                    Row(
                      children: [
                        const Icon(Icons.forum_outlined, size: 18, color: Colors.purpleAccent),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Moltbook Agent Social Transport',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textColor),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _showCreateBountyDialog(context),
                          icon: const Icon(Icons.add, size: 14),
                          label: const Text('Post Bounty', style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purpleAccent.withValues(alpha: 0.2),
                            foregroundColor: Colors.purpleAccent,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Submolt Filter Chips
                    Wrap(
                      spacing: 8,
                      children: [
                        _buildSubmoltChip('alexandria-bounties', 'm/alexandria-bounties'),
                        _buildSubmoltChip('open-science', 'm/open-science'),
                        _buildSubmoltChip('preservation-alerts', 'm/preservation-alerts'),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Posts List
                    if (posts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(
                          child: Text('No posts found in this submolt.', style: TextStyle(color: AppTheme.secondaryColor)),
                        ),
                      )
                    else
                      Column(
                        children: [
                          for (final post in posts) ...[
                            _buildPostCard(context, post, moltbookService),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ),
                    const SizedBox(height: 16),

                    // Section 4: Alexandria Model Context Protocol (MCP) Server
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.terminal, size: 18, color: AppTheme.primaryAccent),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Alexandria MCP Tool Suite (${mcpServer.listTools().length} Registered Tools)',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textColor),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Chip(
                                label: Text('stdio / JSON-RPC 2.0', style: TextStyle(fontSize: 10, color: AppTheme.primaryAccent)),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: () => McpConfigExportDialog.show(context, mcpServer.listTools()),
                                icon: const Icon(Icons.file_download_outlined, size: 14),
                                label: const Text('Export Config', style: TextStyle(fontSize: 10)),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  visualDensity: VisualDensity.compact,
                                  side: const BorderSide(color: AppTheme.primaryAccent, width: 0.8),
                                  foregroundColor: AppTheme.primaryAccent,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final tool in mcpServer.listTools())
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Text(
                                    tool['name'] as String,
                                    style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppTheme.textColor),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmoltChip(String submoltKey, String label) {
    final isSelected = _selectedSubmolt == submoltKey;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : AppTheme.secondaryColor)),
      selected: isSelected,
      selectedColor: Colors.purpleAccent.withValues(alpha: 0.3),
      backgroundColor: Colors.white.withValues(alpha: 0.04),
      side: BorderSide(color: isSelected ? Colors.purpleAccent : Colors.white12),
      visualDensity: VisualDensity.compact,
      onSelected: (_) => setState(() => _selectedSubmolt = submoltKey),
    );
  }

  Widget _buildMetricPill({
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.secondaryColor), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildPostCard(BuildContext context, dynamic post, MoltbookService service) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  post.title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textColor),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (post.isBeaconVerified)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield, size: 11, color: Colors.greenAccent),
                      SizedBox(width: 4),
                      Text('Beacon v2', style: TextStyle(fontSize: 9, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Posted by ${post.authorAgentId} • ${post.submolt}',
            style: const TextStyle(fontSize: 10, color: AppTheme.secondaryColor),
          ),
          const SizedBox(height: 8),
          Text(
            post.content,
            style: const TextStyle(fontSize: 12, color: AppTheme.textColor),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              InkWell(
                onTap: () => service.upvotePost(post.id),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_upward, size: 14, color: Colors.purpleAccent),
                      const SizedBox(width: 4),
                      Text('${post.upvotes}', style: const TextStyle(fontSize: 11, color: Colors.purpleAccent, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (post.submolt == 'alexandria-bounties')
                TextButton(
                  onPressed: () {
                    // Claim bounty
                    final bounties = service.activeBounties;
                    if (bounties.isNotEmpty) {
                      service.claimBounty(bounties.first.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Bounty claimed! Replicating Cauchy RS shards.')),
                      );
                    }
                  },
                  child: const Text('Claim Bounty', style: TextStyle(fontSize: 11, color: AppTheme.primaryAccent)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showCreateBountyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('Post Preservation Bounty (Moltbook)', style: TextStyle(fontSize: 14, color: AppTheme.textColor)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _bountyTitleController,
              decoration: const InputDecoration(labelText: 'Title / Paper Name', isDense: true),
              style: const TextStyle(fontSize: 12, color: AppTheme.textColor),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _bountyCidController,
              decoration: const InputDecoration(labelText: 'Endangered CIDv1', isDense: true),
              style: const TextStyle(fontSize: 12, color: AppTheme.textColor),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _bountyCreditsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Offered Credits (ℭ)', isDense: true),
              style: const TextStyle(fontSize: 12, color: AppTheme.textColor),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.secondaryColor)),
          ),
          ElevatedButton(
            onPressed: () async {
              final cid = _bountyCidController.text.trim();
              final title = _bountyTitleController.text.trim();
              final credits = double.tryParse(_bountyCreditsController.text.trim()) ?? 20.0;

              if (cid.isNotEmpty && title.isNotEmpty) {
                try {
                  final moltbook = ref.read(moltbookServiceProvider);
                  await moltbook.postPreservationBounty(
                    cid: cid,
                    title: title,
                    offeredCredits: credits,
                    force: true,
                  );
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Bounty "$title" broadcast to Moltbook!')),
                    );
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              }
            },
            child: const Text('Publish Bounty'),
          ),
        ],
      ),
    );
  }
}
