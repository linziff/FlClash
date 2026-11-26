import 'dart:async';

import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show CircularProgressIndicator;

import 'qndxx_crisp_service.dart';

class QndxxSupportView extends StatefulWidget {
  const QndxxSupportView({super.key});

  @override
  State<QndxxSupportView> createState() => _QndxxSupportViewState();
}

class _QndxxSupportViewState extends State<QndxxSupportView> {
  String? _error;
  bool _opening = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_openCrisp()),
    );
  }

  Future<void> _openCrisp() async {
    if (mounted)
      setState(() {
        _opening = true;
        _error = null;
      });
    try {
      await QndxxCrispService.instance.open();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      title: '在线客服',
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _error == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(_opening ? '正在打开在线客服…' : '客服窗口已打开'),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _openCrisp,
                      child: const Text('重试打开客服'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
