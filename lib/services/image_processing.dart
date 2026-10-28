// Xử lý ảnh tài liệu viết hoàn toàn bằng Dart (chạy được trên cả iOS và
// Android, không phụ thuộc thư viện native). Gồm: chuẩn hoá ảnh, nhận diện
// mép giấy, nắn phối cảnh, bộ lọc và xoay.
//
// Mọi hàm ở đây là hàm thuần (top-level) để có thể chạy trong Isolate.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Một điểm với toạ độ chuẩn hoá trong khoảng 0..1.
class QuadPoint {
  final double x;
  final double y;
  const QuadPoint(this.x, this.y);

  QuadPoint copyWith({double? x, double? y}) => QuadPoint(x ?? this.x, y ?? this.y);

  @override
  String toString() => '(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)})';
}

/// Tứ giác bao tài liệu, theo thứ tự: trên-trái, trên-phải, dưới-phải, dưới-trái.
class Quad {
  final List<QuadPoint> points;
  const Quad(this.points);

  static const full = Quad([
    QuadPoint(0, 0),
    QuadPoint(1, 0),
    QuadPoint(1, 1),
    QuadPoint(0, 1),
  ]);

  QuadPoint get tl => points[0];
  QuadPoint get tr => points[1];
  QuadPoint get br => points[2];
  QuadPoint get bl => points[3];

  List<double> toList() => [for (final p in points) ...[p.x, p.y]];

  factory Quad.fromList(List<dynamic> v) => Quad([
        for (var i = 0; i < 4; i++)
          QuadPoint((v[i * 2] as num).toDouble(), (v[i * 2 + 1] as num).toDouble()),
      ]);

  /// Sắp xếp 4 điểm bất kỳ về đúng thứ tự TL, TR, BR, BL.
  factory Quad.ordered(List<QuadPoint> pts) {
    final cx = pts.fold<double>(0, (s, p) => s + p.x) / pts.length;
    final cy = pts.fold<double>(0, (s, p) => s + p.y) / pts.length;
    final sorted = [...pts]
      ..sort((a, b) => math.atan2(a.y - cy, a.x - cx).compareTo(math.atan2(b.y - cy, b.x - cx)));
    // Sau khi sắp theo góc (bắt đầu từ -pi), tìm điểm có x+y nhỏ nhất làm TL.
    var start = 0;
    for (var i = 1; i < 4; i++) {
      if (sorted[i].x + sorted[i].y < sorted[start].x + sorted[start].y) start = i;
    }
    return Quad([for (var i = 0; i < 4; i++) sorted[(start + i) % 4]]);
  }

  bool get isFull =>
      points.every((p) => p.x <= 0.001 || p.x >= 0.999) &&
      points.every((p) => p.y <= 0.001 || p.y >= 0.999);

  @override
  String toString() => 'Quad$points';
}

/// Các bộ lọc ảnh tài liệu.
enum ScanFilter { original, enhanced, grayscale, blackWhite, lighten }

// ---------------------------------------------------------------------------
// Chuẩn hoá ảnh đầu vào
// ---------------------------------------------------------------------------

/// Giải mã, xoay theo EXIF, giới hạn kích thước và mã hoá lại JPEG.
/// Sau bước này, toạ độ ảnh khớp với cách Flutter hiển thị.
Uint8List normalizeImage(Uint8List bytes, {int maxSide = 3000}) {
  var image = img.decodeImage(bytes);
  if (image == null) throw const FormatException('Không đọc được ảnh');
  image = img.bakeOrientation(image);
  if (math.max(image.width, image.height) > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.linear)
        : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.linear);
  }
  if (image.numChannels == 4) image = image.convert(numChannels: 3);
  return img.encodeJpg(image, quality: 92);
}

// ---------------------------------------------------------------------------
// Nhận diện mép giấy
// ---------------------------------------------------------------------------

/// Nhận diện tài liệu trong ảnh JPEG/PNG. Trả về null nếu không tìm thấy.
Quad? detectDocumentInImage(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  return detectDocument(image);
}

