import 'ai_detector.dart';
import 'field_detector.dart';

export 'ai_detector.dart' show AiDetectionException, PagePngRenderer, printingPngRenderer;

/// Riconoscimento con la sola API Anthropic (Claude): un [AiFieldDetector] con un servizio solo.
/// La logica comune (richieste, risposte, passaggio al servizio dopo) sta in `ai_detector.dart`.
class AnthropicFieldDetector extends AiFieldDetector {
  AnthropicFieldDetector({
    required String apiKey,
    required String model,
    super.client,
    super.renderer,
    super.maxPages,
  }) : super(chain: [AiAccess(AiProvider.anthropic, apiKey, model)]);

  static final endpoint = anthropicEndpoint;
  static const apiVersion = anthropicApiVersion;

  /// Schema della risposta: elenco di campi con riquadro normalizzato 0–1.
  static Map<String, Object> get responseSchema => aiResponseSchema;

  /// Messaggio per l'utente a partire da un errore HTTP.
  static String errorMessage(int status, String body) => aiErrorMessage(AiProvider.anthropic, status, body);

  /// Converte la risposta dell'API Messages in campi.
  static List<DetectedField> parseResponse(Map<String, dynamic> response, {required int page, String source = 'AI'}) =>
      parseAiFields(aiResponseText(AiProvider.anthropic, response), page: page, source: source);
}
