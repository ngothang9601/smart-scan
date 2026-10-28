import '../services/image_processing.dart';

/// Một dòng chữ OCR, toạ độ chuẩn hoá (0..1) theo ảnh đã xử lý.
class OcrLine {
  final String text;
  final double left, top, right, bottom;
  const OcrLine(this.text, this.left, this.top, this.right, this.bottom);

  List<dynamic> toJson() => [text, left, top, right, bottom];

  factory OcrLine.fromJson(List<dynamic> j) => OcrLine(
        j[0] as String,
        (j[1] as num).toDouble(),
        (j[2] as num).toDouble(),
        (j[3] as num).toDouble(),
        (j[4] as num).toDouble(),
      );
}

/// Một trang đã quét. Đường dẫn ảnh lưu dạng tên tệp tương đối trong thư mục
/// của tài liệu, vì thư mục ứng dụng trên iOS có thể đổi sau mỗi lần cập nhật.
class ScanPage {
  final String id;
  final String originalFile;
  final String processedFile;
  final Quad quad;
  final ScanFilter filter;
  final int quarterTurns;
  final String? ocrText;
  final List<OcrLine> ocrLines;

  const ScanPage({
    required this.id,
    required this.originalFile,
    required this.processedFile,
    required this.quad,
    this.filter = ScanFilter.enhanced,
    this.quarterTurns = 0,
    this.ocrText,
    this.ocrLines = const [],
  });

  ScanPage copyWith({
    String? processedFile,
    Quad? quad,
    ScanFilter? filter,
    int? quarterTurns,
    String? ocrText,
    List<OcrLine>? ocrLines,
    bool clearOcr = false,
  }) =>
      ScanPage(
        id: id,
        originalFile: originalFile,
        processedFile: processedFile ?? this.processedFile,
        quad: quad ?? this.quad,
        filter: filter ?? this.filter,
        quarterTurns: quarterTurns ?? this.quarterTurns,
        ocrText: clearOcr ? null : (ocrText ?? this.ocrText),
        ocrLines: clearOcr ? const [] : (ocrLines ?? this.ocrLines),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'original': originalFile,
        'processed': processedFile,
        'quad': quad.toList(),
        'filter': filter.name,
        'turns': quarterTurns,
        if (ocrText != null) 'ocr': ocrText,
        if (ocrLines.isNotEmpty) 'ocrLines': ocrLines.map((l) => l.toJson()).toList(),
      };

  factory ScanPage.fromJson(Map<String, dynamic> j) => ScanPage(
        id: j['id'] as String,
        originalFile: j['original'] as String,
        processedFile: j['processed'] as String,
        quad: Quad.fromList(j['quad'] as List),
        filter: ScanFilter.values.firstWhere((f) => f.name == j['filter'],
            orElse: () => ScanFilter.enhanced),
        quarterTurns: (j['turns'] as num?)?.toInt() ?? 0,
        ocrText: j['ocr'] as String?,
        ocrLines: (j['ocrLines'] as List? ?? const [])
            .map((l) => OcrLine.fromJson(l as List))
            .toList(),
      );
}

class ScanDocument {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ScanPage> pages;

  const ScanDocument({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.pages,
  });

  ScanDocument copyWith({String? name, List<ScanPage>? pages}) => ScanDocument(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        pages: pages ?? this.pages,
      );

  /// Văn bản OCR của tất cả các trang (nếu đã nhận dạng).
  String get fullText => pages
      .map((p) => p.ocrText)
      .whereType<String>()
      .where((t) => t.trim().isNotEmpty)
      .join('\n\n');

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'created': createdAt.toIso8601String(),
        'updated': updatedAt.toIso8601String(),
        'pages': pages.map((p) => p.toJson()).toList(),
      };

  factory ScanDocument.fromJson(Map<String, dynamic> j) => ScanDocument(
        id: j['id'] as String,
        name: j['name'] as String,
        createdAt: DateTime.parse(j['created'] as String),
        updatedAt: DateTime.parse(j['updated'] as String),
        pages: (j['pages'] as List)
            .map((p) => ScanPage.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}

extension ScanFilterLabel on ScanFilter {
  String get label => switch (this) {
        ScanFilter.original => 'Gốc',
        ScanFilter.enhanced => 'Tăng cường',
        ScanFilter.lighten => 'Làm sáng',
        ScanFilter.grayscale => 'Xám',
        ScanFilter.blackWhite => 'Đen trắng',
      };
}

extension PageLayoutLabel on PageLayout {
  String get label => switch (this) {
        PageLayout.idCard => 'CCCD / thẻ 2 mặt',
        PageLayout.two => '2 ảnh một trang',
        PageLayout.four => '4 ảnh một trang',
        PageLayout.six => '6 ảnh một trang',
      };

  String get hint => switch (this) {
        PageLayout.idCard => 'Mặt trước và mặt sau, in đúng cỡ thẻ thật trên A4',
        PageLayout.two => 'Hai ảnh xếp trên dưới',
        PageLayout.four => 'Lưới 2 × 2',
        PageLayout.six => 'Lưới 2 × 3',
      };

  int get slots => switch (this) {
        PageLayout.idCard || PageLayout.two => 2,
        PageLayout.four => 4,
        PageLayout.six => 6,
      };
}
