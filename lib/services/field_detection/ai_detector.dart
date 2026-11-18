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

/// Servizi AI online, sempre con la chiave dell'utente (come in PackSnap: prima Gemini, poi NanoGPT).
enum AiProvider {
  gemini('Google Gemini', 'gemini-3.5-flash-lite', ['gemini-3.5-flash-lite', 'gemini-3.8-flash'], 'https://aistudio.google.com/apikey'),
  nanogpt('NanoGPT', 'gemini-2.5-flash-lite', ['gemini-2.5-flash-lite', 'google/gemini-3.1-flash-lite', 'google/gemini-3.5-flash-lite'], 'https://nano-gpt.com/api'),
  anthropic('Anthropic (Claude)', 'claude-haiku-5-5', ['claude-haiku-5-5', 'claude-sonnet-5-5'], 'https://console.anthropic.com/settings/keys');

  const AiProvider(this.label, this.defaultModel, this.models, this.keyUrl);

  /// Nome del servizio (marchio, non si traduce).
  final String label;
  final String defaultModel;

  /// Modelli consigliati, dal più economico.
  final List<String> models;

  /// Dove si crea la chiave.
  final String keyUrl;

  /// Risoluzione delle pagine inviate. I modelli Gemini danno riquadri più precisi con più dettaglio;
  /// per Claude bastano 110 dpi (immagini più piccole, meno costo).
  double get dpi => this == anthropic ? 110 : 150;

  static AiProvider? parse(String? v) => AiProvider.values.where((p) => p.name == v).firstOrNull;
}

/// Servizio, chiave e modello per una chiamata.
@immutable
class AiAccess {
  const AiAccess(this.provider, this.apiKey, [String? model]) : model = model ?? '';
  final AiProvider provider;
  final String apiKey;
  final String model;

  String get effectiveModel => model.trim().isEmpty ? provider.defaultModel : model.trim();
}

/// Tipi di campo che l'AI può restituire (nomi di [FieldKind]).
const aiFieldKinds = [
  'fullName', 'lastFirstName', 'firstName', 'lastName', 'birthDate', 'birthPlace', 'birthProvince', //
  'birthPlaceAndDate', 'taxCode', 'address', 'zip', 'city', 'province', 'phone', 'email', 'date', 'place', //
  'placeAndDate', 'signature', 'gender', 'yesNo', 'custom', 'text',
];

/// Istruzioni per l'AI. Con [box2d] i riquadri si chiedono nel formato in cui i modelli Gemini sono allenati
/// (`box_2d`: [ymin, xmin, ymax, xmax] su 0–1000), altrimenti come x0/y0/x1/y1 su 0–1.
String aiFieldPrompt({required bool box2d, List<String> customLabels = const []}) {
  final boxText = box2d
      ? 'box_2d: il riquadro dello spazio vuoto come [ymin, xmin, ymax, xmax] in interi da 0 a 1000 rispetto all\'immagine (0,0 in alto a sinistra), non il riquadro dell\'etichetta'
      : 'box: il riquadro dello spazio vuoto in coordinate normalizzate 0-1 (x0,y0 in alto a sinistra, x1,y1 in basso a destra), non il riquadro dell\'etichetta';
  final optionBox = box2d ? 'box_2d' : 'box';
  final custom = customLabels.where((l) => l.trim().isNotEmpty).map((l) => '"${l.trim()}"').toSet().join(', ');
  return '''
Questa immagine è una pagina di un modulo italiano da compilare con i dati di una persona. Trova gli spazi vuoti da compilare: righe "____", puntini, caselle di testo, spazi dopo i due punti, riquadri per la firma, caselle da spuntare.
Per ogni spazio vuoto indica:
- label: l'etichetta vicina, come è scritta (es. "Cognome", "nato/a a", "Firma");
- kind: il tipo di dato atteso, uno tra: fullName (nome e cognome), lastFirstName (cognome e nome, in quest'ordine), firstName, lastName, birthDate, birthPlace, birthProvince, birthPlaceAndDate, taxCode (codice fiscale), address (via e numero civico), zip (CAP), city (comune di residenza), province (sigla della provincia di residenza), phone, email, date (data di oggi, es. accanto a "Data" o "lì"), place (luogo dove si firma), placeAndDate ("Luogo e data"), signature (firma), gender (caselle M/F), yesNo (caselle Sì/No, Acconsento/Non acconsento), ${custom.isEmpty ? '' : 'custom (uno di questi dati: $custom; in label scrivi esattamente il nome del dato), '}text (qualsiasi altro dato);
- $boxText;
- options: per gender e yesNo ogni opzione con la sua casella ($optionBox); per gli altri tipi un elenco vuoto.
Regole:
- i dati di altre persone (padre, madre, figlio, alunno, coniuge, legale rappresentante) e le date che non sono quella di oggi (scadenza, rilascio, inizio) sono sempre "text";
- un solo campo per spazio: se "Luogo e data" è un solo spazio usa placeAndDate, se sono due spazi usa place e date;
- il riquadro copre tutta la riga vuota da compilare, alta quanto una riga di testo;
- ignora gli spazi già compilati, le intestazioni e il testo delle istruzioni.
Se non ci sono campi, restituisci un elenco vuoto.''';
}

