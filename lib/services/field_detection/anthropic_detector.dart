import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

import '../../core/utils/pdf_coords.dart';
import 'field_detector.dart';
import 'field_kind.dart';

/// Render di una pagina in PNG (sostituibile nei test).
typedef PagePngRenderer = Future<Uint8List?> Function(Uint8List pdf, int page, double dpi);

Future<Uint8List?> printingPngRenderer(Uint8List pdf, int page, double dpi) async {
  await for (final r in Printing.raster(pdf, pages: [page], dpi: dpi)) {
    return r.toPng();
  }
  return null;
}

/// Errore del riconoscimento AI, con messaggio per l'utente.
class AiDetectionException implements Exception {
  const AiDetectionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Riconoscimento con l'API Anthropic: la pagina viene renderizzata in PNG e inviata
/// all'API con la chiave dell'utente. La risposta è vincolata a JSON con uno schema.
class AnthropicFieldDetector implements FieldDetector {
  AnthropicFieldDetector({
    required this.apiKey,
    required this.model,
    http.Client? client,
    PagePngRenderer? renderer,
    this.maxPages = 10,
    this.dpi = 110,
  })  : _client = client ?? http.Client(),
        _render = renderer ?? printingPngRenderer;

  final String apiKey;
  final String model;
  final http.Client _client;
  final PagePngRenderer _render;
  final int maxPages;
  final double dpi;

  static final endpoint = Uri.parse('https://api.anthropic.com/v1/messages');
  static const apiVersion = '2026-10-21';

  @override
  String get name => 'AI';

  static const _kinds = [
    'fullName', 'firstName', 'lastName', 'birthDate', 'birthPlace', 'taxCode', 'address', 'zip', //
    'city', 'province', 'phone', 'email', 'date', 'place', 'placeAndDate', 'signature', 'text',
  ];

  /// Schema della risposta: elenco di campi con riquadro normalizzato 0–1.
  static Map<String, Object> get responseSchema => {
        'type': 'object',
        'additionalProperties': false,
        'required': ['fields'],
        'properties': {
          'fields': {
            'type': 'array',
            'items': {
              'type': 'object',
              'additionalProperties': false,
              'required': ['label', 'kind', 'box'],
              'properties': {
                'label': {'type': 'string', 'description': 'Etichetta del campo come appare sulla pagina'},
                'kind': {'type': 'string', 'enum': _kinds},
                'box': {
                  'type': 'object',
                  'additionalProperties': false,
                  'required': ['x0', 'y0', 'x1', 'y1'],
                  'description': "Spazio vuoto da compilare, coordinate 0-1 rispetto all'immagine, origine in alto a sinistra",
                  'properties': {
                    'x0': {'type': 'number'},
                    'y0': {'type': 'number'},
                    'x1': {'type': 'number'},
                    'y1': {'type': 'number'},
                  },
                },
              },
            },
          },
        },
      };

  static const _prompt = '''
Questa immagine è una pagina di un modulo. Trova gli spazi vuoti da compilare (righe "____", puntini, caselle di testo, spazi dopo i due punti, riquadri per la firma).
Per ogni spazio vuoto indica:
- label: l'etichetta vicina (es. "Cognome", "nato/a a", "Firma");
- kind: il tipo di dato atteso, uno tra: fullName, firstName, lastName, birthDate, birthPlace, taxCode, address, zip, city, province, phone, email, date, place, placeAndDate, signature, text (text = qualsiasi altro dato);
- box: il riquadro dello spazio vuoto in coordinate normalizzate 0-1 (x0,y0 in alto a sinistra, x1,y1 in basso a destra), non il riquadro dell'etichetta.
Ignora gli spazi già compilati. Se non ci sono campi, restituisci un elenco vuoto.''';

