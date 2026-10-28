import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:smart_scan/services/image_processing.dart';

/// Vẽ một "tờ giấy" sáng có chữ trên nền [bg].
img.Image synthetic(List<QuadPoint> corners, {int bg = 60, int w = 800, int h = 1000}) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(bg, bg + 10, bg + 20));
  final rnd = math.Random(1);
  // Nhiễu nền.
  for (var i = 0; i < 4000; i++) {
    final v = bg + rnd.nextInt(30);
    image.setPixelRgb(rnd.nextInt(w), rnd.nextInt(h), v, v, v);
  }
  img.fillPolygon(image,
      vertices: [for (final p in corners) img.Point(p.x * w, p.y * h)],
      color: img.ColorRgb8(235, 235, 228));
  // "Dòng chữ" bên trong.
  final cx = corners.fold<double>(0, (s, p) => s + p.x) / 4 * w;
  final cy = corners.fold<double>(0, (s, p) => s + p.y) / 4 * h;
  for (var k = -4; k <= 4; k++) {
    img.drawLine(image,
        x1: (cx - 120).round(), y1: (cy + k * 30).round(),
        x2: (cx + 120).round(), y2: (cy + k * 30).round(),
        color: img.ColorRgb8(20, 20, 20), thickness: 4);
  }
  return image;
}

double maxError(Quad a, List<QuadPoint> b) {
  var e = 0.0;
  for (var i = 0; i < 4; i++) {
    e = math.max(e, math.max((a.points[i].x - b[i].x).abs(), (a.points[i].y - b[i].y).abs()));
  }
  return e;
}

void main() {
  test('nhận diện tài liệu sáng trên nền tối, bị nghiêng', () {
    const corners = [QuadPoint(0.18, 0.12), QuadPoint(0.82, 0.18), QuadPoint(0.88, 0.86), QuadPoint(0.10, 0.80)];
    final q = detectDocument(synthetic(corners));
    expect(q, isNotNull);
    expect(maxError(q!, corners), lessThan(0.025), reason: '$q');
  });

  test('nhận diện tài liệu trên nền sáng (biên mảnh)', () {
    const corners = [QuadPoint(0.25, 0.20), QuadPoint(0.75, 0.15), QuadPoint(0.80, 0.85), QuadPoint(0.20, 0.80)];
    final q = detectDocument(synthetic(corners, bg: 170));
    expect(q, isNotNull);
    expect(maxError(q!, corners), lessThan(0.025), reason: '$q');
  });

  test('trả về null khi ảnh trống', () {
    final image = img.Image(width: 300, height: 400);
    img.fill(image, color: img.ColorRgb8(128, 128, 128));
    expect(detectDocument(image), isNull);
  });

  test('Quad.ordered sắp xếp đúng thứ tự', () {
    final q = Quad.ordered(const [QuadPoint(0.9, 0.9), QuadPoint(0.1, 0.1), QuadPoint(0.1, 0.9), QuadPoint(0.9, 0.1)]);
    expect(q.toList(), [0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9]);
  });

  test('homography ánh xạ đúng 4 góc', () {
    final from = [[0.0, 0.0], [100.0, 0.0], [100.0, 50.0], [0.0, 50.0]];
    final to = [[10.0, 5.0], [90.0, 12.0], [95.0, 70.0], [3.0, 60.0]];
    final h = computeHomography(from, to);
    for (var i = 0; i < 4; i++) {
      final x = from[i][0], y = from[i][1];
      final z = h[6] * x + h[7] * y + h[8];
      expect((h[0] * x + h[1] * y + h[2]) / z, closeTo(to[i][0], 1e-6));
      expect((h[3] * x + h[4] * y + h[5]) / z, closeTo(to[i][1], 1e-6));
    }
  });

  test('nắn phối cảnh cho ra trang giấy sáng, đúng tỉ lệ', () {
    const corners = [QuadPoint(0.18, 0.12), QuadPoint(0.82, 0.18), QuadPoint(0.88, 0.86), QuadPoint(0.10, 0.80)];
    final src = synthetic(corners);
    final out = warpPerspective(src, const Quad(corners));
    expect(out.width, greaterThan(450));
    expect(out.height, greaterThan(600));
    // Góc của ảnh kết quả phải là giấy (sáng), không phải nền.
    for (final p in [out.getPixel(5, 5), out.getPixel(out.width - 6, out.height - 6)]) {
      expect(p.r, greaterThan(200));
    }
  });

  test('các bộ lọc giữ kích thước và đen trắng chỉ có 0/255', () {
    final src = synthetic(const [QuadPoint(0, 0), QuadPoint(1, 0), QuadPoint(1, 1), QuadPoint(0, 1)]);
    for (final f in ScanFilter.values) {
      final out = applyFilter(src, f);
      expect(out.width, src.width);
      expect(out.height, src.height);
    }
    final bw = applyFilter(src, ScanFilter.blackWhite);
    for (final p in bw) {
      expect(p.r == 0 || p.r == 255, isTrue);
    }
  });

  test('pipeline processPage với xoay 90 độ', () {
    final src = img.encodeJpg(synthetic(const [QuadPoint(0.2, 0.2), QuadPoint(0.8, 0.2), QuadPoint(0.8, 0.8), QuadPoint(0.2, 0.8)]));
    final out = img.decodeJpg(processPage(ProcessRequest(src,
        const Quad([QuadPoint(0.2, 0.2), QuadPoint(0.8, 0.2), QuadPoint(0.8, 0.8), QuadPoint(0.2, 0.8)]),
        ScanFilter.enhanced, 1)))!;
    // Vùng gốc rộng 480 x cao 600, xoay 90° -> rộng ~600, cao ~480.
    expect(out.width, greaterThan(out.height));
  });
}
