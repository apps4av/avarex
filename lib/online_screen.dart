import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'constants.dart';

class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key});
  @override
  OnlineScreenState createState() => OnlineScreenState();
}

class OnlineScreenState extends State<OnlineScreen> {

  bool _visibleProgressLogin = false;
  bool _visibleProgressLogout = false;
  bool _visibleProgressRegister = false;

  @override
  Widget build(BuildContext context) {

    String email;
    String password;

    (email, password) = Storage().userRealmHelper.loadCredentials();

    bool loggedIn = Storage().userRealmHelper.loggedIn;

    Widget widget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(loggedIn ? "Logged In" : "Sign In", style: const TextStyle(fontSize: 20),),
        const Padding(padding: EdgeInsets.all(20)),
        if(!loggedIn)
          TextFormField(
              onChanged: (value) {
                email = value;
              },
              controller: TextEditingController()..text = email,
              decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Email')
          ),
        if(!loggedIn)
          TextFormField(
              obscureText: true,
              onChanged: (value) {
                password = value;
              },
              controller: TextEditingController()..text = password,
              decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Password')
          ),
        if(Storage().userRealmHelper.failedLoginMessage.isNotEmpty)
          Text(Storage().userRealmHelper.failedLoginMessage, style: const TextStyle(color: Colors.red)),
        if(Storage().userRealmHelper.failedRegisterMessage.isNotEmpty)
          Text(Storage().userRealmHelper.failedRegisterMessage, style: const TextStyle(color: Colors.red)),
          if(!loggedIn)
            Row(children: [TextButton(
                onPressed: () {
                  setState(() {
                    _visibleProgressLogin = true;
                  });
                  Storage().userRealmHelper.saveCredentials(email, password);
                  Storage().userRealmHelper.login(email, password).then((value) => setState(() {
                    _visibleProgressLogin = false;
                  }));
                },
                child: const Text("Login")),
              Visibility(visible: _visibleProgressLogin, child: const CircularProgressIndicator())
            ]),
          if(loggedIn)
            Text("You are currently logged in as $email, and your data is backed up automatically when Internet connection is available."),
          if(loggedIn)
            Row(children: [TextButton(
                onPressed: () {
                  setState(() {
                    _visibleProgressLogout = true;
                  });
                  Storage().userRealmHelper.logout().then((value) => setState(() {
                    _visibleProgressLogout = false;
                  }));
                },
                child: const Text("Logout")),
              Visibility(visible: _visibleProgressLogout, child: const CircularProgressIndicator())
            ]),
          const Padding(padding: EdgeInsets.all(20)),
          if(!loggedIn)
            const Text("Do not have a backup account yet?"),
          if(!loggedIn)
            Row(children: [TextButton(
              onPressed: () {
                setState(() {
                  _visibleProgressRegister = true;
                });
                Storage().userRealmHelper.registerUser(email, password).then((value) {
                  setState(() {
                    _visibleProgressRegister = false;
                  });
                }); // now register with mongodb
              }, child: const Text("Register")),
            Visibility(visible: _visibleProgressRegister, child: const CircularProgressIndicator()),
          ]),
      ],
    );

    return Scaffold(
        appBar: AppBar(
            backgroundColor: Constants.appBarBackgroundColor,
            title: const Text("Online Backup"),
        ),
        body: Container(
          padding: const EdgeInsets.fromLTRB(40, 20, 40, 0),
          child: widget
        )
    );
  }
}

