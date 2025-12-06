import 'package:avaremp/constants.dart';
import 'package:avaremp/map_screen.dart';
import 'package:avaremp/services/revenue_cat.dart';
import 'package:avaremp/storage.dart';
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

  void _showPaywall(String route) async {
      try {
        RevenueCatService.presentPaywallIfNeeded().then((entitled) {
          if (mounted) {
            if (entitled) {
              Navigator.pushNamed(context, route);
            }
            else {
              MapScreenState.showToast(context, "Please subscribe before proceeding. Thank you.",
                  Icon(Icons.info, color: Colors.red), 3);
            }
          }
        });
      }
      catch(e) {
        Storage().setException("Unable to initialize Pro Services: $e");
      }
  }

  @override
  Widget build(BuildContext context) {
    final providers = [EmailAuthProvider()];

    if(FirebaseAuth.instance.currentUser != null) {
      RevenueCatService.logIn(FirebaseAuth.instance.currentUser!.uid);
    }

    return Scaffold(
        appBar: AppBar(
            backgroundColor: Constants.appBarBackgroundColor,
            title: const Text("Pro Services"),
        ),
        bottomSheet: SizedBox(
          height: 50,
          child: isLoggedIn ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                child: const Text("Flight Intelligence"),
                onPressed: () {
                  // Offerings and purchase options
                  _showPaywall('/ai');
                },
              ),
              TextButton(
                child: const Text("Backup/Sync"),
                onPressed: () {
                  _showPaywall('/backup');
                },
              ),
            ],
          ) : Padding(padding: EdgeInsets.all(10), child:Text("Please register/sign in to access Pro Services")),
        ),
        body: isLoggedIn ?
          ProfileScreen(
            providers: providers,
            actions: [
              SignedOutAction((context) {
                setState(() {});
              }),
            ],
          ) :
          SignInScreen(
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
