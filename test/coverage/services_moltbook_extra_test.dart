import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/poch_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MoltbookService simple accessors', () {
    test('baseUrl/apiKey/agentId/pubkeyHex/lastPostTime/setApiKey', () async {
      final creditService =
          CreditService(pochService: PoCHService(), initialBalance: 5.0);
      final service = MoltbookService(
        creditService: creditService,
        baseUrl: 'https://example.test',
        apiKey: ' key1 ',
      );
      addTearDown(service.dispose);

      expect(service.baseUrl, 'https://example.test');
      expect(service.apiKey, isNotNull);
      // Key init is asynchronous — give it a moment to populate the
      // identity getters before disposing.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(service.agentId, isA<String>());
      expect(service.pubkeyHex, isA<String>());
      expect(service.lastPostTime, isA<DateTime?>());

      service.setApiKey('  new-key  ');
      expect(service.apiKey, 'new-key');
      service.setApiKey(null);
      expect(service.apiKey, isNull);
    });
  });
}
