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
  bool _visibleProgressResetPassword = false;

  @override
  Widget build(BuildContext context) {

    String email;
    String password;

    (email, password) = Storage().userRealmHelper.loadCredentials();

    bool loggedIn = Storage().userRealmHelper.loggedIn;

    Widget widget = SingleChildScrollView(child:Column(
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
            Text("You are currently logged in as $email, and your data is backed up automatically when Internet connection is available.\nTo delete this account, along with the app's backed up data, send an email to apps4av@gmail.com, with Subject 'Delete Account'."),
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
        const Padding(padding: EdgeInsets.all(10)),
        if(!loggedIn)
          const Text("Forgot password?"),
        if(!loggedIn)
          Row(children: [
            TextButton(
              onPressed: () {
                setState(() {
                  _visibleProgressResetPassword = true;
                });
                Storage().userRealmHelper.resetPasswordRequest(email).then((value) {
                  setState(() {
                    String newPassword = "";
                    String passwordResetCode = "";
                    _visibleProgressResetPassword = false;
                    showDialog<String>(
                      context: context,
                      builder: (BuildContext context) => Dialog.fullscreen(
                          child: Stack(children:[
                            Padding(padding: const EdgeInsets.fromLTRB(40, 50, 40, 0),
                              child:Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("The request to reset your password has been sent. Check your email for the password reset code. Enter a new password, and the password reset code here then press Submit to reset your password."),
                                  TextFormField(
                                    obscureText: true,
                                    onChanged: (value) {
                                      newPassword = value;
                                    },
                                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'New password')
                                  ),

                                  TextFormField(
                                    onChanged: (value) {
                                      passwordResetCode = value;
                                    },
                                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Password reset code')
                                  ),

                                  TextButton(
                                    onPressed: () {
                                      Storage().userRealmHelper.resetPassword(newPassword, passwordResetCode).then((value) {
                                        if(value) {
                                          Navigator.pop(context);
                                        }
                                      }); // now register with mongodb
                                    },
                                    child: const Text('Submit'),
                                  ),
                                ],
                              )
                          ),
                          Align(alignment: Alignment.topRight, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 36, color: Colors.white)))
                        ])
                      )
                    );
                });
              }); // now show dialog

              }, child: const Text("Reset Password")),
            Visibility(visible: _visibleProgressResetPassword, child: const CircularProgressIndicator()),
          ]),
        const Padding(padding: EdgeInsets.all(10)),
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
    ));

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

