import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/widgets/widgets.dart'
    hide Card, Divider, FilledButton, LinearProgressIndicator, IconButton;
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart'
    show
        Icons,
        Icon,
        IconData,
        FilledButton,
        Card,
        Container,
        RoundedRectangleBorder,
        BorderSide,
        Divider,
        Clip,
        LinearProgressIndicator,
        IconButton;
import 'package:flutter/material.dart' show MaterialPageRoute;
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
      // Existing sessions already have a panel URL. Do not block this page on
      // remote-config retries; config refresh runs independently at startup.
      await QndxxConfigService.instance
          .initialize(refreshRemote: false)
          .timeout(const Duration(seconds: 12));
      await _service.restoreSession().timeout(const Duration(seconds: 8));
      final account = await _service.getAccountInfo().timeout(
        const Duration(seconds: 18),
      );
      late final Map<String, dynamic> subscription;
      late final List<Map<String, dynamic>> plans;
      late final List<Map<String, dynamic>> orders;
      late final Map<String, dynamic> invite;
      late final List<Map<String, dynamic>> inviteCodes;
      late final List<Map<String, dynamic>> commissions;
      if (widget.mode == QndxxAccountViewMode.account) {
        final results = await Future.wait<dynamic>([
          _service
              .getSubscriptionInfo()
              .timeout(const Duration(seconds: 12))
              .catchError((_) => <String, dynamic>{}),
          _service
              .getInviteInfo()
              .timeout(const Duration(seconds: 12))
              .catchError((_) => <String, dynamic>{}),
          _service
              .getCommissionDetails()
              .timeout(const Duration(seconds: 12))
              .catchError((_) => <Map<String, dynamic>>[]),
        ]);
        subscription = results[0] as Map<String, dynamic>;
        invite = results[1] as Map<String, dynamic>;
        final rawCodes = invite['codes'];
        inviteCodes = rawCodes is List
            ? rawCodes
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList(growable: false)
            : const [];
        commissions = results[2] as List<Map<String, dynamic>>;
        plans = const [];
        orders = const [];
      } else {
        final results = await Future.wait<dynamic>([
          _service
              .getPlans()
              .timeout(const Duration(seconds: 12))
              .catchError((_) => <Map<String, dynamic>>[]),
          _service
              .getOrders()
              .timeout(const Duration(seconds: 12))
              .catchError((_) => <Map<String, dynamic>>[]),
        ]);
        plans = results[0] as List<Map<String, dynamic>>;
        orders = results[1] as List<Map<String, dynamic>>;
        subscription = const {};
        invite = const {};
        inviteCodes = const [];
        commissions = const [];
      }
      if (!mounted) return;
      setState(() {
        _signedIn = true;
        _account = account;
        _subscription = subscription;
        _plans = plans;
        _orders = orders;
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

  String _orderStatusLabel(dynamic value) {
    final raw = value?.toString().trim().toLowerCase() ?? '';
    switch (raw) {
      case '0':
      case 'pending':
      case 'unpaid':
        return '待支付';
      case '1':
      case 'processing':
      case 'confirming':
        return '处理中';
      case '2':
      case 'cancelled':
      case 'canceled':
        return '已取消';
      case '3':
      case 'completed':
      case 'paid':
        return '已完成';
      default:
        return raw.isEmpty ? '未知' : '未知状态（$raw）';
    }
  }

  String _formatPrice(dynamic value) {
    final amount = num.tryParse(value?.toString() ?? '');
    if (amount == null || amount < 0) return _value(value);
    // XBoard plan/order API amounts are integer cents.
    return '¥' + (amount / 100).toStringAsFixed(2);
  }

  String _formatBytes(dynamic value) {
    final bytes = num.tryParse(value?.toString() ?? '');
    if (bytes == null || bytes < 0) return _value(value);
    final gb = bytes / (1024 * 1024 * 1024);
    return gb >= 1024
        ? '${(gb / 1024).toStringAsFixed(2)} TB'
        : '${gb.toStringAsFixed(2)} GB';
  }

  String _formatPlanTraffic(dynamic value) {
    final gb = num.tryParse(value?.toString() ?? '');
    if (gb == null || gb < 0) return _value(value);
    if (gb >= 1024) return (gb / 1024).toStringAsFixed(2) + ' TB';
    return gb.toStringAsFixed(gb == gb.roundToDouble() ? 0 : 2) + ' GB';
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

  Widget _buildShopHero(BuildContext context) {
    final colors = context.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.primaryContainer, colors.surfaceContainerHigh],
            ),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.55),
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(
                  Icons.storefront_rounded,
                  color: colors.primary,
                  size: 29,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.storefront_rounded,
                          color: colors.primary,
                          size: 19,
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            '青年大学习 商店',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.onSurface,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Icon(
                          Icons.shopping_bag_rounded,
                          color: colors.primary,
                          size: 18,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '选择适合你的套餐，畅享稳定连接',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.auto_awesome_rounded, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }

  IconData _planIcon(Map<String, dynamic> plan) {
    final name = _value(plan['name'], '').toLowerCase();
    if (name.contains('体验') || name.contains('试用')) return Icons.bolt_rounded;
    if (name.contains('流量') || name.contains('不限量'))
      return Icons.data_usage_rounded;
    if (name.contains('高速') || name.contains('加速')) return Icons.speed_rounded;
    if (name.contains('家庭')) return Icons.home_rounded;
    if (name.contains('企业')) return Icons.business_center_rounded;
    if (name.contains('年')) return Icons.calendar_month_rounded;
    return Icons.workspace_premium_rounded;
  }

  Widget _buildPlansSection(BuildContext context) {
    final colors = context.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 14),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 9),
              Text(
                '精选套餐',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '${_plans.length} 款可选',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        if (_plans.isEmpty)
          Card(
            color: colors.surfaceContainerLow,
            elevation: 0,
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('当前面板没有返回可购买套餐')),
            ),
          ),
        for (final plan in _plans)
          Card(
            color: colors.surfaceContainerLow,
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: colors.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_planIcon(plan), color: colors.primary, size: 25),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _value(plan['name'], '未命名套餐'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: colors.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.verified_rounded,
                        color: colors.primary,
                        size: 19,
                      ),
                    ],
                  ),
                  if ((plan['content'] ??
                              plan['description'] ??
                              plan['plan_content'])
                          ?.toString()
                          .trim()
                          .isNotEmpty ==
                      true) ...[
                    const SizedBox(height: 14),
                    MarkdownBody(
                      data:
                          (plan['content'] ??
                                  plan['description'] ??
                                  plan['plan_content'])
                              .toString(),
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(
                          height: 1.5,
                          fontSize: 13,
                          color: colors.onSurfaceVariant,
                        ),
                        listBullet: TextStyle(color: colors.primary),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _PlanFeatureChip(
                        icon: Icons.data_usage_rounded,
                        label: _formatPlanTraffic(plan['transfer_enable']),
                      ),
                      _PlanFeatureChip(
                        icon: Icons.devices_rounded,
                        label: '${_value(plan['device_limit'])} 台设备',
                      ),
                      if (plan['speed_limit'] != null)
                        _PlanFeatureChip(
                          icon: Icons.speed_rounded,
                          label: '${plan['speed_limit']} Mbps',
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(
                    height: 1,
                    color: colors.outlineVariant.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: _PlanPriceRow(plan: plan)),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: () => _purchasePlan(plan),
                        icon: const Icon(Icons.shopping_bag_outlined, size: 17),
                        label: const Text('立即选购'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _inviteUrl(String code) =>
      'https://toufq.com/?code=${Uri.encodeComponent(code)}';

  Future<void> _login() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const QndxxLoginDialog(),
      ),
    );
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
          final cancelled = await _service.cancelOrder(tradeNo);
          if (!cancelled) {
            throw StateError('旧的未支付订单 $tradeNo 取消失败，请先到订单记录中处理');
          }
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
              '订单号：$tradeNo\\n金额：${_formatPrice(detail['total_amount'])}\\n状态：${_orderStatusLabel(detail['status'])}\\n周期：${_value(detail['period'])}',
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
    return DefaultTextStyle.merge(
      // Use the native Windows UI font to avoid the softer fallback face in
      // compact shop labels, prices, and plan descriptions.
      style: TextStyle(fontFamily: Platform.isWindows ? 'Segoe UI' : null),
      child: Scaffold(
        title: widget.mode == QndxxAccountViewMode.shop ? '商店' : '我的',
        backgroundColor: context.colorScheme.surface,
        body: ListView(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: context.contentTopPadding,
            bottom: 24 + context.bottomInset,
          ),
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              ),
            if (_error != null && !_loading)
              Card(
                color: context.colorScheme.errorContainer,
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: context.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '账户数据暂时无法加载：$_error',
                          style: TextStyle(
                            color: context.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '重试',
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            if (widget.mode == QndxxAccountViewMode.shop)
              _buildShopHero(context),
            if (!_signedIn) ...[
              const Text('登录后即可查看套餐、订单和账户服务。'),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: context.colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _login,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.login_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('登录账号'),
                  ],
                ),
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
                      subtitle: Text(
                        _value(
                          (_subscription['plan'] is Map)
                              ? (_subscription['plan'] as Map)['name']
                              : _subscription['plan_name'],
                        ),
                      ),
                    ),
                    ListItem(
                      title: const Text('到期时间'),
                      subtitle: Text(
                        _formatDate(
                          _subscription['expired_at'] ??
                              _subscription['expired_at_timestamp'],
                        ),
                      ),
                    ),
                    ListItem(
                      title: const Text('流量总额'),
                      subtitle: Text(
                        _formatBytes(_subscription['transfer_enable']),
                      ),
                    ),
                    ListItem(
                      title: const Text('设备数量限制'),
                      subtitle: Text(_value(_subscription['device_limit'])),
                    ),
                  ],
                ),
              ],
              if (widget.mode == QndxxAccountViewMode.shop) ...[
                _buildPlansSection(context),
                generateSection(
                  title: '订单记录',
                  items: [
                    if (_orders.isEmpty) const ListItem(title: Text('暂无订单')),
                    for (final order in _orders)
                      ListItem(
                        title: Row(
                          children: [
                            Icon(
                              Icons.receipt_long_rounded,
                              size: 18,
                              color: context.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_value(order['trade_no'], '订单')),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          '金额：${_formatPrice(order['total_amount'])} · 状态：${_orderStatusLabel(order['status'])}',
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
              ],
              if (widget.mode == QndxxAccountViewMode.account) ...[
                generateSection(
                  title: '我的钱包',
                  items: [
                    ListItem(
                      title: const Text('可用佣金'),
                      subtitle: Text(
                        _account['balance'] == null
                            ? '面板暂未提供余额数据'
                            : _formatPrice(_account['balance']),
                      ),
                    ),
                    ListItem(
                      title: const Text('可划转佣金'),
                      subtitle: Text(
                        '¥${_availableCommission().toStringAsFixed(2)}',
                      ),
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
                      subtitle: Text(() {
                        final stat = _invite['stat'];
                        if (stat is List && stat.isNotEmpty) {
                          final invited = stat[0];
                          final total = stat.length > 1
                              ? (num.tryParse(stat[1].toString()) ?? 0) / 100
                              : 0;
                          return '已邀请：$invited 人 · 累计佣金：¥${total.toStringAsFixed(2)}';
                        }
                        return _value(stat);
                      }()),
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
                            Text(
                              '访问：${_value(code['pv'])} · 状态：${code['status'] == true ? '有效' : '停用'}',
                            ),
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
                          '订单金额：${_formatPrice(commission['order_amount'])} · 佣金：${_formatPrice(commission['get_amount'])} · 时间：${_formatDate(commission['created_at'])}',
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
      ),
    );
  }
}

class _PlanFeatureChip extends StatelessWidget {
  const _PlanFeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: context.colorScheme.primary),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanPriceRow extends StatelessWidget {
  const _PlanPriceRow({required this.plan});

  final Map<String, dynamic> plan;

  @override
  Widget build(BuildContext context) {
    const periods = <(String, String)>[
      ('onetime_price', '一次性'),
      ('month_price', '月付'),
      ('quarter_price', '季付'),
      ('half_year_price', '半年'),
      ('year_price', '年付'),
      ('two_year_price', '两年'),
      ('three_year_price', '三年'),
    ];
    final prices = periods
        .map(
          (item) =>
              (item.$2, num.tryParse(plan[item.$1]?.toString() ?? '') ?? 0),
        )
        .where((item) => item.$2 > 0)
        .toList();
    if (prices.isEmpty) return const Text('价格以结算页为准');
    final lowest = prices.reduce((a, b) => a.$2 < b.$2 ? a : b);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '¥${(lowest.$2 / 100).toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: context.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 7),
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(
            '${lowest.$1}起',
            style: TextStyle(
              fontSize: 12,
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const Spacer(),
        Text(
          '${prices.length} 种周期',
          style: TextStyle(
            fontSize: 12,
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
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
        <(String, String, dynamic, IconData)>[
              (
                'onetime_price',
                '一次性',
                plan['onetime_price'],
                Icons.bolt_rounded,
              ),
              (
                'month_price',
                '月付',
                plan['month_price'],
                Icons.calendar_today_rounded,
              ),
              (
                'quarter_price',
                '季付',
                plan['quarter_price'],
                Icons.date_range_rounded,
              ),
              (
                'half_year_price',
                '半年付',
                plan['half_year_price'],
                Icons.event_repeat_rounded,
              ),
              (
                'year_price',
                '年付',
                plan['year_price'],
                Icons.calendar_month_rounded,
              ),
              (
                'two_year_price',
                '两年付',
                plan['two_year_price'],
                Icons.workspace_premium_rounded,
              ),
              (
                'three_year_price',
                '三年付',
                plan['three_year_price'],
                Icons.stars_rounded,
              ),
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
          for (final (period, label, price, icon) in periods)
            GestureDetector(
              onTap: () => Navigator.of(context).pop(period),
              child: Container(
                margin: const EdgeInsets.only(bottom: 9),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: context.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: context.colorScheme.outlineVariant.withValues(
                      alpha: 0.65,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: context.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        icon,
                        color: context.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '¥${((num.tryParse(price.toString()) ?? 0) / 100).toStringAsFixed(2)}',
                      style: TextStyle(
                        color: context.colorScheme.primary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.arrow_circle_right_rounded,
                      color: context.colorScheme.primary,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PaymentMethodOption extends StatelessWidget {
  const _PaymentMethodOption({required this.method, required this.onTap});

  final Map<String, dynamic> method;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = method['name']?.toString() ?? '支付方式';
    final keyword = '${name.toLowerCase()} ${method['id'] ?? ''}'.toLowerCase();
    final icon = keyword.contains('alipay') || name.contains('支付宝')
        ? Icons.account_balance_wallet_rounded
        : keyword.contains('wechat') || name.contains('微信')
        ? Icons.chat_rounded
        : keyword.contains('qq') || name.contains('qq')
        ? Icons.forum_rounded
        : Icons.credit_card_rounded;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: context.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: context.colorScheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: context.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: context.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if ((method['description']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      method['description'].toString(),
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.arrow_circle_right_rounded,
              color: context.colorScheme.primary,
              size: 22,
            ),
          ],
        ),
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
            _PaymentMethodOption(
              method: method,
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
