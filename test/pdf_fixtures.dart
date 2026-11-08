import 'dart:typed_data';
import 'dart:ui';

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// PDF di prova: pagina 1 A4 con testo e campi AcroForm, pagina 2 ruotata di 90°.
Uint8List buildFormPdf({bool rotatedSecondPage = true}) {
  final doc = PdfDocument();
  doc.pageSettings.margins.all = 0;
  doc.pageSettings.size = const Size(595, 842);
  final p1 = doc.pages.add();
  final font = PdfStandardFont(PdfFontFamily.helvetica, 12);
  p1.graphics.drawString('Modulo di prova', font, bounds: const Rect.fromLTWH(50, 40, 300, 20));
  doc.form.fields.add(PdfTextBoxField(p1, 'nome', const Rect.fromLTWH(50, 100, 200, 20)));
  doc.form.fields.add(PdfTextBoxField(p1, 'citta', const Rect.fromLTWH(50, 130, 200, 20), text: 'Milano'));
  doc.form.fields.add(PdfCheckBoxField(p1, 'privacy', const Rect.fromLTWH(50, 160, 14, 14)));
  doc.form.fields.add(PdfComboBoxField(p1, 'provincia', const Rect.fromLTWH(50, 190, 100, 20),
      items: [PdfListFieldItem('MI', 'MI'), PdfListFieldItem('RM', 'RM')]));
  final p2 = doc.pages.add();
  p2.graphics.drawString('Pagina 2', font, bounds: const Rect.fromLTWH(50, 40, 300, 20));
  final bytes = Uint8List.fromList(doc.saveSync());
  doc.dispose();
  if (!rotatedSecondPage) return bytes;
  // /Rotate impostato su una pagina caricata, come nei PDF reali.
  final loaded = PdfDocument(inputBytes: bytes);
  loaded.pages[1].rotation = PdfPageRotateAngle.rotateAngle90;
  final rotated = Uint8List.fromList(loaded.saveSync());
  loaded.dispose();
  return rotated;
}

/// PDF semplice di [pages] pagine A4 senza campi.
Uint8List buildPlainPdf({int pages = 3}) {
  final doc = PdfDocument();
  doc.pageSettings.margins.all = 0;
  doc.pageSettings.size = const Size(595, 842);
  final font = PdfStandardFont(PdfFontFamily.helvetica, 12);
  for (var i = 0; i < pages; i++) {
    doc.pages.add().graphics.drawString('Pagina ${i + 1}', font, bounds: const Rect.fromLTWH(50, 40, 300, 20));
  }
  final bytes = Uint8List.fromList(doc.saveSync());
  doc.dispose();
  return bytes;
}

/// Testo estratto da tutte le pagine.
String extractAllText(Uint8List bytes) {
  final doc = PdfDocument(inputBytes: bytes);
  final text = PdfTextExtractor(doc).extractText();
  doc.dispose();
  return text;
}

/// Modulo senza campi AcroForm, con etichette e spazi da compilare come nei moduli reali.
Uint8List buildUnmarkedFormPdf() {
  final doc = PdfDocument();
  doc.pageSettings.margins.all = 0;
  doc.pageSettings.size = const Size(595, 842);
  final g = doc.pages.add().graphics;
  final f = PdfStandardFont(PdfFontFamily.helvetica, 11);
  void t(String s, double x, double y) => g.drawString(s, f, bounds: Rect.fromLTWH(x, y, 520, 16));
  t('DICHIARAZIONE SOSTITUTIVA', 50, 40);
  t('Il/La sottoscritto/a ______________________________________', 50, 90);
  t('nato/a a ____________________ il ______________', 50, 120);
  t('Codice fiscale:', 50, 150);
  t('Residente in ______________ Via ______________________ CAP _______', 50, 180);
  t('Telefono:', 50, 210);
  t('Email:', 300, 210);
  t('Dichiara di aver letto e compreso quanto sopra riportato.', 50, 250);
  t('Luogo e data ..................................', 50, 300);
  t('Firma', 380, 300);
  final bytes = Uint8List.fromList(doc.saveSync());
  doc.dispose();
  return bytes;
}

/// Modulo con caselle di scelta (Sì/No, M/F) e "Sesso M F" senza caselle.
Uint8List buildChoicesPdf() {
  final doc = PdfDocument();
  doc.pageSettings.margins.all = 0;
  doc.pageSettings.size = const Size(595, 842);
  final g = doc.pages.add().graphics;
  final f = PdfStandardFont(PdfFontFamily.helvetica, 11);
  void t(String s, double x, double y) => g.drawString(s, f, bounds: Rect.fromLTWH(x, y, 520, 16));
  t('Autorizza il trattamento dei dati personali?  [ ] Sì   [ ] No', 50, 100);
  t('Sesso:  [ ] M   [ ] F', 50, 140);
  t('Cognome: ______________________', 50, 180);
  final bytes = Uint8List.fromList(doc.saveSync());
  doc.dispose();
  return bytes;
}

/// Variante senza caselle: "Sesso M F".
Uint8List buildGenderLettersPdf() {
  final doc = PdfDocument();
  doc.pageSettings.margins.all = 0;
  doc.pageSettings.size = const Size(595, 842);
  final f = PdfStandardFont(PdfFontFamily.helvetica, 11);
  doc.pages.add().graphics.drawString('Nome e cognome ____________   Sesso   M   F', f, bounds: const Rect.fromLTWH(50, 100, 520, 16));
  final bytes = Uint8List.fromList(doc.saveSync());
  doc.dispose();
  return bytes;
}