Quad? detectDocument(img.Image image) {
  const target = 360;
  final scale = target / math.max(image.width, image.height);
  final small = scale < 1
      ? img.copyResize(image,
          width: (image.width * scale).round(),
          height: (image.height * scale).round(),
          interpolation: img.Interpolation.average)
      : image;
  final w = small.width, h = small.height;
  final gray = Uint8List(w * h);
  var i = 0;
  for (final p in small) {
    gray[i++] = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
  }
  return detectDocumentGray(gray, w, h);
}

/// Nhận diện trên mảng độ sáng (grayscale) kích thước w×h.
/// Dùng cho cả ảnh chụp và khung hình camera trực tiếp.
Quad? detectDocumentGray(Uint8List gray, int w, int h) {
  final blurred = _boxBlur(gray, w, h, 2);

  // Cách 1: biên Sobel -> vùng kín lớn nhất không chạm viền ảnh.
  final edges = _sobelEdges(blurred, w, h);
  _dilate(edges, w, h);
  final inside = _invert(edges);
  _clearBorderRegions(inside, w, h);
  var region = _largestComponent(inside, w, h);
  if (region != null) {
    // Bù lại phần bị giãn nở khi dilate.
    final quad = _quadFromRegion(region, w, h, grow: 1.5);
    if (quad != null && _isPlausible(quad, w, h)) return quad;
  }

  // Cách 2: phân ngưỡng Otsu -> vùng sáng (hoặc tối) lớn nhất.
  final t = _otsu(blurred);
  for (final bright in [true, false]) {
    final mask = Uint8List(w * h);
    for (var k = 0; k < mask.length; k++) {
      mask[k] = (bright ? blurred[k] > t : blurred[k] <= t) ? 1 : 0;
    }
    _open(mask, w, h);
    region = _largestComponent(mask, w, h);
    if (region == null) continue;
    final quad = _quadFromRegion(region, w, h);
    if (quad != null && _isPlausible(quad, w, h, maxArea: 0.97)) return quad;
  }
  return null;
}

bool _isPlausible(Quad q, int w, int h, {double maxArea = 0.995}) {
  final area = _quadArea(q.points.map((p) => [p.x, p.y]).toList());
  if (area < 0.12 || area > maxArea) return false;
  // Tứ giác phải lồi.
  double? sign;
  for (var i = 0; i < 4; i++) {
    final a = q.points[i], b = q.points[(i + 1) % 4], c = q.points[(i + 2) % 4];
    final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
    if (cross.abs() < 1e-6) return false;
    sign ??= cross.sign;
    if (cross.sign != sign) return false;
  }
  return true;
}

Uint8List _boxBlur(Uint8List src, int w, int h, int r) {
  final tmp = Uint8List(w * h);
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    var sum = 0;
    for (var x = -r; x <= r; x++) {
      sum += src[y * w + x.clamp(0, w - 1)];
    }
    for (var x = 0; x < w; x++) {
      tmp[y * w + x] = sum ~/ (2 * r + 1);
      sum += src[y * w + (x + r + 1).clamp(0, w - 1)] - src[y * w + (x - r).clamp(0, w - 1)];
    }
  }
  for (var x = 0; x < w; x++) {
    var sum = 0;
    for (var y = -r; y <= r; y++) {
      sum += tmp[y.clamp(0, h - 1) * w + x];
    }
    for (var y = 0; y < h; y++) {
      out[y * w + x] = sum ~/ (2 * r + 1);
      sum += tmp[(y + r + 1).clamp(0, h - 1) * w + x] - tmp[(y - r).clamp(0, h - 1) * w + x];
    }
  }
  return out;
}

Uint8List _sobelEdges(Uint8List g, int w, int h) {
  final mag = Float32List(w * h);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final gx = -g[i - w - 1] - 2 * g[i - 1] - g[i + w - 1] + g[i - w + 1] + 2 * g[i + 1] + g[i + w + 1];
      final gy = -g[i - w - 1] - 2 * g[i - w] - g[i - w + 1] + g[i + w - 1] + 2 * g[i + w] + g[i + w + 1];
      mag[i] = math.sqrt((gx * gx + gy * gy).toDouble());
    }
  }
  // Ngưỡng thích ứng: lấy khoảng 12% điểm có gradient mạnh nhất, tối thiểu 40.
  final sorted = Float32List.fromList(mag)..sort();
  final thr = math.max(40.0, sorted[(sorted.length * 0.88).floor()]);
  final out = Uint8List(w * h);
  for (var i = 0; i < mag.length; i++) {
    out[i] = mag[i] >= thr ? 1 : 0;
  }
  return out;
}

