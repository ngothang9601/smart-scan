import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_scan/main.dart';
import 'package:smart_scan/services/document_store.dart';

void main() {
  testWidgets('màn hình thư viện trống hiển thị nút Quét', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('scan_ui');
    final store = DocumentStore(root: tmp);
    await tester.runAsync(store.load);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: store, child: const SmartScanApp()));
    await tester.pumpAndSettle();
    expect(find.text('Chưa có tài liệu nào'), findsOneWidget);
    expect(find.text('Quét'), findsOneWidget);
    tmp.deleteSync(recursive: true);
  });
}
