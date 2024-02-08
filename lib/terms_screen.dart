import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'constants.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {


    String terms = """
This is not an FAA certified GPS. You must assume this software will fail when life and/or property are at risk.
The authors of this software are not liable for any injuries to persons, or damages to aircraft or property including Android devices, related to its use.

** What Information We Collect **

The Apps4Av online service collects identifiable account set-up information in the form of account username (e-mail address). This information must be
provided in order to register and use our platform. The email information
we collect is used for internal verification to complete
registrations / transactions, ensure appropriate legal use of the
service, provide notification to users about updates to the service,
provide notification to users about content upgrade, and help provide
technical support to our users. The privacy of your personal information is very important to us.
We will delete all your information from our records when you unregister from the online service.

** Sharing Your Personal Information **

We do not sell or share your personal information to third parties for
marketing purposes unless you have granted us permission to do so. We
will ask for your permission before we use or share your information
for any purpose other than the reason you provided it or as otherwise
provided by this document. We may also respond to subpoenas, court
orders or legal process by disclosing all your information available to us, if required to do so.

** Security **

We utilize generally accepted security measures (such as encryption / HTTPS) to
protect against the misuse or unauthorized disclosure of any personal
information you submit to us. However, like other Internet sites, we
cannot guarantee that it is completely secure from people who might
attempt to evade security measures or intercept transmissions over
the Internet.

** Enforcement **

If you believe for any reason that we have not followed these privacy
principles, please contact us at apps4av@gmail.com.
and we will act promptly to investigate, correct as appropriate, and
advise you of the correction. Please identify the issue as a Privacy
Policy concern in your communication to apps4av@gmail.com.

** Register/Sign This Document **

The development team for this free aviation app is dedicated to empowering pilots with helpful free, open source, ad-free, and safe tools.
To that end we have decided to require anonymous Registration of users in order to:
 * Advise users immediately in the event we discover any errors in the app or in the FAA materials we process and provide to our users at no charge.
 * Begin offering additional features useful to pilots, such as local airport info and attractions provided by pilots.
 * Enable the potential for future features such as direct anonymous but verified communication between users or devices such as sharing Waypoints, Tracks, and Plans.
 * Ensure that you assume all liability for your use of our free tools more conveniently, without the need to click an agreement at every launch of the app.
 * File flight plans with the FAA.

Do you agree to ALL the above Terms, Conditions, and Privacy Policy?
By clicking "Register" below, you agree to, and sign for ALL the above "Terms, Conditions, and Privacy Policy".
""";

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text("Terms Of Use"),
      ),
      body: SingleChildScrollView(child:
        Container(
          padding: const EdgeInsets.all(10),
          child: Column(children: [
            Text(terms),
            TextButton(onPressed: () {
              Storage().settings.setSign(true);
              Navigator.pop(context);
            },
            child: const Text("Register"), )
          ])
        )
      )
    );
  }
}

