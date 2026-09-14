import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/l10n/app_localizations.dart';
import 'package:alexandria/l10n/app_localizations_en.dart';

void main() {
  group('AppLocalizations Tests', () {
    test('supportedLocales contains en', () {
      expect(AppLocalizations.supportedLocales, contains(const Locale('en')));
    });

    test('delegate reports isSupported correctly', () {
      const delegate = AppLocalizations.delegate;
      expect(delegate.isSupported(const Locale('en')), isTrue);
      expect(delegate.isSupported(const Locale('es')), isFalse);
      expect(delegate.shouldReload(delegate), isFalse);
    });

    test('loads AppLocalizationsEn and provides all string keys', () async {
      final loc = await AppLocalizations.delegate.load(const Locale('en'));
      expect(loc, isA<AppLocalizationsEn>());

      expect(loc.appTitle, equals('Alexandria'));
      expect(loc.homeScreenTitle, equals('Library'));
      expect(loc.addContentTooltip, equals('Add Content'));
      expect(loc.searchHint, equals('Search the archive...'));

      final directEn = AppLocalizationsEn();
      expect(directEn.localeName, equals('en'));
      expect(directEn.appTitle, equals('Alexandria'));
    });

    test('lookupAppLocalizations throws for unsupported locale', () {
      expect(
        () => lookupAppLocalizations(const Locale('fr')),
        throwsFlutterError,
      );
    });

    testWidgets('AppLocalizations.of returns instance within Localizations widget', (tester) async {
      late AppLocalizations found;
      await tester.pumpWidget(
        Localizations(
          locale: const Locale('en'),
          delegates: AppLocalizations.localizationsDelegates,
          child: Builder(
            builder: (context) {
              found = AppLocalizations.of(context)!;
              return Container();
            },
          ),
        ),
      );

      expect(found, isNotNull);
      expect(found.appTitle, equals('Alexandria'));
    });
  });
}
