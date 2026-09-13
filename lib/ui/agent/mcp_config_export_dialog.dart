import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
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

  String _getClaudeConfig() {
    final config = {
      'mcpServers': {
        'alexandria': {
          'command': 'node',
          'args': ['/Users/mey/Alexandria/bin/alexandria_mcp_server.js'],
          'env': {
            'ALX_STDIO_MODE': 'true',
            'ALX_TREASURY_AGENT_ID': 'bcn_governance_steward_01',
          },
        },
      },
    };
    return const JsonEncoder.withIndent('  ').convert(config);
  }

  String _getGeminiConfig() {
    final config = {
      'alexandria': {
        'command': 'node',
        'args': ['/Users/mey/Alexandria/bin/alexandria_mcp_server.js'],
        'protocol': 'json-rpc-2.0',
        'tools_count': widget.tools.length,
        'governance': 'protocol-governance',
      },
    };
    return const JsonEncoder.withIndent('  ').convert(config);
  }

  String _getCursorConfig() {
    final config = {
      'mcpServers': {
        'alexandria-knowledge-core': {
          'command': 'node',
          'args': ['/Users/mey/Alexandria/bin/alexandria_mcp_server.js'],
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

              // Governance Review Ratification Banner
              const GovernanceBanner(compact: true),
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
                  tabs: const [
                    Tab(text: 'Claude Desktop'),
                    Tab(text: 'Gemini CLI'),
                    Tab(text: 'Cursor / Windsurf'),
                    Tab(text: 'Tool Schemas (8)'),
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
                            'Ed25519 Signed • stdio / JSON-RPC 2.0',
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
