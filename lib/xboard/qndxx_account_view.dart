import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intl/intl.dart';

import 'qndxx_config_service.dart';
import 'qndxx_login_dialog.dart';
import 'qndxx_crisp_service.dart';
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
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    super.dispose();
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

  String _formatBytes(dynamic value) {
    final bytes = num.tryParse(value?.toString() ?? '');
    if (bytes == null || bytes < 0) return _value(value);
    final gb = bytes / (1024 * 1024 * 1024);
    return gb >= 1024
        ? '${(gb / 1024).toStringAsFixed(2)} TB'
        : '${gb.toStringAsFixed(2)} GB';
  }

  String _formatDate(dynamic value) {
    if (value == null || value.toString().isEmpty) return '不限时';
    final numeric = int.tryParse(value.toString());
    final date = numeric != null
        ? DateTime.fromMillisecondsSinceEpoch(
            numeric > 9999999999 ? numeric : numeric * 1000,
          )
        : DateTime.tryParse(value.toString());
    return date == null
        ? value.toString()
        : DateFormat('yyyy-MM-dd HH:mm').format(date.toLocal());
  }

  String _inviteUrl(String code) =>
      'https://toufq.com/?code=${Uri.encodeComponent(code)}';


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
    await _service.logout();
    if (!mounted) return;
    setState(() {
      _signedIn = false;
      _account = const {};
      _subscription = const {};
    });
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
        if (Platform.isWindows || Platform.isMacOS) {
          await QndxxCrispService.instance.openPayment(url);
        } else {
          await dialogs.openUrl(url);
        }
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

  double _availableCommission() {
    final stat = _invite['stat'];
    final raw = stat is List && stat.length > 4
        ? stat[4]
        : stat is Map
        ? (stat['available_commission'] ?? stat['availableCommission'])
        : null;
    final cents = num.tryParse(raw?.toString() ?? '') ?? 0;
    return cents / 100;
  }

  Future<void> _transferCommission() async {
    final available = _availableCommission();
    if (available <= 0) {
      await dialogs.showAlert(
        title: '佣金划转',
        message: const TextSpan(text: '当前没有可划转的佣金'),
      );
      return;
    }
    final amount = await dialogs.showCommonDialog<double>(
      child: _TransferCommissionDialog(maxAmount: available),
    );
    if (amount == null) return;
    try {
      await _service.transferCommissionToBalance(amount);
      dialogs.showBanner('佣金已划转至网站钱包', level: BannerLevel.success);
      await _load();
    } catch (error) {
      await dialogs.showAlert(
        title: '佣金划转失败',
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
                    title: const Text('当前套餐'),
                    subtitle: Text(_value(
                      (_subscription['plan'] is Map)
                          ? (_subscription['plan'] as Map)['name']
                          : _subscription['plan_name'],
                    )),
                  ),
                  ListItem(
                    title: const Text('到期时间'),
                    subtitle: Text(_formatDate(
                      _subscription['expired_at'] ?? _subscription['expired_at_timestamp'],
                    )),
                  ),
                  ListItem(
                    title: const Text('流量总额'),
                    subtitle: Text(_formatBytes(_subscription['transfer_enable'])),
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
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((plan['content'] ?? plan['description'] ?? plan['plan_content'])?.toString().trim().isNotEmpty == true)
                            MarkdownBody(
                              data: (plan['content'] ?? plan['description'] ?? plan['plan_content']).toString(),
                            ),
                          const SizedBox(height: 6),
                          Text('流量：${_formatBytes(plan['transfer_enable'])} · 设备：${_value(plan['device_limit'])}'),
                        ],
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
                title: '我的钱包',
                items: [
                  ListItem(
                    title: const Text('可用佣金'),
                    subtitle: Text(_value(
                      _account['balance'],
                      '面板暂未提供余额数据',
                    )),
                  ),
                  ListItem(
                    title: const Text('可划转佣金'),
                    subtitle: Text('¥${_availableCommission().toStringAsFixed(2)}'),
                    trailing: TextButton(
                      onPressed: _transferCommission,
                      child: const Text('划转到钱包'),
                    ),
                  ),
                  const ListItem(
                    title: Text('钱包用途'),
                    subtitle: Text('划转后的余额仅可用于网站消费'),
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
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('访问：${_value(code['pv'])} · 状态：${code['status'] == true ? '有效' : '停用'}'),
                          const SizedBox(height: 8),
                          QrImageView(
                            data: _inviteUrl(_value(code['code'], '')),
                            size: 144,
                            backgroundColor: const Color(0xFFFFFFFF),
                          ),
                        ],
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

class _TransferCommissionDialog extends StatefulWidget {
  const _TransferCommissionDialog({required this.maxAmount});

  final double maxAmount;

  @override
  State<_TransferCommissionDialog> createState() =>
      _TransferCommissionDialogState();
}

class _TransferCommissionDialogState extends State<_TransferCommissionDialog> {
  final _amount = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: '佣金划转到网站钱包',
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final amount = double.tryParse(_amount.text.trim());
            if (amount == null || amount <= 0 || amount > widget.maxAmount) {
              dialogs.showBanner(
                '请输入有效金额，最多可划转 ¥${widget.maxAmount.toStringAsFixed(2)}',
                level: BannerLevel.warning,
              );
              return;
            }
            Navigator.of(context).pop(amount);
          },
          child: const Text('确认划转'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('可划转佣金：¥${widget.maxAmount.toStringAsFixed(2)}'),
          const SizedBox(height: 12),
          TextFormField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              hintText: '请输入划转金额',
              prefixText: '¥ ',
            ),
          ),
          const SizedBox(height: 8),
          const Text('划转至网站钱包后，仅可用于网站消费。'),
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