void _dilate(Uint8List m, int w, int h) {
  final src = Uint8List.fromList(m);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (src[y * w + x] == 1) continue;
      var hit = false;
      for (var dy = -1; dy <= 1 && !hit; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx;
          if (xx >= 0 && xx < w && src[yy * w + xx] == 1) {
            hit = true;
            break;
          }
        }
      }
      if (hit) m[y * w + x] = 1;
    }
  }
}

void _erode(Uint8List m, int w, int h) {
  final inv = _invert(m);
  _dilate(inv, w, h);
  for (var i = 0; i < m.length; i++) {
    m[i] = 1 - inv[i];
  }
}

/// Phép mở hình thái học: loại bỏ nhiễu nhỏ.
void _open(Uint8List m, int w, int h) {
  _erode(m, w, h);
  _erode(m, w, h);
  _dilate(m, w, h);
  _dilate(m, w, h);
}

Uint8List _invert(Uint8List m) {
  final out = Uint8List(m.length);
  for (var i = 0; i < m.length; i++) {
    out[i] = 1 - m[i];
  }
  return out;
}

/// Xoá các vùng nối với viền ảnh (đó là nền, không phải bên trong tài liệu).
void _clearBorderRegions(Uint8List m, int w, int h) {
  final stack = <int>[];
  void push(int x, int y) {
    final i = y * w + x;
    if (m[i] == 1) {
      m[i] = 0;
      stack.add(i);
    }
  }

  for (var x = 0; x < w; x++) {
    push(x, 0);
    push(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    push(0, y);
    push(w - 1, y);
  }
  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    final x = i % w, y = i ~/ w;
    if (x > 0) push(x - 1, y);
    if (x < w - 1) push(x + 1, y);
    if (y > 0) push(x, y - 1);
    if (y < h - 1) push(x, y + 1);
  }
}

/// Trả về danh sách chỉ số điểm thuộc vùng liên thông lớn nhất.
List<int>? _largestComponent(Uint8List m, int w, int h) {
  final labels = Int32List(w * h);
  List<int>? best;
  var label = 0;
  for (var start = 0; start < m.length; start++) {
    if (m[start] == 0 || labels[start] != 0) continue;
    label++;
    final comp = <int>[];
    final stack = <int>[start];
    labels[start] = label;
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      comp.add(i);
      final x = i % w, y = i ~/ w;
      for (final n in [
        if (x > 0) i - 1,
        if (x < w - 1) i + 1,
        if (y > 0) i - w,
        if (y < h - 1) i + w,
      ]) {
        if (m[n] == 1 && labels[n] == 0) {
          labels[n] = label;
          stack.add(n);
        }
      }
    }
    if (best == null || comp.length > best.length) best = comp;
  }
  if (best == null || best.length < w * h * 0.08) return null;
  return best;
}

