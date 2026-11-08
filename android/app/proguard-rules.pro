# Regole R8 per la build di release.

# google_mlkit_text_recognition fa riferimento ai riconoscitori di cinese, giapponese, coreano e
# devanagari, che Sigla non include (usa solo il modello latino): R8 non deve cercarli.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
