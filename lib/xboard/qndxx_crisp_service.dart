import 'dart:io';

import 'package:crisp_chat/crisp_chat.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';

import 'qndxx_config_service.dart';

/// Crisp integration: native Crisp SDK on Android and an app-owned WebView
/// window on Windows/macOS. It never falls back to an external browser.
class QndxxCrispService {
  QndxxCrispService._();

  static final QndxxCrispService instance = QndxxCrispService._();

  Webview? _desktopWindow;

  String get _websiteId => QndxxConfigService.instance.crispWebsiteId;

  Future<void> open() async {
    final websiteId = _websiteId.trim();
    if (websiteId.isEmpty) {
      throw StateError('Crisp Website ID 尚未配置');
    }

    if (Platform.isAndroid) {
      await FlutterCrispChat.openCrispChat(
        config: CrispConfig(
          websiteID: websiteId,
          sessionSegment: 'qndxx_app',
          enableNotifications: false,
        ),
      );
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
      final window = await WebviewWindow.create(
        configuration: const CreateConfiguration(
          title: 'QNDXX 在线客服',
          windowWidth: 440,
          windowHeight: 760,
        ),
      );
      _desktopWindow = window;
      await window.launch(
        'https://go.crisp.chat/chat/embed/?website_id=$websiteId',
      );
      return;
    }

    throw UnsupportedError('当前平台暂不支持 QNDXX Crisp 客服');
  }

  Future<void> close() async {
    await _desktopWindow?.close();
    _desktopWindow = null;
  }
}
