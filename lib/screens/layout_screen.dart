import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/scan_document.dart';
import '../services/document_store.dart';
import '../services/image_processing.dart';
import '../ui/helpers.dart';
import 'page_editor_screen.dart';

/// Ghép nhiều trang vào một trang A4 theo mẫu khung (CCCD 2 mặt, 2/4/6 ảnh).
class LayoutScreen extends StatefulWidget {
  final String docId;
  const LayoutScreen({super.key, required this.docId});

  @override
  State<LayoutScreen> createState() => _LayoutScreenState();
}

class _LayoutScreenState extends State<LayoutScreen> {
  PageLayout _layout = PageLayout.idCard;
  final _selected = <String>[];

  /// Các trang quét gốc (không tính trang đã ghép), theo thứ tự trong tài liệu.
  List<ScanPage> _sources(ScanDocument doc) {
    final scans = doc.pages.where((p) => !p.composed).toList();
    return scans.isEmpty ? doc.pages : scans;
  }

  /// Tự điền khung bằng các trang theo đúng thứ tự.
  void _autoFill() {
    final doc = context.read<DocumentStore>().byId(widget.docId);
    if (doc == null) return;
    _selected
      ..clear()
      ..addAll(_sources(doc).take(_layout.slots).map((p) => p.id));
  }

  @override
  void initState() {
    super.initState();
    _autoFill();
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.remove(id)) return;
      if (_selected.length >= _layout.slots) _selected.removeAt(0);
      _selected.add(id);
    });
  }

  Future<void> _create() => _compose([_selected]);

  /// Ghép toàn bộ trang theo thứ tự, mỗi trang mới chứa [PageLayout.slots] ảnh.
  Future<void> _createAll(ScanDocument doc) {
    final ids = _sources(doc).map((p) => p.id).toList();
    final n = _layout.slots;
    return _compose([
      for (var i = 0; i < ids.length; i += n) ids.sublist(i, (i + n).clamp(0, ids.length)),
    ]);
  }

  Future<void> _compose(List<List<String>> groups) async {
    final store = context.read<DocumentStore>();
    final navigator = Navigator.of(context);
    final pages = await runWithProgress(context, 'Đang ghép trang…', (progress) async {
      final out = <ScanPage>[];
      for (var i = 0; i < groups.length; i++) {
        out.add(await store.addLayoutPage(widget.docId, groups[i], _layout));
        progress(i + 1, groups.length);
      }
      return out;
    });
    if (pages == null || pages.isEmpty) return;
    final page = pages.first;
    final index = store.byId(widget.docId)!.pages.indexWhere((p) => p.id == page.id);
    navigator.pushReplacement(MaterialPageRoute(
        builder: (_) => PageEditorScreen(docId: widget.docId, initialIndex: index)));
  }

  /// Xem trước trang A4 với các ảnh đã đính vào khung.
  Widget _preview(ScanDocument doc, DocumentStore store) {
    const h = 260.0, w = h * a4Width / a4Height, k = h / a4Height;
    final slots = layoutSlots(_layout);
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black26),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black12, offset: Offset(0, 2))],
      ),
      child: Stack(children: [
        for (var i = 0; i < slots.length; i++)
          Positioned(
            left: slots[i][0] * k,
            top: slots[i][1] * k,
            width: slots[i][2] * k,
            height: slots[i][3] * k,
            child: i < _selected.length
                ? Image.file(
                    store.fileOf(doc.id, doc.pages.firstWhere((p) => p.id == _selected[i]).processedFile),
                    fit: BoxFit.contain,
                    cacheWidth: 300)
                : DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                      border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
                    ),
                    child: Center(child: Text('${i + 1}', style: const TextStyle(fontSize: 11))),
                  ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DocumentStore>();
    final doc = store.byId(widget.docId);
    if (doc == null) return const Scaffold();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Ghép trang theo khung')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Text('1. Chọn mẫu khung', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: PageLayout.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final l = PageLayout.values[i];
              final on = l == _layout;
              return GestureDetector(
                onTap: () => setState(() {
                  _layout = l;
                  _autoFill();
                }),
                child: SizedBox(
                  width: 96,
                  child: Column(children: [
                    Container(
                      width: 70,
                      height: 99,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: on ? scheme.primary : Colors.black26, width: on ? 3 : 1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: CustomPaint(painter: _LayoutPreview(l, scheme.primary)),
                    ),
                    const SizedBox(height: 6),
                    Text(l.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: TextStyle(
                            fontSize: 12,
                            color: on ? scheme.primary : null,
                            fontWeight: on ? FontWeight.w600 : null)),
                  ]),
                ),
              );
            },
          ),
        ),
        Text(_layout.hint, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        Center(child: _preview(doc, store)),
        const SizedBox(height: 16),
        Text('2. Các trang được điền vào khung (${_selected.length}/${_layout.slots})',
            style: Theme.of(context).textTheme.titleSmall),
        Text('Đã tự điền theo thứ tự. Chạm vào trang để bỏ hoặc chọn lại.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 130, childAspectRatio: 0.75, crossAxisSpacing: 10, mainAxisSpacing: 10),
          itemCount: doc.pages.length,
          itemBuilder: (_, i) {
            final p = doc.pages[i];
            final order = _selected.indexOf(p.id);
            return GestureDetector(
              onTap: () => _toggle(p.id),
              child: Stack(children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: order >= 0 ? scheme.primary : Colors.black12, width: order >= 0 ? 3 : 1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.file(store.fileOf(doc.id, p.processedFile),
                        fit: BoxFit.cover, cacheWidth: 300),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: CircleAvatar(
                    radius: 13,
                    backgroundColor: order >= 0 ? scheme.primary : Colors.black45,
                    child: Text(order >= 0 ? '${order + 1}' : '${i + 1}',
                        style: TextStyle(fontSize: 12, color: order >= 0 ? scheme.onPrimary : Colors.white)),
                  ),
                ),
              ]),
            );
          },
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            if (_sources(doc).length > _layout.slots) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _createAll(doc),
                  child: Text(
                      'Ghép tất cả (${(_sources(doc).length / _layout.slots).ceil()} trang)'),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: FilledButton.icon(
                onPressed: _selected.isEmpty ? null : _create,
                icon: const Icon(Icons.dashboard_customize_outlined),
                label: const Text('Tạo trang ghép'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _LayoutPreview extends CustomPainter {
  final PageLayout layout;
  final Color color;
  _LayoutPreview(this.layout, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / a4Width, sy = size.height / a4Height;
    final paint = Paint()..color = color.withValues(alpha: 0.35);
    for (final [x, y, w, h] in layoutSlots(layout)) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x * sx, y * sy, w * sx, h * sy), const Radius.circular(2)),
          paint);
    }
  }

  @override
  bool shouldRepaint(_LayoutPreview old) => old.layout != layout || old.color != color;
}
