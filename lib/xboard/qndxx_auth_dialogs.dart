import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/widgets/widgets.dart' hide PopupMenuItem;
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart'
    show Icon, Icons, MenuAnchor, MenuItemButton, OutlinedButton;

import 'qndxx_xboard_service.dart';

class QndxxRegisterDialog extends StatefulWidget {
  const QndxxRegisterDialog({super.key});

  @override
  State<QndxxRegisterDialog> createState() => _QndxxRegisterDialogState();
}

class _QndxxRegisterDialogState extends State<QndxxRegisterDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _invite = TextEditingController();
  bool _busy = false;
  String _emailDomain = 'qq.com';
  static const _emailDomains = [
    'qq.com',
    '163.com',
    '126.com',
    'yeah.net',
    'gmail.com',
    'yahoo.com',
    'sina.com',
    'outlook.com',
    'foxmail.com',
    'mail.ru',
    'bk.ru',
    'gzpuye.com',
    'ne01-e.com',
  ];

  String get _fullEmail {
    // The suffix picker is authoritative. The text field only accepts the
    // mailbox prefix, so the exact selected domain is always sent to XBoard.
    final localPart = _email.text.trim().split('@').first.trim();
    return '$localPart@$_emailDomain';
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    _invite.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_busy) return;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_fullEmail)) {
      await dialogs.showAlert(
        title: '邮箱格式错误',
        message: const TextSpan(text: '请填写有效邮箱地址，并确认所选邮箱后缀。'),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final sent = await QndxxXboardService.instance.sendEmailVerifyCode(
        _fullEmail,
      );
      dialogs.showBanner(
        sent ? '验证码已发送' : '面板未能发送验证码',
        level: sent ? BannerLevel.success : BannerLevel.warning,
      );
    } catch (error) {
      await dialogs.showAlert(
        title: '发送验证码失败',
        message: TextSpan(text: error.toString()),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _register() async {
    if (_busy) return;
    final email = _fullEmail;
    final password = _password.text;
    final code = _code.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) ||
        password.isEmpty ||
        code.isEmpty) {
      await dialogs.showAlert(
        title: '注册账号',
        message: const TextSpan(text: '请填写有效邮箱、密码和邮箱验证码'),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final success = await QndxxXboardService.instance.register(
        email: email,
        password: password,
        emailCode: code,
        inviteCode: _invite.text.trim().isEmpty ? null : _invite.text.trim(),
      );
      if (!mounted) return;
      if (success) {
        dialogs.showBanner('注册成功，请返回登录', level: BannerLevel.success);
        Navigator.of(context).pop();
      } else {
        await dialogs.showAlert(
          title: '注册失败',
          message: const TextSpan(text: '面板未确认注册成功，请检查信息后重试'),
        );
      }
    } catch (error) {
      if (!mounted) return;
      await dialogs.showAlert(
        title: '注册失败',
        message: TextSpan(text: error.toString()),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: '注册账号',
      hasFields: true,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _register,
          child: Text(_busy ? '处理中…' : '注册'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          Row(
            children: [
              Icon(
                Icons.person_add_alt_1_rounded,
                color: context.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Text('注册账号', style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: '邮箱前缀',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
              ),
              SizedBox(
                // Use MenuAnchor rather than DropdownButton: the suffix menu
                // is presented in an overlay and remains selectable inside
                // the custom auth dialog on Windows and Android.
                width: 156,
                child: MenuAnchor(
                  menuChildren: [
                    for (final domain in _emailDomains)
                      MenuItemButton(
                        leadingIcon: const Icon(
                          Icons.alternate_email_rounded,
                          size: 18,
                        ),
                        onPressed: _busy
                            ? null
                            : () => setState(() => _emailDomain = domain),
                        child: Text('@$domain'),
                      ),
                  ],
                  builder: (context, controller, child) {
                    return OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => controller.isOpen
                              ? controller.close()
                              : controller.open(),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '@$_emailDomain',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.left,
                            ),
                          ),
                          const Icon(Icons.arrow_drop_down_rounded),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '注册邮箱：$_fullEmail',
              style: TextStyle(
                fontSize: 12,
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextFormField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: '设置密码',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
          ),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _code,
                  decoration: const InputDecoration(
                    hintText: '邮箱验证码（必填）',
                    prefixIcon: Icon(Icons.mark_email_unread_outlined),
                  ),
                ),
              ),
              TextButton(
                onPressed: _busy ? null : _sendCode,
                child: const Text('发送验证码'),
              ),
            ],
          ),
          TextFormField(
            controller: _invite,
            decoration: const InputDecoration(
              hintText: '邀请码（选填）',
              prefixIcon: Icon(Icons.confirmation_number_outlined),
            ),
          ),
        ],
      ),
    );
  }
}

class QndxxForgotPasswordDialog extends StatefulWidget {
  const QndxxForgotPasswordDialog({super.key});

  @override
  State<QndxxForgotPasswordDialog> createState() =>
      _QndxxForgotPasswordDialogState();
}

class _QndxxForgotPasswordDialogState extends State<QndxxForgotPasswordDialog> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_email.text.trim().isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final sent = await QndxxXboardService.instance.sendEmailVerifyCode(
        _email.text.trim(),
      );
      dialogs.showBanner(
        sent ? '验证码已发送' : '面板未能发送验证码',
        level: sent ? BannerLevel.success : BannerLevel.warning,
      );
    } catch (error) {
      await dialogs.showAlert(
        title: '发送验证码失败',
        message: TextSpan(text: error.toString()),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    if (_email.text.trim().isEmpty ||
        _code.text.trim().isEmpty ||
        _password.text.isEmpty) {
      await dialogs.showAlert(
        title: '重置密码',
        message: const TextSpan(text: '请填写邮箱、验证码和新密码'),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final success = await QndxxXboardService.instance.forgotPassword(
        _email.text.trim(),
        _code.text.trim(),
        _password.text,
      );
      if (!mounted) return;
      if (success) {
        dialogs.showBanner('密码已重置，请使用新密码登录', level: BannerLevel.success);
        Navigator.of(context).pop();
      } else {
        await dialogs.showAlert(
          title: '重置失败',
          message: const TextSpan(text: '面板未确认密码重置成功'),
        );
      }
    } catch (error) {
      if (!mounted) return;
      await dialogs.showAlert(
        title: '重置密码失败',
        message: TextSpan(text: error.toString()),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: '找回密码',
      hasFields: true,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _reset,
          child: Text(_busy ? '处理中…' : '重置密码'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          Row(
            children: [
              Icon(
                Icons.lock_reset_rounded,
                color: context.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              const Text('找回密码', style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              hintText: '注册邮箱',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _code,
                  decoration: const InputDecoration(
                    hintText: '邮箱验证码',
                    prefixIcon: Icon(Icons.mark_email_unread_outlined),
                  ),
                ),
              ),
              TextButton(
                onPressed: _busy ? null : _sendCode,
                child: const Text('发送验证码'),
              ),
            ],
          ),
          TextFormField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: '新密码',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
          ),
        ],
      ),
    );
  }
}