Quad? _quadFromRegion(List<int> region, int w, int h, {double grow = 0}) {
  // Bao lồi của vùng (thuật toán monotone chain), chỉ cần điểm đầu/cuối mỗi hàng.
  final minX = List<int>.filled(h, w), maxX = List<int>.filled(h, -1);
  for (final i in region) {
    final x = i % w, y = i ~/ w;
    if (x < minX[y]) minX[y] = x;
    if (x > maxX[y]) maxX[y] = x;
  }
  final pts = <List<double>>[];
  for (var y = 0; y < h; y++) {
    if (maxX[y] < 0) continue;
    pts.add([minX[y].toDouble(), y.toDouble()]);
    if (maxX[y] != minX[y]) pts.add([maxX[y].toDouble(), y.toDouble()]);
  }
  final hull = _convexHull(pts);
  if (hull.length < 4) return null;

  // Chọn 4 đỉnh của bao lồi tạo tứ giác diện tích lớn nhất (tối ưu cục bộ).
  var idx = <int>[0, 0, 0, 0];
  double f(List<double> p, int k) => switch (k) {
        0 => -(p[0] + p[1]),
        1 => p[0] - p[1],
        2 => p[0] + p[1],
        _ => p[1] - p[0],
      };
  for (var k = 0; k < 4; k++) {
    var bi = 0;
    for (var j = 1; j < hull.length; j++) {
      if (f(hull[j], k) > f(hull[bi], k)) bi = j;
    }
    idx[k] = bi;
  }
  var bestArea = _quadArea([for (final j in idx) hull[j]]);
  var improved = true;
  var guard = 0;
  while (improved && guard++ < 50) {
    improved = false;
    for (var k = 0; k < 4; k++) {
      for (var j = 0; j < hull.length; j++) {
        final cand = [...idx]..[k] = j;
        final a = _quadArea([for (final c in cand) hull[c]]);
        if (a > bestArea + 1e-9) {
          bestArea = a;
          idx = cand;
          improved = true;
        }
      }
    }
  }
  final corners = [for (final j in idx) hull[j]];
  final cx = corners.fold<double>(0, (s, p) => s + p[0]) / 4;
  final cy = corners.fold<double>(0, (s, p) => s + p[1]) / 4;
  return Quad.ordered([
    for (final p in corners)
      () {
        // Đẩy nhẹ ra ngoài để bù hiệu ứng làm mờ/giãn nở.
        final dx = p[0] - cx, dy = p[1] - cy;
        final len = math.sqrt(dx * dx + dy * dy);
        final k = len == 0 ? 0 : grow / len;
        return QuadPoint(
          ((p[0] + dx * k + 0.5) / w).clamp(0.0, 1.0),
          ((p[1] + dy * k + 0.5) / h).clamp(0.0, 1.0),
        );
      }(),
  ]);
}

List<List<double>> _convexHull(List<List<double>> pts) {
  pts.sort((a, b) => a[0] != b[0] ? a[0].compareTo(b[0]) : a[1].compareTo(b[1]));
  double cross(List<double> o, List<double> a, List<double> b) =>
      (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
  final lower = <List<double>>[];
  for (final p in pts) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <List<double>>[];
  for (final p in pts.reversed) {
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  return [...lower.sublist(0, lower.length - 1), ...upper.sublist(0, upper.length - 1)];
}

/// Diện tích đa giác (công thức shoelace); với toạ độ chuẩn hoá thì là tỉ lệ ảnh.
double _quadArea(List<List<double>> p) {
  var s = 0.0;
  for (var i = 0; i < p.length; i++) {
    final a = p[i], b = p[(i + 1) % p.length];
    s += a[0] * b[1] - b[0] * a[1];
  }
  return s.abs() / 2;
}

int _otsu(Uint8List g) {
  final hist = List<int>.filled(256, 0);
  for (final v in g) {
    hist[v]++;
  }
  final total = g.length;
  var sum = 0.0;
  for (var t = 0; t < 256; t++) {
    sum += t * hist[t];
  }
  var sumB = 0.0, wB = 0, best = 0.0, thr = 127;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB, mF = (sum - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      thr = t;
    }
  }
  return thr;
}

// ---------------------------------------------------------------------------
// Nắn phối cảnh
// ---------------------------------------------------------------------------

/// Tính ma trận đồng nhất (homography) 3×3 ánh xạ 4 điểm [from] sang [to].
List<double> computeHomography(List<List<double>> from, List<List<double>> to) {
  final a = List.generate(8, (_) => List<double>.filled(9, 0));
  for (var i = 0; i < 4; i++) {
    final x = from[i][0], y = from[i][1], u = to[i][0], v = to[i][1];
    a[i * 2] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u];
    a[i * 2 + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v];
  }
  // Khử Gauss có chọn phần tử trội.
  for (var c = 0; c < 8; c++) {
    var piv = c;
    for (var r = c + 1; r < 8; r++) {
      if (a[r][c].abs() > a[piv][c].abs()) piv = r;
    }
    final t = a[c];
    a[c] = a[piv];
    a[piv] = t;
    final d = a[c][c];
    if (d.abs() < 1e-12) throw StateError('Tứ giác suy biến');
    for (var k = c; k < 9; k++) {
      a[c][k] /= d;
    }
    for (var r = 0; r < 8; r++) {
      if (r == c) continue;
      final f = a[r][c];
      if (f == 0) continue;
      for (var k = c; k < 9; k++) {
        a[r][k] -= f * a[c][k];
      }
    }
  }
  return [for (var r = 0; r < 8; r++) a[r][8], 1];
}

