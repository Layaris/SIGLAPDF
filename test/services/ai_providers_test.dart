import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sigla/core/storage/key_value_store.dart';
import 'package:sigla/core/utils/pdf_coords.dart';
import 'package:sigla/features/settings/settings_model.dart';
import 'package:sigla/features/settings/settings_repository.dart';
import 'package:sigla/services/field_detection/ai_detector.dart';
import 'package:sigla/services/field_detection/field_detector.dart';
import 'package:sigla/services/field_detection/field_kind.dart';
import 'package:sigla/services/pdf_service.dart';

import '../pdf_fixtures.dart';

final _dpis = <double>[];
Future<Uint8List?> _fakePng(Uint8List pdf, int page, double dpi) async {
  _dpis.add(dpi);
  return Uint8List.fromList([137, 80, 78, 71]);
}

http.Response _gemini(Object fields, {String finish = 'STOP', bool withThought = false}) => http.Response(
      jsonEncode({
        'candidates': [
          {
            'finishReason': finish,
            'content': {
              'parts': [
                if (withThought) {'text': 'ragiono...', 'thought': true},
                {'text': jsonEncode({'fields': fields})},
              ],
            },
          },
        ],
      }),
      200,
    );

http.Response _nano(String content, {String finish = 'stop'}) => http.Response(
      jsonEncode({
        'choices': [
          {
            'finish_reason': finish,
            'message': {'role': 'assistant', 'content': content},
          },
        ],
      }),
      200,
    );

