import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/xboard/qndxx_config_service.dart';
import 'package:fl_clash/xboard/qndxx_login_dialog.dart';
import 'package:fl_clash/xboard/qndxx_xboard_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prism_ui/theme_data.dart' as prism;

/// Fresh, self-contained implementation of the QNDXX account tab.
/// It deliberately has no nested Scaffold, Navigator, modal host, or tab shell.
class QndxxMyView extends ConsumerStatefulWidget {
  const QndxxMyView({super.key});

  @override
  ConsumerState<QndxxMyView> createState() => _QndxxMyViewState();
}

class _QndxxMyViewState extends ConsumerState<QndxxMyView> {
  final _service = QndxxXboardService.instance;
  bool _loading = true;
  bool _signedIn = false;
  String? _error;
  Map<String, dynamic> _account = const {};
  Map<String, dynamic> _subscription = const {};
  Map<String, dynamic> _invite = const {};
  List<Map<String, dynamic>> _codes = const [];
  List<Map<String, dynamic>> _commissions = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_loading && _signedIn) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await QndxxConfigService.instance
          .initialize(refreshRemote: false)
          .timeout(const Duration(seconds: 10));
      await _service.restoreSession().timeout(const Duration(seconds: 8));
      final account = await _service
          .getAccountInfo()
          .timeout(const Duration(seconds: 15));
      final results = await Future.wait<dynamic>([
        _service.getSubscriptionInfo().timeout(const Duration(seconds: 12)),
        _service.getInviteInfo().timeout(const Duration(seconds: 12)),
        _service.getCommissionDetails().timeout(const Duration(seconds: 12)),
      ]);
      final invite = results[1] as Map<String, dynamic>;
      final rawCodes = invite['codes'];
      if (!mounted) return;
      setState(() {
        _signedIn = true;
        _account = account;
        _subscription = results[0] as Map<String, dynamic>;
        _invite = invite;
        _codes = rawCodes is List
            ? rawCodes.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : const [];
        _commissions = results[2] as List<Map<String, dynamic>>;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _signedIn = false;
        _error = error.toString();
        _account = const {};
        _subscription = const {};
        _invite = const {};
        _codes = const [];
        _commissions = const [];
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _text(dynamic value, [String fallback = '—']) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _date(dynamic value) {
    if (value == null || value.toString().isEmpty) return '不限时';
    final n = int.tryParse(value.toString());
    final date = n == null
        ? DateTime.tryParse(value.toString())
        : DateTime.fromMillisecondsSinceEpoch(n > 9999999999 ? n : n * 1000);
    if (date == null) return value.toString();
    final d = date.toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _money(dynamic cents) {
    final value = num.tryParse(cents?.toString() ?? '');
    return value == null ? '—' : '¥${(value / 100).toStringAsFixed(2)}';
  }

  String _traffic(dynamic bytes) {
    final value = num.tryParse(bytes?.toString() ?? '');
    if (value == null) return '—';
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _inviteUrl(String code) => 'https://toufq.com/?code=${Uri.encodeComponent(code)}';

  Future<void> _login() async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const QndxxLoginDialog(),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后会清除本设备保存的登录凭据，不会删除本地订阅配置。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('退出')),
        ],
      ),
    );
    if (ok != true) return;
    await _service.logout();
    if (!mounted) return;
    setState(() {
      _signedIn = false;
      _account = const {};
      _subscription = const {};
      _invite = const {};
      _codes = const [];
      _commissions = const [];
    });
  }

  Future<void> _makeInvite() async {
    try {
      await _service.generateInviteCode();
      if (mounted) await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Widget _section(String title, IconData icon, List<Widget> children) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(icon, color: colors.primary),
              const SizedBox(width: 9),
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _value(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(children: [
      Expanded(child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
      const SizedBox(width: 12),
      Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeSettingProvider.select((s) => s.themeMode));
    final plan = _subscription['plan'];
    final planName = plan is Map ? plan['name'] : _subscription['plan_name'];
    final stat = _invite['stat'];
    final invited = stat is List && stat.isNotEmpty ? stat[0].toString() : '0';
    final commission = stat is List && stat.length > 1 ? _money(stat[1]) : '¥0.00';
    final available = stat is List && stat.length > 4 ? _money(stat[4]) : '¥0.00';

    return ColoredBox(
      color: colors.surface,
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  const Expanded(child: Text('我的', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
                  IconButton(tooltip: '刷新', onPressed: _loading ? null : _refresh, icon: const Icon(Icons.refresh_rounded)),
                ]),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              key: const PageStorageKey<String>('qndxx-my-page-v2'),
              padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
              children: [
                if (_loading) const LinearProgressIndicator(),
                if (_error != null) Card(
                  color: colors.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!, style: TextStyle(color: colors.onErrorContainer)),
                  ),
                ),
                if (!_signedIn) ...[
                  const SizedBox(height: 28),
                  Icon(Icons.account_circle_outlined, size: 64, color: colors.primary),
                  const SizedBox(height: 12),
                  const Center(child: Text('登录 QNDXX 账号，管理套餐与账户服务')),
                  const SizedBox(height: 18),
                  FilledButton.icon(onPressed: _loading ? null : _login, icon: const Icon(Icons.login), label: const Text('登录账号')),
                ] else ...[
                  _section('账户信息', Icons.person_outline_rounded, [
                    _value('登录账号', _text(_account['email'] ?? _account['username'])),
                    _value('当前套餐', _text(planName, '暂未订阅')),
                    _value('到期时间', _date(_subscription['expired_at'] ?? _subscription['expired_at_timestamp'])),
                    _value('流量总额', _traffic(_subscription['transfer_enable'])),
                    _value('设备限制', _text(_subscription['device_limit'])),
                  ]),
                  _section('邀请与返利', Icons.card_giftcard_rounded, [
                    _value('已邀请人数', invited),
                    _value('累计佣金', commission),
                    _value('可用佣金', available),
                    Align(alignment: Alignment.centerLeft, child: FilledButton.tonalIcon(onPressed: _loading ? null : _makeInvite, icon: const Icon(Icons.add_link), label: const Text('生成邀请码'))),
                    for (final code in _codes) ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_text(code['code'], '邀请码')),
                      subtitle: Text('访问次数：${_text(code['pv'], '0')} · ${code['status'] == true ? '有效' : '停用'}'),
                      trailing: IconButton(tooltip: '复制邀请链接', icon: const Icon(Icons.copy), onPressed: () => Clipboard.setData(ClipboardData(text: _inviteUrl(_text(code['code'], ''))))),
                    ),
                    if (_codes.isEmpty) const Text('暂无邀请码'),
                    const Divider(),
                    for (final item in _commissions.take(10))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('订单：${_text(item['trade_no'])}'),
                        subtitle: Text('佣金：${_money(item['get_amount'])} · ${_date(item['created_at'])}'),
                      ),
                  ]),
                  _section('网站钱包', Icons.account_balance_wallet_outlined, [
                    _value('钱包余额', _money(_account['balance'])),
                    const Text('佣金划转功能将在新页面完成验证后接入，避免旧页面逻辑继续影响稳定性。'),
                  ]),
                  _section('外观设置', Icons.palette_outlined, [
                    SegmentedButton<prism.ThemeMode>(
                      segments: const [
                        ButtonSegment(value: prism.ThemeMode.system, label: Text('跟随系统'), icon: Icon(Icons.brightness_auto)),
                        ButtonSegment(value: prism.ThemeMode.light, label: Text('浅色'), icon: Icon(Icons.light_mode)),
                        ButtonSegment(value: prism.ThemeMode.dark, label: Text('深色'), icon: Icon(Icons.dark_mode)),
                      ],
                      selected: {themeMode},
                      onSelectionChanged: (v) => ref.read(themeSettingProvider.notifier).value = ref.read(themeSettingProvider).copyWith(themeMode: v.first),
                    ),
                  ]),
                  _section('账户操作', Icons.settings_outlined, [
                    OutlinedButton.icon(onPressed: _loading ? null : _refresh, icon: const Icon(Icons.refresh), label: const Text('刷新账户数据')),
                    const SizedBox(height: 8),
                    FilledButton.icon(onPressed: _logout, icon: const Icon(Icons.logout), label: const Text('退出登录')),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
