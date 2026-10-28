
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/scan_document.dart';
import '../services/document_store.dart';
import '../services/image_processing.dart';
import '../services/ocr_service.dart';
import '../ui/helpers.dart';
import 'crop_screen.dart';

/// Xem và chỉnh từng trang: cắt lại, xoay, bộ lọc, nhận dạng chữ, xoá.
class PageEditorScreen extends StatefulWidget {
  final String docId;
  final int initialIndex;
  final bool openCrop;

  const PageEditorScreen(
      {super.key, required this.docId, this.initialIndex = 0, this.openCrop = false});

  @override
  State<PageEditorScreen> createState() => _PageEditorScreenState();
}

class _PageEditorScreenState extends State<PageEditorScreen> {
  late final PageController _pager = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  bool _busy = false;
  bool _showFilters = false;
  List<Uint8List>? _previews;
  String? _previewsFor;

  DocumentStore get _store => context.read<DocumentStore>();

  @override
  void initState() {
    super.initState();
    if (widget.openCrop) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _crop());
    }
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  ScanPage? get _page {
    final doc = _store.byId(widget.docId);
    if (doc == null || doc.pages.isEmpty) return null;
    return doc.pages[_index.clamp(0, doc.pages.length - 1)];
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
    } catch (e) {
      if (mounted) showSnack(context, 'Lỗi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _crop() async {
    final page = _page;
    if (page == null) return;
    final quad = await Navigator.push<Quad>(
      context,
      MaterialPageRoute(
        builder: (_) => CropScreen(
          original: _store.fileOf(widget.docId, page.originalFile),
          initial: page.quad,
        ),
      ),
    );
    if (quad == null) return;
    await _run(() async {
      await _store.updatePage(widget.docId, page.id, quad: quad);
      _previewsFor = null;
    });
  }

  Future<void> _rotate(int delta) async {
    final page = _page;
    if (page == null) return;
    await _run(() async {
      await _store.updatePage(widget.docId, page.id,
          quarterTurns: (page.quarterTurns + delta) % 4);
      _previewsFor = null;
    });
  }

  Future<void> _toggleFilters() async {
    setState(() => _showFilters = !_showFilters);
    final page = _page;
    if (!_showFilters || page == null) return;
    final key = '${page.id}/${page.quad.toList()}/${page.quarterTurns}';
    if (_previewsFor == key) return;
    setState(() => _previews = null);
    final original = await _store.fileOf(widget.docId, page.originalFile).readAsBytes();
    final previews = await compute(filterPreviews, (original, page.quad, page.quarterTurns));
    if (!mounted) return;
    setState(() {
      _previews = previews;
      _previewsFor = key;
    });
  }

  Future<void> _setFilter(ScanFilter f) async {
    final page = _page;
    if (page == null || page.filter == f) return;
    await _run(() => _store.updatePage(widget.docId, page.id, filter: f));
  }

  Future<void> _ocr() async {
    final page = _page;
    if (page == null) return;
    var text = page.ocrText;
    if (text == null) {
      await _run(() async {
        final (t, lines) =
            await OcrService.instance.recognize(_store.fileOf(widget.docId, page.processedFile));
        await _store.setOcr(widget.docId, page.id, t, lines);
        text = t;
      });
    }
    if (!mounted || text == null) return;
    await showOcrSheet(context, text!);
  }

  Future<void> _delete() async {
    final page = _page;
    if (page == null) return;
    if (!await confirm(context, 'Xoá trang?', 'Trang này sẽ bị xoá vĩnh viễn.')) return;
    final doc = _store.byId(widget.docId)!;
    final last = doc.pages.length == 1;
    await _store.deletePage(widget.docId, page.id);
    if (!mounted) return;
    if (last) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else {
      setState(() => _index = _index.clamp(0, doc.pages.length - 2));
    }
  }

  Future<void> _share() async {
    final page = _page;
    if (page == null) return;
    await shareFiles(context, [_store.fileOf(widget.docId, page.processedFile)]);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DocumentStore>();
    final doc = store.byId(widget.docId);
    if (doc == null || doc.pages.isEmpty) return const Scaffold();
    final page = doc.pages[_index.clamp(0, doc.pages.length - 1)];

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        title: Text('Trang ${_index + 1}/${doc.pages.length}'),
        actions: [
          IconButton(tooltip: 'Chia sẻ ảnh', icon: const Icon(Icons.ios_share), onPressed: _share),
          IconButton(
              tooltip: 'Xoá trang', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            PageView.builder(
              controller: _pager,
              itemCount: doc.pages.length,
              onPageChanged: (i) => setState(() {
                _index = i;
                _showFilters = false;
              }),
              itemBuilder: (_, i) => InteractiveViewer(
                maxScale: 5,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Image.file(
                      store.fileOf(widget.docId, doc.pages[i].processedFile),
                      key: ValueKey(doc.pages[i].processedFile),
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),
            ),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black38,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ]),
        ),
        if (_showFilters) _filterStrip(page),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _Tool(icon: Icons.crop, label: 'Cắt', onTap: _busy ? null : _crop),
              _Tool(icon: Icons.rotate_left, label: 'Xoay trái', onTap: _busy ? null : () => _rotate(-1)),
              _Tool(icon: Icons.rotate_right, label: 'Xoay phải', onTap: _busy ? null : () => _rotate(1)),
              _Tool(
                icon: Icons.auto_awesome,
                label: 'Bộ lọc',
                active: _showFilters,
                onTap: _busy ? null : _toggleFilters,
              ),
              _Tool(icon: Icons.text_fields, label: 'Nhận dạng chữ', onTap: _busy ? null : _ocr),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _filterStrip(ScanPage page) {
    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: ScanFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final f = ScanFilter.values[i];
          final selected = f == page.filter;
          final color = Theme.of(context).colorScheme.primary;
          return GestureDetector(
            onTap: _busy ? null : () => _setFilter(f),
            child: Column(children: [
              Container(
                width: 64,
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: selected ? color : Colors.white24, width: selected ? 3 : 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: _previews == null
                    ? const Center(
                        child: SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                    : Image.memory(_previews![i], fit: BoxFit.cover, gaplessPlayback: true),
              ),
              const SizedBox(height: 4),
              Text(f.label,
                  style: TextStyle(color: selected ? color : Colors.white70, fontSize: 12)),
            ]),
          );
        },
      ),
    );
  }
}

class _Tool extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  const _Tool({required this.icon, required this.label, this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    final color = active ? Theme.of(context).colorScheme.primary : Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: onTap == null ? Colors.white38 : color),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ]),
      ),
    );
  }
}

/// Bảng hiển thị văn bản nhận dạng được, cho phép sao chép / chia sẻ.
Future<void> showOcrSheet(BuildContext context, String text) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Text('Văn bản nhận dạng', style: Theme.of(ctx).textTheme.titleMedium),
            const Spacer(),
            IconButton(
              tooltip: 'Sao chép',
              icon: const Icon(Icons.copy),
              onPressed: text.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: text));
                      showSnack(ctx, 'Đã sao chép văn bản');
                    },
            ),
            Builder(
              builder: (b) => IconButton(
                tooltip: 'Chia sẻ',
                icon: const Icon(Icons.share),
                onPressed: text.isEmpty ? null : () => shareText(b, text),
              ),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: scroll,
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              text.isEmpty ? 'Không tìm thấy chữ trong trang này.' : text,
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
          ),
        ),
      ]),
    ),
  );
}