/// Cắt và nắn tài liệu theo [quad] thành ảnh chữ nhật.
img.Image warpPerspective(img.Image src, Quad quad, {int maxSide = 2400}) {
  if (src.numChannels != 3) src = src.convert(numChannels: 3);
  final sw = src.width, sh = src.height;
  final pts = [for (final p in quad.points) [p.x * (sw - 1), p.y * (sh - 1)]];
  double dist(List<double> a, List<double> b) =>
      math.sqrt(math.pow(a[0] - b[0], 2) + math.pow(a[1] - b[1], 2));
  var outW = math.max(dist(pts[0], pts[1]), dist(pts[3], pts[2]));
  var outH = math.max(dist(pts[0], pts[3]), dist(pts[1], pts[2]));
  final s = math.min(1.0, maxSide / math.max(outW, outH));
  final ow = math.max(1, (outW * s).round()), oh = math.max(1, (outH * s).round());

  // Ánh xạ ngược: điểm đích -> điểm nguồn.
  final hm = computeHomography([
    [0, 0],
    [ow - 1.0, 0],
    [ow - 1.0, oh - 1.0],
    [0, oh - 1.0],
  ], pts);

  final srcBytes = src.getBytes(order: img.ChannelOrder.rgb);
  final out = Uint8List(ow * oh * 3);
  var o = 0;
  for (var y = 0; y < oh; y++) {
    for (var x = 0; x < ow; x++) {
      final z = hm[6] * x + hm[7] * y + hm[8];
      var fx = (hm[0] * x + hm[1] * y + hm[2]) / z;
      var fy = (hm[3] * x + hm[4] * y + hm[5]) / z;
      fx = fx.clamp(0.0, sw - 1.001);
      fy = fy.clamp(0.0, sh - 1.001);
      final x0 = fx.floor(), y0 = fy.floor();
      final ax = fx - x0, ay = fy - y0;
      final i00 = (y0 * sw + x0) * 3;
      final i10 = i00 + 3;
      final i01 = i00 + sw * 3;
      final i11 = i01 + 3;
      for (var c = 0; c < 3; c++) {
        final top = srcBytes[i00 + c] + (srcBytes[i10 + c] - srcBytes[i00 + c]) * ax;
        final bot = srcBytes[i01 + c] + (srcBytes[i11 + c] - srcBytes[i01 + c]) * ax;
        out[o++] = (top + (bot - top) * ay).round();
      }
    }
  }
  return img.Image.fromBytes(width: ow, height: oh, bytes: out.buffer, numChannels: 3);
}

// ---------------------------------------------------------------------------
// Bộ lọc
// ---------------------------------------------------------------------------

/// Ước lượng nền giấy (độ sáng tổng thể) bằng cách làm mờ mạnh ảnh thu nhỏ.
img.Image _background(img.Image src) {
  final small = img.copyResize(src,
      width: math.max(8, src.width ~/ 24),
      height: math.max(8, src.height ~/ 24),
      interpolation: img.Interpolation.average);
  // Phép "đóng" đơn giản: lấy max cục bộ để chữ tối không kéo nền xuống.
  final maxed = small.clone();
  for (var y = 0; y < small.height; y++) {
    for (var x = 0; x < small.width; x++) {
      num r = 0, g = 0, b = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final p = small.getPixelClamped(x + dx, y + dy);
          r = math.max(r, p.r);
          g = math.max(g, p.g);
          b = math.max(b, p.b);
        }
      }
      maxed.setPixelRgb(x, y, r, g, b);
    }
  }
  final blurred = img.gaussianBlur(maxed, radius: 2);
  return img.copyResize(blurred,
      width: src.width, height: src.height, interpolation: img.Interpolation.linear);
}

