import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:file_picker/file_picker.dart';
import 'package:alexandria/ui/theme/app_theme.dart';
import 'package:alexandria/logic/content_repository.dart';

class CreationWizard extends ConsumerStatefulWidget {
  const CreationWizard({super.key});

  @override
  ConsumerState<CreationWizard> createState() => _CreationWizardState();
}

class _CreationWizardState extends ConsumerState<CreationWizard> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // State
  List<PlatformFile> _files = [];
  String _category = 'book'; // auto-detected
  final Map<String, TextEditingController> _metaControllers = {};

  // Core Info
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _descController = TextEditingController(); // optional
  bool _isEncrypted = false;
  bool _isUploading = false;

  // Metadata Fields Config (Reuse or Import shared)
  // For brevity, using simplified subset or copying logic.
  // Ideally this should be in a separate config file.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.canvasColor,
      appBar: AppBar(
        title: Text(
          'THE SCRIPTORIUM',
          style: AppTheme.darkTheme.textTheme.headlineSmall?.copyWith(
            color: AppTheme.primaryColor,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Progress Bar
          LinearProgressIndicator(
            value: (_currentStep + 1) / 4,
            backgroundColor: AppTheme.surfaceColor,
            valueColor: const AlwaysStoppedAnimation(AppTheme.primaryColor),
          ).animate().slideX(begin: -1, duration: 500.ms),

          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _StepSelection(
                  files: _files,
                  onPick: _pickFiles,
                  onRemove: (f) => setState(() => _files.remove(f)),
                ),
                _StepEnrichment(
                  category: _category,
                  titleCtrl: _titleController,
                  authorCtrl: _authorController,
                  metaControllers: _metaControllers,
                  onCategoryChanged: (v) => setState(() => _category = v),
                ),
                _StepProtection(
                  isEncrypted: _isEncrypted,
                  onToggle: (v) => setState(() => _isEncrypted = v),
                  summary: _buildSummary(),
                ),
                _StepSealing(isUploading: _isUploading, onUpload: _submit),
              ],
            ),
          ),

          // Navigation
          if (!_isUploading)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surfaceColor,
                border: Border(
                  top: BorderSide(
                    color: AppTheme.primaryColor.withValues(alpha: 0.2),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentStep > 0)
                    TextButton(
                      onPressed: _prevPage,
                      child: const Text(
                        'BACK',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  else
                    const SizedBox(width: 48),

                  ElevatedButton(
                    onPressed: _files.isEmpty ? null : _nextPage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: AppTheme.canvasColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                    child: Text(
                      _currentStep == 2 ? 'SEAL & PRESERVE' : 'NEXT STEP',
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _nextPage() {
    if (_currentStep == 2) {
      _submit();
    } else {
      setState(() => _currentStep++);
      _pageController.nextPage(duration: 300.ms, curve: Curves.easeInOut);
    }
  }

  void _prevPage() {
    setState(() => _currentStep--);
    _pageController.previousPage(duration: 300.ms, curve: Curves.easeInOut);
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
      );
      if (result != null) {
        setState(() => _files = result.files);
        // Simulate analysis or call service
        // _smartFillMetadata();
      }
    } catch (e) {
      // handle error
    }
  }

  Future<void> _submit() async {
    setState(() {
      _currentStep = 3;
      _isUploading = true;
    });
    _pageController.jumpToPage(3);

    // Call Repo
    try {
      final repo = ref.read(contentRepositoryProvider);
      await repo.createContent(
        _titleController.text.isEmpty
            ? _files.first.name
            : _titleController.text,
        _descController.text,
        _authorController.text.isEmpty ? 'Anonymous' : _authorController.text,
        files: _files,
        category: _category,
        isEncrypted: _isEncrypted,
      );

      if (mounted) {
        await Future.delayed(1.seconds); // Success Animation
        if (!mounted) return;
        // ignore: use_build_context_synchronously
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _isUploading = false);
      // Show error
    }
  }

  String _buildSummary() =>
      'Preserving ${_files.length} file(s) as $_category.';
}

class _StepSelection extends StatelessWidget {
  final List<PlatformFile> files;
  final VoidCallback onPick;
  final Function(PlatformFile) onRemove;

  const _StepSelection({
    required this.files,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
                onTap: onPick,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    border: Border.all(color: AppTheme.primaryColor, width: 2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.upload_file,
                        size: 64,
                        color: AppTheme.primaryColor.withValues(alpha: 0.8),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'DRAG & DROP\nOR TAP',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.primaryColor),
                      ),
                    ],
                  ),
                ),
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .boxShadow(
                begin: BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.3),
                  blurRadius: 20,
                ),
                end: BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.5),
                  blurRadius: 30,
                ),
              ),

          const SizedBox(height: 32),

          if (files.isNotEmpty)
            SizedBox(
              height: 150,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                itemCount: files.length,
                itemBuilder: (context, index) {
                  final f = files[index];
                  return ListTile(
                    title: Text(
                      f.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => onRemove(f),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _StepEnrichment extends StatelessWidget {
  final String category;
  final TextEditingController titleCtrl;
  final TextEditingController authorCtrl;
  final Map<String, TextEditingController> metaControllers;
  final Function(String) onCategoryChanged;

  const _StepEnrichment({
    required this.category,
    required this.titleCtrl,
    required this.authorCtrl,
    required this.metaControllers,
    required this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'METADATA ENRICHMENT',
            style: TextStyle(color: AppTheme.secondaryColor, letterSpacing: 2),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: titleCtrl,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: authorCtrl,
            decoration: const InputDecoration(labelText: 'Author'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey(category),
            initialValue: category,
            items: ['book', 'image', 'video', 'code', 'other']
                .map(
                  (c) =>
                      DropdownMenuItem(value: c, child: Text(c.toUpperCase())),
                )
                .toList(),
            onChanged: (v) => onCategoryChanged(v!),
            decoration: const InputDecoration(labelText: 'Category'),
          ),
          // Add meta controllers dynamically here if needed
        ],
      ),
    );
  }
}

class _StepProtection extends StatelessWidget {
  final bool isEncrypted;
  final Function(bool) onToggle;
  final String summary;

  const _StepProtection({
    required this.isEncrypted,
    required this.onToggle,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.security, size: 80, color: AppTheme.honorColor),
          const SizedBox(height: 32),
          Text(
            summary,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 32),
          SwitchListTile(
            title: const Text(
              'Enable Encryption',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: const Text(
              'AES-256 Client-Side Encryption',
              style: TextStyle(color: Colors.white54),
            ),
            value: isEncrypted,
            onChanged: onToggle,
            activeTrackColor: AppTheme.primaryColor.withValues(alpha: 0.5),
            activeThumbColor: AppTheme.primaryColor,
          ),
        ],
      ),
    );
  }
}

class _StepSealing extends StatelessWidget {
  final bool isUploading;
  final VoidCallback onUpload;

  const _StepSealing({required this.isUploading, required this.onUpload});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isUploading) ...[
            const CircularProgressIndicator(color: AppTheme.primaryColor),
            const SizedBox(height: 32),
            const Text(
              'UPLOADING TO IPFS SWARM...',
              style: TextStyle(color: AppTheme.primaryColor, letterSpacing: 2),
            ),
          ] else ...[
            const Icon(
              Icons.check_circle_outline,
              size: 100,
              color: Colors.green,
            ),
            const SizedBox(height: 24),
            const Text(
              'Ready to Seal',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
          ],
        ],
      ),
    );
  }
}
