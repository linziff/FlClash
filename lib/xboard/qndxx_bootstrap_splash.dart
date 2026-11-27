import 'package:flutter/material.dart';

/// First Flutter frame shown immediately, before Rust, database and platform
/// initialization. This avoids leaving Windows blank and Android on a static
/// system splash while the expensive bootstrap work runs.
class QndxxBootstrapSplash extends StatelessWidget {
  const QndxxBootstrapSplash({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFFF5F7FB);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: background,
        body: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.82, end: 1),
            duration: const Duration(milliseconds: 1100),
            curve: Curves.easeOutCubic,
            builder: (context, scale, child) => Opacity(
              opacity: ((scale - 0.82) / 0.18).clamp(0.0, 1.0),
              child: Transform.scale(scale: scale, child: child),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(25),
                  child: Image.asset(
                    'assets/images/qndxx_adaptive_foreground.png',
                    width: 112,
                    height: 112,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox(
                      width: 112,
                      height: 112,
                      child: Center(child: Icon(Icons.apps_rounded, size: 72)),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                const Text(
                  '青年大学习',
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF202938),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '安全、稳定、便捷的网络连接体验',
                  style: TextStyle(fontSize: 14, color: Color(0xFF687386)),
                ),
                const SizedBox(height: 30),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
