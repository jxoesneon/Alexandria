import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/plugin_service.dart';
import '../theme/app_theme.dart';

class DoiHarvesterDialog extends ConsumerStatefulWidget {
  final String? initialDoi;

  const DoiHarvesterDialog({super.key, this.initialDoi});

  @override
  ConsumerState<DoiHarvesterDialog> createState() => _DoiHarvesterDialogState();
}

class _DoiHarvesterDialogState extends ConsumerState<DoiHarvesterDialog> {
  final TextEditingController _textController = TextEditingController();
  bool _downloadPdf = true;
  bool _isProcessing = false;
  String? _statusMessage;
  List<Map<String, dynamic>> _harvestedResults = [];
  List<String> _detectedDois = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialDoi != null && widget.initialDoi!.isNotEmpty) {
      _textController.text = widget.initialDoi!;
      _detectedDois = DoiResolver.extractDoisInText(widget.initialDoi!);
    }
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _textController.text;
    final dois = DoiResolver.extractDoisInText(text);
    if (!listEquals(dois, _detectedDois)) {
      setState(() {
        _detectedDois = dois;
      });
    }
  }

  bool listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _harvest() async {
    if (_detectedDois.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter at least one valid DOI or text containing DOIs.'),
          backgroundColor: AppTheme.dangerColor,
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Resolving and harvesting ${_detectedDois.length} scientific work(s)...';
      _harvestedResults = [];
    });

    final pluginService = ref.read(pluginServiceProvider);
    final result = await pluginService.executeAction(
      'org.alexandria.plugin.doi-harvester',
      'harvest_batch',
      {
        'input': _detectedDois,
        'downloadPdf': _downloadPdf,
      },
    );

    if (mounted) {
      setState(() {
        _isProcessing = false;
        if (result.success && result.data is Map) {
          final data = result.data as Map<String, dynamic>;
          _harvestedResults =
              (data['results'] as List?)?.cast<Map<String, dynamic>>() ?? [];
          _statusMessage = result.message;
        } else {
          _statusMessage = result.message;
        }
      });
    }
  }

  void _loadSampleDoi() {
    _textController.text =
        '10.1038/s41586-020-2649-2\n10.1145/3377811.3380327\n10.1126/science.1058040';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 640,
        constraints: const BoxConstraints(maxHeight: 700),
        decoration: BoxDecoration(
          color: AppTheme.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.primaryAccent.withValues(alpha: 0.3),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Dialog Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.science_outlined,
                      color: AppTheme.primaryAccent,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DOI SCIENTIFIC HARVESTER',
                          style: theme.textTheme.titleMedium?.copyWith(
                            letterSpacing: 1.0,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Preserve peer-reviewed literature into Alexandria safe harbor',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.secondaryColor,
                          ),
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
            ),
            const Divider(height: 1, color: Colors.white12),

            // Dialog Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Enter DOI(s) or Paste Bibliography / Markdown:',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textColor,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _loadSampleDoi,
                          icon: const Icon(Icons.auto_awesome, size: 14),
                          label: const Text('Sample DOIs', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primaryAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _textController,
                      maxLines: 4,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: Colors.white,
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'e.g. 10.1038/s41586-020-2649-2\nhttps://doi.org/10.1145/3377811.3380327\nor paste any text containing DOIs...',
                        hintStyle: const TextStyle(color: Colors.white24),
                        filled: true,
                        fillColor: AppTheme.canvasColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppTheme.primaryAccent),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Detected DOIs Pill
                    if (_detectedDois.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.primaryAccent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline,
                                color: AppTheme.primaryAccent, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              '${_detectedDois.length} DOI(s) ready for safe-harbor preservation',
                              style: const TextStyle(
                                color: AppTheme.primaryAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),

                    // Options Switch
                    Material(
                      type: MaterialType.transparency,
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Download Open-Access PDF',
                          style: TextStyle(fontSize: 13, color: AppTheme.textColor),
                        ),
                        subtitle: const Text(
                          'Fetches original PDF if open-access; falls back to archival markdown dossier if paywalled',
                          style: TextStyle(fontSize: 11, color: AppTheme.secondaryColor),
                        ),
                        value: _downloadPdf,
                        onChanged: (val) => setState(() => _downloadPdf = val),
                        activeThumbColor: AppTheme.primaryAccent,
                      ),
                    ),

                    if (_isProcessing) ...[
                      const SizedBox(height: 16),
                      Center(
                        child: Column(
                          children: [
                            const CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(AppTheme.primaryAccent),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _statusMessage ?? 'Harvesting...',
                              style: const TextStyle(
                                color: AppTheme.secondaryColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Results List
                    if (_harvestedResults.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Harvested Scientific Documents:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._harvestedResults.map((item) => _buildResultCard(item)),
                    ],
                  ],
                ),
              ),
            ),

            // Dialog Footer
            const Divider(height: 1, color: Colors.white12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _isProcessing ? null : _harvest,
                    icon: const Icon(Icons.download_for_offline_outlined, size: 18),
                    label: Text(_detectedDois.length > 1
                        ? 'Harvest ${_detectedDois.length} Works'
                        : 'Harvest & Ingest'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryAccent,
                      foregroundColor: AppTheme.canvasColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> item) {
    final success = item['success'] == true;
    final title = item['title'] as String? ?? item['doi'] ?? 'Unknown Work';
    final format = item['format'] as String? ?? 'md';
    final capturedPdf = item['capturedPdf'] == true;
    final author = item['author'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.canvasColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: success ? AppTheme.honorColor.withValues(alpha: 0.4) : Colors.red.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            success
                ? (capturedPdf ? Icons.picture_as_pdf : Icons.article_outlined)
                : Icons.error_outline,
            color: success
                ? (capturedPdf ? Colors.greenAccent : AppTheme.primaryAccent)
                : AppTheme.dangerColor,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (author.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    author,
                    style: const TextStyle(color: AppTheme.secondaryColor, fontSize: 11),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        format.toUpperCase(),
                        style: const TextStyle(color: Colors.white70, fontSize: 10),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (capturedPdf)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.honorColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'OPEN ACCESS PDF',
                          style: TextStyle(
                            color: Color(0xFF4ADE80),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
