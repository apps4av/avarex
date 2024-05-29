import 'package:avaremp/progress_button_message_input_widget.dart';
import 'package:avaremp/progress_button_message_widget.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'constants.dart';

class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key});
  @override
  OnlineScreenState createState() => OnlineScreenState();
}

class OnlineScreenState extends State<OnlineScreen> {

  @override
  Widget build(BuildContext context) {

    String email;
    String password;

    (email, password) = Storage().userRealmHelper.loadCredentials();

    bool loggedIn = Storage().userRealmHelper.loggedIn;

    Widget widget = SingleChildScrollView(child:Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.all(20)),
        if(!loggedIn)
          ProgressButtonMessageInputWidget("Sign In", "Email", email, "Password", password, "Login", Storage().userRealmHelper.login, (value) {
            if(value) setState(() {});
          }, ""),
        if(loggedIn)
          ProgressButtonMessageWidget("You are logged in as $email, and your data is backed up automatically when Internet connection is available.", "Logout", Storage().userRealmHelper.logout, const [], (value) {
            if(value) setState(() {});
          }, ""),
        if(!loggedIn)
          ProgressButtonMessageWidget("Do not have a backup account yet?", "Register", Storage().userRealmHelper.registerUser, [email, password], null, "Successfully Registered $email."),

        if(!loggedIn)
          ProgressButtonMessageWidget("Forgot Password?", "Reset Password", Storage().userRealmHelper.resetPasswordRequest, [email], (value) {
            if(value) {
              showDialog<String>(
                context: context,
                builder: (BuildContext context) =>
                  Dialog.fullscreen(
                    child: Stack(children:[
                        Padding(padding: const EdgeInsets.fromLTRB(40, 50, 40, 0),
                        child:ProgressButtonMessageInputWidget(
                          "The request to reset your password has been sent. Check your email for the password reset code. Enter the password reset code a new password here then press Submit to reset your password.", "Password Reset Code", "", "New Password", "", "Submit", Storage().userRealmHelper.resetPassword,
                            (value) {
                              if(value) {
                                setState(() {});
                                Navigator.pop(context);
                              }
                            }, "Your password has been reset.")
                        ),
                        Align(alignment: Alignment.topRight, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 36, color: Colors.white)))
                      ])
                  )
              );
            }
          }, ""),

        // can only delete account if logged in
        if(loggedIn)
          ProgressButtonMessageInputWidget("To delete this account, enter your password and press Submit.", "Email", email, "Password", "", "Submit", Storage().userRealmHelper.deleteAccount,
          (value) {}, "Your account has been deleted."),
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

