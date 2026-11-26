import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show CircularProgressIndicator;
import 'package:in_app_webview_flutter/flutter_inappwebview.dart';

import 'qndxx_config_service.dart';

/// Crisp is rendered inside the current QNDXX page on Android, Windows and
/// macOS. It must not create a second native window or launch an external app.
class QndxxSupportView extends StatefulWidget {
  const QndxxSupportView({super.key});

  @override
  State<QndxxSupportView> createState() => _QndxxSupportViewState();
}

class _QndxxSupportViewState extends State<QndxxSupportView> {
  InAppWebViewController? _controller;
  bool _loading = true;
  String? _error;

  String get _crispUrl {
    final websiteId = QndxxConfigService.instance.crispWebsiteId.trim();
    return 'https://go.crisp.chat/chat/embed/?website_id=${Uri.encodeComponent(websiteId)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      title: '在线客服',
      body: Padding(
        // Keep the embedded page above the floating Android glass dock and
        // the system gesture area instead of painting behind navigation.
        padding: EdgeInsets.only(bottom: context.bottomInset),
        child: Stack(
          fit: StackFit.expand,
          children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(_crispUrl)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              domStorageEnabled: true,
              thirdPartyCookiesEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              supportZoom: false,
            ),
            onWebViewCreated: (controller) {
              _controller = controller;
            },
            onLoadStart: (controller, url) {
              if (!mounted) return;
              setState(() {
                _loading = true;
                _error = null;
              });
            },
            onLoadStop: (controller, url) {
              if (!mounted) return;
              setState(() => _loading = false);
            },
            onReceivedError: (controller, request, error) {
              if (!mounted || request.isForMainFrame != true) return;
              setState(() {
                _loading = false;
                _error = error.description;
              });
            },
          ),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            ColoredBox(
              color: const Color(0xFFF5F5F5),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            _loading = true;
                            _error = null;
                          });
                          _controller?.reload();
                        },
                        child: const Text('重新加载客服'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
