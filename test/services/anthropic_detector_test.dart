import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sigla/services/field_detection/anthropic_detector.dart';
import 'package:sigla/services/field_detection/field_detector.dart';
import 'package:sigla/services/field_detection/field_kind.dart';
import 'package:sigla/services/pdf_service.dart';

import '../pdf_fixtures.dart';

Future<Uint8List?> _fakePng(Uint8List pdf, int page, double dpi) async => Uint8List.fromList([137, 80, 78, 71]);

Map<String, dynamic> _reply(Object fields, {String stop = 'end_turn'}) => {
      'id': 'msg_1',
      'type': 'message',
      'role': 'assistant',
      'stop_reason': stop,
      'content': [
        {'type': 'text', 'text': jsonEncode({'fields': fields})},
      ],
    };

void main() {
  final pdf = buildPlainPdf(pages: 2);
  final pages = const PdfService().inspect(pdf).pages;

  test('invia immagine e schema JSON con gli header giusti, legge i campi', () async {
    late http.Request sent;
    final client = MockClient((req) async {
      sent = req;
      return http.Response(
        jsonEncode(_reply([
          {'label': 'Cognome', 'kind': 'lastName', 'box': {'x0': 0.3, 'y0': 0.2, 'x1': 0.7, 'y1': 0.23}},
          {'label': 'Firma', 'kind': 'signature', 'box': {'x0': 0.6, 'y0': 0.9, 'x1': 0.4, 'y1': 0.85}},
          {'label': 'Strano', 'kind': 'boh', 'box': {'x0': 0.1, 'y0': 0.5, 'x1': 0.3, 'y1': 0.52}},
          {'label': 'Rotto', 'kind': 'email', 'box': {'x0': 0.1}},
        ])),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final d = AnthropicFieldDetector(apiKey: 'sk-test', model: 'claude-haiku-5-5', client: client, renderer: _fakePng);
    final fields = await d.detect(DetectionInput(pdf: pdf, pages: pages, pageIndexes: const [1]));

    expect(sent.url.toString(), 'https://api.anthropic.com/v1/messages');
    expect(sent.headers['x-api-key'], 'sk-test');
    expect(sent.headers['anthropic-version'], '2026-10-21');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['model'], 'claude-haiku-5-5');
    expect(body['output_config']['format']['type'], 'json_schema');
    final content = (body['messages'] as List).single['content'] as List;
    expect(content.first['type'], 'image');
    expect(content.first['source']['media_type'], 'image/png');

    expect(fields, hasLength(3));
    expect(fields[0].kind, FieldKind.lastName);
    expect(fields[0].page, 1);
    expect(fields[0].source, 'AI');
    expect(fields[0].rect.x, closeTo(0.3, 1e-9));
    expect(fields[1].rect.x, closeTo(0.4, 1e-9), reason: 'coordinate invertite riordinate');
    expect(fields[2].kind, FieldKind.text, reason: 'tipo sconosciuto → testo');
  });

  test('errori HTTP tradotti in messaggi chiari', () async {
    for (final (code, text) in [
      (401, 'Chiave API non valida'),
      (429, 'Troppe richieste'),
      (529, 'non è disponibile'),
      (404, 'Modello non trovato'),
    ]) {
      final client = MockClient((_) async => http.Response('{"type":"error","error":{"type":"x","message":"m"}}', code));
      final d = AnthropicFieldDetector(apiKey: 'k', model: 'm', client: client, renderer: _fakePng);
      await expectLater(
        d.detect(DetectionInput(pdf: pdf, pages: pages)),
        throwsA(isA<AiDetectionException>().having((e) => e.message, 'message', contains(text))),
      );
    }
  });

  test('chiave mancante, rifiuto e rete assente', () async {
    final noKey = AnthropicFieldDetector(apiKey: ' ', model: 'm', renderer: _fakePng);
    await expectLater(noKey.detect(DetectionInput(pdf: pdf, pages: pages)), throwsA(isA<AiDetectionException>()));

    expect(
      () => AnthropicFieldDetector.parseResponse(_reply(const [], stop: 'refusal'), page: 0),
      throwsA(isA<AiDetectionException>()),
    );
    final offline = AnthropicFieldDetector(
      apiKey: 'k',
      model: 'm',
      client: MockClient((_) async => throw http.ClientException('offline')),
      renderer: _fakePng,
    );
    await expectLater(
      offline.detect(DetectionInput(pdf: pdf, pages: pages)),
      throwsA(isA<AiDetectionException>().having((e) => e.message, 'm', contains('Connessione'))),
    );
  });

  test('tollera testo attorno al JSON e risposte senza campi', () {
    final r = {
      'stop_reason': 'end_turn',
      'content': [
        {'type': 'text', 'text': 'Ecco: {"fields":[{"label":"Data","kind":"date","box":{"x0":0.1,"y0":0.1,"x1":0.3,"y1":0.12}}]} fine'},
      ],
    };
    expect(AnthropicFieldDetector.parseResponse(r, page: 0).single.kind, FieldKind.date);
    expect(AnthropicFieldDetector.parseResponse({'content': <Object>[]}, page: 0), isEmpty);
  });

  test('analizza al massimo maxPages pagine', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response(jsonEncode(_reply(const [])), 200);
    });
    final d = AnthropicFieldDetector(apiKey: 'k', model: 'm', client: client, renderer: _fakePng, maxPages: 1);
    await d.detect(DetectionInput(pdf: pdf, pages: pages));
    expect(calls, 1);
  });
}