/// Schema JSON della risposta (Claude: x0..y1 su 0–1).
Map<String, Object> get aiBoxSchema => {
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

Map<String, Object> get aiResponseSchema => {
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
              'kind': {'type': 'string', 'enum': aiFieldKinds},
              'box': {
                ...aiBoxSchema,
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
                    'box': aiBoxSchema,
                  },
                },
              },
            },
          },
        },
      },
    };

/// Schema nel formato di Gemini (OpenAPI, tipi in maiuscolo), con `box_2d` su 0–1000.
Map<String, Object> get geminiResponseSchema {
  const box = {
    'type': 'ARRAY',
    'description': '[ymin, xmin, ymax, xmax] da 0 a 1000',
    'items': {'type': 'INTEGER'},
  };
  return {
    'type': 'OBJECT',
    'properties': {
      'fields': {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'properties': {
            'label': {'type': 'STRING'},
            'kind': {'type': 'STRING', 'enum': aiFieldKinds},
            'box_2d': box,
            'options': {
              'type': 'ARRAY',
              'items': {
                'type': 'OBJECT',
                'properties': {'label': {'type': 'STRING'}, 'box_2d': box},
                'required': ['label', 'box_2d'],
              },
            },
          },
          'required': ['label', 'kind', 'box_2d'],
        },
      },
    },
    'required': ['fields'],
  };
}

/// Schema di Gemini → JSON Schema normale (per NanoGPT, che lo riceve scritto nel testo).
Object? plainSchema(Object? s) {
  if (s is Map) {
    return {
      for (final e in s.entries)
        e.key as String: e.key == 'type' && e.value is String ? (e.value as String).toLowerCase() : plainSchema(e.value),
    };
  }
  if (s is List) return [for (final v in s) plainSchema(v)];
  return s;
}

// ---------------------------------------------------------------------------
// Richieste e risposte dei tre servizi
// ---------------------------------------------------------------------------

final anthropicEndpoint = Uri.parse('https://api.anthropic.com/v1/messages');
const anthropicApiVersion = '2026-10-21';
Uri geminiEndpoint(String model) => Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent');

/// Indirizzo "diretto" di NanoGPT (richieste fino a 32 MB; nano-gpt.com si ferma a 4,5 MB). CORS aperto.
final nanoGptEndpoint = Uri.parse('https://api.nano-gpt.com/api/v1/chat/completions');

/// Prompt di prova della connessione (testo soltanto: costa pochissimo).
const _pingPrompt = 'Rispondi solo con questo JSON: {"fields": []}';

