import 'dart:async';
import 'dart:io';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/pages/error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_api/rust_api.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'application.dart';
import 'bootstrap.dart';
import 'common/app_data.dart';
import 'common/common.dart';
import 'common/preferences_store.dart';
import 'common/window.dart';
import 'xboard/qndxx_bootstrap_splash.dart';
import 'xboard/qndxx_config_service.dart';
import 'xboard/qndxx_remote_status_service.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (details) {
        Future.microtask(() {
          commonPrint.log(
            'exception: ${details.exception} stack: ${details.stack}',
            logLevel: LogLevel.warning,
          );
        });
      };
      // Paint the branded splash on the very first Flutter frame. Do not wait
      // for Rust, platform, configuration or database initialization first.
      runApp(const _QndxxBootstrapGate());
    },
    (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    },
  );
}

class _QndxxBootstrapGate extends StatefulWidget {
  const _QndxxBootstrapGate();

  @override
  State<_QndxxBootstrapGate> createState() => _QndxxBootstrapGateState();
}

class _QndxxBootstrapGateState extends State<_QndxxBootstrapGate> {
  Widget? _application;
  final DateTime _startedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      if (Platform.isWindows || Platform.isLinux) {
        SharedPreferencesStorePlatform.instance = AtomicFilePreferencesStore(
          appPath.sharedPreferencesPath,
        );
      }
      await QndxxConfigService.instance.initialize(refreshRemote: false);
      await RustLib.init();
      final version = await system.init();
      final container = await bootstrap.init(version);
      await FlClashHttpOverrides.trustCoreRoots();
      HttpOverrides.global = FlClashHttpOverrides(container);
      request.attach(container.read);

      // Keep the animation visible long enough to be perceived even on fast
      // machines; slow initialization naturally extends the splash.
      const minimumSplashDuration = Duration(milliseconds: 4500);
      final elapsed = DateTime.now().difference(_startedAt);
      if (elapsed < minimumSplashDuration) {
        await Future<void>.delayed(minimumSplashDuration - elapsed);
      }
      if (!mounted) return;
      setState(() {
        _application = UncontrolledProviderScope(
          container: container,
          child: const Application(),
        );
      });
      unawaited(_refreshQndxxServices());
    } catch (error, stack) {
      if (!mounted) return;
      setState(() {
        _application = InitErrorApp(
          error: error,
          stack: stack,
          onClearData: clearAppData,
          onExit: _exitAfterInitFailure,
        );
      });
      unawaited(window?.showInitFailure(onExit: _exitAfterInitFailure));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _application ?? const QndxxBootstrapSplash();
  }
}

Future<void> _refreshQndxxServices() async {
  await QndxxConfigService.instance.refresh();
  try {
    await QndxxRemoteStatusService.instance.startIfEnabled();
  } catch (_) {}
}

Future<void> _exitAfterInitFailure() async {
  await system.exit();
  window?.forceExit();
}
