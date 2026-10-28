import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:smart_scan/models/scan_document.dart';
import 'package:smart_scan/services/document_store.dart';
import 'package:smart_scan/services/image_processing.dart';
import 'package:smart_scan/services/pdf_service.dart';

Uint8List samplePhoto() {
  final image = img.Image(width: 600, height: 800);
  img.fill(image, color: img.ColorRgb8(50, 60, 70));
  img.fillRect(image, x1: 100, y1: 120, x2: 500, y2: 700, color: img.ColorRgb8(240, 240, 235));
  img.drawLine(image, x1: 150, y1: 300, x2: 450, y2: 300, color: img.ColorRgb8(0, 0, 0), thickness: 5);
  return img.encodeJpg(image);
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('scan_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('tạo tài liệu, sửa trang, sắp xếp, lưu và đọc lại', () async {
    final store = DocumentStore(root: tmp);
    await store.load();
    final doc = await store.createDocument([samplePhoto(), samplePhoto()], name: 'Hợp đồng');
    expect(doc.pages, hasLength(2));
    // Mép giấy được tự nhận diện (không phải toàn ảnh).
    expect(doc.pages.first.quad.isFull, isFalse);
    final cropped = img.decodeJpg(store.fileOf(doc.id, doc.pages.first.processedFile).readAsBytesSync())!;
    expect(cropped.width, inInclusiveRange(380, 420));

    await store.setOcr(doc.id, doc.pages[0].id, 'xin chào', const [OcrLine('xin chào', .1, .1, .5, .15)]);
    final p = await store.updatePage(doc.id, doc.pages[0].id, filter: ScanFilter.blackWhite);
    expect(p.ocrText, 'xin chào', reason: 'đổi bộ lọc không xoá OCR');
    final r = await store.updatePage(doc.id, doc.pages[0].id, quarterTurns: 1);
    expect(r.ocrText, isNull, reason: 'xoay thì OCR cũ không còn đúng');

    final firstId = doc.pages[0].id;
    await store.reorderPages(doc.id, 0, 1);
    expect(store.byId(doc.id)!.pages.last.id, firstId);
    await store.rename(doc.id, 'Hợp đồng thuê nhà');
    await store.addPages(doc.id, [samplePhoto()]);

    final again = DocumentStore(root: tmp);
    await again.load();
    final loaded = again.byId(doc.id)!;
    expect(loaded.name, 'Hợp đồng thuê nhà');
    expect(loaded.pages, hasLength(3));
    expect(loaded.pages.firstWhere((p) => p.id == firstId).quarterTurns, 1);
    expect(again.search('thuê'), hasLength(1));

    await again.deletePage(doc.id, loaded.pages.first.id);
    expect(again.byId(doc.id)!.pages, hasLength(2));
    final copy = await again.duplicate(doc.id);
    expect(again.documents, hasLength(2));
    await again.deleteDocument(copy.id);
    expect(Directory('${tmp.path}/${copy.id}').existsSync(), isFalse);
  });

  test('xuất PDF có lớp chữ tiếng Việt ẩn', () async {
    final font = File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync();
    for (final size in PdfPageSize.values) {
      final bytes = await PdfService.build(
        'Thử',
        [samplePhoto(), samplePhoto()],
        [const [OcrLine('Cộng hoà xã hội chủ nghĩa Việt Nam', .1, .1, .9, .14)], const []],
        ByteData.sublistView(font),
        size,
      );
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
      expect(bytes.length, greaterThan(10000));
    }
  });
}