/// Richiesta HTTP pronta per un servizio. Con [png] null è una prova della connessione (solo testo).
({Uri url, Map<String, String> headers, Map<String, Object> body}) aiRequest(AiAccess ai, Uint8List? png, {List<String> customLabels = const []}) {
  final model = ai.effectiveModel;
  final key = ai.apiKey.trim();
  final b64 = png == null ? null : base64Encode(png);
  switch (ai.provider) {
    case AiProvider.anthropic:
      return (
        url: anthropicEndpoint,
        headers: {
          'content-type': 'application/json',
          'x-api-key': key,
          'anthropic-version': anthropicApiVersion,
          // Necessario per chiamare l'API direttamente dal browser (la chiave è dell'utente).
          if (kIsWeb) 'anthropic-dangerous-direct-browser-access': 'true',
        },
        body: {
          'model': model,
          'max_tokens': png == null ? 50 : 8000,
          if (png != null)
            'output_config': {
              'format': {'type': 'json_schema', 'schema': aiResponseSchema},
            },
          'messages': [
            {
              'role': 'user',
              'content': [
                if (b64 != null)
                  {
                    'type': 'image',
                    'source': {'type': 'base64', 'media_type': 'image/png', 'data': b64},
                  },
                {'type': 'text', 'text': png == null ? _pingPrompt : aiFieldPrompt(box2d: false, customLabels: customLabels)},
              ],
            },
          ],
        },
      );
    case AiProvider.gemini:
      return (
        url: geminiEndpoint(model),
        headers: {'content-type': 'application/json', 'x-goog-api-key': key},
        body: {
          'contents': [
            {
              'parts': [
                if (b64 != null) {'inline_data': {'mime_type': 'image/png', 'data': b64}},
                {'text': png == null ? _pingPrompt : aiFieldPrompt(box2d: true, customLabels: customLabels)},
              ],
            },
          ],
          'generationConfig': {
            'responseMimeType': 'application/json',
            if (png != null) 'responseSchema': geminiResponseSchema,
            'temperature': 0,
            'maxOutputTokens': png == null ? 50 : 8192,
          },
        },
      );
    case AiProvider.nanogpt:
      // Formato OpenAI. Il formato della risposta si chiede a parole: i modelli più economici su NanoGPT
      // non supportano le "structured outputs", quindi niente response_format (come in PackSnap).
      return (
        url: nanoGptEndpoint,
        headers: {'content-type': 'application/json', 'authorization': 'Bearer $key'},
        body: {
          'model': model,
          'messages': [
            {
              'role': 'user',
              'content': [
                if (b64 != null) {'type': 'image_url', 'image_url': {'url': 'data:image/png;base64,$b64'}},
                {'type': 'text', 'text': png == null ? _pingPrompt : aiFieldPrompt(box2d: true, customLabels: customLabels)},
                if (png != null)
                  {
                    'type': 'text',
                    'text': 'Rispondi solo con un oggetto JSON valido, senza testo prima o dopo e senza ```, che rispetti '
                        'questo JSON Schema: ${jsonEncode(plainSchema(geminiResponseSchema))}',
                  },
              ],
            },
          ],
          'temperature': 0,
          'max_tokens': png == null ? 50 : 8192,
          'stream': false,
        },
      );
  }
}

