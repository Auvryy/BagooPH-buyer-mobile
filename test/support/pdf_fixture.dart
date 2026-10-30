import 'dart:convert';
import 'dart:typed_data';

/// A complete, local PDF with visible text and a synthetic URI annotation.
Uint8List evidencePdf(String label) {
  if (!RegExp(r'^[A-Za-z0-9 .-]+$').hasMatch(label)) {
    throw ArgumentError('Use plain ASCII fixture text.');
  }
  final stream = 'BT /F1 16 Tf 24 128 Td ($label) Tj ET\n';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 180] '
        '/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R '
        '/Annots [6 0 R] >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Length ${stream.length} >>\nstream\n${stream}endstream',
    '<< /Type /Annot /Subtype /Link /Rect [24 120 275 146] '
        '/Border [0 0 0] /A << /S /URI '
        '/URI (https://example.invalid/evidence) >> >>',
  ];
  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var index = 0; index < objects.length; index++) {
    offsets.add(buffer.length);
    buffer.write('${index + 1} 0 obj\n${objects[index]}\nendobj\n');
  }
  final crossReference = buffer.length;
  buffer.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$crossReference\n%%EOF\n',
  );
  return Uint8List.fromList(ascii.encode(buffer.toString()));
}
