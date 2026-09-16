import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import '../common/governance_badge.dart';
import '../theme/app_theme.dart';

/// Modal dialog for 1-click exporting MCP configurations to external agent runtimes
class McpConfigExportDialog extends StatefulWidget {
  final List<Map<String, dynamic>> tools;

  const McpConfigExportDialog({
    super.key,
    required this.tools,
  });

  static Future<void> show(BuildContext context, List<Map<String, dynamic>> tools) {
    return showDialog(
      context: context,
      builder: (context) => McpConfigExportDialog(tools: tools),
    );
  }

  @override
  State<McpConfigExportDialog> createState() => _McpConfigExportDialogState();
}

class _McpConfigExportDialogState extends State<McpConfigExportDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Resolves the on-disk path of the dev MCP simulator. The exported
  /// configs previously embedded a developer's absolute home-directory
  /// path (`/Users/mey/...`), which resolves nowhere on any other machine.
  ///
  /// Dev builds execute from `<project>/build/<platform>/...`, so we walk
  /// ancestors of [Platform.resolvedExecutable] looking for the project
  /// root (a directory containing both `pubspec.yaml` and the simulator
  /// script). When the root can't be found — e.g. an installed release
  /// build — a documented `<alexandria>` placeholder is emitted for the
  /// user to fill in.
  String _resolveSimulatorPath() {
    const scriptRel = 'bin/alexandria_mcp_server.js';
    try {
      var dir = File(Platform.resolvedExecutable).parent;
      for (var i = 0; i < 16; i++) {
        final candidate = p.join(dir.path, scriptRel);
        if (File(candidate).existsSync() &&
            File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
          return candidate;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    } catch (_) {
      // Platform.resolvedExecutable unsupported — fall through.
    }
    return '<alexandria>/$scriptRel';
  }

  String _getClaudeConfig() {
    final config = {
      'mcpServers': {
        'alexandria-simulator': {
          'command': 'node',
          'args': [_resolveSimulatorPath(), '--dev'],
          'env': {
            'ALX_MCP_MODE': 'simulator',
          },
        },
      },
    };
    return const JsonEncoder.withIndent('  ').convert(config);
  }

  String _getGeminiConfig() {
    final config = {
      'alexandria-simulator': {
        'command': 'node',
        'args': [_resolveSimulatorPath(), '--dev'],
        'protocol': 'json-rpc-2.0',
        'simulated': true,
        'tools_count': widget.tools.length,
        'governance': 'protocol-governance',
      },
    };
    return const JsonEncoder.withIndent('  ').convert(config);
  }

  String _getCursorConfig() {
    final config = {
      'mcpServers': {
        'alexandria-simulator': {
          'command': 'node',
          'args': [_resolveSimulatorPath(), '--dev'],
        },
      },
    };
    return const JsonEncoder.withIndent('  ').convert(config);
  }

  String _getRawToolSchemas() {
    return const JsonEncoder.withIndent('  ').convert(widget.tools);
  }

  void _copyToClipboard(String content) {
    Clipboard.setData(ClipboardData(text: content));
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Configuration copied to clipboard! Paste into your agent settings.'),
        backgroundColor: AppTheme.honorColor,
        duration: Duration(seconds: 3),
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
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
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.hub_outlined, color: AppTheme.primaryAccent, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Connect External AI Agents (ALX-006)',
                          style: GoogleFonts.newsreader(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '1-Click Model Context Protocol (MCP) configuration for Claude, Gemini, Cursor, and Windsurf.',
                          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.secondaryColor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppTheme.secondaryColor),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Alexandria Core Team Ratification Banner
              const GovernanceBanner(compact: true),
              const SizedBox(height: 12),

              // Simulator honesty disclaimer (ALX-010/011 veto):
              // the exported stdio server is the dev simulator — no live
              // credits, payouts, or archive state. Financial/minting
              // tools were removed from it entirely.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.honorColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppTheme.honorColor.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.science_outlined,
                        size: 14, color: AppTheme.honorColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Dev simulator — requires --dev. Exposes mock data only: no live credits, payouts, or minting. The production tool surface runs inside the app.',
                        style: GoogleFonts.inter(
                            fontSize: 11, color: AppTheme.secondaryColor),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Tab Bar
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.canvasColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorColor: AppTheme.primaryAccent,
                  labelColor: AppTheme.primaryAccent,
                  unselectedLabelColor: AppTheme.secondaryColor,
                  labelStyle: GoogleFonts.jetBrainsMono(fontSize: 12, fontWeight: FontWeight.bold),
                  tabs: [
                    const Tab(text: 'Claude Desktop'),
                    const Tab(text: 'Gemini CLI'),
                    const Tab(text: 'Cursor / Windsurf'),
                    Tab(text: 'Tool Schemas (${widget.tools.length})'),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Code Viewer Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildCodeTab(_getClaudeConfig(), 'claude_desktop_config.json'),
                    _buildCodeTab(_getGeminiConfig(), 'gemini_config.json'),
                    _buildCodeTab(_getCursorConfig(), '.cursor/mcp.json'),
                    _buildCodeTab(_getRawToolSchemas(), 'alexandria_mcp_tools.json'),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              // Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.lock_outline, size: 14, color: AppTheme.honorColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Dev simulator • stdio / JSON-RPC 2.0 • mock data',
                            style: GoogleFonts.jetBrainsMono(fontSize: 11, color: AppTheme.secondaryColor),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () {
                      final currentIdx = _tabController.index;
                      String content = '';
                      if (currentIdx == 0) content = _getClaudeConfig();
                      if (currentIdx == 1) content = _getGeminiConfig();
                      if (currentIdx == 2) content = _getCursorConfig();
                      if (currentIdx == 3) content = _getRawToolSchemas();
                      _copyToClipboard(content);
                    },
                    icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
                    label: Text(_copied ? 'Copied!' : 'Copy Active Config'),
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

  Widget _buildCodeTab(String code, String filename) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.canvasColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.secondaryColor.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                filename,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: AppTheme.primaryAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              InkWell(
                onTap: () => _copyToClipboard(code),
                child: Row(
                  children: [
                    const Icon(Icons.copy, size: 13, color: AppTheme.secondaryColor),
                    const SizedBox(width: 4),
                    Text(
                      'Copy',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: AppTheme.secondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 16, color: AppTheme.surfaceColor),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                code,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  color: AppTheme.textColor,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