void main() {
  final pdf = buildPlainPdf(pages: 2);
  final pages = const PdfService().inspect(pdf).pages;
  setUp(_dpis.clear);

  test('Gemini: modello nell\'indirizzo, chiave nell\'header, immagine e schema con box_2d', () async {
    late http.Request sent;
    final client = MockClient((req) async {
      sent = req;
      return _gemini([
        {'label': 'Cognome', 'kind': 'lastName', 'box_2d': [200, 300, 230, 700]},
        {'label': 'Patente', 'kind': 'custom', 'box_2d': [400, 100, 430, 500]},
        {'label': '', 'kind': 'custom', 'box_2d': [500, 100, 530, 500]},
      ], withThought: true);
    });
    final d = AiFieldDetector(chain: const [AiAccess(AiProvider.gemini, ' AIza-k ', '')], client: client, renderer: _fakePng);
    final fields = await d.detect(DetectionInput(pdf: pdf, pages: pages, pageIndexes: const [0], extraLabels: const ['Patente']));

    expect(sent.url.toString(), 'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent');
    expect(sent.headers['x-goog-api-key'], 'AIza-k');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    final parts = body['contents'][0]['parts'] as List;
    expect(parts.first['inline_data']['mime_type'], 'image/png');
    expect(parts.last['text'], contains('"Patente"'), reason: 'i dati personalizzati del profilo vanno nelle istruzioni');
    expect(parts.last['text'], contains('box_2d'));
    final cfg = body['generationConfig'] as Map;
    expect(cfg['responseMimeType'], 'application/json');
    expect(jsonEncode(cfg['responseSchema']), contains('box_2d'));
    expect(_dpis.single, 150);

    expect(fields, hasLength(3));
    expect(fields[0].kind, FieldKind.lastName);
    expect(fields[0].rect.x, closeTo(0.3, 1e-9));
    expect(fields[0].rect.y, closeTo(0.2, 1e-9));
    expect(fields[0].rect.right, closeTo(0.7, 1e-9));
    expect(fields[1].kind, FieldKind.custom);
    expect(fields[1].label, 'Patente');
    expect(fields[2].kind, FieldKind.text, reason: 'dato personalizzato senza nome → testo');
    expect(d.usedProviders, {AiProvider.gemini});
    expect(d.lastWarning, isNull);
  });

  test('NanoGPT: formato OpenAI, chiave Bearer, schema nel testo, JSON tra ```', () async {
    late http.Request sent;
    final client = MockClient((req) async {
      sent = req;
      return _nano('Ecco i campi:\n```json\n{"fields":[{"label":"Firma","kind":"signature","box_2d":[880,550,920,900]}]}\n```');
    });
    final d = AiFieldDetector(chain: const [AiAccess(AiProvider.nanogpt, 'nk', 'google/gemini-3.1-flash-lite')], client: client, renderer: _fakePng);
    final fields = await d.detect(DetectionInput(pdf: pdf, pages: pages, pageIndexes: const [1]));

    expect(sent.url.toString(), 'https://api.nano-gpt.com/api/v1/chat/completions');
    expect(sent.headers['authorization'], 'Bearer nk');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['model'], 'google/gemini-3.1-flash-lite');
    expect(body.containsKey('response_format'), isFalse, reason: 'i modelli economici non lo supportano');
    final content = body['messages'][0]['content'] as List;
    expect(content.first['image_url']['url'], startsWith('data:image/png;base64,'));
    expect(content.last['text'], contains('JSON Schema'));
    expect(content.last['text'], contains('"type":"object"'), reason: 'schema Gemini tradotto in JSON Schema normale');

    expect(fields.single.kind, FieldKind.signature);
    expect(fields.single.page, 1);
  });

  test('automatico: Gemini al limite → NanoGPT per questa pagina e per le successive', () async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add(req.url.host);
      if (req.url.host.contains('googleapis')) return http.Response('{"error":{"code":429,"status":"RESOURCE_EXHAUSTED"}}', 429);
      return _nano('{"fields":[{"label":"Nome","kind":"firstName","box_2d":[200,300,230,700]}]}');
    });
    final d = AiFieldDetector(
      chain: const [AiAccess(AiProvider.gemini, 'g'), AiAccess(AiProvider.nanogpt, 'n')],
      client: client,
      renderer: _fakePng,
    );
    final fields = await d.detect(DetectionInput(pdf: pdf, pages: pages));
    expect(fields, hasLength(2));
    expect(calls, ['generativelanguage.googleapis.com', 'api.nano-gpt.com', 'api.nano-gpt.com'], reason: 'Gemini non si riprova a ogni pagina');
    expect(d.usedProviders, {AiProvider.nanogpt});
    expect(d.lastWarning, contains('Google Gemini'));
    expect(d.lastWarning, contains('Limite di richieste'));
    expect(d.lastWarning, contains('NanoGPT'));
  });

  test('tutti i servizi falliscono: errore con i motivi di ognuno', () async {
    final client = MockClient((req) async => req.url.host.contains('nano')
        ? http.Response('{"error":{"message":"Insufficient balance"}}', 402)
        : http.Response('{"error":{"code":400,"message":"API key not valid.","status":"INVALID_ARGUMENT","details":[{"reason":"API_KEY_INVALID"}]}}', 400));
    final d = AiFieldDetector(
      chain: const [AiAccess(AiProvider.gemini, 'g'), AiAccess(AiProvider.nanogpt, 'n')],
      client: client,
      renderer: _fakePng,
    );
    await expectLater(
      d.detect(DetectionInput(pdf: pdf, pages: pages)),
      throwsA(isA<AiDetectionException>()
          .having((e) => e.message, 'gemini', contains('Chiave Google Gemini non valida'))
          .having((e) => e.message, 'nano', contains('Credito esaurito su NanoGPT'))),
    );
  });

  test('risposte Gemini tagliate o bloccate: messaggi chiari', () async {
    for (final r in [_gemini(const [], finish: 'MAX_TOKENS'), _gemini(const [], finish: 'SAFETY')]) {
      final d = AiFieldDetector(chain: const [AiAccess(AiProvider.gemini, 'g')], client: MockClient((_) async => r), renderer: _fakePng);
      await expectLater(d.detect(DetectionInput(pdf: pdf, pages: pages)), throwsA(isA<AiDetectionException>()));
    }
    expect(aiErrorMessage(AiProvider.gemini, 503, ''), contains('Google Gemini non è disponibile'));
    expect(aiErrorMessage(AiProvider.nanogpt, 429, ''), contains('Troppe richieste a NanoGPT'));
    expect(aiErrorMessage(AiProvider.nanogpt, 400, '{"error":{"message":"model does not support images"}}'), contains('model does not support images'));
  });

  test('prova della connessione: solo testo, poco costosa', () async {
    late Map<String, dynamic> body;
    final ok = MockClient((req) async {
      body = jsonDecode(req.body) as Map<String, dynamic>;
      return _gemini(const []);
    });
    await testAiConnection(const AiAccess(AiProvider.gemini, 'g'), client: ok);
    expect(jsonEncode(body), isNot(contains('inline_data')));
    expect(body['generationConfig']['maxOutputTokens'], 50);

    await expectLater(
      testAiConnection(const AiAccess(AiProvider.nanogpt, 'n'), client: MockClient((_) async => http.Response('{}', 401))),
      throwsA(isA<AiDetectionException>().having((e) => e.message, 'm', contains('Chiave NanoGPT non valida'))),
    );
    await expectLater(testAiConnection(const AiAccess(AiProvider.anthropic, ' ')), throwsA(isA<AiDetectionException>()));
  });

  test('impostazioni: ordine dei servizi, scelta di uno solo, chiavi fuori dal backup', () async {
    const s = AppSettings(geminiApiKey: 'g', nanoGptApiKey: '', aiApiKey: 'a', geminiModel: 'gemini-3.8-flash');
    expect(s.aiChain.map((a) => a.provider), [AiProvider.gemini, AiProvider.anthropic]);
    expect(s.aiChain.first.effectiveModel, 'gemini-3.8-flash');
    expect(s.copyWith(aiMode: 'anthropic').aiChain.map((a) => a.provider), [AiProvider.anthropic]);
    expect(s.copyWith(aiMode: 'nanogpt').aiChain, isEmpty, reason: 'scelto NanoGPT ma senza chiave');
    expect(const AppSettings().aiChain, isEmpty);

    final backup = s.copyWith(nanoGptApiKey: 'n', aiMode: 'gemini').toBackupMap();
    expect(backup.toString(), isNot(contains('nanoGptApiKey')));
    expect(backup.toString(), isNot(contains('geminiApiKey')));
    expect(backup['aiMode'], 'gemini');
    final back = AppSettings.fromMap(s.toMap());
    expect(back.geminiApiKey, 'g');
    expect(AppSettings.fromMap({'aiMode': 'boh'}).aiMode, 'auto');

    final repo = SettingsRepository(MemoryKeyValueStore());
    await repo.update((x) => x.copyWith(geminiApiKey: 'locale-g', nanoGptApiKey: 'locale-n'));
    await repo.restoreFromBackup({...backup, 'geminiModel': 'x'});
    expect(repo.value.geminiApiKey, 'locale-g', reason: 'le chiavi restano quelle del dispositivo');
    expect(repo.value.nanoGptApiKey, 'locale-n');
    expect(repo.value.geminiModel, 'x');
  });

  test('unione: posizioni del dispositivo tenute, dall\'AI solo i campi in più', () {
    DetectedField f(int page, double x, double y, FieldKind k, String src) =>
        DetectedField(page: page, kind: k, label: k.name, rect: NormRect(x, y, 0.3, 0.03), source: src);
    final local = [f(0, 0.3, 0.2, FieldKind.lastName, 'locale')];
    final ai = [
      f(0, 0.31, 0.205, FieldKind.text, 'AI'), // stesso spazio: si tiene quello del dispositivo
      f(0, 0.3, 0.5, FieldKind.taxCode, 'AI'), // in più
      f(1, 0.3, 0.2, FieldKind.email, 'AI'), // altra pagina
    ];
    final merged = mergeDetections(local, ai);
    expect(merged.map((m) => m.kind), [FieldKind.lastName, FieldKind.taxCode, FieldKind.email]);
    expect(merged.first.source, 'locale');
  });

  test('riquadri: box 0–1 e box_2d 0–1000, invertiti o fuori scala', () {
    expect(aiRect({'x0': 0.7, 'y0': 0.3, 'x1': 0.2, 'y1': 0.1})!.x, closeTo(0.2, 1e-9));
    final r = aiRect([300, 100, 200, 1200])!;
    expect(r.y, closeTo(0.2, 1e-9));
    expect(r.right, 1.0);
    expect(aiRect([1, 2, 3]), isNull);
    expect(aiRect('x'), isNull);
  });
}
