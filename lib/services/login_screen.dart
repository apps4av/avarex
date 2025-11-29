import 'package:avaremp/constants.dart';
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

  @override
  Widget build(BuildContext context) {
    final providers = [EmailAuthProvider()];

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
                onPressed: () async {
                  Navigator.pushNamed(context, '/ai');
                },
              ),
              TextButton(
                child: const Text("Backup/Sync"),
                onPressed: () async {
                  Navigator.pushNamed(context, '/backup');
                },
              ),
            ],
          ) : Padding(padding: EdgeInsets.all(10), child:Text("Please sign in to access Pro Services")),
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
