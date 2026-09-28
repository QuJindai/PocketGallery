import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('knowledge page exposes required library management actions', () async {
    final source = await File('lib/ui/knowledge_page.dart').readAsString();
    expect(source, contains('导入 TXT / MD / PDF'));
    expect(source, contains('重建 Embedding'));
    expect(source, contains('删除文档'));
    expect(source, contains('0 chunks'));
    expect(source, contains('扫描件/图片型 PDF'));
    expect(source, contains('FTS5 READY'));
  });
}
