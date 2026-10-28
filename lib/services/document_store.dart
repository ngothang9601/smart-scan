import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/scan_document.dart';
import 'image_processing.dart';

/// Chạy trong isolate: chuẩn hoá ảnh, nhận diện mép, xử lý trang.
(Uint8List, Quad, Uint8List) _importJob((Uint8List, ScanFilter) args) {
  final original = normalizeImage(args.$1);
  final quad = detectDocumentInImage(original) ?? Quad.full;
  final processed = processPage(ProcessRequest(original, quad, args.$2, 0));
  return (original, quad, processed);
}

/// Thư viện tài liệu: lưu ảnh trên thiết bị và danh mục trong index.json.
class DocumentStore extends ChangeNotifier {
  DocumentStore({Directory? root}) : _rootOverride = root;

  final Directory? _rootOverride;
  static const _uuid = Uuid();

  late Directory _root;
  final List<ScanDocument> _docs = [];
  bool _loaded = false;

  bool get loaded => _loaded;

  /// Tài liệu mới cập nhật nằm đầu danh sách.
  List<ScanDocument> get documents =>
      List.unmodifiable([..._docs]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)));

  ScanDocument? byId(String id) {
    for (final d in _docs) {
      if (d.id == id) return d;
    }
    return null;
  }

  File get _indexFile => File('${_root.path}/index.json');

  Directory dirOf(String docId) => Directory('${_root.path}/$docId');

  File fileOf(String docId, String name) => File('${_root.path}/$docId/$name');

  Future<void> load() async {
    _root = _rootOverride ??
        Directory('${(await getApplicationDocumentsDirectory()).path}/scans');
    await _root.create(recursive: true);
    if (await _indexFile.exists()) {
      try {
        final list = jsonDecode(await _indexFile.readAsString()) as List;
        _docs
          ..clear()
          ..addAll(list.map((e) => ScanDocument.fromJson(e as Map<String, dynamic>)));
      } catch (e) {
        debugPrint('Không đọc được index.json: $e');
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final tmp = File('${_indexFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(_docs.map((d) => d.toJson()).toList()));
    await tmp.rename(_indexFile.path);
    notifyListeners();
  }

  void _put(ScanDocument doc) {
    final i = _docs.indexWhere((d) => d.id == doc.id);
    if (i >= 0) {
      _docs[i] = doc;
    } else {
      _docs.add(doc);
    }
  }

  /// Tìm theo tên hoặc nội dung OCR.
  List<ScanDocument> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return documents;
    return documents
        .where((d) => d.name.toLowerCase().contains(q) || d.fullText.toLowerCase().contains(q))
        .toList();
  }

  static String defaultName() =>
      'Scan ${DateFormat('dd-MM-yyyy HH.mm').format(DateTime.now())}';

  // -------------------------------------------------------------------------
  // Tạo / thêm trang
  // -------------------------------------------------------------------------

  /// Tạo trang mới từ ảnh: chuẩn hoá, tự nhận diện mép, cắt và lọc.
  Future<ScanPage> _importImage(String docId, Uint8List raw, ScanFilter filter) async {
    final pageId = _uuid.v4();
    final result = await compute(_importJob, (raw, filter));
    final dir = dirOf(docId);
    await dir.create(recursive: true);
    final originalName = 'orig_$pageId.jpg';
    final processedName = 'page_${pageId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await fileOf(docId, originalName).writeAsBytes(result.$1);
    await fileOf(docId, processedName).writeAsBytes(result.$3);
    return ScanPage(
      id: pageId,
      originalFile: originalName,
      processedFile: processedName,
      quad: result.$2,
      filter: filter,
    );
  }

  Future<ScanDocument> createDocument(
    List<Uint8List> images, {
    String? name,
    ScanFilter filter = ScanFilter.enhanced,
    void Function(int done, int total)? onProgress,
  }) async {
    final id = _uuid.v4();
    final pages = <ScanPage>[];
    for (var i = 0; i < images.length; i++) {
      pages.add(await _importImage(id, images[i], filter));
      onProgress?.call(i + 1, images.length);
    }
    final now = DateTime.now();
    final doc = ScanDocument(
        id: id, name: name ?? defaultName(), createdAt: now, updatedAt: now, pages: pages);
    _put(doc);
    await _save();
    return doc;
  }

  Future<ScanDocument> addPages(
    String docId,
    List<Uint8List> images, {
    ScanFilter filter = ScanFilter.enhanced,
    void Function(int done, int total)? onProgress,
  }) async {
    final doc = byId(docId)!;
    final pages = [...doc.pages];
    for (var i = 0; i < images.length; i++) {
      pages.add(await _importImage(docId, images[i], filter));
      onProgress?.call(i + 1, images.length);
    }
    final updated = doc.copyWith(pages: pages);
    _put(updated);
    await _save();
    return updated;
  }

  /// Ghép các trang [pageIds] vào một trang mới theo mẫu khung, thêm vào cuối tài liệu.
  Future<ScanPage> addLayoutPage(String docId, List<String> pageIds, PageLayout layout) async {
    final doc = byId(docId)!;
    final images = <Uint8List>[];
    for (final id in pageIds) {
      final p = doc.pages.firstWhere((p) => p.id == id);
      images.add(await fileOf(docId, p.processedFile).readAsBytes());
    }
    final composed = await compute(composeLayout, (images, layout));
    final pageId = _uuid.v4();
    final originalName = 'orig_$pageId.jpg';
    final processedName = 'page_${pageId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await fileOf(docId, originalName).writeAsBytes(composed);
    await fileOf(docId, processedName).writeAsBytes(composed);
    final page = ScanPage(
      id: pageId,
      originalFile: originalName,
      processedFile: processedName,
      quad: Quad.full,
      filter: ScanFilter.original,
      composed: true,
    );
    _put(doc.copyWith(pages: [...doc.pages, page]));
    await _save();
    return page;
  }

  // -------------------------------------------------------------------------
  // Chỉnh sửa trang
  // -------------------------------------------------------------------------

  /// Xử lý lại trang với vùng cắt / bộ lọc / góc xoay mới.
  Future<ScanPage> updatePage(
    String docId,
    String pageId, {
    Quad? quad,
    ScanFilter? filter,
    int? quarterTurns,
  }) async {
    final doc = byId(docId)!;
    final idx = doc.pages.indexWhere((p) => p.id == pageId);
    final old = doc.pages[idx];
    final next = old.copyWith(quad: quad, filter: filter, quarterTurns: quarterTurns);
    final original = await fileOf(docId, old.originalFile).readAsBytes();
    final req = ProcessRequest(original, next.quad, next.filter, next.quarterTurns);
    final processed = await compute(processPage, req);
    // Tên tệp mới để Flutter không dùng ảnh cũ trong bộ nhớ đệm.
    final name = 'page_${pageId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await fileOf(docId, name).writeAsBytes(processed);
    final oldFile = fileOf(docId, old.processedFile);
    if (await oldFile.exists()) await oldFile.delete();
    // Đổi vùng cắt hoặc góc xoay thì vị trí chữ OCR cũ không còn đúng.
    final geometryChanged = (quad != null && quad.toList().toString() != old.quad.toList().toString()) ||
        (quarterTurns != null && quarterTurns != old.quarterTurns);
    final page = next.copyWith(processedFile: name, clearOcr: geometryChanged);
    final pages = [...doc.pages]..[idx] = page;
    _put(doc.copyWith(pages: pages));
    await _save();
    return page;
  }

  Future<void> setOcr(String docId, String pageId, String text, List<OcrLine> lines) async {
    final doc = byId(docId)!;
    final pages = [
      for (final p in doc.pages)
        p.id == pageId ? p.copyWith(ocrText: text, ocrLines: lines) : p,
    ];
    _put(doc.copyWith(pages: pages));
    await _save();
  }

  Future<void> deletePage(String docId, String pageId) async {
    final doc = byId(docId)!;
    final page = doc.pages.firstWhere((p) => p.id == pageId);
    for (final f in [page.originalFile, page.processedFile]) {
      final file = fileOf(docId, f);
      if (await file.exists()) await file.delete();
    }
    final pages = doc.pages.where((p) => p.id != pageId).toList();
    if (pages.isEmpty) {
      await deleteDocument(docId);
      return;
    }
    _put(doc.copyWith(pages: pages));
    await _save();
  }

  Future<void> reorderPages(String docId, int oldIndex, int newIndex) async {
    final doc = byId(docId)!;
    final pages = [...doc.pages];
    final p = pages.removeAt(oldIndex);
    pages.insert(newIndex, p);
    _put(doc.copyWith(pages: pages));
    await _save();
  }

  Future<void> rename(String docId, String name) async {
    final doc = byId(docId)!;
    _put(doc.copyWith(name: name.trim().isEmpty ? doc.name : name.trim()));
    await _save();
  }

  Future<void> deleteDocument(String docId) async {
    _docs.removeWhere((d) => d.id == docId);
    final dir = dirOf(docId);
    if (await dir.exists()) await dir.delete(recursive: true);
    await _save();
  }

  /// Nhân bản tài liệu (sao chép toàn bộ ảnh).
  Future<ScanDocument> duplicate(String docId) async {
    final doc = byId(docId)!;
    final id = _uuid.v4();
    await dirOf(id).create(recursive: true);
    for (final p in doc.pages) {
      for (final f in [p.originalFile, p.processedFile]) {
        await fileOf(docId, f).copy(fileOf(id, f).path);
      }
    }
    final now = DateTime.now();
    final copy = ScanDocument(
        id: id, name: '${doc.name} (bản sao)', createdAt: now, updatedAt: now, pages: doc.pages);
    _put(copy);
    await _save();
    return copy;
  }
}
