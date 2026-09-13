import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/credits/credit_service.dart';
import '../../services/credits/poch_service.dart';
import '../../services/seed/starter_seed_service.dart';
import '../common/governance_badge.dart';
import '../theme/app_theme.dart';

/// Interactive First-Run Onboarding Wizard for new Alexandria users and nodes
class FirstRunWizardDialog extends ConsumerStatefulWidget {
  final VoidCallback? onComplete;

  const FirstRunWizardDialog({super.key, this.onComplete});

  static Future<void> show(BuildContext context, {VoidCallback? onComplete}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => FirstRunWizardDialog(onComplete: onComplete),
    );
  }

  @override
  ConsumerState<FirstRunWizardDialog> createState() => _FirstRunWizardDialogState();
}

class _FirstRunWizardDialogState extends ConsumerState<FirstRunWizardDialog> {
  int _currentStep = 0;
  double _storageAllocationGb = 1.0;
  String _selectedSeedPackId = 'open-science-landmarks';
  bool _isIngesting = false;
  String? _statusMessage;

  final int _totalSteps = 4;

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
    } else {
      _completeOnboarding();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  Future<void> _completeOnboarding() async {
    setState(() {
      _isIngesting = true;
      _statusMessage = 'Allocating Common Heritage cache & ingesting starter archive...';
    });

    try {
      // 1. Configure PoCH Storage Cache
      final pochService = ref.read(pochServiceProvider);
      // Allocate the storage baseline
      pochService.recordStorageAllocation((_storageAllocationGb * 1024 * 1024 * 1024).toInt());

      // 2. Ingest Selected Starter Pack
      if (_selectedSeedPackId.isNotEmpty) {
        final seedService = ref.read(starterSeedServiceProvider);
        await seedService.ingestSeedPack(_selectedSeedPackId);
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onComplete?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Welcome to Alexandria! Your node is active with 100 ℭ and Starter Commons.'),
            backgroundColor: AppTheme.honorColor,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isIngesting = false;
          _statusMessage = 'Setup error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.primaryAccent, width: 1.2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Progress Indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(Icons.auto_stories, color: AppTheme.primaryAccent, size: 16),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Alexandria Onboarding',
                        style: GoogleFonts.newsreader(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textColor,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: List.generate(_totalSteps, (index) {
                      final isActive = index == _currentStep;
                      final isPassed = index < _currentStep;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: isActive ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppTheme.primaryAccent
                              : (isPassed ? AppTheme.honorColor : AppTheme.secondaryColor.withValues(alpha: 0.3)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Step Content Area
              Expanded(
                child: _isIngesting
                    ? _buildIngestingState()
                    : IndexedStack(
                        index: _currentStep,
                        children: [
                          _buildStep0Welcome(),
                          _buildStep1GenesisGrant(),
                          _buildStep2StorageBaseline(),
                          _buildStep3StarterPacks(),
                        ],
                      ),
              ),

              const SizedBox(height: 20),
              // Navigation Controls
              if (!_isIngesting)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (_currentStep > 0)
                      OutlinedButton.icon(
                        onPressed: _prevStep,
                        icon: const Icon(Icons.arrow_back, size: 16),
                        label: const Text('Back'),
                      )
                    else
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Skip Tour', style: TextStyle(color: AppTheme.secondaryColor)),
                      ),
                    FilledButton.icon(
                      onPressed: _nextStep,
                      icon: Icon(
                        _currentStep == _totalSteps - 1 ? Icons.check : Icons.arrow_forward,
                        size: 16,
                      ),
                      label: Text(_currentStep == _totalSteps - 1 ? 'Launch Archive' : 'Continue'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryAccent,
                        foregroundColor: AppTheme.canvasColor,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Step 0: Welcome & The Governance Review
  Widget _buildStep0Welcome() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Decentralized Archival Infrastructure & Common Heritage',
            style: GoogleFonts.newsreader(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Alexandria is an immutable, peer-to-peer preservation network operating under the statutory non-profit safe harbor of 17 U.S.C. § 108, 17 U.S.C. § 512, and the Marrakesh Treaty. Governed under the Governance review board architectural standard.',
            style: GoogleFonts.inter(fontSize: 13, height: 1.6, color: AppTheme.textColor),
          ),
          const SizedBox(height: 16),
          const GovernanceBanner(),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.canvasColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user_outlined, color: AppTheme.honorColor, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Zero corporate trackers, zero speculative tokens, and zero proprietary lock-in. Content is verified by cryptographic multihashes (CIDv1).',
                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.secondaryColor),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Step 1: Genesis 100 ℭ Grant
  Widget _buildStep1GenesisGrant() {
    final balance = ref.watch(creditBalanceProvider);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your Common Heritage Grant',
            style: GoogleFonts.newsreader(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.textColor),
          ),
          const SizedBox(height: 8),
          Text(
            'Every new node receives an initial allocation of Archival Credits (ℭ) to query the swarm, harvest papers, and request remote replication.',
            style: GoogleFonts.inter(fontSize: 14, height: 1.6, color: AppTheme.textColor),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryAccent.withValues(alpha: 0.15),
                  AppTheme.surfaceColor,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.primaryAccent, width: 1.2),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryAccent.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.account_balance_wallet, color: AppTheme.primaryAccent, size: 32),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Current Available Balance', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.secondaryColor)),
                    Text(
                      '${balance.toStringAsFixed(1)} ℭ',
                      style: GoogleFonts.jetBrainsMono(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent),
                    ),
                    Text('≈ ${(balance * 10).toInt()} Sats Parity (1 ℭ = 10 Sats)', style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.honorColor)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('How You Earn More Credits:', style: GoogleFonts.newsreader(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textColor)),
          const SizedBox(height: 8),
          _buildPillarTile(Icons.storage_outlined, 'Storage Pillar', 'Seed content & answer Proof of Retrievability (PoR) challenges.'),
          _buildPillarTile(Icons.memory_outlined, 'Compute Pillar', 'Run Cauchy Reed-Solomon parity repair & OCR processing.'),
          _buildPillarTile(Icons.verified_outlined, 'Verification Pillar', 'Audit DOIs against Crossref/OpenAlex and vote on metadata.'),
          _buildPillarTile(Icons.campaign_outlined, 'Opt-in Sponsorships', 'Earn an 85% kickback viewing ethical, privacy-preserving institutional ads.'),
        ],
      ),
    );
  }

  Widget _buildPillarTile(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textColor),
                children: [
                  TextSpan(text: '$title: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: desc, style: const TextStyle(color: AppTheme.secondaryColor)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Step 2: Storage Baseline Allocation
  Widget _buildStep2StorageBaseline() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Proof of Common Heritage (PoCH)',
            style: GoogleFonts.newsreader(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.textColor),
          ),
          const SizedBox(height: 8),
          Text(
            'To maintain an un-censorable library, every node contributes a mandatory minimum baseline of 1.0 GB local storage cache. Nodes with PoCH ≥ 1.0 enjoy unthrottled maximum download speeds.',
            style: GoogleFonts.inter(fontSize: 14, height: 1.6, color: AppTheme.textColor),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.canvasColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Node Storage Cache Limit:', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textColor)),
                    Text(
                      '${_storageAllocationGb.toStringAsFixed(1)} GB',
                      style: GoogleFonts.jetBrainsMono(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent),
                    ),
                  ],
                ),
                Slider(
                  value: _storageAllocationGb,
                  min: 0.5,
                  max: 10.0,
                  divisions: 19,
                  activeColor: AppTheme.primaryAccent,
                  inactiveColor: AppTheme.secondaryColor.withValues(alpha: 0.3),
                  onChanged: (val) {
                    setState(() => _storageAllocationGb = val);
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('0.5 GB', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppTheme.secondaryColor)),
                    Text('1.0 GB Target', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppTheme.honorColor, fontWeight: FontWeight.bold)),
                    Text('10.0 GB', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: AppTheme.secondaryColor)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.speed, color: AppTheme.honorColor, size: 18),
              const SizedBox(width: 8),
              Text(
                'QoS Status: 1.0x Full Line Speed (Unthrottled)',
                style: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.honorColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Step 3: Starter Seed Packs
  Widget _buildStep3StarterPacks() {
    final seedService = ref.read(starterSeedServiceProvider);
    final packs = seedService.getAvailableSeedPacks();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '1-Click Starter Archive Packs',
            style: GoogleFonts.newsreader(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.textColor),
          ),
          const SizedBox(height: 8),
          Text(
            'Start with a pre-indexed collection of public-domain and open-access landmark works so your library is immediately alive.',
            style: GoogleFonts.inter(fontSize: 14, height: 1.6, color: AppTheme.textColor),
          ),
          const SizedBox(height: 14),
          ...packs.map((pack) {
            final isSelected = _selectedSeedPackId == pack.id;
            return InkWell(
              onTap: () => setState(() => _selectedSeedPackId = pack.id),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primaryAccent.withValues(alpha: 0.12) : AppTheme.canvasColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? AppTheme.primaryAccent : AppTheme.secondaryColor.withValues(alpha: 0.2),
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: isSelected ? AppTheme.primaryAccent : AppTheme.secondaryColor,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  pack.name,
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.surfaceColor,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${pack.documents.length} Works • ${pack.estimatedSizeMb} MB',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10,
                                    color: AppTheme.primaryAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            pack.description,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppTheme.secondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => setState(() => _selectedSeedPackId = ''),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _selectedSeedPackId.isEmpty ? AppTheme.primaryAccent.withValues(alpha: 0.12) : AppTheme.canvasColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedSeedPackId.isEmpty ? AppTheme.primaryAccent : AppTheme.secondaryColor.withValues(alpha: 0.2),
                  width: _selectedSeedPackId.isEmpty ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _selectedSeedPackId.isEmpty ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: _selectedSeedPackId.isEmpty ? AppTheme.primaryAccent : AppTheme.secondaryColor,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Clean Slate (Start Empty)',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textColor,
                          ),
                        ),
                        Text(
                          'Begin with an empty library and ingest documents or harvest DOIs manually.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppTheme.secondaryColor,
                          ),
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
    );
  }

  Widget _buildIngestingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppTheme.primaryAccent),
          const SizedBox(height: 20),
          Text(
            'Initializing Alexandria Commons...',
            style: GoogleFonts.newsreader(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textColor),
          ),
          const SizedBox(height: 8),
          Text(
            _statusMessage ?? 'Please wait...',
            style: GoogleFonts.jetBrainsMono(fontSize: 12, color: AppTheme.secondaryColor),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
