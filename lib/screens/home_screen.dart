import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/scan_document.dart';
import '../services/document_store.dart';
import '../services/pdf_service.dart';
import '../ui/helpers.dart';
import 'document_screen.dart';
import 'scan_flow.dart';

/// Thư viện tài liệu: tìm kiếm, mở, đổi tên, chia sẻ, xoá; nút quét mới.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _onAction(BuildContext anchor, String action, ScanDocument doc) async {
    final store = context.read<DocumentStore>();
    switch (action) {
      case 'rename':
        final name = await askText(context, title: 'Đổi tên tài liệu', initial: doc.name);
        if (name != null) await store.rename(doc.id, name);
      case 'pdf':
        final file = await runWithProgress(context, 'Đang tạo PDF…',
            (_) => PdfService.export(doc, (p) => store.fileOf(doc.id, p.processedFile)));
        if (file != null && anchor.mounted) {
          await shareFiles(anchor, [file], subject: doc.name, mimeType: 'application/pdf');
        }
      case 'duplicate':
        await store.duplicate(doc.id);
      case 'delete':
        if (await confirm(context, 'Xoá tài liệu?', '"${doc.name}" sẽ bị xoá vĩnh viễn.')) {
          await store.deleteDocument(doc.id);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<DocumentStore>();
    final docs = store.search(_query);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Scan'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SearchBar(
              controller: _search,
              hintText: 'Tìm theo tên hoặc nội dung chữ',
              leading: const Icon(Icons.search),
              trailing: [
                if (_query.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() {
                      _search.clear();
                      _query = '';
                    }),
                  ),
              ],
              onChanged: (v) => setState(() => _query = v),
              elevation: const WidgetStatePropertyAll(0),
            ),
          ),
        ),
      ),
      body: !store.loaded
          ? const Center(child: CircularProgressIndicator())
          : docs.isEmpty
              ? _empty(context)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 120),
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _DocTile(doc: docs[i], onAction: _onAction),
                ),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton.small(
          heroTag: 'gallery',
          tooltip: 'Nhập ảnh từ thư viện',
          backgroundColor: scheme.secondaryContainer,
          onPressed: () => startScan(context, source: ScanSource.gallery),
          child: const Icon(Icons.photo_library_outlined),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'scan',
          onPressed: () => startScan(context),
          icon: const Icon(Icons.document_scanner_outlined),
          label: const Text('Quét'),
        ),
      ]),
    );
  }

  Widget _empty(BuildContext context) {
    final searching = _query.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(searching ? Icons.search_off : Icons.document_scanner_outlined,
              size: 72, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            searching ? 'Không tìm thấy tài liệu phù hợp' : 'Chưa có tài liệu nào',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (!searching) ...[
            const SizedBox(height: 8),
            const Text('Nhấn "Quét" để chụp giấy tờ, hoá đơn, sách vở…',
                textAlign: TextAlign.center),
          ],
        ]),
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  final ScanDocument doc;
  final Future<void> Function(BuildContext anchor, String action, ScanDocument doc) onAction;

  const _DocTile({required this.doc, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final store = context.read<DocumentStore>();
    final first = doc.pages.isEmpty ? null : doc.pages.first;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => DocumentScreen(docId: doc.id))),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 60,
                height: 78,
                child: first == null
                    ? const ColoredBox(color: Colors.black12)
                    : Image.file(store.fileOf(doc.id, first.processedFile),
                        key: ValueKey(first.processedFile), fit: BoxFit.cover, cacheWidth: 180),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(doc.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(
                  '${DateFormat('dd/MM/yyyy HH:mm').format(doc.updatedAt)} · ${doc.pages.length} trang',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ]),
            ),
            Builder(
              builder: (anchor) => PopupMenuButton<String>(
                onSelected: (v) => onAction(anchor, v, doc),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Đổi tên')),
                  PopupMenuItem(value: 'pdf', child: Text('Chia sẻ PDF')),
                  PopupMenuItem(value: 'duplicate', child: Text('Nhân bản')),
                  PopupMenuItem(value: 'delete', child: Text('Xoá')),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
