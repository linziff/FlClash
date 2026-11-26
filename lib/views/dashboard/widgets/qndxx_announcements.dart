import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/views/dashboard/widgets/card.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../../xboard/qndxx_xboard_service.dart';

/// Compact, rotating announcement strip shared by desktop and mobile dashboard.
class QndxxAnnouncementBanner extends StatefulWidget {
  const QndxxAnnouncementBanner({super.key});

  @override
  State<QndxxAnnouncementBanner> createState() =>
      _QndxxAnnouncementBannerState();
}

class _QndxxAnnouncementBannerState extends State<QndxxAnnouncementBanner> {
  static final Set<String> _shownNodeAnnouncements = <String>{};
  final _service = QndxxXboardService.instance;
  List<Map<String, dynamic>> _notices = const [];
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await _service.restoreSession();
      final notices = await _service.getNotices();
      if (!mounted || notices.isEmpty) return;
      setState(() => _notices = notices);
      if (notices.length > 1) {
        _timer = Timer.periodic(const Duration(seconds: 5), (_) {
          if (mounted) setState(() => _index = (_index + 1) % _notices.length);
        });
      }
      final nodeNotices = notices.where(_hasNodeTag).toList();
      if (nodeNotices.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          for (final nodeNotice in nodeNotices) {
            if (!mounted) break;
            if (_shownNodeAnnouncements.add(_noticeKey(nodeNotice))) {
              await _showNotice(nodeNotice);
            }
          }
        });
      }
    } catch (_) {
      // Announcements are optional; the dashboard remains usable offline.
    }
  }

  String _noticeKey(Map<String, dynamic> notice) =>
      (notice['id'] ?? notice['title'] ?? notice['content'] ?? notice.hashCode)
          .toString();

  bool _hasNodeTag(Map<String, dynamic> notice) {
    final tagValues = [
      notice['tag'],
      notice['tags'],
      notice['type'],
      notice['category'],
      notice['label'],
    ];
    for (final value in tagValues) {
      final values = value is Iterable
          ? value.map((item) => item.toString())
          : [value?.toString() ?? ''];
      if (values.any((item) =>
          RegExp(r'(^|[,，;；|/\s])节点($|[,，;；|/\s])').hasMatch(item))) {
        return true;
      }
    }
    final title = notice['title']?.toString() ?? '';
    return RegExp(r'^[\s【\[]*(节点|节点公告)[】\]]').hasMatch(title) ||
        RegExp(r'(^|\s)#节点($|\s)').hasMatch(title);
  }

  Future<void> _showNotice(Map<String, dynamic> notice) async {
    await dialogs.showCommonDialog<void>(
      child: _QndxxAnnouncementDialog(notice: notice),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_notices.isEmpty) return const SizedBox.shrink();
    final notice = _notices[_index];
    final title = notice['title']?.toString().trim();
    final content = notice['content']?.toString().trim() ?? '';
    final colors = context.colorScheme;
    return DashboardCard(
      padding: EdgeInsets.zero,
      child: Semantics(
        button: true,
        label: '公告：${title?.isNotEmpty == true ? title : content}',
        child: GestureDetector(
          onTap: () => _showNotice(notice),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(
                      Icons.campaign_rounded,
                      color: colors.onPrimaryContainer,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.25),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Column(
                      key: ValueKey(_noticeKey(notice)),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title?.isNotEmpty == true ? title! : '平台公告',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        if (content.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            content.replaceAll(RegExp(r'[#*_\x60>\[\]()]'), ''),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded,
                    color: colors.onSurfaceVariant, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QndxxAnnouncementDialog extends StatelessWidget {
  const _QndxxAnnouncementDialog({required this.notice});

  final Map<String, dynamic> notice;

  @override
  Widget build(BuildContext context) {
    final title = notice['title']?.toString().trim();
    final content = notice['content']?.toString() ?? '';
    return AlertDialog(
      title: title?.isNotEmpty == true ? title! : '平台公告',
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('我知道了'),
        ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 440),
        child: SingleChildScrollView(
          child: MarkdownBody(
            data: content.isEmpty ? '暂无公告内容' : content,
            selectable: true,
          ),
        ),
      ),
    );
  }
}