/// Testo JSON della risposta, o eccezione con un messaggio chiaro (rifiuto, risposta tagliata…).
String aiResponseText(AiProvider provider, Map<String, dynamic> r) {
  switch (provider) {
    case AiProvider.anthropic:
      final stop = r['stop_reason'];
      if (stop == 'refusal') throw AiDetectionException(tr('Il servizio AI ha rifiutato di analizzare questa pagina.'));
      if (stop == 'max_tokens') throw AiDetectionException(tr('Risposta AI incompleta. Riprova.'));
      final content = r['content'];
      if (content is! List) return '';
      return content.whereType<Map<dynamic, dynamic>>().where((b) => b['type'] == 'text').map((b) => b['text']).whereType<String>().join();
    case AiProvider.gemini:
      if ((r['promptFeedback'] as Map?)?['blockReason'] != null) {
        throw AiDetectionException(tr('Il servizio AI ha rifiutato di analizzare questa pagina.'));
      }
      final cands = r['candidates'];
      if (cands is! List || cands.isEmpty) return '';
      final c = cands.first as Map;
      final finish = c['finishReason'];
      if (finish == 'MAX_TOKENS') throw AiDetectionException(tr('Risposta AI incompleta. Riprova.'));
      if (finish == 'SAFETY' || finish == 'RECITATION' || finish == 'PROHIBITED_CONTENT' || finish == 'BLOCKLIST') {
        throw AiDetectionException(tr('Il servizio AI ha rifiutato di analizzare questa pagina.'));
      }
      final parts = (c['content'] as Map?)?['parts'];
      if (parts is! List) return '';
      return parts.whereType<Map<dynamic, dynamic>>().where((p) => p['thought'] != true).map((p) => p['text']).whereType<String>().join();
    case AiProvider.nanogpt:
      final choices = r['choices'];
      if (choices is! List || choices.isEmpty) return '';
      final c = choices.first as Map;
      if (c['finish_reason'] == 'length') throw AiDetectionException(tr('Risposta AI incompleta. Riprova.'));
      if (c['finish_reason'] == 'content_filter') throw AiDetectionException(tr('Il servizio AI ha rifiutato di analizzare questa pagina.'));
      final raw = (c['message'] as Map?)?['content'];
      return raw is String
          ? raw
          : raw is List
              ? raw.whereType<Map<dynamic, dynamic>>().map((p) => p['text'] as String? ?? '').join()
              : '';
  }
}

/// Messaggio per l'utente a partire da un errore HTTP del servizio.
String aiErrorMessage(AiProvider provider, int status, String body) {
  String? apiMsg;
  String? apiStatus;
  try {
    final err = (jsonDecode(body) as Map)['error'];
    if (err is Map) {
      apiMsg = err['message'] as String?;
      apiStatus = '${err['status'] ?? err['code'] ?? err['type'] ?? ''}';
    } else if (err is String) {
      apiMsg = err;
    }
  } catch (_) {}
  final low = '${apiMsg ?? ''} $apiStatus ${body.length > 400 ? body.substring(0, 400) : body}'.toLowerCase();
  final name = provider.label;
  final badKey = tr('Chiave {0} non valida. Controllala in Impostazioni.', [name]);
  final noCredit = tr('Credito esaurito su {0}. Ricaricalo e riprova.', [name]);
  final short = apiMsg == null ? null : (apiMsg.length > 200 ? '${apiMsg.substring(0, 200)}…' : apiMsg);
  return switch (status) {
    401 => badKey,
    402 => noCredit,
    403 => provider == AiProvider.gemini ? badKey : tr('La chiave {0} non ha i permessi per questa richiesta.', [name]),
    404 => tr('Modello non trovato su {0}. Controlla il nome del modello in Impostazioni.', [name]),
    413 => tr('La pagina è troppo grande per il servizio AI.'),
    429 when provider == AiProvider.gemini => tr('Limite di richieste di Google Gemini raggiunto. Riprova più tardi.'),
    429 => tr('Troppe richieste a {0}. Riprova tra poco.', [name]),
    400 when low.contains('api_key') || low.contains('api key') => badKey,
    400 when low.contains('credit') || low.contains('balance') || low.contains('insufficient') => noCredit,
    400 => short != null ? tr('Richiesta rifiutata da {0}: {1}', [name, short]) : tr('Richiesta rifiutata da {0}.', [name]),
    >= 500 => tr('{0} non è disponibile in questo momento. Riprova più tardi.', [name]),
    _ => tr('Errore di {0} ({1}).', [name, status]),
  };
}

