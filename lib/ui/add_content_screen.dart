import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../logic/content_repository.dart';
import 'theme/app_theme.dart';
import '../services/metadata_scrubbing_service.dart';
import '../services/metadata_service.dart';
import 'widgets/info_glass.dart';

class AddContentScreen extends ConsumerStatefulWidget {
  const AddContentScreen({super.key});

  @override
  ConsumerState<AddContentScreen> createState() => _AddContentScreenState();
}

class _AddContentScreenState extends ConsumerState<AddContentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _authorController = TextEditingController();

  // Dynamic controllers map: key -> controller
  final Map<String, TextEditingController> _metadataControllers = {};

  // File handling
  List<PlatformFile> _selectedFiles = [];

  String _selectedCategory = 'book';

  // Category Definitions
  final Map<String, List<Map<String, String>>> _categoryFields = {
    'book': [
      {'key': 'isbn', 'label': 'ISBN', 'type': 'text'},
      {'key': 'publisher', 'label': 'Publisher', 'type': 'text'},
      {'key': 'year', 'label': 'Year', 'type': 'number'},
      {'key': 'genre', 'label': 'Genre', 'type': 'text'},
      {'key': 'page_count', 'label': 'Page Count', 'type': 'number'},
      {'key': 'language', 'label': 'Language', 'type': 'text'},
      {'key': 'edition', 'label': 'Edition', 'type': 'text'},
    ],
    'paper': [
      {'key': 'doi', 'label': 'DOI', 'type': 'text'},
      {'key': 'journal', 'label': 'Journal', 'type': 'text'},
      {'key': 'institution', 'label': 'Institution', 'type': 'text'},
      {'key': 'year', 'label': 'Year', 'type': 'number'},
      {'key': 'volume', 'label': 'Volume', 'type': 'text'},
      {'key': 'issue', 'label': 'Issue', 'type': 'text'},
      {
        'key': 'keywords',
        'label': 'Keywords (comma separated)',
        'type': 'text',
      },
    ],
    'video': [
      {'key': 'duration', 'label': 'Duration (e.g. 10:00)', 'type': 'text'},
      {'key': 'resolution', 'label': 'Resolution (e.g. 1080p)', 'type': 'text'},
      {'key': 'director', 'label': 'Director', 'type': 'text'},
      {'key': 'year', 'label': 'Year', 'type': 'number'},
      {'key': 'codec', 'label': 'Codec', 'type': 'text'},
      {'key': 'framerate', 'label': 'Frame Rate (fps)', 'type': 'number'},
      {'key': 'bitrate', 'label': 'Bitrate (Mbps)', 'type': 'number'},
    ],
    'audio': [
      {'key': 'duration', 'label': 'Duration', 'type': 'text'},
      {'key': 'artist', 'label': 'Artist', 'type': 'text'},
      {'key': 'album', 'label': 'Album', 'type': 'text'},
      {'key': 'bitrate', 'label': 'Bitrate (kbps)', 'type': 'number'},
      {'key': 'composer', 'label': 'Composer', 'type': 'text'},
      {'key': 'isrc', 'label': 'ISRC', 'type': 'text'},
      {'key': 'sample_rate', 'label': 'Sample Rate (Hz)', 'type': 'number'},
    ],
    'image': [
      {'key': 'resolution', 'label': 'Resolution (WxH)', 'type': 'text'},
      {'key': 'camera_model', 'label': 'Camera Model', 'type': 'text'},
      {'key': 'date_taken', 'label': 'Date Taken', 'type': 'text'},
      {'key': 'location', 'label': 'Location', 'type': 'text'},
      {'key': 'iso', 'label': 'ISO', 'type': 'number'},
      {'key': 'shutter_speed', 'label': 'Shutter Speed', 'type': 'text'},
      {'key': 'aperture', 'label': 'Aperture (f/)', 'type': 'text'},
      {'key': 'focal_length', 'label': 'Focal Length (mm)', 'type': 'text'},
    ],
    'model': [
      {'key': 'format', 'label': 'Format', 'type': 'text'},
      {'key': 'poly_count', 'label': 'Poly Count', 'type': 'number'},
      {'key': 'rigged', 'label': 'Rigged (yes/no)', 'type': 'text'},
      {'key': 'materials', 'label': 'Materials (count)', 'type': 'number'},
      {'key': 'textures', 'label': 'Textures (count)', 'type': 'number'},
      {
        'key': 'animation_count',
        'label': 'Animations (count)',
        'type': 'number',
      },
    ],
    'dataset': [
      {'key': 'format', 'label': 'Format', 'type': 'text'},
      {'key': 'row_count', 'label': 'Row Count', 'type': 'number'},
      {'key': 'license', 'label': 'License', 'type': 'text'},
      {'key': 'size_gb', 'label': 'Size (GB)', 'type': 'number'},
      {'key': 'columns', 'label': 'Column Count', 'type': 'number'},
      {'key': 'spatial_coverage', 'label': 'Spatial Coverage', 'type': 'text'},
    ],
    'code': [
      {'key': 'language', 'label': 'Language', 'type': 'text'},
      {'key': 'repository_url', 'label': 'Repository URL', 'type': 'text'},
      {'key': 'version', 'label': 'Version', 'type': 'text'},
      {'key': 'license', 'label': 'License', 'type': 'text'},
      {'key': 'framework', 'label': 'Framework', 'type': 'text'},
      {
        'key': 'dependencies',
        'label': 'Dependencies (count)',
        'type': 'number',
      },
    ],
    'other': [],
  };

  bool _isLoading = false;
  bool _isAnalyzing = false;
  bool _enableEncryption = false;
  bool _stripMetadata = true; // Privacy by default

  // Metadata scrubbing detection state
  List<String> _detectedSensitiveFields = [];
  bool _isDetectingMetadata = false;
  bool _metadataDetectionDone = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _authorController.dispose();
    for (var c in _metadataControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // Update controllers when category changes
  void _updateControllers() {
    final fields = _categoryFields[_selectedCategory] ?? [];

    // Remove unused
    _metadataControllers.removeWhere(
      (key, _) => !fields.any((f) => f['key'] == key),
    );

    // Add missing
    for (var f in fields) {
      if (!_metadataControllers.containsKey(f['key'])) {
        _metadataControllers[f['key']!] = TextEditingController();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _updateControllers();
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true, // We need bytes for IPFS (on Web/Desktop primarily)
      );

      if (result != null) {
        setState(() {
          _selectedFiles = result.files;
          _metadataDetectionDone = false;
          _detectedSensitiveFields = [];
          _smartFillMetadata(); // Trigger smart detection
          _detectSensitiveMetadataFields(); // Trigger scrubbing detection
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error picking files: $e')));
      }
    }
  }

  Future<void> _smartFillMetadata() async {
    if (_selectedFiles.isEmpty) return;

    if (mounted) {
      setState(() => _isAnalyzing = true);
    }
    final service = ref.read(metadataServiceProvider);

    try {
      final file = _selectedFiles.first;
      final metadata = await service.extractMetadata(file);

      if (!mounted) return;

      // 1. Infer Category
      // We auto-switch if the user hasn't manually changed it from default 'book' OR if previously auto-set.
      // Simpler heuristic: If the file extension strongly suggests a category, we switch to it.
      String? inferredCategory;
      final ext = file.extension?.toLowerCase();

      if ([
        'mp4',
        'mkv',
        'mov',
        'avi',
        'flv',
        'wmv',
        'webm',
        'm4v',
        '3gp',
        'ts',
      ].contains(ext)) {
        inferredCategory = 'video';
      } else if ([
        'mp3',
        'wav',
        'aac',
        'flac',
        'ogg',
        'm4a',
        'wma',
        'aiff',
        'alac',
      ].contains(ext)) {
        inferredCategory = 'audio';
      } else if ([
        'jpg',
        'jpeg',
        'png',
        'webp',
        'heic',
        'gif',
        'bmp',
        'tiff',
        'svg',
        'ico',
        'raw',
        'cr2',
        'nef',
      ].contains(ext)) {
        inferredCategory = 'image';
      } else if ([
        'pdf',
        'epub',
        'mobi',
        'azw3',
        'djvu',
        'txt',
        'rtf',
        'cbz',
        'cbr',
      ].contains(ext)) {
        inferredCategory = 'book';
      } else if (['doc', 'docx', 'odt', 'latex', 'tex'].contains(ext)) {
        inferredCategory = 'paper';
      } else if ([
        'obj',
        'gltf',
        'glb',
        'fbx',
        'stl',
        'ply',
        'usd',
        'usdz',
        'dae',
        'blend',
      ].contains(ext)) {
        inferredCategory = 'model';
      } else if ([
        'csv',
        'json',
        'parquet',
        'tsv',
        'xls',
        'xlsx',
        'ods',
        'xml',
        'sql',
        'db',
        'hdf5',
      ].contains(ext)) {
        inferredCategory = 'dataset';
      } else if ([
        'dart',
        'py',
        'js',
        'html',
        'css',
        'cpp',
        'c',
        'java',
        'kt',
        'swift',
        'rs',
        'go',
        'rb',
        'php',
        'sh',
        'bat',
        'ps1',
        'md',
        'yml',
        'yaml',
      ].contains(ext)) {
        inferredCategory = 'code';
      }

      // If we found a category and it's different, switch and update UI
      if (inferredCategory != null && inferredCategory != _selectedCategory) {
        setState(() {
          _selectedCategory = inferredCategory!;
          _updateControllers();
        });
      }

      // 2. Prefill Fields (Controllers are now prepared)
      setState(() {
        // Image / Video
        if (metadata.containsKey('resolution') &&
            _metadataControllers.containsKey('resolution')) {
          _metadataControllers['resolution']!.text = metadata['resolution'];
        }
        if (metadata.containsKey('camera_model') &&
            _metadataControllers.containsKey('camera_model')) {
          _metadataControllers['camera_model']!.text = metadata['camera_model'];
        }
        if (metadata.containsKey('iso') &&
            _metadataControllers.containsKey('iso')) {
          _metadataControllers['iso']!.text = metadata['iso'];
        }
        if (metadata.containsKey('aperture') &&
            _metadataControllers.containsKey('aperture')) {
          _metadataControllers['aperture']!.text = metadata['aperture'];
        }
        if (metadata.containsKey('shutter_speed') &&
            _metadataControllers.containsKey('shutter_speed')) {
          _metadataControllers['shutter_speed']!.text =
              metadata['shutter_speed'];
        }
        if (metadata.containsKey('focal_length') &&
            _metadataControllers.containsKey('focal_length')) {
          _metadataControllers['focal_length']!.text = metadata['focal_length'];
        }
        if (metadata.containsKey('date_taken') &&
            _metadataControllers.containsKey('date_taken')) {
          _metadataControllers['date_taken']!.text = metadata['date_taken'];
        }
        if (metadata.containsKey('location') &&
            _metadataControllers.containsKey('location')) {
          _metadataControllers['location']!.text = metadata['location'];
        }

        // Dataset / Code
        if (metadata.containsKey('row_count') &&
            _metadataControllers.containsKey('row_count')) {
          _metadataControllers['row_count']!.text =
              metadata['row_count'].toString();
        }
        if (metadata.containsKey('dependencies') &&
            _metadataControllers.containsKey('dependencies')) {
          _metadataControllers['dependencies']!.text =
              metadata['dependencies'].toString();
        }

        // General Size/Format
        if (_metadataControllers.containsKey('size_gb')) {
          final sizeBytes = metadata['size_bytes'] as int? ?? file.size;
          // Convert to GB with 6 decimals for small files, or just concise string
          final sizeGb = (sizeBytes / (1024 * 1024 * 1024));
          _metadataControllers['size_gb']!.text = sizeGb.toStringAsFixed(6);
        }

        if (_metadataControllers.containsKey('format')) {
          _metadataControllers['format']!.text =
              (metadata['format'] ?? file.extension ?? 'unknown').toString();
        }
      });
    } catch (e) {
      debugPrint('Metadata extraction failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  Future<void> _detectSensitiveMetadataFields() async {
    if (_selectedFiles.isEmpty || !_stripMetadata) {
      setState(() {
        _detectedSensitiveFields = [];
        _metadataDetectionDone = true;
      });
      return;
    }

    final file = _selectedFiles.first;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() {
        _detectedSensitiveFields = [];
        _metadataDetectionDone = true;
      });
      return;
    }

    setState(() => _isDetectingMetadata = true);

    try {
      final service = ref.read(metadataScrubbingServiceProvider);
      final detected = await service.detectSensitiveFields(
        Uint8List.fromList(bytes),
      );
      if (!mounted) return;
      setState(() {
        _detectedSensitiveFields = detected;
        _metadataDetectionDone = true;
      });
    } catch (e) {
      debugPrint('Sensitive field detection failed: $e');
      if (mounted) {
        setState(() {
          _detectedSensitiveFields = [];
          _metadataDetectionDone = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isDetectingMetadata = false);
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one file.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final repo = ref.read(contentRepositoryProvider);

      Uint8List fileBytes = Uint8List.fromList(_selectedFiles.first.bytes!);

      // Scrub metadata if enabled and file is a supported image type
      if (_stripMetadata) {
        final scrubbingService = ref.read(metadataScrubbingServiceProvider);
        final fileType = scrubbingService.detectFileType(fileBytes);
        if (fileType != null && scrubbingService.isSupportedType(fileType)) {
          final result = await scrubbingService.scrubMetadata(fileBytes);
          if (result.wasModified) {
            fileBytes = result.scrubbedBytes;
          }
        }
      }

      await repo.createContent(
        title: _titleController.text,
        description: _descController.text,
        author: _authorController.text,
        fileData: fileBytes,
        isEncrypted: _enableEncryption,
      );
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentFields = _categoryFields[_selectedCategory] ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Add New Content')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                TextFormField(
                  controller: _descController,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                TextFormField(
                  controller: _authorController,
                  decoration: const InputDecoration(labelText: 'Author'),
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 24),

                // File Picker Area
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _pickFiles,
                        icon: const Icon(Icons.attach_file),
                        label: Text(
                          _selectedFiles.isEmpty
                              ? 'Select Files'
                              : 'Add More Files',
                        ),
                      ),
                      if (_selectedFiles.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        ..._selectedFiles.map(
                          (f) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.insert_drive_file,
                              color: Colors.white70,
                            ),
                            title: Text(f.name),
                            subtitle: Text(
                              '${(f.size / 1024).toStringAsFixed(1)} KB',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () {
                                setState(() {
                                  _selectedFiles.remove(f);
                                  _metadataDetectionDone = false;
                                  _detectedSensitiveFields = [];
                                });
                                if (_stripMetadata &&
                                    _selectedFiles.isNotEmpty) {
                                  _detectSensitiveMetadataFields();
                                }
                              },
                            ),
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 8),
                        Text(
                          'No files selected (Required)',
                          style: TextStyle(
                            color: Colors.red[300],
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (_isAnalyzing) ...[
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(),
                        const SizedBox(height: 4),
                        const Text(
                          'Analyzing Metadata...',
                          style: TextStyle(fontSize: 10, color: Colors.white60),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Category Dropdown
                DropdownButtonFormField<String>(
                  key: ValueKey(_selectedCategory), // Ensure rebuild
                  initialValue: _selectedCategory,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: _categoryFields.keys
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c.toUpperCase()),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedCategory = val;
                        _updateControllers();
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Dynamic Metadata Fields
                if (currentFields.isNotEmpty) ...[
                  Text(
                    'Metadata (${_selectedCategory.toUpperCase()})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  ...currentFields.map((f) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: TextFormField(
                        controller: _metadataControllers[f['key']],
                        decoration: InputDecoration(
                          labelText: f['label'],
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        keyboardType: f['type'] == 'number'
                            ? TextInputType.number
                            : TextInputType.text,
                      ),
                    );
                  }),
                ],

                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SwitchListTile(
                        title: const Text('Encrypt Content'),
                        subtitle: const Text(
                          'Only users with the key can view files.',
                        ),
                        value: _enableEncryption,
                        onChanged: (val) =>
                            setState(() => _enableEncryption = val),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(right: 16.0),
                      child: InfoGlass(
                        title: 'AES-256 Encryption',
                        description:
                            'When enabled, your file is encrypted client-side before upload. The key is wrapped with your Master Key. Without the key, the IPFS CID contains only random noise.',
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: SwitchListTile(
                        title: const Text('Strip Metadata for Privacy'),
                        subtitle: const Text(
                          'Removes GPS location, device info, and author data from images before upload.',
                        ),
                        value: _stripMetadata,
                        onChanged: (val) {
                          setState(() {
                            _stripMetadata = val;
                            _metadataDetectionDone = false;
                            _detectedSensitiveFields = [];
                          });
                          if (val) {
                            _detectSensitiveMetadataFields();
                          }
                        },
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(right: 16.0),
                      child: InfoGlass(
                        title: 'EXIF Stripping',
                        description:
                            'EXIF metadata in images can reveal your location, device, and identity. This strips GPS coordinates, camera serial numbers, and author fields before preservation.',
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
                if (_stripMetadata && _selectedFiles.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  if (_isDetectingMetadata)
                    const Padding(
                      padding: EdgeInsets.only(left: 16.0, bottom: 8.0),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Scanning for sensitive metadata...',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_metadataDetectionDone)
                    Padding(
                      padding: const EdgeInsets.only(left: 16.0, bottom: 8.0),
                      child: Chip(
                        label: Text(
                          _detectedSensitiveFields.isEmpty
                              ? 'No sensitive fields detected — already clean'
                              : '${_detectedSensitiveFields.length} sensitive fields detected — will be stripped',
                          style: const TextStyle(fontSize: 11),
                        ),
                        backgroundColor: _detectedSensitiveFields.isEmpty
                            ? AppTheme.honorColor.withValues(alpha: 0.2)
                            : Colors.amber.withValues(alpha: 0.2),
                        side: BorderSide(
                          color: _detectedSensitiveFields.isEmpty
                              ? AppTheme.honorColor.withValues(alpha: 0.4)
                              : Colors.amber.withValues(alpha: 0.4),
                        ),
                        avatar: Icon(
                          _detectedSensitiveFields.isEmpty
                              ? Icons.verified_user
                              : Icons.privacy_tip,
                          size: 16,
                          color: _detectedSensitiveFields.isEmpty
                              ? AppTheme.honorColor
                              : Colors.amber,
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                          onPressed: _submit,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                          ),
                          child: const Text('Create Manifest'),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
