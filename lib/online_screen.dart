import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'constants.dart';

class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key});
  @override
  OnlineScreenState createState() => OnlineScreenState();
}

class OnlineScreenState extends State<OnlineScreen> {

  bool _visibleRegister = false;

  @override
  Widget build(BuildContext context) {

    String email;
    String password;

    (email, password) = Storage().userRealmHelper.loadCredentials();
    String confirmPassword = "";

    return Scaffold(
        appBar: AppBar(
            backgroundColor: Constants.appBarBackgroundColor,
            title: const Text("Online Backup"),
            actions: []
        ),
        body: Container(
          padding: const EdgeInsets.fromLTRB(40, 20, 40, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Sign In", style: TextStyle(fontSize: 20),),
              const Padding(padding: EdgeInsets.all(20)),
              TextFormField(
                  onChanged: (value) {
                    email = value;
                  },
                  controller: TextEditingController()..text = email,
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Email')
              ),
              TextFormField(
                  obscureText: true,
                  onChanged: (value) {
                    password = value;
                  },
                  controller: TextEditingController()..text = password,
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Password')
              ),
              const Padding(padding: EdgeInsets.all(20)),
              TextButton(
                onPressed: () {
                  Storage().userRealmHelper.init();
                },
                child: const Text("Login")),
              const Padding(padding: EdgeInsets.all(20)),
              const Text("Do not have an account yet?"),
              TextFormField(
                  obscureText: true,
                  onChanged: (value) {
                    confirmPassword = value;
                  },
                  controller: TextEditingController()..text = confirmPassword,
                  decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Confirm Password')
              ),
              const Padding(padding: EdgeInsets.all(20)),
              TextButton(
                onPressed: () {
                  Storage().userRealmHelper.registerUser(email, password).then((value) {
                    setState(() {
                      _visibleRegister = false;
                      Storage().userRealmHelper.saveCredentials(email, password);
                    });
                  }); // now register with mongodb
              }, child: const Text("Register")),
              Visibility(visible: _visibleRegister, child: const CircularProgressIndicator()),
            ],
          )

        )
    );
  }
}

