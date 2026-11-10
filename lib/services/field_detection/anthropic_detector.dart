import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

import '../../core/l10n/l10n.dart';
import '../../core/utils/pdf_coords.dart';
import 'field_detector.dart';
import 'field_kind.dart';
import 'local_text_detector.dart';

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
    'fullName', 'lastFirstName', 'firstName', 'lastName', 'birthDate', 'birthPlace', 'birthProvince', //
    'birthPlaceAndDate', 'taxCode', 'address', 'zip', 'city', 'province', 'phone', 'email', 'date', 'place', //
    'placeAndDate', 'signature', 'gender', 'yesNo', 'text',
  ];

  static Map<String, Object> get _boxSchema => {
        'type': 'object',
        'additionalProperties': false,
        'required': ['x0', 'y0', 'x1', 'y1'],
        'properties': {
          'x0': {'type': 'number'},
          'y0': {'type': 'number'},
          'x1': {'type': 'number'},
          'y1': {'type': 'number'},
        },
      };

  /// Avviso sull'ultima ricerca (pagine non analizzate), da mostrare all'utente; null se tutto bene.
  String? lastWarning;

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
              'required': ['label', 'kind', 'box', 'options'],
              'properties': {
                'label': {'type': 'string', 'description': 'Etichetta del campo come appare sulla pagina'},
                'kind': {'type': 'string', 'enum': _kinds},
                'box': {
                  ..._boxSchema,
                  'description': "Spazio vuoto da compilare, coordinate 0-1 rispetto all'immagine, origine in alto a sinistra",
                },
                'options': {
                  'type': 'array',
                  'description': 'Solo per gender e yesNo: ogni opzione con la sua casella. Vuoto per gli altri tipi.',
                  'items': {
                    'type': 'object',
                    'additionalProperties': false,
                    'required': ['label', 'box'],
                    'properties': {
                      'label': {'type': 'string', 'description': 'Testo dell\'opzione, es. "M", "F", "Sì", "No", "Acconsento"'},
                      'box': _boxSchema,
                    },
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
- kind: il tipo di dato atteso, uno tra: fullName (nome e cognome), lastFirstName (cognome e nome, in quest'ordine), firstName, lastName, birthDate, birthPlace, birthProvince, birthPlaceAndDate, taxCode, address, zip, city, province, phone, email, date, place, placeAndDate, signature, gender (caselle M/F), yesNo (caselle Sì/No, Acconsento/Non acconsento), text (qualsiasi altro dato, anche nomi o date di altre persone come il padre o un figlio, e date di scadenza o rilascio);
- box: il riquadro dello spazio vuoto in coordinate normalizzate 0-1 (x0,y0 in alto a sinistra, x1,y1 in basso a destra), non il riquadro dell'etichetta;
- options: per gender e yesNo, ogni opzione con il riquadro della sua casella; per gli altri tipi un elenco vuoto.
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
    if (apiKey.trim().isEmpty) throw AiDetectionException(tr('Inserisci la chiave API in Impostazioni.'));
    lastWarning = null;
    final out = <DetectedField>[];
    final pages = input.targetPages.toList();
    final todo = pages.take(maxPages).toList();
    var done = 0;
    for (final p in todo) {
      try {
        final png = await _render(input.pdf, p, dpi);
        if (png != null) {
          final response = await _send(png);
          out.addAll(parseResponse(response, page: p, source: name));
        }
        done++;
      } on AiDetectionException catch (e) {
        // Le pagine già analizzate non si buttano: si restituiscono con un avviso.
        if (done == 0) rethrow;
        lastWarning = tr('Analizzate {0} pagine su {1}: {2}', [done, pages.length, e.message]);
        break;
      }
    }
    if (lastWarning == null && pages.length > todo.length) {
      lastWarning = tr('Il riconoscimento AI ha analizzato solo le prime {0} pagine su {1}.', [todo.length, pages.length]);
    }
    // Campi compilabili già presenti nel PDF: non si propone testo sopra di loro.
    return out.where((f) => !input.avoid.any((a) => a.$1 == f.page && _overlap(a.$2, f.rect) > 0.3)).toList();
  }

  static double _overlap(NormRect a, NormRect b) {
    final ix = (a.right < b.right ? a.right : b.right) - (a.x > b.x ? a.x : b.x);
    final iy = (a.bottom < b.bottom ? a.bottom : b.bottom) - (a.y > b.y ? a.y : b.y);
    if (ix <= 0 || iy <= 0) return 0;
    final small = a.w * a.h < b.w * b.h ? a.w * a.h : b.w * b.h;
    return small <= 0 ? 0 : ix * iy / small;
  }

  Future<Map<String, dynamic>> _send(Uint8List png) async {
    http.Response res;
    try {
      res = await _client
          .post(endpoint, headers: headers, body: jsonEncode(buildRequest(png)))
          .timeout(const Duration(seconds: 90));
    } catch (_) {
      throw AiDetectionException(tr('Connessione non riuscita. Controlla internet e riprova.'));
    }
    if (res.statusCode != 200) throw AiDetectionException(errorMessage(res.statusCode, res.body));
    try {
      return (jsonDecode(utf8.decode(res.bodyBytes)) as Map).cast<String, dynamic>();
    } catch (_) {
      throw AiDetectionException(tr('Risposta non valida dal servizio AI.'));
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
      401 => tr('Chiave API non valida. Controllala in Impostazioni.'),
      402 => tr('Credito esaurito sull\'account Anthropic. Ricaricalo e riprova.'),
      403 => tr('La chiave API non ha i permessi per questa richiesta.'),
      404 => tr('Modello non trovato. Controlla il nome del modello in Impostazioni.'),
      413 => tr('La pagina è troppo grande per il servizio AI.'),
      429 => tr('Troppe richieste. Riprova tra poco.'),
      400 when (apiMsg ?? '').toLowerCase().contains('credit') => tr('Credito esaurito sull\'account Anthropic. Ricaricalo e riprova.'),
      400 => apiMsg != null ? tr('Richiesta rifiutata: {0}', [apiMsg]) : tr('Richiesta rifiutata.'),
      >= 500 => tr('Il servizio AI non è disponibile in questo momento. Riprova più tardi.'),
      _ => tr('Errore del servizio AI ({0}).', [status]),
    };
  }

  static NormRect? _rect(Object? box) {
    if (box is! Map) return null;
    double? n(Object? v) => v is num ? v.toDouble().clamp(0.0, 1.0) : null;
    final x0 = n(box['x0']), y0 = n(box['y0']), x1 = n(box['x1']), y1 = n(box['y1']);
    if (x0 == null || y0 == null || x1 == null || y1 == null) return null;
    final l = x0 < x1 ? x0 : x1, r = x0 < x1 ? x1 : x0, t = y0 < y1 ? y0 : y1, b = y0 < y1 ? y1 : y0;
    if (r - l <= 0 || b - t <= 0) return null;
    return NormRect(l, t, r - l, b - t);
  }

  /// Converte la risposta dell'API in campi. Tollera testo attorno al JSON.
  static List<DetectedField> parseResponse(Map<String, dynamic> response, {required int page, String source = 'AI'}) {
    final stop = response['stop_reason'];
    if (stop == 'refusal') throw AiDetectionException(tr('Il servizio AI ha rifiutato di analizzare questa pagina.'));
    final content = response['content'];
    if (content is! List) return const [];
    final text = content
        .whereType<Map<dynamic, dynamic>>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'])
        .whereType<String>()
        .join();
    // Risposta tagliata: il JSON sarebbe incompleto, meglio dirlo chiaramente.
    if (stop == 'max_tokens') throw AiDetectionException(tr('Risposta AI incompleta. Riprova.'));
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return const [];
    Object? decoded;
    try {
      decoded = jsonDecode(text.substring(start, end + 1));
    } catch (_) {
      throw AiDetectionException(tr('Risposta AI non leggibile.'));
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
      var kind = FieldKind.parse(f['kind'] as String?) ?? FieldKind.text;
      final options = <ChoiceOption>[];
      if (kind.isChoice) {
        for (final o in (f['options'] is List ? f['options'] as List : const []).whereType<Map<dynamic, dynamic>>()) {
          final label = LocalTextFieldDetector.optionLabel('${o['label'] ?? ''}');
          final r = _rect(o['box']);
          if (label != null && r != null) options.add(ChoiceOption(label, r));
        }
        if (options.isEmpty) kind = FieldKind.text; // scelta senza caselle utilizzabili
      }
      out.add(DetectedField(
        page: page,
        kind: kind,
        label: (f['label'] as String? ?? '').trim(),
        rect: NormRect(left, top, right - left, bottom - top).clamped(minSize: 0.004),
        source: source,
        options: options,
      ));
    }
    return out;
  }
}
