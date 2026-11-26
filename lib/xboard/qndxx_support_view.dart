import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';

import 'qndxx_crisp_service.dart';

class QndxxSupportView extends StatelessWidget {
  const QndxxSupportView({super.key});

  Future<void> _openCrisp() async {
    try {
      await QndxxCrispService.instance.open();
    } catch (error) {
      await dialogs.showAlert(
        title: '在线客服暂不可用',
        message: TextSpan(text: error.toString()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      title: 'QNDXX 客服中心',
      body: ListView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: context.contentTopPadding,
          bottom: 24 + context.bottomInset,
        ),
        children: [
          const Text('遇到连接、订阅或账户问题？通过 Crisp 联系在线客服。'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _openCrisp,
            child: const Text('联系在线客服'),
          ),
          const SizedBox(height: 12),
          const Text('客服窗口将在应用内打开。若当前平台缺少所需 WebView 运行环境，页面会提示具体原因。'),
        ],
      ),
    );
  }
}
