import 'dart:async';

import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';

const qndxxLogoUrl = 'https://img.toufq.com/IMG/QNDXXLG.png';

class QndxxBrandLogo extends StatelessWidget {
  const QndxxBrandLogo({super.key, this.size = 76});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.23),
      child: Image.asset(
        'assets/images/QNDXXLG.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(size * 0.23),
          ),
          child: Text(
            '青',
            style: TextStyle(
              fontSize: size * 0.48,
              fontWeight: FontWeight.w700,
              color: context.colorScheme.onPrimaryContainer,
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
    Future<void>.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: 'Hi，欢迎使用',
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOut,
        child: AnimatedScale(
          scale: _visible ? 1 : 0.92,
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const QndxxBrandLogo(size: 92),
              const SizedBox(height: 18),
              Text(
                '青年大学习',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: context.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '官网发布页：toufq.com',
                style: TextStyle(
                  fontSize: 14,
                  color: context.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