  /// Corpo della richiesta all'API Messages.
  Map<String, Object> buildRequest(Uint8List png) => {
        'model': model,
        'max_tokens': 8000,
        'output_config': {
          'format': {'type': 'json_schema', 'schema': responseSchema},
        },
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'image',
                'source': {'type': 'base64', 'media_type': 'image/png', 'data': base64Encode(png)},
              },
              {'type': 'text', 'text': _prompt},
            ],
          },
        ],
      };

  Map<String, String> get headers => {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': apiVersion,
        // Necessario per chiamare l'API direttamente dal browser (la chiave è dell'utente).
        if (kIsWeb) 'anthropic-dangerous-direct-browser-access': 'true',
      };

  @override
  Future<List<DetectedField>> detect(DetectionInput input) async {
    if (apiKey.trim().isEmpty) throw const AiDetectionException('Inserisci la chiave API in Impostazioni.');
    final out = <DetectedField>[];
    for (final p in input.targetPages.take(maxPages)) {
      final png = await _render(input.pdf, p, dpi);
      if (png == null) continue;
      final response = await _send(png);
      out.addAll(parseResponse(response, page: p, source: name));
    }
    return out;
  }

  Future<Map<String, dynamic>> _send(Uint8List png) async {
    http.Response res;
    try {
      res = await _client
          .post(endpoint, headers: headers, body: jsonEncode(buildRequest(png)))
          .timeout(const Duration(seconds: 90));
    } catch (_) {
      throw const AiDetectionException('Connessione non riuscita. Controlla internet e riprova.');
    }
    if (res.statusCode != 200) throw AiDetectionException(errorMessage(res.statusCode, res.body));
    try {
      return (jsonDecode(utf8.decode(res.bodyBytes)) as Map).cast<String, dynamic>();
    } catch (_) {
      throw const AiDetectionException('Risposta non valida dal servizio AI.');
    }
  }

  /// Messaggio per l'utente a partire da un errore HTTP.
  static String errorMessage(int status, String body) {
    String? apiMsg;
    try {
      final err = (jsonDecode(body) as Map)['error'];
      if (err is Map) apiMsg = err['message'] as String?;
    } catch (_) {}
    return switch (status) {
      401 => 'Chiave API non valida. Controllala in Impostazioni.',
      403 => 'La chiave API non ha i permessi per questa richiesta.',
      404 => 'Modello non trovato. Controlla il nome del modello in Impostazioni.',
      413 => 'La pagina è troppo grande per il servizio AI.',
      429 => 'Troppe richieste o credito esaurito. Riprova tra poco.',
      400 => 'Richiesta rifiutata${apiMsg != null ? ': $apiMsg' : '.'}',
      >= 500 => 'Il servizio AI non è disponibile in questo momento. Riprova più tardi.',
      _ => 'Errore del servizio AI ($status).',
    };
  }

  /// Converte la risposta dell'API in campi. Tollera testo attorno al JSON.
  static List<DetectedField> parseResponse(Map<String, dynamic> response, {required int page, String source = 'AI'}) {
    final stop = response['stop_reason'];
    if (stop == 'refusal') throw const AiDetectionException('Il servizio AI ha rifiutato di analizzare questa pagina.');
    final content = response['content'];
    if (content is! List) return const [];
    final text = content
        .whereType<Map<dynamic, dynamic>>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'])
        .whereType<String>()
        .join();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      if (stop == 'max_tokens') throw const AiDetectionException('Risposta AI incompleta. Riprova.');
      return const [];
    }
    Object? decoded;
    try {
      decoded = jsonDecode(text.substring(start, end + 1));
    } catch (_) {
      throw const AiDetectionException('Risposta AI non leggibile.');
    }
    final fields = decoded is Map ? decoded['fields'] : null;
    if (fields is! List) return const [];
    final out = <DetectedField>[];
    for (final f in fields.whereType<Map<dynamic, dynamic>>()) {
      final box = f['box'];
      if (box is! Map) continue;
      double? n(Object? v) => v is num ? v.toDouble().clamp(0.0, 1.0) : null;
      final x0 = n(box['x0']), y0 = n(box['y0']), x1 = n(box['x1']), y1 = n(box['y1']);
      if (x0 == null || y0 == null || x1 == null || y1 == null) continue;
      final left = x0 < x1 ? x0 : x1, right = x0 < x1 ? x1 : x0;
      final top = y0 < y1 ? y0 : y1, bottom = y0 < y1 ? y1 : y0;
      if (right - left < 0.01 || bottom - top < 0.004) continue;
      out.add(DetectedField(
        page: page,
        kind: FieldKind.parse(f['kind'] as String?) ?? FieldKind.text,
        label: (f['label'] as String? ?? '').trim(),
        rect: NormRect(left, top, right - left, bottom - top).clamped(minSize: 0.004),
        source: source,
      ));
    }
    return out;
  }
}