/// Riquadro da `{x0,y0,x1,y1}` (0–1) oppure da `box_2d` `[ymin, xmin, ymax, xmax]` (0–1000).
NormRect? aiRect(Object? box) {
  double? x0, y0, x1, y1;
  if (box is Map) {
    double? n(Object? v) => v is num ? v.toDouble() : null;
    x0 = n(box['x0']);
    y0 = n(box['y0']);
    x1 = n(box['x1']);
    y1 = n(box['y1']);
  } else if (box is List && box.length == 4 && box.every((v) => v is num)) {
    final v = [for (final e in box) (e as num).toDouble() / 1000];
    y0 = v[0];
    x0 = v[1];
    y1 = v[2];
    x1 = v[3];
  }
  if (x0 == null || y0 == null || x1 == null || y1 == null) return null;
  double c(double v) => v.clamp(0.0, 1.0);
  final l = c(x0 < x1 ? x0 : x1), r = c(x0 < x1 ? x1 : x0), t = c(y0 < y1 ? y0 : y1), b = c(y0 < y1 ? y1 : y0);
  if (r - l <= 0 || b - t <= 0) return null;
  return NormRect(l, t, r - l, b - t);
}

/// Converte il JSON dei campi in [DetectedField]. Tollera testo e ``` attorno al JSON.
List<DetectedField> parseAiFields(String text, {required int page, String source = 'AI'}) {
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
    final rect = aiRect(f['box'] ?? f['box_2d']);
    if (rect == null || rect.w < 0.01 || rect.h < 0.004) continue;
    var kind = FieldKind.parse(f['kind'] as String?) ?? FieldKind.text;
    final label = (f['label'] as String? ?? '').trim();
    if (kind == FieldKind.custom && label.isEmpty) kind = FieldKind.text;
    final options = <ChoiceOption>[];
    if (kind.isChoice) {
      for (final o in (f['options'] is List ? f['options'] as List : const []).whereType<Map<dynamic, dynamic>>()) {
        final optLabel = LocalTextFieldDetector.optionLabel('${o['label'] ?? ''}');
        final r = aiRect(o['box'] ?? o['box_2d']);
        if (optLabel != null && r != null) options.add(ChoiceOption(optLabel, r));
      }
      if (options.isEmpty) kind = FieldKind.text; // scelta senza caselle utilizzabili
    }
    out.add(DetectedField(
      page: page,
      kind: kind,
      label: label,
      rect: rect.clamped(minSize: 0.004),
      source: source,
      options: options,
    ));
  }
  return out;
}

/// Quota di sovrapposizione di due riquadri, rispetto al più piccolo (0–1).
double rectOverlap(NormRect a, NormRect b) {
  final ix = (a.right < b.right ? a.right : b.right) - (a.x > b.x ? a.x : b.x);
  final iy = (a.bottom < b.bottom ? a.bottom : b.bottom) - (a.y > b.y ? a.y : b.y);
  if (ix <= 0 || iy <= 0) return 0;
  final small = a.w * a.h < b.w * b.h ? a.w * a.h : b.w * b.h;
  return small <= 0 ? 0 : ix * iy / small;
}

/// Una chiamata a un servizio: corpo JSON della risposta oppure [AiDetectionException].
Future<Map<String, dynamic>> aiPost(http.Client client, AiAccess ai, Uint8List? png, {List<String> customLabels = const [], Duration timeout = const Duration(seconds: 90)}) async {
  if (ai.apiKey.trim().isEmpty) throw AiDetectionException(tr('Inserisci la chiave {0} in Impostazioni.', [ai.provider.label]));
  final req = aiRequest(ai, png, customLabels: customLabels);
  http.Response res;
  try {
    res = await client.post(req.url, headers: req.headers, body: jsonEncode(req.body)).timeout(timeout);
  } catch (_) {
    throw AiDetectionException(tr('Connessione a {0} non riuscita. Controlla internet e riprova.', [ai.provider.label]));
  }
  if (res.statusCode != 200) throw AiDetectionException(aiErrorMessage(ai.provider, res.statusCode, res.body));
  try {
    return (jsonDecode(utf8.decode(res.bodyBytes)) as Map).cast<String, dynamic>();
  } catch (_) {
    throw AiDetectionException(tr('Risposta non valida dal servizio AI.'));
  }
}

/// Prova la connessione con una richiesta di solo testo (costa pochissimo). Lancia [AiDetectionException].
Future<void> testAiConnection(AiAccess ai, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final r = await aiPost(c, ai, null, timeout: const Duration(seconds: 30));
    aiResponseText(ai.provider, r);
  } finally {
    if (client == null) c.close();
  }
}

