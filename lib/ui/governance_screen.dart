import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/governance_service.dart';
import 'theme/app_theme.dart';
import 'widgets/glass_card.dart';
import 'widgets/info_glass.dart';

/// Provider for checking if current user can vote
final canVoteProvider = FutureProvider<bool>((ref) async {
  final governance = ref.watch(governanceServiceProvider);
  return governance.canVote();
});

/// Provider for checking if current user can create proposals
final canCreateProposalProvider = FutureProvider<bool>((ref) async {
  final governance = ref.watch(governanceServiceProvider);
  return governance.canCreateProposal();
});

class GovernanceScreen extends ConsumerWidget {
  const GovernanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final governance = ref.watch(governanceServiceProvider);
    final proposals = governance.proposals;
    final activeProposals = governance.activeProposals;
    final canVoteAsync = ref.watch(canVoteProvider);
    final canCreateAsync = ref.watch(canCreateProposalProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Row(
          children: [
            Text('THE PARLIAMENT'),
            SizedBox(width: 8),
            InfoGlass(
              title: 'Governance',
              description: 'Participate in decentralized governance. '
                  'Create proposals, vote on changes, and shape the future of Alexandria.',
              small: true,
              color: AppTheme.primaryColor,
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        actions: [
          canCreateAsync.when(
            data: (canCreate) => canCreate
                ? IconButton(
                    icon: const Icon(
                      Icons.add_circle,
                      color: AppTheme.primaryColor,
                    ),
                    onPressed: () => _showCreateProposalDialog(context, ref),
                  )
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.primaryColor.withValues(alpha: 0.1),
              AppTheme.canvasColor,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stats Row
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _StatCard(
                      label: 'Active',
                      value: '${activeProposals.length}',
                      color: AppTheme.primaryColor,
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      label: 'Total',
                      value: '${proposals.length}',
                      color: AppTheme.secondaryColor,
                    ),
                    const Spacer(),
                    canVoteAsync.when(
                      data: (canVote) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: canVote
                              ? AppTheme.honorColor.withValues(alpha: 0.2)
                              : Colors.grey.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: canVote ? AppTheme.honorColor : Colors.grey,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              canVote ? Icons.how_to_vote : Icons.block,
                              size: 16,
                              color:
                                  canVote ? AppTheme.honorColor : Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              canVote ? 'ELIGIBLE' : 'NOT ELIGIBLE',
                              style: TextStyle(
                                color:
                                    canVote ? AppTheme.honorColor : Colors.grey,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms),

              // Proposals List
              Expanded(
                child: proposals.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.how_to_vote_outlined,
                              size: 64,
                              color: Colors.white24,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No proposals yet',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(color: Colors.white54),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Be the first to create a governance proposal',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: Colors.white38),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: proposals.length,
                        itemBuilder: (context, index) {
                          final proposal = proposals[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _ProposalCard(
                              proposal: proposal,
                              onTap: () => _showProposalDetail(
                                context,
                                ref,
                                proposal,
                              ),
                            ),
                          )
                              .animate()
                              .fadeIn(delay: (index * 100).ms)
                              .slideX(begin: 0.1);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateProposalDialog(BuildContext context, WidgetRef ref) {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    ProposalType selectedType = ProposalType.gatewayAddition;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text(
            'Create Proposal',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<ProposalType>(
                  initialValue: selectedType,
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Proposal Type',
                    labelStyle: const TextStyle(color: Colors.white54),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                  ),
                  items: ProposalType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(_proposalTypeName(type)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedType = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: titleController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Title',
                    labelStyle: const TextStyle(color: Colors.white54),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'Description',
                    labelStyle: const TextStyle(color: Colors.white54),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final governance = ref.read(governanceServiceProvider);
                await governance.createProposal(
                  type: selectedType,
                  title: titleController.text,
                  description: descController.text,
                  payload: {},
                );
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showProposalDetail(
    BuildContext context,
    WidgetRef ref,
    Proposal proposal,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ProposalDetailSheet(proposal: proposal),
    );
  }

  String _proposalTypeName(ProposalType type) {
    switch (type) {
      case ProposalType.schemaChange:
        return 'Schema Change';
      case ProposalType.gatewayAddition:
        return 'Gateway Addition';
      case ProposalType.priorityChange:
        return 'Priority Change';
      case ProposalType.weightAdjustment:
        return 'Weight Adjustment';
      case ProposalType.emergency:
        return 'Emergency';
    }
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color.withValues(alpha: 0.7),
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  final Proposal proposal;
  final VoidCallback onTap;

  const _ProposalCard({required this.proposal, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isActive = proposal.status == ProposalStatus.active;
    final statusColor = _getStatusColor(proposal.status);

    return GlassCard(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    proposal.status.name.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDate(proposal.deadline),
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              proposal.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              proposal.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 16),
            // Voting Progress
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: proposal.approvalPercentage,
                      backgroundColor: AppTheme.dangerColor.withValues(
                        alpha: 0.3,
                      ),
                      valueColor: AlwaysStoppedAnimation(
                        proposal.approvalPercentage >= 0.5
                            ? AppTheme.honorColor
                            : AppTheme.dangerColor,
                      ),
                      minHeight: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${(proposal.approvalPercentage * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: proposal.approvalPercentage >= 0.5
                        ? AppTheme.honorColor
                        : AppTheme.dangerColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.people, size: 14, color: Colors.white38),
                const SizedBox(width: 4),
                Text(
                  '${proposal.votes.length} votes',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const Spacer(),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'VOTE NOW',
                      style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(ProposalStatus status) {
    switch (status) {
      case ProposalStatus.active:
        return AppTheme.primaryColor;
      case ProposalStatus.approved:
      case ProposalStatus.executed:
        return AppTheme.honorColor;
      case ProposalStatus.rejected:
      case ProposalStatus.expired:
        return AppTheme.dangerColor;
      case ProposalStatus.draft:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    final diff = date.difference(DateTime.now());
    if (diff.isNegative) {
      return 'Ended';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}d left';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h left';
    } else {
      return '${diff.inMinutes}m left';
    }
  }
}

class _ProposalDetailSheet extends ConsumerWidget {
  final Proposal proposal;

  const _ProposalDetailSheet({required this.proposal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canVoteAsync = ref.watch(canVoteProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E293B),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                proposal.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                proposal.description,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 24),
              // Voting Section
              if (proposal.status == ProposalStatus.active)
                canVoteAsync.when(
                  data: (canVote) => canVote
                      ? Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _vote(context, ref, true),
                                icon: const Icon(Icons.thumb_up),
                                label: const Text('APPROVE'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.honorColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _vote(context, ref, false),
                                icon: const Icon(Icons.thumb_down),
                                label: const Text('REJECT'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.dangerColor,
                                  side: const BorderSide(
                                    color: AppTheme.dangerColor,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.white54),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'You need at least 10 reputation and 30 days in the network to vote.',
                                  style: TextStyle(color: Colors.white54),
                                ),
                              ),
                            ],
                          ),
                        ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              const SizedBox(height: 24),
              // Vote Breakdown
              const Text(
                'VOTE BREAKDOWN',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _VoteBar(
                    label: 'Approve',
                    value: proposal.approvalWeight,
                    total: proposal.totalVoteWeight,
                    color: AppTheme.honorColor,
                  ),
                  const SizedBox(width: 16),
                  _VoteBar(
                    label: 'Reject',
                    value: proposal.rejectionWeight,
                    total: proposal.totalVoteWeight,
                    color: AppTheme.dangerColor,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _vote(BuildContext context, WidgetRef ref, bool approve) async {
    final governance = ref.read(governanceServiceProvider);
    final success = await governance.vote(
      proposalId: proposal.id,
      approve: approve,
    );
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Vote recorded!' : 'Failed to vote'),
          backgroundColor: success ? AppTheme.honorColor : AppTheme.dangerColor,
        ),
      );
    }
  }
}

class _VoteBar extends StatelessWidget {
  final String label;
  final double value;
  final double total;
  final Color color;

  const _VoteBar({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final percentage = total > 0 ? value / total : 0.0;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(color: color)),
              Text(
                '${(percentage * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percentage,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }
}
