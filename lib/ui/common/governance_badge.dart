import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// The Five Governance Voices
enum GovernanceVoice {
  coherence(
    name: 'Coherence',
    color: Color(0xFF38BDF8), // Cyan
    icon: Icons.hub_outlined,
    mandate: 'CIDv1 Standard & Ontological Harmony',
    description:
        'Enforces universal content addressing, multihash invariants, and schema non-contradiction across all archive collections.',
  ),
  capability(
    name: 'Capability',
    color: AppTheme.primaryAccent, // Parchment Gold (0xFFD4A373)
    icon: Icons.bolt_outlined,
    mandate: 'Universal Harvesting & Cauchy Compute',
    description:
        'Empowers nodes and AI agents to ingest landmark DOIs, compute Cauchy Reed-Solomon GF(2^8) parity shards, and verify retrievability.',
  ),
  safety(
    name: 'Safety',
    color: AppTheme.honorColor, // Emerald (0xFF4A7C59)
    icon: Icons.shield_outlined,
    mandate: 'US §108 Immunity & Zero-PII Privacy',
    description:
        'Preserves non-profit safe harbor under US Copyright Act §108, DMCA 512, with zero telemetry and client-side attention verification.',
  ),
  efficiency(
    name: 'Efficiency',
    color: Color(0xFFA78BFA), // Lavender / Violet
    icon: Icons.speed_outlined,
    mandate: 'Zero-Gas Ledger & Fair-Queue QoS',
    description:
        'Maintains sub-millisecond local contextual matching, lightweight Merkle hash-chains, and logarithmic bandwidth QoS scheduling.',
  ),
  evolution(
    name: 'Evolution',
    color: Color(0xFFFB7185), // Rose Coral
    icon: Icons.all_inclusive,
    mandate: 'Moltbook Agent Swarm & Sovereign Rails',
    description:
        'Connects autonomous AI agents over Moltbook (Beacon v2) with non-custodial Cashu Chaumian e-cash and live Bitcoin Lightning payouts.',
  );

  final String name;
  final Color color;
  final IconData icon;
  final String mandate;
  final String description;

  const GovernanceVoice({
    required this.name,
    required this.color,
    required this.icon,
    required this.mandate,
    required this.description,
  });
}

/// Comprehensive banner highlighting protocol governance and ratification
class GovernanceBanner extends StatelessWidget {
  final bool compact;
  final VoidCallback? onTap;

  const GovernanceBanner({
    super.key,
    this.compact = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryAccent.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.all(compact ? 12.0 : 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: AppTheme.primaryAccent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alexandria Protocol Governance',
                      style: GoogleFonts.newsreader(
                        fontSize: compact ? 15 : 17,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textColor,
                      ),
                    ),
                    Text(
                      'Unanimously Ratified Protocol',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppTheme.secondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.honorColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.honorColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_outline,
                        color: AppTheme.honorColor, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      'Active',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.honorColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: GovernanceVoice.values.map((voice) {
              return Tooltip(
                message: '${voice.mandate}\n${voice.description}',
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.canvasColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: voice.color.withValues(alpha: 0.5)),
                ),
                child: InkWell(
                  onTap: () {
                    _showVoiceDetails(context, voice);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: voice.color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: voice.color.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(voice.icon, size: 13, color: voice.color),
                        const SizedBox(width: 6),
                        Text(
                          voice.name,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: voice.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _showVoiceDetails(BuildContext context, GovernanceVoice voice) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: voice.color.withValues(alpha: 0.5)),
        ),
        title: Row(
          children: [
            Icon(voice.icon, color: voice.color, size: 22),
            const SizedBox(width: 10),
            Text(
              '${voice.name} Voice',
              style: GoogleFonts.newsreader(
                fontSize: 20,
                color: AppTheme.textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: voice.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                voice.mandate,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: voice.color,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              voice.description,
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.5,
                color: AppTheme.textColor,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close',
                style: TextStyle(color: AppTheme.primaryAccent)),
          ),
        ],
      ),
    );
  }
}

/// Compact row of 5 colored dots/icons for headers and app bars
class GovernancePillRow extends StatelessWidget {
  const GovernancePillRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: GovernanceVoice.values.map((v) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.5),
          child: Tooltip(
            message: '${v.name} Voice: ${v.mandate}',
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: v.color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: v.color.withValues(alpha: 0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
