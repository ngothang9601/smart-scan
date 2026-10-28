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

  void _toggle(String id) {
    setState(() {
      if (_selected.remove(id)) return;
      if (_selected.length >= _layout.slots) _selected.removeAt(0);
      _selected.add(id);
    });
  }

  Future<void> _create() async {
    final store = context.read<DocumentStore>();
    final navigator = Navigator.of(context);
    final page = await runWithProgress(
        context, 'Đang ghép trang…', (_) => store.addLayoutPage(widget.docId, _selected, _layout));
    if (page == null) return;
    final index = store.byId(widget.docId)!.pages.indexWhere((p) => p.id == page.id);
    navigator.pushReplacement(MaterialPageRoute(
        builder: (_) => PageEditorScreen(docId: widget.docId, initialIndex: index)));
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
                  while (_selected.length > l.slots) {
                    _selected.removeAt(0);
                  }
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
        const SizedBox(height: 16),
        Text('2. Chọn ${_layout.slots} trang theo thứ tự (${_selected.length}/${_layout.slots})',
            style: Theme.of(context).textTheme.titleSmall),
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
          child: FilledButton.icon(
            onPressed: _selected.isEmpty ? null : _create,
            icon: const Icon(Icons.dashboard_customize_outlined),
            label: const Text('Tạo trang ghép'),
          ),
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
