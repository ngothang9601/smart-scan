import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/document_store.dart';
import '../ui/helpers.dart';
import 'camera_screen.dart';
import 'document_screen.dart';
import 'page_editor_screen.dart';

enum ScanSource { camera, gallery }

/// Chụp hoặc nhập ảnh, xử lý và lưu thành tài liệu mới (hoặc thêm vào [docId]).
Future<void> startScan(BuildContext context,
    {ScanSource source = ScanSource.camera, String? docId}) async {
  final store = context.read<DocumentStore>();
  final navigator = Navigator.of(context);

  final List<Uint8List> images;
  if (source == ScanSource.camera) {
    images = await navigator.push<List<Uint8List>>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => CameraScreen(startInBatchMode: docId != null),
          ),
        ) ??
        const [];
  } else {
    images = await pickFromGallery();
  }
  if (images.isEmpty || !context.mounted) return;

  final label = images.length == 1 ? 'Đang xử lý ảnh…' : 'Đang xử lý ${images.length} ảnh…';
  if (docId != null) {
    final before = store.byId(docId)?.pages.length ?? 0;
    final doc = await runWithProgress(
        context, label, (p) => store.addPages(docId, images, onProgress: p));
    if (doc != null && images.length == 1) {
      await navigator.push(MaterialPageRoute(
          builder: (_) => PageEditorScreen(docId: docId, initialIndex: before, openCrop: true)));
    }
    return;
  }

  final doc =
      await runWithProgress(context, label, (p) => store.createDocument(images, onProgress: p));
  if (doc == null) return;
  navigator.push(MaterialPageRoute(builder: (_) => DocumentScreen(docId: doc.id)));
  // Một trang: mở ngay màn hình cắt để người dùng kiểm tra mép giấy.
  if (doc.pages.length == 1) {
    navigator.push(MaterialPageRoute(
        builder: (_) => PageEditorScreen(docId: doc.id, openCrop: true)));
  }
}
