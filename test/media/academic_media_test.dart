import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/media/academic_media_service.dart';

void main() {
  group('Academic Media Parser Tests', () {
    late AcademicMediaService academicService;

    setUp(() {
      academicService = AcademicMediaService();
    });

    test('parses LaTeX document title, author, and citations', () {
      const tex = r'''
      \documentclass{article}
      \title{General Relativity and Gravitation}
      \author{Albert Einstein \and Marcel Grossmann}
      \begin{abstract}
      A geometric theory of gravitation.
      \end{abstract}
      \usepackage{amsmath}
      \usepackage{physics}
      \begin{document}
      See \cite{lorentz1904, poincare1905}.
      \end{document}
      ''';

      final meta = academicService.parseLatex(tex);
      expect(meta.title, equals('General Relativity and Gravitation'));
      expect(meta.authors.length, equals(2));
      expect(meta.packages, contains('amsmath'));
      expect(meta.citations, contains('lorentz1904'));
    });

    test('parses BibTeX entries accurately', () {
      const bib = '''
      @article{shannon1948,
        title = {A Mathematical Theory of Communication},
        author = {Claude E. Shannon},
        year = {1948}
      }
      ''';

      final entries = academicService.parseBibtex(bib);
      expect(entries.length, equals(1));
      expect(entries.first.key, equals('shannon1948'));
      expect(entries.first.year, equals(1948));
    });
  });
}
