import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Hiện hộp thoại tiến trình trong khi chạy [task].
Future<T?> runWithProgress<T>(
  BuildContext context,
  String message,
  Future<T> Function(void Function(int done, int total) progress) task,
) async {
  final progress = ValueNotifier<double?>(null);
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, v, _) => Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            CircularProgressIndicator(value: v),
            const SizedBox(height: 20),
            Text(message, textAlign: TextAlign.center),
          ]),
        ),
      ),
    ),
  );
  try {
    return await task((done, total) => progress.value = done / total);
  } catch (e) {
    if (context.mounted) showSnack(context, 'Lỗi: $e');
    return null;
  } finally {
    navigator.pop();
    progress.dispose();
  }
}

Future<String?> askText(BuildContext context,
    {required String title, String initial = '', String confirm = 'Lưu'}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(confirm)),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title, String message,
    {String action = 'Xoá'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Chọn nhiều ảnh từ thư viện ảnh của máy.
Future<List<Uint8List>> pickFromGallery() async {
  final files = await ImagePicker().pickMultiImage(imageQuality: 100);
  return [for (final f in files) await f.readAsBytes()];
}

Rect? _origin(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

Future<void> shareFiles(BuildContext context, List<File> files,
    {String? subject, String mimeType = 'image/jpeg'}) async {
  await SharePlus.instance.share(ShareParams(
    files: [for (final f in files) XFile(f.path, mimeType: mimeType)],
    subject: subject,
    sharePositionOrigin: _origin(context),
  ));
}

Future<void> shareText(BuildContext context, String text, {String? subject}) async {
  await SharePlus.instance.share(ShareParams(
    text: text,
    subject: subject,
    sharePositionOrigin: _origin(context),
  ));
}
