import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'qndxx_config_service.dart';
import 'qndxx_crisp_service.dart';
import 'qndxx_login_dialog.dart';
import 'qndxx_remote_status_service.dart';
import 'qndxx_xboard_service.dart';

class QndxxAccountView extends ConsumerStatefulWidget {
  const QndxxAccountView({super.key, this.mode = QndxxAccountViewMode.account});

  final QndxxAccountViewMode mode;

  @override
  ConsumerState<QndxxAccountView> createState() => _QndxxAccountViewState();
}

enum QndxxAccountViewMode { shop, account }

class _QndxxAccountViewState extends ConsumerState<QndxxAccountView> {
  final _service = QndxxXboardService.instance;
  final _remoteStatus = QndxxRemoteStatusService.instance;
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
    _remoteStatus.addListener(_onRemoteStatusChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _remoteStatus.removeListener(_onRemoteStatusChanged);
    super.dispose();
  }

  void _onRemoteStatusChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _toggleRemoteStatus() async {
    try {
      await _remoteStatus.setEnabled(!_remoteStatus.isEnabled);
    } catch (error) {
      if (!mounted) return;
      await dialogs.showAlert(
        title: '远程状态连接失败',
        message: TextSpan(text: error.toString()),
      );
    }
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
      try {
        await _remoteStatus.startIfEnabled();
      } catch (_) {}
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
      title: '退出账号',
      message: const TextSpan(text: '退出后会清除本设备保存的登录凭据，不会删除本地订阅配置。'),
      confirmText: '退出登录',
      destructive: true,
    );
    if (accepted != true) return;
    await _remoteStatus.setEnabled(false);
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
      // Cancel previous unpaid orders before creating a new purchase.
      final pendingOrders = await _service.getOrders();
      for (final order in pendingOrders) {
        final status = order['status']?.toString();
        final tradeNo = order['trade_no']?.toString() ?? '';
        if (status == '0' && tradeNo.isNotEmpty) {
          await _service.cancelOrder(tradeNo);
        }
      }
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
      final checkoutData = result['data'];
      final nestedData = checkoutData is Map
          ? Map<String, dynamic>.from(checkoutData)
          : const <String, dynamic>{};
      final url =
          result['url']?.toString() ??
          nestedData['url']?.toString() ??
          (checkoutData is String ? checkoutData : null) ??
          (nestedData['data'] is String ? nestedData['data'] as String : null);
      final checkoutType = result['type'] ?? nestedData['type'];
      final isFreePayment =
          checkoutType == -1 &&
          (checkoutData == true || nestedData['data'] == true);
      if (url != null && url.isNotEmpty) {
        await dialogs.openUrl(url);
      } else if (isFreePayment) {
        dialogs.showBanner('订单已完成，无需支付', level: BannerLevel.success);
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

  Future<void> _showOrder(Map<String, dynamic> order) async {
    final tradeNo = order['trade_no']?.toString() ?? '';
    if (tradeNo.isEmpty) return;
    try {
      final detail = await _service.getOrder(tradeNo);
      if (detail == null) return;
      await dialogs.showAlert(
        title: '订单详情',
        message: TextSpan(
          text:
              '订单号：$tradeNo\\n金额：${_value(detail['total_amount'])}\\n状态：${_value(detail['status'])}\\n周期：${_value(detail['period'])}',
        ),
      );
    } catch (error) {
      await dialogs.showAlert(
        title: '读取订单失败',
        message: TextSpan(text: error.toString()),
      );
    }
  }

  Future<void> _cancelOrder(Map<String, dynamic> order) async {
    final tradeNo = order['trade_no']?.toString() ?? '';
    if (tradeNo.isEmpty) return;
    final accepted = await dialogs.showMessage(
      title: '取消订单',
      message: TextSpan(text: '确定取消订单 $tradeNo 吗？'),
      confirmText: '取消订单',
      destructive: true,
    );
    if (accepted != true) return;
    try {
      final success = await _service.cancelOrder(tradeNo);
      if (success) {
        dialogs.showBanner('订单已取消', level: BannerLevel.success);
        await _load();
      } else {
        await dialogs.showAlert(
          title: '取消订单失败',
          message: const TextSpan(text: '面板未确认取消操作'),
        );
      }
    } catch (error) {
      await dialogs.showAlert(
        title: '取消订单失败',
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
        message: TextSpan(text: '${_value(detail['status'])}\n\n$messages'),
      );
    } catch (error) {
      await dialogs.showAlert(
        title: '读取工单失败',
        message: TextSpan(text: error.toString()),
      );
    }
  }

  Future<void> _replyTicket(Map<String, dynamic> ticket) async {
    final id = int.tryParse('${ticket['id']}');
    if (id == null) return;
    final message = await dialogs.showCommonDialog<String>(
      child: const _QndxxMessageDialog(title: '回复工单'),
    );
    if (message == null || message.trim().isEmpty) return;
    try {
      await _service.replyTicket(id, message.trim());
      dialogs.showBanner('回复已发送', level: BannerLevel.success);
      await _load();
    } catch (error) {
      await dialogs.showAlert(
        title: '发送回复失败',
        message: TextSpan(text: error.toString()),
      );
    }
  }

  Future<void> _closeTicket(Map<String, dynamic> ticket) async {
    final id = int.tryParse('${ticket['id']}');
    if (id == null) return;
    final accepted = await dialogs.showMessage(
      title: '关闭工单',
      message: const TextSpan(text: '确定关闭这个客服工单吗？'),
      confirmText: '关闭工单',
      destructive: true,
    );
    if (accepted != true) return;
    try {
      await _service.closeTicket(id);
      dialogs.showBanner('工单已关闭', level: BannerLevel.success);
      await _load();
    } catch (error) {
      await dialogs.showAlert(
        title: '关闭工单失败',
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
      title: widget.mode == QndxxAccountViewMode.shop ? '商店' : '我的',
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
            const Text('登录后即可查看套餐、订单和账户服务。'),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: context.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : _login,
              child: const Text('登录账号'),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _openSupport, child: const Text('在线客服')),
          ] else ...[
            if (widget.mode == QndxxAccountViewMode.account) ...[
              generateSection(
                title: '账号信息',
                items: [
                  ListItem(
                    title: const Text('邮箱'),
                    subtitle: Text(
                      _value(_account['email'] ?? _account['username']),
                    ),
                  ),
                  ListItem(
                    title: const Text('套餐'),
                    subtitle: Text(
                      _value(
                        (_subscription['plan'] is Map)
                            ? (_subscription['plan'] as Map)['name']
                            : null,
                      ),
                    ),
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
            ],
            if (widget.mode == QndxxAccountViewMode.shop) ...[
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
                  if (_orders.isEmpty) const ListItem(title: Text('暂无订单')),
                  for (final order in _orders)
                    ListItem(
                      title: Text(_value(order['trade_no'], '订单')),
                      subtitle: Text(
                        '金额：${_value(order['total_amount'])} · 状态：${_value(order['status'])}',
                      ),
                      onTap: () => _showOrder(order),
                      trailing: (order['status']?.toString() == '0')
                          ? TextButton(
                              onPressed: () => _cancelOrder(order),
                              child: const Text('取消'),
                            )
                          : null,
                    ),
                ],
              ),
              generateSection(
                title: '公告',
                items: [
                  if (_notices.isEmpty) const ListItem(title: Text('暂无公告')),
                  for (final notice in _notices)
                    ListItem(
                      title: Text(_value(notice['title'], '公告')),
                      subtitle: Text(_value(notice['content']), maxLines: 2),
                    ),
                ],
              ),
            ],
            if (widget.mode == QndxxAccountViewMode.account) ...[
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
                  if (_tickets.isEmpty) const ListItem(title: Text('暂无工单')),
                  for (final ticket in _tickets)
                    ListItem(
                      title: Text(_value(ticket['subject'], '工单')),
                      subtitle: Text(
                        '状态：${_value(ticket['status'])} · 更新时间：${_value(ticket['updated_at'])}',
                      ),
                      onTap: () => _showTicket(ticket),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () => _replyTicket(ticket),
                            child: const Text('回复'),
                          ),
                          TextButton(
                            onPressed: () => _closeTicket(ticket),
                            child: const Text('关闭'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              generateSection(
                title: '远程设备状态',
                items: [
                  ListItem(
                    title: const Text('WebSocket 状态上报'),
                    subtitle: Text(
                      _remoteStatus.isConnected
                          ? '已安全连接；仅发送随机设备 ID 和心跳'
                          : _remoteStatus.isEnabled
                          ? '已启用，等待安全连接；不会执行远程 HTTP 任务'
                          : '默认关闭；启用后仅发送随机设备 ID 和心跳',
                    ),
                    trailing: TextButton(
                      onPressed: _toggleRemoteStatus,
                      child: Text(_remoteStatus.isEnabled ? '停用' : '启用'),
                    ),
                  ),
                ],
              ),
              generateSection(
                title: '账户操作',
                items: [
                  ListItem(title: const Text('刷新账户数据'), onTap: _load),
                  ListItem(title: const Text('退出登录'), onTap: _logout),
                ],
              ),
            ],
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
    final periods =
        <(String, String, dynamic)>[
              ('onetime_price', '一次性', plan['onetime_price']),
              ('month_price', '月付', plan['month_price']),
              ('quarter_price', '季付', plan['quarter_price']),
              ('half_year_price', '半年付', plan['half_year_price']),
              ('year_price', '年付', plan['year_price']),
              ('two_year_price', '两年付', plan['two_year_price']),
              ('three_year_price', '三年付', plan['three_year_price']),
            ]
            .where((item) => (num.tryParse(item.$3?.toString() ?? '') ?? 0) > 0)
            .toList();
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
              onTap: () => Navigator.of(context).pop(method['id']?.toString()),
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
            Navigator.of(
              context,
            ).pop({'subject': subject, 'message': message, 'level': 1});
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

class _QndxxMessageDialog extends StatefulWidget {
  const _QndxxMessageDialog({required this.title});

  final String title;

  @override
  State<_QndxxMessageDialog> createState() => _QndxxMessageDialogState();
}

class _QndxxMessageDialogState extends State<_QndxxMessageDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: widget.title,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final value = _controller.text.trim();
            if (value.isNotEmpty) Navigator.of(context).pop(value);
          },
          child: const Text('发送'),
        ),
      ],
      child: TextFormField(
        controller: _controller,
        minLines: 3,
        maxLines: 6,
        decoration: const InputDecoration(hintText: '请输入回复内容'),
      ),
    );
  }
}
