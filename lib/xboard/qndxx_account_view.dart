import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'qndxx_config_service.dart';
import 'qndxx_crisp_service.dart';
import 'qndxx_login_dialog.dart';
import 'qndxx_xboard_service.dart';

class QndxxAccountView extends ConsumerStatefulWidget {
  const QndxxAccountView({super.key});

  @override
  ConsumerState<QndxxAccountView> createState() => _QndxxAccountViewState();
}

class _QndxxAccountViewState extends ConsumerState<QndxxAccountView> {
  final _service = QndxxXboardService.instance;
  bool _loading = false;
  bool _signedIn = false;
  Map<String, dynamic> _account = const {};
  Map<String, dynamic> _subscription = const {};
  Map<String, dynamic> _invite = const {};
  List<Map<String, dynamic>> _inviteCodes = const [];
  List<Map<String, dynamic>> _commissions = const [];
  List<Map<String, dynamic>> _plans = const [];
  List<Map<String, dynamic>> _orders = const [];
  List<Map<String, dynamic>> _notices = const [];
  List<Map<String, dynamic>> _tickets = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await QndxxConfigService.instance.initialize(refreshRemote: true);
      await _service.restoreSession();
      final account = await _service.getAccountInfo();
      final subscription = await _service.getSubscriptionInfo().catchError(
        (_) => <String, dynamic>{},
      );
      final plans = await _service.getPlans().catchError(
        (_) => <Map<String, dynamic>>[],
      );
      final orders = await _service.getOrders().catchError(
        (_) => <Map<String, dynamic>>[],
      );
      final notices = await _service.getNotices().catchError(
        (_) => <Map<String, dynamic>>[],
      );
      final invite = await _service.getInviteInfo().catchError(
        (_) => <String, dynamic>{},
      );
      final inviteCodes = await _service.getInviteCodes().catchError(
        (_) => <Map<String, dynamic>>[],
      );
      final commissions = await _service.getCommissionDetails().catchError(
        (_) => <Map<String, dynamic>>[],
      );
      final tickets = await _service.getTickets().catchError(
        (_) => <Map<String, dynamic>>[],
      );
      if (!mounted) return;
      setState(() {
        _signedIn = true;
        _account = account;
        _subscription = subscription;
        _plans = plans;
        _orders = orders;
        _notices = notices;
        _invite = invite;
        _inviteCodes = inviteCodes;
        _commissions = commissions;
        _tickets = tickets;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _signedIn = false;
        _error = error.toString();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _value(dynamic value, [String fallback = '—']) {
    if (value == null || value.toString().trim().isEmpty) return fallback;
    return value.toString();
  }

  Future<void> _login() async {
    await dialogs.showCommonDialog<void>(child: const QndxxLoginDialog());
    await _load();
  }

  Future<void> _logout() async {
    final accepted = await dialogs.showMessage(
      title: '退出 QNDXX 账号',
      message: const TextSpan(text: '退出后会清除本设备保存的登录凭据，不会删除本地订阅配置。'),
      confirmText: '退出登录',
      destructive: true,
    );
    if (accepted != true) return;
    await _service.logout();
    if (!mounted) return;
    setState(() {
      _signedIn = false;
      _account = const {};
      _subscription = const {};
    });
  }

  Future<void> _openSupport() async {
    try {
      await QndxxCrispService.instance.open();
    } catch (error) {
      await dialogs.showAlert(
        title: '在线客服暂不可用',
        message: TextSpan(text: error.toString()),
      );
    }
  }

  Future<void> _purchasePlan(Map<String, dynamic> plan) async {
    final period = await dialogs.showCommonDialog<String>(
      child: _PlanPeriodDialog(plan: plan),
    );
    if (period == null) return;
    try {
      final planId = int.tryParse('${plan['id']}');
      if (planId == null) throw const FormatException('套餐 ID 无效');
      final tradeNo = await _service.createOrder(planId, period);
      final methods = await _service.getPaymentMethods(tradeNo);
      if (methods.isEmpty) {
        await dialogs.showAlert(
          title: '订单已创建',
          message: TextSpan(text: '订单号：$tradeNo\n面板暂未提供可用支付方式。'),
        );
        await _load();
        return;
      }
      final method = await dialogs.showCommonDialog<String>(
        child: _PaymentMethodDialog(methods: methods),
      );
      if (method == null) return;
      final result = await _service.checkoutOrder(tradeNo, method);
      final url = result['url']?.toString() ??
          (result['data'] is Map
              ? (result['data'] as Map)['url']?.toString()
              : null);
      if (url != null && url.isNotEmpty) {
        await dialogs.openUrl(url);
      } else {
        await dialogs.showAlert(
          title: '支付结果',
          message: TextSpan(text: result.toString()),
        );
      }
      await _load();
    } catch (error) {
      await dialogs.showAlert(
        title: '创建订单失败',
        message: TextSpan(text: error.toString()),
      );
    }
  }

  Future<void> _createTicket() async {
    final ticket = await dialogs.showCommonDialog<Map<String, Object?>>(
      child: const _CreateTicketDialog(),
    );
    if (ticket == null) return;
    try {
      await _service.createTicket(
        ticket['subject']! as String,
        ticket['message']! as String,
        ticket['level']! as int,
      );
      dialogs.showBanner('工单已提交', level: BannerLevel.success);
      await _load();
    } catch (error) {
      await dialogs.showAlert(
        title: '提交工单失败',
        message: TextSpan(text: error.toString()),
      );
    }
  }

  Future<void> _showTicket(Map<String, dynamic> ticket) async {
    final id = int.tryParse('${ticket['id']}');
    if (id == null) return;
    try {
      final detail = await _service.getTicket(id);
      final messages = detail['messages'] is List
          ? (detail['messages'] as List).map((e) => e.toString()).join('\n\n')
          : '';
      await dialogs.showAlert(
        title: _value(detail['subject'], '工单详情'),
        message: TextSpan(
          text: '${_value(detail['status'])}\n\n$messages',
        ),
      );
    } catch (error) {
      await dialogs.showAlert(
        title: '读取工单失败',
        message: TextSpan(text: error.toString()),
      );
    }
  }

  Future<void> _generateInvite() async {
    try {
      final code = await _service.generateInviteCode();
      dialogs.showBanner('已生成邀请码：$code', level: BannerLevel.success);
      await _load();
    } catch (error) {
      await dialogs.showAlert(
        title: '生成邀请码失败',
        message: TextSpan(text: error.toString()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      title: 'QNDXX 账户中心',
      isLoading: _loading,
      body: ListView(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: context.contentTopPadding,
          bottom: 24 + context.bottomInset,
        ),
        children: [
          if (!_signedIn) ...[
            const Text('登录 QNDXX XBoard 账号，即可管理订阅、套餐、订单、公告、邀请和工单。'),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: context.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : _login,
              child: const Text('XBoard 登录'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _openSupport,
              child: const Text('在线客服'),
            ),
          ] else ...[
            generateSection(
              title: '账号信息',
              items: [
                ListItem(
                  title: const Text('邮箱'),
                  subtitle: Text(_value(_account['email'] ?? _account['username'])),
                ),
                ListItem(
                  title: const Text('用户 ID'),
                  subtitle: Text(_value(_account['id'])),
                ),
                ListItem(
                  title: const Text('面板'),
                  subtitle: Text(_value(_account['panelUrl'])),
                ),
                ListItem(
                  title: const Text('套餐'),
                  subtitle: Text(_value(
                    (_subscription['plan'] is Map)
                        ? (_subscription['plan'] as Map)['name']
                        : null,
                  )),
                ),
                ListItem(
                  title: const Text('到期时间'),
                  subtitle: Text(_value(_subscription['expired_at'])),
                ),
                ListItem(
                  title: const Text('设备数量限制'),
                  subtitle: Text(_value(_subscription['device_limit'])),
                ),
              ],
            ),
            generateSection(
              title: '可用套餐',
              items: [
                if (_plans.isEmpty)
                  const ListItem(title: Text('当前面板没有返回可购买套餐')),
                for (final plan in _plans)
                  ListItem(
                    title: Text(_value(plan['name'], '未命名套餐')),
                    subtitle: Text(
                      '流量：${_value(plan['transfer_enable'])} · 设备：${_value(plan['device_limit'])}',
                    ),
                    trailing: TextButton(
                      onPressed: () => _purchasePlan(plan),
                      child: const Text('购买'),
                    ),
                  ),
              ],
            ),
            generateSection(
              title: '订单记录',
              items: [
                if (_orders.isEmpty)
                  const ListItem(title: Text('暂无订单')),
                for (final order in _orders)
                  ListItem(
                    title: Text(_value(order['trade_no'], '订单')),
                    subtitle: Text(
                      '金额：${_value(order['total_amount'])} · 状态：${_value(order['status'])}',
                    ),
                  ),
              ],
            ),
            generateSection(
              title: '公告',
              items: [
                if (_notices.isEmpty)
                  const ListItem(title: Text('暂无公告')),
                for (final notice in _notices)
                  ListItem(
                    title: Text(_value(notice['title'], '公告')),
                    subtitle: Text(_value(notice['content']), maxLines: 2),
                  ),
              ],
            ),
            generateSection(
              title: '邀请与佣金',
              items: [
                ListItem(
                  title: const Text('邀请统计'),
                  subtitle: Text(_value(_invite['stat'])),
                ),
                ListItem(
                  title: const Text('生成邀请码'),
                  trailing: TextButton(
                    onPressed: _generateInvite,
                    child: const Text('生成'),
                  ),
                ),
                if (_inviteCodes.isEmpty)
                  const ListItem(title: Text('暂无邀请码')),
                for (final code in _inviteCodes)
                  ListItem(
                    title: Text(_value(code['code'], '邀请码')),
                    subtitle: Text(
                      '访问：${_value(code['pv'])} · 状态：${code['status'] == true ? '有效' : '停用'}',
                    ),
                  ),
                if (_commissions.isNotEmpty)
                  const ListItem(title: Text('佣金明细')),
                for (final commission in _commissions)
                  ListItem(
                    title: Text('订单：${_value(commission['trade_no'])}'),
                    subtitle: Text(
                      '订单金额：${_value(commission['order_amount'])} · 佣金：${_value(commission['get_amount'])}',
                    ),
                  ),
              ],
            ),
            generateSection(
              title: '工单支持',
              items: [
                ListItem(
                  title: const Text('创建工单'),
                  trailing: TextButton(
                    onPressed: _createTicket,
                    child: const Text('新建'),
                  ),
                ),
                if (_tickets.isEmpty)
                  const ListItem(title: Text('暂无工单')),
                for (final ticket in _tickets)
                  ListItem(
                    title: Text(_value(ticket['subject'], '工单')),
                    subtitle: Text(
                      '状态：${_value(ticket['status'])} · 更新时间：${_value(ticket['updated_at'])}',
                    ),
                    onTap: () => _showTicket(ticket),
                  ),
              ],
            ),
            generateSection(
              title: '账户操作',
              items: [
                ListItem(
                  title: const Text('刷新账户数据'),
                  onTap: _load,
                ),
                ListItem(
                  title: const Text('在线客服 Crisp'),
                  onTap: _openSupport,
                ),
                ListItem(
                  title: const Text('退出登录'),
                  onTap: _logout,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanPeriodDialog extends StatelessWidget {
  const _PlanPeriodDialog({required this.plan});

  final Map<String, dynamic> plan;

  @override
  Widget build(BuildContext context) {
    final periods = <(String, String, dynamic)>[
      ('onetime_price', '一次性', plan['onetime_price']),
      ('month_price', '月付', plan['month_price']),
      ('quarter_price', '季付', plan['quarter_price']),
      ('half_year_price', '半年付', plan['half_year_price']),
      ('year_price', '年付', plan['year_price']),
      ('two_year_price', '两年付', plan['two_year_price']),
      ('three_year_price', '三年付', plan['three_year_price']),
    ] .where((item) => (num.tryParse(item.$3?.toString() ?? '') ?? 0) > 0).toList();
    return AlertDialog(
      title: '选择套餐周期',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (period, label, price) in periods)
            ListItem(
              title: Text(label),
              subtitle: Text('¥$price'),
              onTap: () => Navigator.of(context).pop(period),
            ),
        ],
      ),
    );
  }
}

class _PaymentMethodDialog extends StatelessWidget {
  const _PaymentMethodDialog({required this.methods});

  final List<Map<String, dynamic>> methods;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: '选择支付方式',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final method in methods)
            ListItem(
              title: Text(method['name']?.toString() ?? '支付方式'),
              subtitle: Text(method['description']?.toString() ?? ''),
              onTap: () => Navigator.of(context).pop(
                method['id']?.toString(),
              ),
            ),
        ],
      ),
    );
  }
}

class _CreateTicketDialog extends StatefulWidget {
  const _CreateTicketDialog();

  @override
  State<_CreateTicketDialog> createState() => _CreateTicketDialogState();
}

class _CreateTicketDialogState extends State<_CreateTicketDialog> {
  final _subject = TextEditingController();
  final _message = TextEditingController();

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: '提交客服工单',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final subject = _subject.text.trim();
            final message = _message.text.trim();
            if (subject.isEmpty || message.isEmpty) return;
            Navigator.of(context).pop({
              'subject': subject,
              'message': message,
              'level': 1,
            });
          },
          child: const Text('提交'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          TextFormField(
            controller: _subject,
            decoration: const InputDecoration(hintText: '工单标题'),
          ),
          TextFormField(
            controller: _message,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(hintText: '请描述你遇到的问题'),
          ),
        ],
      ),
    );
  }
}
