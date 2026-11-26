import 'package:fl_clash/common/app_ports.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/ui/icons/app_glyphs.dart';
import 'package:fl_clash/views/views.dart';
import 'package:fl_clash/xboard/qndxx_account_view.dart';
import 'package:fl_clash/xboard/qndxx_support_view.dart';

class Navigation implements NavigationPort {
  static Navigation? _instance;

  @override
  List<NavigationItem> getItems({
    bool openLogs = false,
    bool hasProxies = false,
  }) {
    return [
      NavigationItem(
        glyph: AppGlyphs.dashboard,
        label: PageLabel.dashboard,
        builder: (_) => const DashboardView(),
      ),
      NavigationItem(
        glyph: AppGlyphs.shop,
        label: PageLabel.shop,
        builder: (_) => const QndxxAccountView(mode: QndxxAccountViewMode.shop),
      ),
      NavigationItem(
        glyph: AppGlyphs.customerService,
        label: PageLabel.customerService,
        builder: (_) => const QndxxSupportView(),
      ),
      NavigationItem(
        glyph: AppGlyphs.qndxxAccount,
        label: PageLabel.account,
        builder: (_) => const QndxxAccountView(mode: QndxxAccountViewMode.account),
      ),
    ];
  }

  Navigation._internal();

  factory Navigation() {
    _instance ??= Navigation._internal();
    return _instance!;
  }
}

final navigation = Navigation();
