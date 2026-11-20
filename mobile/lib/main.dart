import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/home_shell.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: Config.supabaseUrl,
    publishableKey: Config.supabaseKey,
  );
  // Web builds are only used for automated UI tests: expose the semantics tree.
  if (kIsWeb) SemanticsBinding.instance.ensureSemantics();
  runApp(const CloudStorageApp());
  app.start();
}

class CloudStorageApp extends StatelessWidget {
  const CloudStorageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Config.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      // Keep layouts compact when the phone uses a very large font size.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: MediaQuery.textScalerOf(context)
              .clamp(minScaleFactor: 0.9, maxScaleFactor: 1.1),
        ),
        child: child!,
      ),
      home: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          if (app.startupError != null) {
            return Scaffold(
              body: ErrorRetry(message: app.startupError!, onRetry: app.start),
            );
          }
          if (!app.ready) return const SplashScreen();
          return const HomeShell();
        },
      ),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.glow),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Image.asset('assets/logo.png', width: 96, height: 96),
              ),
              const SizedBox(height: 18),
              const Text(
                Config.appName,
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  color: AppColors.text,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 32),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