img.Image applyFilter(img.Image src, ScanFilter filter) {
  if (src.numChannels != 3) src = src.convert(numChannels: 3);
  switch (filter) {
    case ScanFilter.original:
      return src;
    case ScanFilter.lighten:
      return img.adjustColor(src.clone(), brightness: 1.12, contrast: 1.05, gamma: 0.9);
    case ScanFilter.enhanced:
    case ScanFilter.grayscale:
    case ScanFilter.blackWhite:
      break;
  }

  final bg = _background(src);
  final s = src.getBytes(order: img.ChannelOrder.rgb);
  final b = bg.getBytes(order: img.ChannelOrder.rgb);
  final n = src.width * src.height;
  final out = Uint8List(n * 3);

  if (filter == ScanFilter.enhanced) {
    // Chia cho nền -> giấy trắng, giữ màu mực; tăng tương phản nhẹ.
    for (var i = 0; i < n * 3; i++) {
      final v = s[i] / math.max(1, b[i]);
      final c = 255 * math.pow(v.clamp(0.0, 1.0), 1.6);
      out[i] = c.round().clamp(0, 255);
    }
    return img.Image.fromBytes(
        width: src.width, height: src.height, bytes: out.buffer, numChannels: 3);
  }

  final norm = Uint8List(n);
  for (var i = 0; i < n; i++) {
    final l = 0.299 * s[i * 3] + 0.587 * s[i * 3 + 1] + 0.114 * s[i * 3 + 2];
    final lb = 0.299 * b[i * 3] + 0.587 * b[i * 3 + 1] + 0.114 * b[i * 3 + 2];
    norm[i] = (255 * (l / math.max(1, lb)).clamp(0.0, 1.0)).round();
  }
  if (filter == ScanFilter.grayscale) {
    for (var i = 0; i < n; i++) {
      final v = (255 * math.pow(norm[i] / 255, 1.4)).round();
      out[i * 3] = out[i * 3 + 1] = out[i * 3 + 2] = v;
    }
  } else {
    final t = math.min(_otsu(norm) + 10, 225);
    for (var i = 0; i < n; i++) {
      final v = norm[i] > t ? 255 : 0;
      out[i * 3] = out[i * 3 + 1] = out[i * 3 + 2] = v;
    }
  }
  return img.Image.fromBytes(
      width: src.width, height: src.height, bytes: out.buffer, numChannels: 3);
}

// ---------------------------------------------------------------------------
// Pipeline hoàn chỉnh cho một trang
// ---------------------------------------------------------------------------

class ProcessRequest {
  final Uint8List original;
  final Quad quad;
  final ScanFilter filter;
  final int quarterTurns;
  const ProcessRequest(this.original, this.quad, this.filter, this.quarterTurns);
}

/// Cắt + nắn + lọc + xoay, trả về JPEG.
Uint8List processPage(ProcessRequest r) {
  var image = img.decodeImage(r.original);
  if (image == null) throw const FormatException('Không đọc được ảnh');
  image = r.quad.isFull ? image : warpPerspective(image, r.quad);
  image = applyFilter(image, r.filter);
  final turns = r.quarterTurns % 4;
  if (turns != 0) image = img.copyRotate(image, angle: 90 * turns);
  return img.encodeJpg(image, quality: 88);
}

/// Tạo ảnh thu nhỏ để xem trước bộ lọc.
Uint8List makeThumbnail(Uint8List jpg, {int width = 240}) {
  final image = img.decodeImage(jpg)!;
  return img.encodeJpg(img.copyResize(image, width: width), quality: 80);
}

/// Ảnh xem trước nhỏ cho từng bộ lọc (dùng trong thanh chọn bộ lọc).
List<Uint8List> filterPreviews((Uint8List, Quad, int) args) {
  var image = img.decodeImage(args.$1)!;
  image = img.copyResize(image, width: math.min(image.width, 900));
  image = args.$2.isFull
      ? img.copyResize(image, width: math.min(image.width, 240))
      : warpPerspective(image, args.$2, maxSide: 260);
  final turns = args.$3 % 4;
  if (turns != 0) image = img.copyRotate(image, angle: 90 * turns);
  return [
    for (final f in ScanFilter.values) img.encodeJpg(applyFilter(image, f), quality: 75),
  ];
}
