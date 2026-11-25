import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'qndxx_xboard_service.dart';

class QndxxLoginDialog extends ConsumerStatefulWidget {
  const QndxxLoginDialog({super.key});

  @override
  ConsumerState<QndxxLoginDialog> createState() => _QndxxLoginDialogState();
}

class _QndxxLoginDialogState extends ConsumerState<QndxxLoginDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loginAndImport() async {
    if (_busy) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      await dialogs.showAlert(
        title: 'QNDXX XBoard',
        message: const TextSpan(text: '请输入邮箱和密码'),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final service = QndxxXboardService.instance;
      final account = await service.login(email: email, password: password);
      final subscription = await service.downloadSubscription();
      final action = ref.read(profilesActionProvider.notifier);

      final profile = await Profile.normal(label: 'QNDXX').saveFile(
        subscription.bytes,
        validate: (path, ageSecretKey) async {
          final file = File(path);
          return action.validateConfigWithData(await file.readAsBytes());
        },
      );

      action.putProfile(
        profile.copyWith(
          subscriptionInfo: subscription.userInfo == null
              ? null
              : SubscriptionInfo.formHString(subscription.userInfo),
        ),
      );
      await service.bindProfile(profile.id);

      if (!mounted) return;
      dialogs.showBanner('QNDXX 登录成功：${account.email}，订阅已导入', level: BannerLevel.success);
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      await dialogs.showAlert(
        title: 'QNDXX 登录或订阅失败',
        message: TextSpan(text: error.toString()),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: 'QNDXX XBoard 登录',
      hasFields: true,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _loginAndImport,
          child: _busy
              ? const Text('登录中…')
              : const Text('登录并导入订阅'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          const Text('自动选择响应最快的 QNDXX 面板，并导入账号订阅。'),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username],
            decoration: const InputDecoration(labelText: '邮箱'),
          ),
          TextFormField(
            controller: _passwordController,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: const InputDecoration(labelText: '密码'),
            onFieldSubmitted: (_) => _loginAndImport(),
          ),
        ],
      ),
    );
  }
}
