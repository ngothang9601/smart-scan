import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/image_processing.dart';
import '../widgets/quad_overlay.dart';

/// Màn hình chỉnh vùng cắt trên ảnh gốc. Trả về [Quad] mới khi xác nhận.
class CropScreen extends StatefulWidget {
  final File original;
  final Quad initial;

  const CropScreen({super.key, required this.original, required this.initial});

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  late Quad _quad = widget.initial;
  Size? _imageSize;
  bool _detecting = false;

  @override
  void initState() {
    super.initState();
    _loadSize();
  }

  Future<void> _loadSize() async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(await widget.original.readAsBytes());
    final d = await ui.ImageDescriptor.encoded(buffer);
    if (mounted) setState(() => _imageSize = Size(d.width.toDouble(), d.height.toDouble()));
    d.dispose();
    buffer.dispose();
  }

  Future<void> _autoDetect() async {
    setState(() => _detecting = true);
    final bytes = await widget.original.readAsBytes();
    final q = await compute(detectDocumentInImage, bytes);
    if (!mounted) return;
    setState(() => _detecting = false);
    if (q == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không tìm thấy mép giấy, hãy kéo các góc bằng tay')));
    } else {
      setState(() => _quad = q);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Cắt ảnh'),
        actions: [
          IconButton(
            tooltip: 'Xác nhận',
            icon: const Icon(Icons.check),
            onPressed: () => Navigator.pop(context, _quad),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: _imageSize == null
                    ? const CircularProgressIndicator()
                    : AspectRatio(
                        aspectRatio: _imageSize!.width / _imageSize!.height,
                        child: QuadEditor(
                          quad: _quad,
                          onChanged: (q) => setState(() => _quad = q),
                          child: Image.file(widget.original, fit: BoxFit.fill),
                        ),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _ToolButton(
                icon: _detecting ? Icons.hourglass_top : Icons.auto_fix_high,
                label: 'Tự động',
                onTap: _detecting ? null : _autoDetect,
              ),
              _ToolButton(
                icon: Icons.fullscreen,
                label: 'Toàn ảnh',
                onTap: () => setState(() => _quad = Quad.full),
              ),
              _ToolButton(
                icon: Icons.check_circle,
                label: 'Xong',
                onTap: () => Navigator.pop(context, _quad),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _ToolButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: Colors.white),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ]),
      ),
    );
  }
}
