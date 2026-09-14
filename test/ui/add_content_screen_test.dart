import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/logic/content_repository.dart';
import 'package:alexandria/services/cid_service.dart';
import 'package:alexandria/services/metadata_scrubbing_service.dart';
import 'package:alexandria/services/metadata_service.dart';
import 'package:alexandria/ui/add_content_screen.dart';

class _FakeContentRepository implements ContentRepository {
  bool createContentCalled = false;
  String? lastTitle;
  String? lastAuthor;
  bool? lastEncrypted;
  Uint8List? lastFileData;

  @override
  Future<String> createContent({
    required String title,
    String? author,
    String? description,
    required Uint8List fileData,
    bool isEncrypted = false,
    List<String>? tags,
    String? category,
    String? format,
    Map<String, dynamic>? extraMetadata,
  }) async {
    createContentCalled = true;
    lastTitle = title;
    lastAuthor = author;
    lastEncrypted = isEncrypted;
    lastFileData = fileData;
    return 'new-uuid-123';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockMetadataService implements MetadataExtractionService {
  @override
  Future<Map<String, dynamic>> extractMetadata(PlatformFile file) async {
    return {
      'resolution': '1920x1080',
      'camera_model': 'Nikon Z8',
      'iso': '100',
      'aperture': 'f/2.8',
      'shutter_speed': '1/250',
      'focal_length': '50mm',
      'date_taken': '2026-01-01',
      'location': 'Alexandria Library',
      'row_count': 500,
      'dependencies': 12,
      'size_bytes': 1048576,
      'format': 'png',
    };
  }
}

class _MockScrubbingService implements MetadataScrubbingService {
  @override
  Future<List<String>> detectSensitiveFields(Uint8List bytes) async {
    return ['GPSLatitude', 'Make', 'Model'];
  }

  @override
  String? detectFileType(Uint8List bytes) => 'png';

  @override
  bool isSupportedType(String type) => true;

  @override
  Future<ScrubbingResult> scrubMetadata(
    Uint8List bytes, {
    ScrubbingOptions options = ScrubbingOptions.privacy,
  }) async {
    return ScrubbingResult(
      scrubbedBytes: Uint8List.fromList([1, 2, 3, 4]),
      newCid: 'bafytest',
      removedFields: ['GPSLatitude'],
      originalSize: 5,
      scrubbedSize: 4,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AddContentScreen Tests', () {
    testWidgets('renders add content form with inputs and category selector', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final cidService = CidService();
      final scrubbingService = MetadataScrubbingService(cidService);
      final metadataService = MetadataExtractionService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contentRepositoryProvider.overrideWithValue(_FakeContentRepository()),
            metadataScrubbingServiceProvider.overrideWithValue(scrubbingService),
            metadataServiceProvider.overrideWithValue(metadataService),
          ],
          child: const MaterialApp(
            home: AddContentScreen(),
          ),
        ),
      );

      expect(find.text('Add New Content'), findsOneWidget);
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Author'), findsOneWidget);
      expect(find.text('Description'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'Opticks');
      await tester.enterText(find.byType(TextFormField).at(2), 'Isaac Newton');
      await tester.pump();
    });

    testWidgets('interacts with category dropdown, toggles switches, and validates missing files', (tester) async {
      tester.view.physicalSize = const Size(1920, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeRepo = _FakeContentRepository();
      final mockMeta = _MockMetadataService();
      final mockScrub = _MockScrubbingService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contentRepositoryProvider.overrideWithValue(fakeRepo),
            metadataScrubbingServiceProvider.overrideWithValue(mockScrub),
            metadataServiceProvider.overrideWithValue(mockMeta),
          ],
          child: const MaterialApp(
            home: AddContentScreen(),
          ),
        ),
      );

      // Fill in required fields so validation succeeds past FormState.validate()
      await tester.enterText(find.byType(TextFormField).at(0), 'Opticks');
      await tester.enterText(find.byType(TextFormField).at(2), 'Isaac Newton');
      await tester.pump();

      // Change category to 'dataset'
      final dropdownFinder = find.byType(DropdownButtonFormField<String>);
      expect(dropdownFinder, findsOneWidget);
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      await tester.tap(find.text('DATASET').last);
      await tester.pumpAndSettle();

      expect(find.text('Metadata (DATASET)'), findsOneWidget);

      // Toggle encryption switch
      final encryptSwitch = find.widgetWithText(SwitchListTile, 'Encrypt Content');
      expect(encryptSwitch, findsOneWidget);
      await tester.tap(encryptSwitch);
      await tester.pumpAndSettle();

      // Toggle strip metadata switch
      final stripSwitch = find.widgetWithText(SwitchListTile, 'Strip Metadata for Privacy');
      expect(stripSwitch, findsOneWidget);
      await tester.tap(stripSwitch);
      await tester.pumpAndSettle();
      await tester.tap(stripSwitch);
      await tester.pumpAndSettle();

      // Ensure Create Manifest is visible and tap it
      await tester.ensureVisible(find.text('Create Manifest'));
      await tester.tap(find.text('Create Manifest'));
      await tester.pumpAndSettle();

      expect(find.text('Please select at least one file.'), findsOneWidget);
    });

    testWidgets('populates initialFiles, analyzes metadata, and submits manifest', (tester) async {
      tester.view.physicalSize = const Size(1920, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeRepo = _FakeContentRepository();
      final mockMeta = _MockMetadataService();
      final mockScrub = _MockScrubbingService();

      final sampleFile = PlatformFile(
        name: 'test_sample.png',
        size: 1024,
        bytes: Uint8List.fromList([10, 20, 30, 40, 50]),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contentRepositoryProvider.overrideWithValue(fakeRepo),
            metadataScrubbingServiceProvider.overrideWithValue(mockScrub),
            metadataServiceProvider.overrideWithValue(mockMeta),
          ],
          child: MaterialApp(
            home: AddContentScreen(initialFiles: [sampleFile]),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('test_sample.png'), findsOneWidget);
      expect(find.textContaining('sensitive fields detected'), findsOneWidget);

      // Enter required fields
      await tester.enterText(find.byType(TextFormField).at(0), 'Principia');
      await tester.enterText(find.byType(TextFormField).at(1), 'Philosophiae Naturalis');
      await tester.enterText(find.byType(TextFormField).at(2), 'Isaac Newton');
      await tester.pump();

      // Submit the form
      await tester.ensureVisible(find.text('Create Manifest'));
      await tester.tap(find.text('Create Manifest'));
      await tester.pumpAndSettle();

      expect(fakeRepo.createContentCalled, isTrue);
      expect(fakeRepo.lastTitle, 'Principia');
      expect(fakeRepo.lastAuthor, 'Isaac Newton');
      expect(fakeRepo.lastFileData, isNotNull);
    });
  });
}
