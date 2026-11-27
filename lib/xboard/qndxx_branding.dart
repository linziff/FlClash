import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';

import 'qndxx_config_service.dart';

const qndxxLogoUrl = 'https://img.toufq.com/IMG/QNDXXLG.png';

class QndxxBrandLogo extends StatelessWidget {
  const QndxxBrandLogo({super.key, this.size = 76});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.23),
      child: Image.asset(
        'assets/images/qndxx_app_icon.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          child: Text(
            'Q',
            style: TextStyle(
              fontSize: size * 0.62,
              fontWeight: FontWeight.w800,
              color: context.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class QndxxStartupSplash extends StatefulWidget {
  const QndxxStartupSplash({super.key});

  @override
  State<QndxxStartupSplash> createState() => _QndxxStartupSplashState();
}

class _QndxxStartupSplashState extends State<QndxxStartupSplash> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Scaffold(
      title: '青年大学习',
      backgroundColor: colors.surface,
      body: ColoredBox(
        color: colors.surface,
        child: SafeArea(
          child: Center(
            child: AnimatedOpacity(
              opacity: _visible ? 1 : 0,
              duration: const Duration(milliseconds: 1200),
              curve: Curves.easeOutCubic,
              child: AnimatedScale(
                scale: _visible ? 1 : 0.9,
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Keep the source logo's transparent edges visible.
                      // A colored tile behind it made the splash look like
                      // a second, mismatched app icon.
                      const QndxxBrandLogo(size: 112),
                      const SizedBox(height: 28),
                      Text(
                        '青年大学习',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: colors.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '安全、稳定、便捷的网络连接体验',
                        style: TextStyle(
                          fontSize: 14,
                          color: colors.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),
                      const SizedBox(
                        width: 26,
                        height: 26,
                        child: ActivityIndicator(),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        QndxxConfigService.instance.appWebsite,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
