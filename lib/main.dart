import 'package:avaremp/logbook/logbook_screen.dart';
import 'package:avaremp/instruments/pfd_screen.dart';
import 'package:avaremp/longpress_screen.dart';
import 'package:avaremp/place/airspace_3d_screen.dart';
import 'package:avaremp/plan/plan_action_screen.dart';
import 'package:avaremp/services/app_check.dart';
import 'package:avaremp/services/login_screen.dart';
import 'package:avaremp/services/revenue_cat.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/writing_screen.dart';
import 'aircraft/aircraft_performance_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'ai/ai_screen.dart';
import 'checklist/checklist_screen.dart';
import 'community/community_screen.dart';
import 'constants.dart';
import 'destination/destination.dart';
import 'documents_screen.dart';
import 'chart/download_screen.dart';
import 'firebase_options.dart';
import 'io/io_screen.dart';
import 'link/link_screen.dart';
import 'main_screen.dart';
import 'scheduler/scheduler_screen.dart';
import 'onboarding_screen.dart';
import 'services/backup_screen.dart';
import 'splash_screen.dart';

class CustomWidgetsBinding extends WidgetsFlutterBinding {
  @override
  ImageCache createImageCache() => Storage().imageCache;

  final List<EmailVerificationController> _emailVerificationControllers = [];

  @override
  void addObserver(WidgetsBindingObserver observer) {
    if (observer is EmailVerificationController) {
      _emailVerificationControllers.add(observer);
    }
    super.addObserver(observer);
  }

  @override
  bool removeObserver(WidgetsBindingObserver observer) {
    if (observer is EmailVerificationController) {
      _emailVerificationControllers.remove(observer);
    }
    return super.removeObserver(observer);
  }

  @override
  void handleAppLifecycleStateChanged(AppLifecycleState state) {
    // ProfileScreen never disposes EmailVerificationController; after sign-out
    // it still receives resume and hits currentUser!. Drop it first.
    for (final controller in List<EmailVerificationController>.of(
        _emailVerificationControllers)) {
      if (controller.auth.currentUser == null) {
        controller.dispose();
      }
    }
    super.handleAppLifecycleStateChanged(state);
  }
}

void main() {
  // this is to control cache. Nexrad needs it or image caching will make it impossible to animate weather
  CustomWidgetsBinding();
  runApp(const StartupApp());
}

class StartupApp extends StatefulWidget {
  const StartupApp({super.key});

  @override
  State<StartupApp> createState() => _StartupAppState();
}

class _StartupAppState extends State<StartupApp> {
  /// Long enough to read the logo on a hot restart, when there is no native splash.
  static const Duration _minimumVisible = Duration(milliseconds: 1500);
  bool _initialized = false;
  bool _minimumElapsed = false;

  bool get _openApp => _initialized && _minimumElapsed;

  @override
  void initState() {
    super.initState();
    // Drop the native/web splash once this logo screen has actually painted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });
    _start();
    Future<void>.delayed(_minimumVisible, () {
      if(!mounted) {
        return;
      }
      setState(() {
        _minimumElapsed = true;
      });
    });
  }

  Future<void> _start() async {
    await Storage().init();
    if(Constants.firebaseAvailable) {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        await AppCheckService.activate();
        FirebaseUIAuth.configureProviders([
          EmailAuthProvider(),
        ]);
        if(Constants.shouldShowProServices) {
          await RevenueCatService.initPlatformState();
        }
      }
      catch (e) {
        // ignore errors here
      }
    }
    if(!mounted) {
      return;
    }
    setState(() {
      _initialized = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if(!_openApp) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: SplashScreen.background,
        ),
        home: const SplashScreen(),
      );
    }
    return const MainApp();
  }
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeData>(
        valueListenable: Storage().themeNotifier,
        builder: (context, value, child) {
          return SafeArea(child: MaterialApp(
            debugShowCheckedModeBanner: false,
            initialRoute: '/',
            routes: {
              '/': (context) =>
              Storage().settings.showIntro()
                  ? const OnBoardingScreen()
                  : const MainScreen(),
              '/download': (context) => const DownloadScreen(),
              '/documents': (context) => const DocumentsScreen(),
              '/checklists': (context) => const ChecklistScreen(),
              '/performance': (context) => const AircraftPerformanceScreen(),
              '/logbook': (context) => const LogbookScreen(),
              '/pro': (context) => const LoginScreen(),
              if(Constants.shouldShowBluetoothSpp) '/io': (context) => const IoScreen(),
              if(Constants.shouldShowDeviceLink) '/link': (context) => const LinkScreen(),
              '/notes': (context) => const WritingScreen(),
              '/airspace3d': (context) => const Airspace3DScreen(),
              '/pfd': (context) => const PfdScreen(),
              '/plan_actions': (context) => const PlanActionScreen(),
              '/ai': (context) => const AiScreen(),
              '/backup': (context) => const BackupScreen(),
              '/community': (context) => const CommunityScreen(),
              '/scheduler': (context) => const SchedulerScreen(),
              '/popup': (context) {
                  final args = ModalRoute.of(context)!.settings.arguments as List<Destination>;
                  return LongPressScreen(destinations: args);
                }
            },
            theme: value,
          )); // Safe Area so things from OS do not get in the way
        });
    }
  }
