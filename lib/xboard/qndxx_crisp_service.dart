import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'qndxx_config_service.dart';

/// Crisp integration: native Crisp SDK on Android and an app-owned WebView
/// window on Windows/macOS. It never falls back to an external browser.
class QndxxCrispService {
  QndxxCrispService._();

  static final QndxxCrispService instance = QndxxCrispService._();

  Webview? _desktopWindow;

  static const _androidChannel = MethodChannel('qndxx/crisp');

  String get _websiteId => QndxxConfigService.instance.crispWebsiteId;

  Future<void> open() async {
    final websiteId = _websiteId.trim();
    if (websiteId.isEmpty) {
      throw StateError('Crisp Website ID 尚未配置');
    }

    if (Platform.isAndroid) {
      await _androidChannel.invokeMethod<void>('openChat', {
        'websiteId': websiteId,
      });
      return;
    }

    if (Platform.isWindows || Platform.isMacOS) {
      final available = await WebviewWindow.isWebviewAvailable();
      if (!available) {
        throw StateError(
          Platform.isWindows
              ? '未检测到 Microsoft Edge WebView2 Runtime。请安装 WebView2 Runtime 后重试；QNDXX 不会跳转到外部浏览器。'
              : '当前 macOS 环境无法创建内嵌 WebView；QNDXX 不会跳转到外部浏览器。',
        );
      }

      await _desktopWindow?.close();
      final supportDirectory = await getApplicationSupportDirectory();
      final webviewDataDirectory = Directory(
        p.join(supportDirectory.path, 'QNDXX', 'CrispWebView2'),
      );
      if (Platform.isWindows) {
        await webviewDataDirectory.create(recursive: true);
      }
      final window = await WebviewWindow.create(
        configuration: CreateConfiguration(
          title: 'QNDXX 在线客服',
          windowWidth: 440,
          windowHeight: 760,
          windows: WindowsWebviewOptions(
            userDataFolder: Platform.isWindows
                ? p.join(supportDirectory.path, 'QNDXX', 'CrispWebView2')
                : supportDirectory.path,
          ),
        ),
      );
      _desktopWindow = window;
      unawaited(
        window.onClose.then((_) {
          if (identical(_desktopWindow, window)) _desktopWindow = null;
        }),
      );
      try {
        await window.launch(
          'https://go.crisp.chat/chat/embed/?website_id=$websiteId',
        );
      } catch (_) {
        _desktopWindow = null;
        await window.close();
        rethrow;
      }
      return;
    }

    throw UnsupportedError('当前平台暂不支持 QNDXX Crisp 客服');
  }

  Future<void> close() async {
    await _desktopWindow?.close();
    _desktopWindow = null;
  }
}
