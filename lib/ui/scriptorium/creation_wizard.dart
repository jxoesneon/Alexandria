import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logic/content_repository.dart';
import '../../providers/library_providers.dart';
import '../widgets/glass_card.dart';

class CreationWizard extends ConsumerStatefulWidget {
  const CreationWizard({super.key});

  @override
  ConsumerState<CreationWizard> createState() => _CreationWizardState();
}

class _CreationWizardState extends ConsumerState<CreationWizard> {
  int _currentStep = 0;
  bool _encrypt = false;
  bool _isSubmitting = false;
  PlatformFile? _pickedFile;
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _descController = TextEditingController();
  final _contentController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _descController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (result != null && result.files.isNotEmpty) {
        setState(() => _pickedFile = result.files.first);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the file picker: $e')),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A title is required.')),
      );
      setState(() => _currentStep = 1);
      return;
    }

    final pickedBytes = _pickedFile?.bytes;
    final Uint8List? fileData = pickedBytes != null
        ? Uint8List.fromList(pickedBytes)
        : _contentController.text.isNotEmpty
            ? Uint8List.fromList(utf8.encode(_contentController.text))
            : null;
    if (fileData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Select a file or enter some text content.')),
      );
      setState(() => _currentStep = 0);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref.read(contentRepositoryProvider).createContent(
            title: _titleController.text.trim(),
            author: _authorController.text.trim().isEmpty
                ? null
                : _authorController.text.trim(),
            description: _descController.text.trim().isEmpty
                ? null
                : _descController.text.trim(),
            fileData: fileData,
            isEncrypted: _encrypt,
            format: _pickedFile?.extension?.toLowerCase() ?? 'txt',
          );
      ref.invalidate(libraryDashboardProvider);
      ref.invalidate(recentItemsProvider);
      ref.invalidate(newArrivalsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document added to your library.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add the document: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Document to Library'),
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepTapped: (step) {
          if (step <= _currentStep + 1) {
            setState(() => _currentStep = step);
          }
        },
        onStepContinue: () {
          if (_currentStep < 2) {
            setState(() => _currentStep += 1);
          } else {
            _submit();
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) {
            setState(() => _currentStep -= 1);
          } else {
            Navigator.pop(context);
          }
        },
        steps: [
          Step(
            title: const Text('Select File'),
            subtitle: const Text('Choose a document, book, audio, or dataset'),
            isActive: _currentStep >= 0,
            content: GlassCard(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.cloud_upload_outlined,
                        size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(_pickedFile == null
                        ? 'Pick a file, or write text on the next step'
                        : 'Selected: ${_pickedFile!.name}'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.file_open),
                      label: const Text('Browse Files'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Step(
            title: const Text('Document Details'),
            subtitle: const Text('Enter title, author, and description'),
            isActive: _currentStep >= 1,
            content: Column(
              children: [
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    hintText: 'e.g. The Republic',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _authorController,
                  decoration: const InputDecoration(
                    labelText: 'Author or Organization',
                    hintText: 'e.g. Plato',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _descController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    hintText: 'Summary or context of this document...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _contentController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Text Content (required without a file)',
                    hintText: 'Write or paste the document text...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          Step(
            title: const Text('Privacy & Security'),
            subtitle: const Text('Configure envelope encryption options'),
            isActive: _currentStep >= 2,
            content: GlassCard(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    title: const Text('Encrypt with Personal Key (AES-256)'),
                    subtitle: const Text(
                        'Only you and people with the key will be able to read this file.'),
                    value: _encrypt,
                    onChanged: (val) => setState(() => _encrypt = val),
                  ),
                  if (_isSubmitting)
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: LinearProgressIndicator(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
