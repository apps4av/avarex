import 'package:avaremp/constants.dart';
import 'package:avaremp/services/revenue_cat.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/toast.dart';
import 'package:firebase_auth/firebase_auth.dart' hide EmailAuthProvider;
import 'package:firebase_ui_auth/firebase_ui_auth.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  LoginScreenState createState() => LoginScreenState();
}

class LoginScreenState extends State<LoginScreen> {

  bool isLoggedIn = FirebaseAuth.instance.currentUser != null;
  @override
  void initState() {
    super.initState();
    // add listener for auth state change
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      isLoggedIn = user != null;
    });
  }

  static void showPaywall(BuildContext context, String route) async {
    showPaywallThen(context, (ctx) => Navigator.pushNamed(ctx, route));
  }

  /// Opens a Cloud feature (Backup/Sync, Community, Scheduler).
  /// Sign-in is required so the action is tied to an account. These features
  /// are free — they do not use the Pro paywall.
  static void openCloudFeature(BuildContext context, String route) {
    requireSignInThen(context, (ctx) => Navigator.pushNamed(ctx, route));
  }

  /// Sign-in-only gate (no Pro entitlement required). Runs [onSignedIn] when
  /// the user is authenticated, otherwise sends them to the sign-in screen.
  /// Used by features that are free but still need an accountable identity
  /// (e.g. Airport Businesses & Reviews).
  static void requireSignInThen(
      BuildContext context, void Function(BuildContext context) onSignedIn) {
    if (FirebaseAuth.instance.currentUser == null) {
      Navigator.pushNamed(context, "/pro");
    } else {
      onSignedIn(context);
    }
  }

  /// Like [showPaywall] but runs [onEntitled] once the user is signed in and
  /// has an active Pro entitlement, instead of navigating to a fixed named
  /// route. Used by Flight Intelligence.
  static void showPaywallThen(
      BuildContext context, void Function(BuildContext context) onEntitled) async {
    if(FirebaseAuth.instance.currentUser == null) {
      Navigator.pushNamed(context, "/pro");
    }
    else {
      try {
        RevenueCatService.presentPaywallIfNeeded().then((entitled) {
          if (context.mounted) {
            if (entitled) {
              onEntitled(context);
            }
            else {
              Toast.showToast(
                  context, "Please subscribe before proceeding. Thank you.",
                  Icon(Icons.info, color: Colors.red), 3);
            }
          }
        });
      }
      catch (e) {
        Storage().setException("Unable to initialize Account: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final providers = [EmailAuthProvider()];

    final user = FirebaseAuth.instance.currentUser;
    if(user != null && Constants.shouldShowProServices) {
      RevenueCatService.logIn(
        user.uid,
        email: user.email,
        displayName: user.displayName,
      );
    }

    final accountAppBar = AppBar(
      backgroundColor: Constants.appBarBackgroundColor,
      title: const Text("Account"),
    );

    if (isLoggedIn) {
      return ProfileScreen(
        providers: providers,
        appBar: accountAppBar,
        actions: [
          SignedOutAction((context) {
            setState(() {});
          }),
        ],
      );
    }

    return Scaffold(
        appBar: accountAppBar,
        bottomSheet: const SizedBox(
          height: 58,
          child: Padding(
            padding: EdgeInsets.all(10),
            child: Text("Please register/sign in to access cloud services"),
          ),
        ),
        body: SignInScreen(
          providers: providers,
          actions: [
            AuthStateChangeAction<UserCreated>((context, state) {
              setState(() {});
            }),
            AuthStateChangeAction<SignedIn>((context, state) {
              setState(() {});
            }),
          ],
        )
    );
  }
}
