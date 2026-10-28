import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/scan_document.dart';

enum PdfPageSize { fit, a4, letter }

extension PdfPageSizeLabel on PdfPageSize {
  String get label => switch (this) {
        PdfPageSize.fit => 'Vừa ảnh',
        PdfPageSize.a4 => 'A4',
        PdfPageSize.letter => 'Letter',
      };
}

class _PdfJob {
  final String title;
  final List<Uint8List> images;
  final List<List<OcrLine>> lines;
  final ByteData? font;
  final PdfPageSize size;
  const _PdfJob(this.title, this.images, this.lines, this.font, this.size);
}

/// Tạo PDF; nếu trang đã có OCR thì chèn lớp chữ ẩn để PDF tìm kiếm/sao chép được.
Future<Uint8List> _buildPdf(_PdfJob job) async {
  final doc = pw.Document(title: job.title, creator: 'Smart Scan');
  final font = job.font == null ? null : pw.Font.ttf(job.font!);
  for (var i = 0; i < job.images.length; i++) {
    final image = pw.MemoryImage(job.images[i]);
    final iw = image.width!.toDouble(), ih = image.height!.toDouble();
    final PdfPageFormat format;
    const margin = 18.0;
    switch (job.size) {
      case PdfPageSize.fit:
        // 150 dpi -> điểm PDF (1/72 inch).
        format = PdfPageFormat(iw * 72 / 150, ih * 72 / 150);
      case PdfPageSize.a4:
        format = iw > ih ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
      case PdfPageSize.letter:
        format = iw > ih ? PdfPageFormat.letter.landscape : PdfPageFormat.letter;
    }
    final m = job.size == PdfPageSize.fit ? 0.0 : margin;
    final availW = format.width - 2 * m, availH = format.height - 2 * m;
    final scale = (availW / iw) < (availH / ih) ? availW / iw : availH / ih;
    final w = iw * scale, h = ih * scale;

    doc.addPage(pw.Page(
      pageFormat: format,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Center(
        child: pw.SizedBox(
          width: w,
          height: h,
          child: pw.Stack(children: [
            pw.Image(image, width: w, height: h, fit: pw.BoxFit.fill),
            if (font != null)
              for (final l in job.lines[i])
                if (l.text.trim().isNotEmpty && l.right > l.left && l.bottom > l.top)
                  pw.Positioned(
                    left: l.left * w,
                    top: l.top * h,
                    child: pw.SizedBox(
                      width: (l.right - l.left) * w,
                      height: (l.bottom - l.top) * h,
                      child: pw.FittedBox(
                        fit: pw.BoxFit.fill,
                        child: pw.Text(l.text,
                            style: pw.TextStyle(
                                font: font,
                                fontSize: 12,
                                renderingMode: PdfTextRenderingMode.invisible)),
                      ),
                    ),
                  ),
          ]),
        ),
      ),
    ));
  }
  return doc.save();
}

class PdfService {
  static Future<ByteData?> _loadFont() async {
    try {
      return await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    } catch (_) {
      return null;
    }
  }

  /// Ghép các trang thành PDF và lưu vào thư mục tạm; trả về tệp PDF.
  static Future<File> export(
    ScanDocument doc,
    File Function(ScanPage) fileOf, {
    PdfPageSize size = PdfPageSize.a4,
  }) async {
    final images = [for (final p in doc.pages) await fileOf(p).readAsBytes()];
    final lines = [for (final p in doc.pages) p.ocrLines];
    final hasOcr = lines.any((l) => l.isNotEmpty);
    final job = _PdfJob(doc.name, images, lines, hasOcr ? await _loadFont() : null, size);
    final bytes = await compute(_buildPdf, job);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${safeFileName(doc.name)}.pdf');
    await file.writeAsBytes(bytes);
    return file;
  }

  /// Dùng trực tiếp trong test.
  @visibleForTesting
  static Future<Uint8List> build(String title, List<Uint8List> images, List<List<OcrLine>> lines,
          ByteData? font, PdfPageSize size) =>
      _buildPdf(_PdfJob(title, images, lines, font, size));
}

String safeFileName(String name) {
  final s = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return s.isEmpty ? 'scan' : s;
}
