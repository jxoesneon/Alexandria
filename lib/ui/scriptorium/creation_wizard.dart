import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/glass_card.dart';

class CreationWizard extends ConsumerStatefulWidget {
  const CreationWizard({super.key});

  @override
  ConsumerState<CreationWizard> createState() => _CreationWizardState();
}

class _CreationWizardState extends ConsumerState<CreationWizard> {
  int _currentStep = 0;
  bool _encrypt = false;
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _descController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Document to Library'),
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep < 2) {
            setState(() => _currentStep += 1);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Document successfully added and encrypted.')),
            );
            Navigator.pop(context);
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
                    const Icon(Icons.cloud_upload_outlined, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    const Text('Drag and drop files here, or browse'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {},
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
                    subtitle: const Text('Only you and people with the key will be able to read this file.'),
                    value: _encrypt,
                    onChanged: (val) => setState(() => _encrypt = val),
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
