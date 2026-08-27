import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R3.1 continues through OAuth after the gated-model license step', () {
    final home = File('lib/ui/home_page.dart').readAsStringSync();
    final setup = File('lib/services/model_setup_service.dart').readAsStringSync();

    expect(setup, contains('continueAfterLicense'));
    expect(home, contains('setup.continueAfterLicense'));
    expect(home, contains('已完成许可，继续官方授权并下载'));
  });

  test('R3.1 reports textless PDFs instead of silently accepting zero chunks', () {
    final home = File('lib/ui/home_page.dart').readAsStringSync();

    expect(home, contains('0 chunks · 未提取到可检索文本'));
    expect(home, contains('可能是扫描件/图片型 PDF'));
  });

  test('R3.1 retrieval status distinguishes authorization from active preparation', () {
    final home = File('lib/ui/home_page.dart').readAsStringSync();

    expect(home, isNot(contains('检索完成 · 模型仍在自动准备')));
    expect(home, contains('检索完成 · Embedding 尚未就绪（FTS5 可用）'));
  });

  test('R3.1+ stays on the stable R3 Android identity and advances app version', () {
    final bootstrap = File('scripts/bootstrap_android.sh').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(bootstrap, contains('com.qujindai.pocketgallery_phone_pilot.r3'));
    expect(
      pubspec,
      contains(RegExp(
        r'version: 0\.(3\.[1-9][0-9]*|[4-9]\.[0-9]+)\+(?:[4-9]|[1-9][0-9]+)',
      )),
    );
  });
}