/// Riconoscimento con l'AI online. Prova i servizi di [chain] in ordine: se uno non ce la fa (chiave che non
/// va, credito o limite finiti, rete, risposta illeggibile) passa al successivo per le pagine che restano.
class AiFieldDetector implements FieldDetector {
  AiFieldDetector({
    required List<AiAccess> chain,
    http.Client? client,
    PagePngRenderer? renderer,
    this.maxPages = 10,
  })  : chain = List.unmodifiable(chain),
        _client = client ?? http.Client(),
        _render = renderer ?? printingPngRenderer;

  final List<AiAccess> chain;
  final http.Client _client;
  final PagePngRenderer _render;
  final int maxPages;

  @override
  String get name => 'AI';

  /// Avviso sull'ultima ricerca (servizio cambiato, pagine non analizzate); null se tutto bene.
  String? lastWarning;

  /// Servizi che hanno risposto nell'ultima ricerca.
  final Set<AiProvider> usedProviders = {};

  @override
  Future<List<DetectedField>> detect(DetectionInput input) async {
    if (chain.isEmpty) throw AiDetectionException(tr('Inserisci la chiave API in Impostazioni › Riconoscimento AI'));
    lastWarning = null;
    usedProviders.clear();
    final notes = <String>[];
    final out = <DetectedField>[];
    final pages = input.targetPages.toList();
    final todo = pages.take(maxPages).toList();
    var cur = 0;
    var done = 0;
    String? stopped;
    for (final p in todo) {
      final rendered = <double, Uint8List?>{};
      while (true) {
        final ai = chain[cur];
        try {
          final dpi = ai.provider.dpi;
          final png = rendered.containsKey(dpi) ? rendered[dpi] : (rendered[dpi] = await _render(input.pdf, p, dpi));
          if (png != null) {
            final r = await aiPost(_client, ai, png, customLabels: input.extraLabels);
            out.addAll(parseAiFields(aiResponseText(ai.provider, r), page: p, source: name));
            usedProviders.add(ai.provider);
          }
          done++;
          break;
        } on AiDetectionException catch (e) {
          if (cur < chain.length - 1) {
            cur++;
            notes.add(tr('{0}: {1} Uso {2}.', [ai.provider.label, e.message, chain[cur].provider.label]));
            continue;
          }
          // Le pagine già analizzate non si buttano: si restituiscono con un avviso.
          if (done == 0) {
            if (notes.isEmpty) rethrow;
            throw AiDetectionException([...notes, e.message].join('\n'));
          }
          stopped = tr('Analizzate {0} pagine su {1}: {2}', [done, pages.length, e.message]);
          break;
        }
      }
      if (stopped != null) break;
    }
    if (stopped != null) {
      notes.add(stopped);
    } else if (pages.length > todo.length) {
      notes.add(tr('Il riconoscimento AI ha analizzato solo le prime {0} pagine su {1}.', [todo.length, pages.length]));
    }
    lastWarning = notes.isEmpty ? null : notes.join('\n');
    // Campi compilabili già presenti nel PDF: non si propone testo sopra di loro.
    return out.where((f) => !input.avoid.any((a) => a.$1 == f.page && rectOverlap(a.$2, f.rect) > 0.3)).toList();
  }
}

/// Unisce i campi trovati sul dispositivo (posizioni esatte dal testo del PDF) con quelli dell'AI
/// (trova anche ciò che il dizionario non conosce e legge le scansioni): un campo AI che si sovrappone a uno
/// già trovato sulla stessa pagina si scarta, gli altri si aggiungono.
List<DetectedField> mergeDetections(List<DetectedField> local, List<DetectedField> ai) {
  final out = [...local];
  for (final f in ai) {
    final dup = out.any((l) => l.page == f.page && rectOverlap(l.rect, f.rect) > 0.3);
    if (!dup) out.add(f);
  }
  return out;
}
