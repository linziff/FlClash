import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show Icon, IconButton, Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'qndxx_auth_dialogs.dart';
import 'qndxx_branding.dart';
import 'qndxx_remote_status_service.dart';
import 'qndxx_subscription_decryptor.dart';
import 'qndxx_xboard_service.dart';

class QndxxLoginDialog extends ConsumerStatefulWidget {
  const QndxxLoginDialog({super.key, this.mandatory = false});

  final bool mandatory;

  @override
  ConsumerState<QndxxLoginDialog> createState() => _QndxxLoginDialogState();
}

class _QndxxLoginDialogState extends ConsumerState<QndxxLoginDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  bool _authenticated = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<Uint8List> _normalizeSubscription(List<int> bytes) async {
    final content = utf8.decode(bytes, allowMalformed: false).trim();
    if (QndxxSubscriptionDecryptor.looksLikeClash(content)) {
      return Uint8List.fromList(bytes);
    }
    if (!QndxxSubscriptionDecryptor.looksLikeShareLinks(content)) {
      throw const FormatException('订阅内容不是有效的 Mihomo 配置或节点分享链接');
    }

    final lines = content
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toList(growable: false);
    final decoded = await ref.read(coreHandlerProvider).decodeShareLinks(lines);
    final proxiesByName = <String, Map<String, dynamic>>{};
    for (final proxy in decoded.expand((items) => items)) {
      final name = proxy['name']?.toString().trim() ?? '';
      if (name.isNotEmpty) proxiesByName.putIfAbsent(name, () => proxy);
    }
    if (proxiesByName.isEmpty) {
      throw const FormatException('节点分享链接无法解析，请检查订阅协议格式');
    }

    const groupName = 'QNDXX 节点选择';
    final profile = <String, dynamic>{
      'mode': 'rule',
      'proxies': proxiesByName.values.toList(growable: false),
      'proxy-groups': [
        {
          'name': groupName,
          'type': 'select',
          'proxies': ['DIRECT', ...proxiesByName.keys],
        },
      ],
      'rules': ['MATCH,$groupName'],
    };
    // JSON is a valid YAML 1.2 document and avoids lossy hand-written YAML
    // escaping for passwords, IPv6 addresses, and transport options.
    return Uint8List.fromList(utf8.encode(jsonEncode(profile)));
  }

  Future<void> _loginAndImport() async {
    if (_busy) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      await dialogs.showAlert(
        title: '登录失败',
        message: const TextSpan(text: '请输入邮箱和密码'),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final service = QndxxXboardService.instance;
      final account = await service.login(email: email, password: password);
      // Remote status is independent of subscription import; start it
      // without making the user wait for its network handshake.
      unawaited(
        QndxxRemoteStatusService.instance.startIfEnabled().catchError((_) {}),
      );
      final subscription = await service.downloadSubscription();
      final action = ref.read(profilesActionProvider.notifier);
      final boundId = await service.boundProfileId;
      final existingProfile = boundId == null
          ? null
          : ref.read(profilesProvider).getProfile(boundId);

      final normalizedSubscription = await _normalizeSubscription(
        subscription.bytes,
      );
      final profile = await (existingProfile ?? Profile.normal(label: '青年大学习'))
          .saveFile(
            normalizedSubscription,
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
      dialogs.showBanner(
        'QNDXX 登录成功：${account.email}，订阅已导入',
        level: BannerLevel.success,
      );
      setState(() => _authenticated = true);
      if (widget.mandatory) await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      await dialogs.showAlert(
        title: '登录或订阅失败',
        message: TextSpan(text: error.toString()),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The first-launch login is mandatory: prevent system back, swipe-back,
    // and route-pop actions from dismissing it before authentication.
    return PopScope<void>(
      canPop: !widget.mandatory || _authenticated,
      child: Scaffold(
        hideLeading: widget.mandatory,
        title: '登录账号',
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                children: [
                  const Center(child: QndxxBrandLogo(size: 84)),
                  const SizedBox(height: 20),
                  Text(
                    '欢迎使用青年大学习',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: context.colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '登录账号后即可同步订阅并管理你的服务。',
                    style: TextStyle(
                      fontSize: 14,
                      color: context.colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(
                      hintText: '邮箱',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      hintText: '密码',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    onFieldSubmitted: (_) => _loginAndImport(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => unawaited(
                                dialogs.showCommonDialog<void>(
                                  child: const QndxxForgotPasswordDialog(),
                                ),
                              ),
                        icon: const Icon(Icons.lock_reset_rounded, size: 17),
                        label: const Text('忘记密码'),
                      ),
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => unawaited(
                                dialogs.showCommonDialog<void>(
                                  child: const QndxxRegisterDialog(),
                                ),
                              ),
                        icon: const Icon(
                          Icons.person_add_alt_1_rounded,
                          size: 17,
                        ),
                        label: const Text('注册账号'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _busy ? null : _loginAndImport,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _busy
                          ? const Text('登录中…')
                          : const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.login_rounded, size: 18),
                                SizedBox(width: 8),
                                Text('登录并导入订阅'),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
