import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/image_processing.dart';
import '../ui/helpers.dart';
import '../widgets/quad_overlay.dart';

/// Màn hình chụp: xem trước camera, khung mép giấy trực tiếp, tự chụp,
/// đèn flash, chế độ một trang / nhiều trang. Trả về danh sách ảnh đã chụp.
class CameraScreen extends StatefulWidget {
  final bool startInBatchMode;
  const CameraScreen({super.key, this.startInBatchMode = false});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;
  final _shots = <Uint8List>[];
  late bool _batch = widget.startInBatchMode;
  bool _autoCapture = true;
  bool _taking = false;
  FlashMode _flash = FlashMode.off;

  // Nhận diện trực tiếp.
  bool _streaming = false;
  bool _analyzing = false;
  DateTime _lastAnalysis = DateTime.fromMillisecondsSinceEpoch(0);
  Quad? _liveQuad;
  Quad? _stableRef;
  DateTime? _stableSince;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _streaming = false;
      c.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _init();
    }
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _error = 'Thiết bị không có camera');
        return;
      }
      final cam = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cams.first);
      final c = CameraController(
        cam,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
      );
      await c.initialize();
      await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await c.setFlashMode(_flash);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _error = null;
      });
      await _startStream();
    } on CameraException catch (e) {
      setState(() => _error = e.code == 'CameraAccessDenied'
          ? 'Ứng dụng chưa được cấp quyền camera. Hãy bật trong Cài đặt.'
          : 'Lỗi camera: ${e.description}');
    }
  }

  Future<void> _startStream() async {
    final c = _controller;
    if (c == null || _streaming) return;
    try {
      await c.startImageStream(_onFrame);
      _streaming = true;
    } catch (_) {
      // Một số máy không hỗ trợ stream song song; vẫn chụp được bình thường.
    }
  }

  Future<void> _stopStream() async {
    final c = _controller;
    if (c == null || !_streaming) return;
    _streaming = false;
    try {
      await c.stopImageStream();
    } catch (_) {}
  }

  void _onFrame(CameraImage frame) {
    if (_analyzing || _taking) return;
    final now = DateTime.now();
    if (now.difference(_lastAnalysis).inMilliseconds < 300) return;
    _lastAnalysis = now;
    _analyzing = true;
    final gray = _toGray(frame);
    final rotation = _controller!.description.sensorOrientation;
    compute(_detectFrame, (gray.$1, gray.$2, gray.$3, rotation)).then((q) {
      _analyzing = false;
      if (!mounted) return;
      setState(() => _liveQuad = q);
      _checkAutoCapture(q);
    });
  }

  /// Lấy kênh độ sáng và thu nhỏ (~240px) để nhận diện nhanh.
  static (Uint8List, int, int) _toGray(CameraImage f) {
    final plane = f.planes.first;
    final step = (f.width > f.height ? f.width : f.height) ~/ 240;
    final s = step < 1 ? 1 : step;
    final w = f.width ~/ s, h = f.height ~/ s;
    final out = Uint8List(w * h);
    final bytes = plane.bytes;
    final bpr = plane.bytesPerRow;
    final bgra = f.format.group == ImageFormatGroup.bgra8888;
    var o = 0;
    for (var y = 0; y < h; y++) {
      final row = y * s * bpr;
      for (var x = 0; x < w; x++) {
        if (bgra) {
          final i = row + x * s * 4;
          out[o++] = (bytes[i] * 29 + bytes[i + 1] * 150 + bytes[i + 2] * 77) >> 8;
        } else {
          out[o++] = bytes[row + x * s];
        }
      }
    }
    return (out, w, h);
  }

  void _checkAutoCapture(Quad? q) {
    if (!_autoCapture || _taking || q == null) {
      _stableRef = null;
      _stableSince = null;
      return;
    }
    final ref = _stableRef;
    final moved = ref == null ||
        List.generate(4, (i) {
          final a = ref.points[i], b = q.points[i];
          return (a.x - b.x).abs() + (a.y - b.y).abs();
        }).any((d) => d > 0.03);
    if (moved) {
      _stableRef = q;
      _stableSince = DateTime.now();
    } else if (DateTime.now().difference(_stableSince!).inMilliseconds > 1500) {
      _stableRef = null;
      _stableSince = null;
      _capture();
    }
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || _taking || !c.value.isInitialized) return;
    setState(() => _taking = true);
    try {
      await _stopStream();
      final file = await c.takePicture();
      final bytes = await file.readAsBytes();
      unawaited(File(file.path).delete().catchError((_) => File(file.path)));
      HapticFeedback.mediumImpact();
      _shots.add(bytes);
      if (!_batch) {
        if (mounted) Navigator.pop(context, _shots);
        return;
      }
    } on CameraException catch (e) {
      if (mounted) showSnack(context, 'Không chụp được: ${e.description}');
    } finally {
      if (mounted) {
        setState(() {
          _taking = false;
          _liveQuad = null;
        });
        if (_batch) await _startStream();
      }
    }
  }

  Future<void> _importGallery() async {
    await _stopStream();
    final images = await pickFromGallery();
    if (!mounted) return;
    if (images.isNotEmpty) {
      _shots.addAll(images);
      if (!_batch) {
        Navigator.pop(context, _shots);
        return;
      }
      setState(() {});
    }
    await _startStream();
  }

  Future<void> _cycleFlash() async {
    const order = [FlashMode.off, FlashMode.auto, FlashMode.always, FlashMode.torch];
    final next = order[(order.indexOf(_flash) + 1) % order.length];
    await _controller?.setFlashMode(next);
    setState(() => _flash = next);
  }

  IconData get _flashIcon => switch (_flash) {
        FlashMode.off => Icons.flash_off,
        FlashMode.auto => Icons.flash_auto,
        FlashMode.always => Icons.flash_on,
        FlashMode.torch => Icons.highlight,
      };

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(children: [
          _topBar(),
          Expanded(
            child: Center(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white)),
                    )
                  : (c == null || !c.value.isInitialized)
                      ? const CircularProgressIndicator()
                      : AspectRatio(
                          aspectRatio: 1 / c.value.aspectRatio,
                          child: Stack(fit: StackFit.expand, children: [
                            CameraPreview(c),
                            if (_liveQuad != null)
                              CustomPaint(
                                painter: QuadPainter(_liveQuad!,
                                    color: Colors.lightBlueAccent, shadeOutside: false),
                              ),
                            if (_taking) Container(color: Colors.white24),
                          ]),
                        ),
            ),
          ),
          _bottomBar(),
        ]),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(children: [
        IconButton(
          color: Colors.white,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context, _shots),
        ),
        const Spacer(),
        IconButton(color: Colors.white, icon: Icon(_flashIcon), onPressed: _cycleFlash),
        TextButton.icon(
          onPressed: () => setState(() => _autoCapture = !_autoCapture),
          icon: Icon(_autoCapture ? Icons.motion_photos_auto : Icons.motion_photos_off,
              color: _autoCapture ? Colors.lightBlueAccent : Colors.white),
          label: Text(_autoCapture ? 'Tự chụp' : 'Chụp tay',
              style: const TextStyle(color: Colors.white)),
        ),
      ]),
    );
  }

  Widget _bottomBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SegmentedButton<bool>(
          style: SegmentedButton.styleFrom(
            foregroundColor: Colors.white,
            selectedForegroundColor: Colors.black,
            selectedBackgroundColor: Colors.white,
          ),
          segments: const [
            ButtonSegment(value: false, label: Text('Một trang')),
            ButtonSegment(value: true, label: Text('Nhiều trang')),
          ],
          selected: {_batch},
          onSelectionChanged: (s) => setState(() => _batch = s.first),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Nhập từ thư viện ảnh',
                color: Colors.white,
                iconSize: 30,
                icon: const Icon(Icons.photo_library_outlined),
                onPressed: _importGallery,
              ),
            ),
          ),
          GestureDetector(
            onTap: _capture,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _taking ? Colors.grey : Colors.white,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: _shots.isEmpty
                  ? const SizedBox(width: 56)
                  : GestureDetector(
                      onTap: () => Navigator.pop(context, _shots),
                      child: Badge(
                        label: Text('${_shots.length}'),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(_shots.last,
                              width: 52, height: 64, fit: BoxFit.cover, cacheWidth: 120),
                        ),
                      ),
                    ),
            ),
          ),
        ]),
        if (_batch && _shots.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(context, _shots),
              icon: const Icon(Icons.check),
              label: Text('Xong (${_shots.length} trang)'),
            ),
          ),
      ]),
    );
  }
}

/// Chạy trong isolate: nhận diện trên khung hình và xoay về hướng dọc.
Quad? _detectFrame((Uint8List, int, int, int) a) {
  final q = detectDocumentGray(a.$1, a.$2, a.$3);
  if (q == null) return null;
  final rotated = [
    for (final p in q.points)
      switch (a.$4) {
        90 => QuadPoint(1 - p.y, p.x),
        180 => QuadPoint(1 - p.x, 1 - p.y),
        270 => QuadPoint(p.y, 1 - p.x),
        _ => p,
      },
  ];
  return Quad.ordered(rotated);
}
