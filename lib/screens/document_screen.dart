import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/scan_document.dart';
import '../services/document_store.dart';
import '../services/ocr_service.dart';
import '../services/pdf_service.dart';
import '../ui/helpers.dart';
import 'layout_screen.dart';
import 'page_editor_screen.dart';
import 'scan_flow.dart';

/// Chi tiết một tài liệu: lưới các trang, sắp xếp, thêm trang, xuất PDF, OCR.
class DocumentScreen extends StatefulWidget {
  final String docId;
  const DocumentScreen({super.key, required this.docId});

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  bool _reorder = false;

  DocumentStore get _store => context.read<DocumentStore>();

  Future<void> _rename(ScanDocument doc) async {
    final name = await askText(context, title: 'Đổi tên tài liệu', initial: doc.name);
    if (name != null) await _store.rename(doc.id, name);
  }

  Future<void> _exportPdf(BuildContext anchor, ScanDocument doc) async {
    final size = await showModalBottomSheet<PdfPageSize>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Khổ giấy PDF', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          for (final s in PdfPageSize.values)
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(s.label),
              subtitle: s == PdfPageSize.fit ? const Text('Kích thước trang theo ảnh') : null,
              onTap: () => Navigator.pop(ctx, s),
            ),
        ]),
      ),
    );
    if (size == null || !mounted) return;
    final file = await runWithProgress(context, 'Đang tạo PDF…',
        (_) => PdfService.export(doc, (p) => _store.fileOf(doc.id, p.processedFile), size: size));
    if (file != null && anchor.mounted) {
      await shareFiles(anchor, [file], subject: doc.name, mimeType: 'application/pdf');
    }
  }

  Future<void> _shareImages(BuildContext anchor, ScanDocument doc) => shareFiles(
      anchor, [for (final p in doc.pages) _store.fileOf(doc.id, p.processedFile)],
      subject: doc.name);

  /// Nhận dạng chữ cho các trang chưa có OCR, rồi hiện toàn bộ văn bản.
  Future<void> _ocrAll(ScanDocument doc) async {
    final todo = doc.pages.where((p) => p.ocrText == null).toList();
    if (todo.isNotEmpty) {
      final ok = await runWithProgress(context, 'Đang nhận dạng chữ…', (progress) async {
        for (var i = 0; i < todo.length; i++) {
          final (text, lines) =
              await OcrService.instance.recognize(_store.fileOf(doc.id, todo[i].processedFile));
          await _store.setOcr(doc.id, todo[i].id, text, lines);
          progress(i + 1, todo.length);
        }
        return true;
      });
      if (ok == null) return;
    }
    if (!mounted) return;
    await showOcrSheet(context, _store.byId(doc.id)!.fullText);
  }

  Future<void> _delete(ScanDocument doc) async {
    if (!await confirm(context, 'Xoá tài liệu?', '"${doc.name}" và ${doc.pages.length} trang sẽ bị xoá vĩnh viễn.')) {
      return;
    }
    await _store.deleteDocument(doc.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DocumentStore>();
    final doc = store.byId(widget.docId);
    if (doc == null) return const Scaffold();

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => _rename(doc),
          child: Text(doc.name, overflow: TextOverflow.ellipsis),
        ),
        actions: [
          IconButton(
            tooltip: _reorder ? 'Xong' : 'Sắp xếp trang',
            icon: Icon(_reorder ? Icons.check : Icons.swap_vert),
            onPressed: () => setState(() => _reorder = !_reorder),
          ),
          Builder(
            builder: (anchor) => PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'rename':
                    await _rename(doc);
                  case 'images':
                    await _shareImages(anchor, doc);
                  case 'layout':
                    await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => LayoutScreen(docId: doc.id)));
                  case 'ocr':
                    await _ocrAll(doc);
                  case 'copy':
                    final text = doc.fullText;
                    if (text.isEmpty) {
                      showSnack(context, 'Chưa có văn bản. Hãy chạy "Nhận dạng chữ" trước.');
                    } else {
                      await Clipboard.setData(ClipboardData(text: text));
                      if (context.mounted) showSnack(context, 'Đã sao chép văn bản');
                    }
                  case 'duplicate':
                    await _store.duplicate(doc.id);
                    if (context.mounted) showSnack(context, 'Đã tạo bản sao');
                  case 'delete':
                    await _delete(doc);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.edit), title: Text('Đổi tên'))),
                PopupMenuItem(value: 'images', child: ListTile(leading: Icon(Icons.image_outlined), title: Text('Chia sẻ ảnh JPG'))),
                PopupMenuItem(value: 'layout', child: ListTile(leading: Icon(Icons.dashboard_customize_outlined), title: Text('Ghép trang theo khung'))),
                PopupMenuItem(value: 'ocr', child: ListTile(leading: Icon(Icons.text_fields), title: Text('Nhận dạng chữ (tất cả)'))),
                PopupMenuItem(value: 'copy', child: ListTile(leading: Icon(Icons.copy), title: Text('Sao chép văn bản'))),
                PopupMenuItem(value: 'duplicate', child: ListTile(leading: Icon(Icons.file_copy_outlined), title: Text('Nhân bản'))),
                PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Xoá tài liệu'))),
              ],
            ),
          ),
        ],
      ),
      body: _reorder ? _reorderList(doc) : _grid(doc),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => startScan(context, docId: doc.id),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Thêm trang'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'Thêm từ thư viện ảnh',
              onPressed: () => startScan(context, docId: doc.id, source: ScanSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Builder(
                builder: (anchor) => FilledButton.icon(
                  onPressed: () => _exportPdf(anchor, doc),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Xuất PDF'),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _grid(ScanDocument doc) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.72,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: doc.pages.length,
      itemBuilder: (_, i) {
        final page = doc.pages[i];
        return GestureDetector(
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => PageEditorScreen(docId: doc.id, initialIndex: i))),
          child: Column(children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black12, offset: Offset(0, 2))],
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.file(
                  _store.fileOf(doc.id, page.processedFile),
                  key: ValueKey(page.processedFile),
                  fit: BoxFit.contain,
                  cacheWidth: 400,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${i + 1}'),
              if (page.ocrText != null) ...[
                const SizedBox(width: 4),
                const Icon(Icons.text_snippet_outlined, size: 14),
              ],
            ]),
          ]),
        );
      },
    );
  }

  Widget _reorderList(ScanDocument doc) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: doc.pages.length,
      onReorderItem: (oldIndex, newIndex) => _store.reorderPages(doc.id, oldIndex, newIndex),
      itemBuilder: (_, i) {
        final page = doc.pages[i];
        return ListTile(
          key: ValueKey(page.id),
          leading: Image.file(_store.fileOf(doc.id, page.processedFile),
              width: 44, height: 56, fit: BoxFit.cover, cacheWidth: 120),
          title: Text('Trang ${i + 1}'),
          subtitle: Text(page.filter.label),
          trailing: const Icon(Icons.drag_handle),
        );
      },
    );
  }
}
