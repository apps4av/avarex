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

    (email, password) = Storage().realmHelper.loadCredentials();

    bool loggedIn = Storage().realmHelper.loggedIn;

    Widget widget = SingleChildScrollView(child:Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.all(20)),
        if(!loggedIn)
          ProgressButtonMessageInputWidget("Sign In", "Email", email, "Password", password, "Login", Storage().realmHelper.login, (result, input1, input2) {
            Storage().settings.setEmailBackup(input1);
            Storage().settings.setPasswordBackup(input2);
            if(result) {
              setState(() {
              });
            };
          }, ""),
        if(loggedIn)
          ProgressButtonMessageWidget("You are logged in as $email, and your data is backed up automatically when Internet connection is available.", "Logout", Storage().realmHelper.logout, const [], (value) {
            if(value) setState(() {});
          }, ""),

        if(!loggedIn)
          ProgressButtonMessageWidget("Do not have a backup account yet?", "Register", (args) {
              showDialog<String>(
                  context: context,
                  builder: (BuildContext context) =>
                      Dialog.fullscreen(
                          child: Stack(children:[
                            Padding(padding: const EdgeInsets.fromLTRB(40, 50, 40, 0),
                                child:ProgressButtonMessageInputWidget(
                                    "To register a new account, enter an email and password then press Submit.", "Email", email, "Password", password, "Submit", Storage().realmHelper.registerUser,
                                        (result, input1, input2) {
                                          if(result) {
                                            setState(() {
                                              Storage().settings.setEmailBackup(input1);
                                              Storage().settings.setPasswordBackup(input2);
                                            });
                                          };
                                        },
                                    "You are now registered.")
                            ),
                            Align(alignment: Alignment.topRight, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 36)))
                          ])
                      )
              );
              return Future(() => "");
            }, const [], (value) {}, ""),

        if(!loggedIn)
          ProgressButtonMessageWidget("Forgot Password?", "Reset Password", Storage().realmHelper.resetPasswordRequest, [email], (value) {
            if(value) {
              showDialog<String>(
                context: context,
                builder: (BuildContext context) =>
                  Dialog.fullscreen(
                    child: Stack(children:[
                        Padding(padding: const EdgeInsets.fromLTRB(40, 50, 40, 0),
                        child:ProgressButtonMessageInputWidget(
                          "The request to reset your password has been sent to $email. Check your email for the password reset code. Enter the password reset code and a new password then press Submit to reset your password.", "Password Reset Code", "", "New Password", "", "Submit", Storage().realmHelper.resetPassword,
                            (result, input1, input2) {
                              if(result) {
                                setState(() {});
                              }
                            }, "Your password has been reset.")
                        ),
                        Align(alignment: Alignment.topRight, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 36)))
                      ])
                  )
              );
            }
          }, ""),

        // can only delete account if logged in
        if(loggedIn)

          ProgressButtonMessageWidget("Do you want to delete the account?", "Proceed", (args) {
            showDialog<String>(
                context: context,
                builder: (BuildContext context) =>
                    Dialog.fullscreen(
                        child: Stack(children:[
                          Padding(padding: const EdgeInsets.fromLTRB(40, 50, 40, 0),
                              child: ProgressButtonMessageInputWidget("To delete $email account, enter 'delete' in Confirm, enter password, then press Submit.", "Confirm", "", "Password", "", "Submit", Storage().realmHelper.deleteAccount,
                                (result, input1, input2) {
                                  Storage().realmHelper.logout([]).then((value) => setState(() {}));
                                }, "Your account has been deleted."),
                          ),
                          Align(alignment: Alignment.topRight, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 36)))
                        ])
                    )
            );
            return Future(() => "");
          }, const [], (value) {}, ""),
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

