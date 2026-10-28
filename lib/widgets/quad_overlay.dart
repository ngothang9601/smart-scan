import 'package:flutter/material.dart';

import '../services/image_processing.dart';

/// Vẽ tứ giác tài liệu lên vùng [Size] (toạ độ chuẩn hoá -> pixel).
class QuadPainter extends CustomPainter {
  final Quad quad;
  final Color color;
  final bool shadeOutside;
  final bool drawHandles;

  QuadPainter(this.quad,
      {required this.color, this.shadeOutside = true, this.drawHandles = false});

  @override
  void paint(Canvas canvas, Size size) {
    final pts = [for (final p in quad.points) Offset(p.x * size.width, p.y * size.height)];
    final path = Path()..addPolygon(pts, true);
    if (shadeOutside) {
      final outside = Path.combine(
          PathOperation.difference, Path()..addRect(Offset.zero & size), path);
      canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.45));
    }
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
    if (drawHandles) {
      for (final p in pts) {
        canvas.drawCircle(p, 13, Paint()..color = Colors.white.withValues(alpha: 0.9));
        canvas.drawCircle(
            p,
            13,
            Paint()
              ..color = color
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3);
      }
    }
  }

  @override
  bool shouldRepaint(QuadPainter old) =>
      old.quad != quad || old.color != color || old.drawHandles != drawHandles;
}

/// Trình chỉnh tứ giác: kéo 4 góc (hoặc trung điểm cạnh) để chỉnh vùng cắt.
class QuadEditor extends StatefulWidget {
  final Quad quad;
  final ValueChanged<Quad> onChanged;
  final Widget child;

  const QuadEditor({super.key, required this.quad, required this.onChanged, required this.child});

  @override
  State<QuadEditor> createState() => _QuadEditorState();
}

class _QuadEditorState extends State<QuadEditor> {
  /// 0..3: góc; 4..7: cạnh (giữa góc i và i+1).
  int? _active;
  Offset? _touch;

  int? _hitTest(Offset pos, Size size) {
    final pts = [
      for (final p in widget.quad.points) Offset(p.x * size.width, p.y * size.height)
    ];
    int? best;
    var bestDist = 44.0;
    for (var i = 0; i < 4; i++) {
      final d = (pts[i] - pos).distance;
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    if (best != null) return best;
    for (var i = 0; i < 4; i++) {
      final mid = (pts[i] + pts[(i + 1) % 4]) / 2;
      final d = (mid - pos).distance;
      if (d < bestDist) {
        bestDist = d;
        best = 4 + i;
      }
    }
    return best;
  }

  void _move(Offset delta, Size size) {
    final i = _active;
    if (i == null) return;
    final dx = delta.dx / size.width, dy = delta.dy / size.height;
    QuadPoint shift(QuadPoint p) =>
        QuadPoint((p.x + dx).clamp(0.0, 1.0), (p.y + dy).clamp(0.0, 1.0));
    final pts = [...widget.quad.points];
    if (i < 4) {
      pts[i] = shift(pts[i]);
    } else {
      final a = i - 4, b = (i - 3) % 4;
      pts[a] = shift(pts[a]);
      pts[b] = shift(pts[b]);
    }
    widget.onChanged(Quad(pts));
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => setState(() {
          _active = _hitTest(d.localPosition, size);
          _touch = d.localPosition;
        }),
        onPanUpdate: (d) {
          _move(d.delta, size);
          setState(() => _touch = d.localPosition);
        },
        onPanEnd: (_) => setState(() {
          _active = null;
          _touch = null;
        }),
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: widget.child),
          Positioned.fill(
            child: CustomPaint(
              painter: QuadPainter(widget.quad, color: color, drawHandles: true),
            ),
          ),
          // Kính lúp giúp đặt góc chính xác.
          if (_active != null && _active! < 4 && _touch != null)
            Positioned(
              left: _touch!.dx - 50,
              top: _touch!.dy - 150,
              child: IgnorePointer(
                child: RawMagnifier(
                  size: const Size(100, 100),
                  magnificationScale: 2,
                  focalPointOffset: const Offset(0, 100),
                  decoration: MagnifierDecoration(
                    shape: CircleBorder(side: BorderSide(color: color, width: 3)),
                  ),
                ),
              ),
            ),
        ]),
      );
    });
  }
}
