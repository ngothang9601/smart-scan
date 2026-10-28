import 'dart:io';

import 'dart:ui';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/scan_document.dart';

/// Nhận dạng chữ (OCR) ngay trên thiết bị bằng Google ML Kit — không cần mạng.
/// Bộ chữ Latin hỗ trợ tiếng Việt, tiếng Anh và các ngôn ngữ châu Âu.
class OcrService {
  OcrService._();
  static final instance = OcrService._();

  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<(String, List<OcrLine>)> recognize(File image) async {
    final result = await _recognizer.processImage(InputImage.fromFile(image));
    final size = await _imageSize(image);
    final lines = <OcrLine>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        final r = line.boundingBox;
        lines.add(OcrLine(
          line.text,
          (r.left / size.width).clamp(0.0, 1.0),
          (r.top / size.height).clamp(0.0, 1.0),
          (r.right / size.width).clamp(0.0, 1.0),
          (r.bottom / size.height).clamp(0.0, 1.0),
        ));
      }
    }
    return (result.text, lines);
  }

  Future<Size> _imageSize(File file) async {
    final buffer = await ImmutableBuffer.fromUint8List(await file.readAsBytes());
    final descriptor = await ImageDescriptor.encoded(buffer);
    final size = Size(descriptor.width.toDouble(), descriptor.height.toDouble());
    descriptor.dispose();
    buffer.dispose();
    return size;
  }
}
