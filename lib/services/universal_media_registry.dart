import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'external_player_service.dart';

final universalMediaRegistryProvider =
    Provider((_) => UniversalMediaRegistry());

enum MediaDomain {
  academicAndScience,
  tabularAndDatasets,
  literatureAndComics,
  audioAndAcoustic,
  visualArtAndSpatial,
  webAndSoftwareHeritage,
  genericBinary,
}

class MediaFormatDescriptor {
  final String extension;
  final String mimeType;
  final String canonicalName;
  final MediaDomain domain;
  final SupportedApp preferredApp;
  final int recommendedFastCdcChunkSize;

  const MediaFormatDescriptor({
    required this.extension,
    required this.mimeType,
    required this.canonicalName,
    required this.domain,
    required this.preferredApp,
    this.recommendedFastCdcChunkSize = 8192,
  });
}

class UniversalMediaRegistry {
  final Map<String, MediaFormatDescriptor> _registry = {};

  UniversalMediaRegistry() {
    _registerAll();
  }

  void _registerAll() {
    // 1. Academic, Science & Computation
    _add(const MediaFormatDescriptor(
      extension: 'tex',
      mimeType: 'application/x-tex',
      canonicalName: 'LaTeX Source Document',
      domain: MediaDomain.academicAndScience,
      preferredApp: SupportedApp.codeEditor,
      recommendedFastCdcChunkSize: 4096,
    ));
    _add(const MediaFormatDescriptor(
      extension: 'bib',
      mimeType: 'application/x-bibtex',
      canonicalName: 'BibTeX Bibliography Database',
      domain: MediaDomain.academicAndScience,
      preferredApp: SupportedApp.codeEditor,
      recommendedFastCdcChunkSize: 4096,
    ));
    _add(const MediaFormatDescriptor(
      extension: 'typ',
      mimeType: 'text/x-typst',
      canonicalName: 'Typst Document',
      domain: MediaDomain.academicAndScience,
      preferredApp: SupportedApp.codeEditor,
      recommendedFastCdcChunkSize: 4096,
    ));
    _add(const MediaFormatDescriptor(
      extension: 'ipynb',
      mimeType: 'application/x-ipynb+json',
      canonicalName: 'Jupyter Computational Notebook',
      domain: MediaDomain.academicAndScience,
      preferredApp: SupportedApp.codeEditor,
      recommendedFastCdcChunkSize: 8192,
    ));

    // 2. Tabular & Columnar Datasets
    _add(const MediaFormatDescriptor(
      extension: 'parquet',
      mimeType: 'application/vnd.apache.parquet',
      canonicalName: 'Apache Parquet Columnar Storage',
      domain: MediaDomain.tabularAndDatasets,
      preferredApp: SupportedApp.systemDefault,
      recommendedFastCdcChunkSize: 32768,
    ));
    _add(const MediaFormatDescriptor(
      extension: 'arrow',
      mimeType: 'application/vnd.apache.arrow.file',
      canonicalName: 'Apache Arrow Feather Table',
      domain: MediaDomain.tabularAndDatasets,
      preferredApp: SupportedApp.systemDefault,
      recommendedFastCdcChunkSize: 32768,
    ));
    _add(const MediaFormatDescriptor(
      extension: 'fits',
      mimeType: 'application/fits',
      canonicalName: 'Flexible Image Transport System (FITS Astronomy)',
      domain: MediaDomain.tabularAndDatasets,
      preferredApp: SupportedApp.systemDefault,
      recommendedFastCdcChunkSize: 65536,
    ));
    _add(const MediaFormatDescriptor(
      extension: 'csv',
      mimeType: 'text/csv',
      canonicalName: 'Comma-Separated Values',
      domain: MediaDomain.tabularAndDatasets,
      preferredApp: SupportedApp.systemDefault,
      recommendedFastCdcChunkSize: 8192,
    ));

    // 3. Literature, Scanned Books & Comics
    _add(const MediaFormatDescriptor(
      extension: 'djvu',
      mimeType: 'image/vnd.djvu',
      canonicalName: 'DjVu Scanned Book',
      domain: MediaDomain.literatureAndComics,
      preferredApp: SupportedApp.calibre,
      recommendedFastCdcChunkSize: 16384,
    ));
    _add(const MediaFormatDescriptor(
      extension: 'cbz',
      mimeType: 'application/vnd.comicbook+zip',
      canonicalName: 'Comic Book Archive (Zip)',
      domain: MediaDomain.literatureAndComics,
      preferredApp: SupportedApp.calibre,
      recommendedFastCdcChunkSize: 32768,
    ));
    _add(const MediaFormatDescriptor(
      extension: 'epub',
      mimeType: 'application/epub+zip',
      canonicalName: 'Electronic Publication (EPUB)',
      domain: MediaDomain.literatureAndComics,
      preferredApp: SupportedApp.calibre,
      recommendedFastCdcChunkSize: 16384,
    ));
    _add(const MediaFormatDescriptor(
      extension: 'pdf',
      mimeType: 'application/pdf',
      canonicalName: 'Portable Document Format (PDF)',
      domain: MediaDomain.literatureAndComics,
      preferredApp: SupportedApp.calibre,
      recommendedFastCdcChunkSize: 16384,
    ));

    // 4. Audio & Acoustic Archives
    _add(const MediaFormatDescriptor(
      extension: 'flac',
      mimeType: 'audio/flac',
      canonicalName: 'Free Lossless Audio Codec (FLAC)',
      domain: MediaDomain.audioAndAcoustic,
      preferredApp: SupportedApp.vlc,
      recommendedFastCdcChunkSize: 32768,
    ));
    _add(const MediaFormatDescriptor(
      extension: 'opus',
      mimeType: 'audio/opus',
      canonicalName: 'Opus Interactive Audio',
      domain: MediaDomain.audioAndAcoustic,
      preferredApp: SupportedApp.vlc,
      recommendedFastCdcChunkSize: 16384,
    ));
    _add(const MediaFormatDescriptor(
      extension: 'm4b',
      mimeType: 'audio/mp4',
      canonicalName: 'MPEG-4 Audiobook with Chapters',
      domain: MediaDomain.audioAndAcoustic,
      preferredApp: SupportedApp.vlc,
      recommendedFastCdcChunkSize: 32768,
    ));
    _add(const MediaFormatDescriptor(
      extension: 'musicxml',
      mimeType: 'application/vnd.recordare.musicxml+xml',
      canonicalName: 'MusicXML Notation Score',
      domain: MediaDomain.audioAndAcoustic,
      preferredApp: SupportedApp.systemDefault,
      recommendedFastCdcChunkSize: 4096,
    ));

    // 5. Visual Art & 3D Spatial Heritage
    _add(const MediaFormatDescriptor(
      extension: 'jxl',
      mimeType: 'image/jxl',
      canonicalName: 'JPEG XL Archival Raster',
      domain: MediaDomain.visualArtAndSpatial,
      preferredApp: SupportedApp.systemDefault,
      recommendedFastCdcChunkSize: 16384,
    ));
    _add(const MediaFormatDescriptor(
      extension: 'tiff',
      mimeType: 'image/tiff',
      canonicalName: 'Tagged Image File Format (TIFF Master)',
      domain: MediaDomain.visualArtAndSpatial,
      preferredApp: SupportedApp.systemDefault,
      recommendedFastCdcChunkSize: 65536,
    ));
    _add(const MediaFormatDescriptor(
      extension: 'glb',
      mimeType: 'model/gltf-binary',
      canonicalName: 'glTF 2.0 Binary Spatial Model',
      domain: MediaDomain.visualArtAndSpatial,
      preferredApp: SupportedApp.blender,
      recommendedFastCdcChunkSize: 32768,
    ));
    _add(const MediaFormatDescriptor(
      extension: 'ply',
      mimeType: 'application/x-ply',
      canonicalName: 'Polygon File Format / Gaussian Splat',
      domain: MediaDomain.visualArtAndSpatial,
      preferredApp: SupportedApp.blender,
      recommendedFastCdcChunkSize: 65536,
    ));
    _add(const MediaFormatDescriptor(
      extension: 'kicad_sch',
      mimeType: 'application/x-kicad-schematic',
      canonicalName: 'KiCad Open Hardware Schematic',
      domain: MediaDomain.visualArtAndSpatial,
      preferredApp: SupportedApp.kicad,
      recommendedFastCdcChunkSize: 8192,
    ));

    // 6. Web & Software Heritage
    _add(const MediaFormatDescriptor(
      extension: 'warc',
      mimeType: 'application/warc',
      canonicalName: 'Web ARChive (ISO 28500)',
      domain: MediaDomain.webAndSoftwareHeritage,
      preferredApp: SupportedApp.replayWeb,
      recommendedFastCdcChunkSize: 32768,
    ));
    _add(const MediaFormatDescriptor(
      extension: 'bundle',
      mimeType: 'application/x-git-bundle',
      canonicalName: 'Git Repository Offline Bundle',
      domain: MediaDomain.webAndSoftwareHeritage,
      preferredApp: SupportedApp.codeEditor,
      recommendedFastCdcChunkSize: 32768,
    ));
    _add(const MediaFormatDescriptor(
      extension: 'wasm',
      mimeType: 'application/wasm',
      canonicalName: 'WebAssembly Binary Module',
      domain: MediaDomain.webAndSoftwareHeritage,
      preferredApp: SupportedApp.systemDefault,
      recommendedFastCdcChunkSize: 16384,
    ));
  }

  void _add(MediaFormatDescriptor desc) {
    _registry[desc.extension.toLowerCase()] = desc;
  }

  MediaFormatDescriptor resolveExtension(String ext) {
    final clean = ext.replaceFirst('.', '').toLowerCase();
    return _registry[clean] ??
        MediaFormatDescriptor(
          extension: clean,
          mimeType: 'application/octet-stream',
          canonicalName: 'Generic Binary Object',
          domain: MediaDomain.genericBinary,
          preferredApp: SupportedApp.systemDefault,
        );
  }
}
