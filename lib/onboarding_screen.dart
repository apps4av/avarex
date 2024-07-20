import 'package:avaremp/plan_lmfs.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/unit_conversion.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'main_screen.dart';

import 'package:introduction_screen/introduction_screen.dart';


class OnBoardingScreen extends StatefulWidget {
  const OnBoardingScreen({super.key});

  @override
  OnBoardingScreenState createState() => OnBoardingScreenState();
}

class OnBoardingScreenState extends State<OnBoardingScreen> {
  final _introKey = GlobalKey<IntroductionScreenState>();
  bool _visibleRegister = false;

  void _onIntroEnd(context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainScreen()),
    );
  }

  Widget _buildImage(String assetName, [double width = 350]) {
    return Image.asset('assets/images/$assetName', width: width);
  }

  Widget _buildFullscreenImage(String assetName) {
    return Image.asset('assets/images/$assetName', fit: BoxFit.cover, height: double.infinity, width: double.infinity, alignment: Alignment.center,);
  }

  @override
  Widget build(BuildContext context) {
    bool signed = Storage().settings.isSigned();
    String email = Storage().settings.getEmail();
    const bodyStyle = TextStyle(fontSize: 19.0);

    const pageDecoration = PageDecoration(
      titleTextStyle: TextStyle(fontSize: 28.0, fontWeight: FontWeight.w700),
      bodyTextStyle: bodyStyle,
      bodyPadding: EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 16.0),
      pageColor: Colors.blueAccent,
      imagePadding: EdgeInsets.zero,
    );

    String gpsEnabledMessage = Storage().gpsDisabled ? "Make sure the GPS is enabled on this device." : "";
    String gpsDeniedMessage = Storage().gpsNotPermitted ? "Make sure the app has permissions to use this device's GPS." : "";

    // make GPS page, this requires logic.
    PageViewModel gpsPage = PageViewModel(
      title: "Internet and GPS",
      bodyWidget: Column(
          children:[
            const Text("Connect this device to the Internet. Internet connection is required to download charts and weather. The connection may be turned off during the flight.\n\n\n"
              "Make sure you are in an area where GPS signals are strong.\n\n"
              "The app uses the best possible GPS source available on this device.\n"
              " 1) You must provide the app with permissions to access the GPS.\n"
              " 2) You may connect your external GPS/ADS-B receiver to UDP port 4000, 43211, or 49002.\n"),
              Text("$gpsDeniedMessage\n$gpsEnabledMessage\n"),
              Storage().gpsNotPermitted ? TextButton(onPressed: () { Geolocator.openAppSettings(); }, child: const Text("GPS Permissions"),) : Container(),
              Storage().gpsDisabled ? TextButton(onPressed: () { Geolocator.openLocationSettings(); }, child: const Text("Enable GPS")) : Container(),
          ]
      ),

      decoration: pageDecoration,
    );

    // make GPS page, this requires logic.
    PageViewModel unitsPage = PageViewModel(
      title: "Units",
      bodyWidget: Column(
          children:[
            Text("Select your preferred distance, speed, and elevation units (${Storage().settings.getUnits()})\n"),
            Switch(value: Storage().settings.getUnits() == "Maritime", onChanged: (value) {
              setState(() {
                if(value == true) {
                  Storage().settings.setUnits("Maritime");
                } else {
                  Storage().settings.setUnits("Imperial");
                }
                Storage().units = UnitConversion(Storage().settings.getUnits());
              });
            }),
          ]
      ),
      decoration: pageDecoration,
    );

    return IntroductionScreen(
      key: _introKey,
      globalBackgroundColor: Colors.white,
      allowImplicitScrolling: false,
      safeAreaList: const [false, false, true, false],
      pages: [
        PageViewModel(
          title: "Sign the Terms of Use",
          bodyWidget: Column(children: [
            const Text(
                """
** YOU MUST FULLY READ, AGREE TO, AND SIGN THIS AGREEMENT TO CONTINUE. **\n\n
This is not an FAA certified GPS. You must assume this software will fail when life and/or property are at risk. The authors of this software are not liable for any injuries to persons, or damages to aircraft or property including Android devices, related to its use.

** What Information We Collect **

The Apps4Av online service collects identifiable account set-up information in the form of account username (e-mail address). This information must be provided in order to register and use our platform. The email information we collect is used for internal verification to complete registrations / transactions, ensure appropriate legal use of the service, provide notification to users about updates to the service, provide notification to users about content upgrade, and help provide technical support to our users. The privacy of your personal information is very important to us. We will delete all your information from our records when you unregister from the online service.

** Sharing Your Personal Information **

We do not sell or share your personal information to third parties for marketing purposes unless you have granted us permission to do so. We will ask for your permission before we use or share your information for any purpose other than the reason you provided it or as otherwise provided by this document. We may also respond to subpoenas, court orders or legal process by disclosing all your information available to us, if required to do so.

** Security **

We utilize generally accepted security measures (such as encryption / HTTPS) to protect against the misuse or unauthorized disclosure of any personal information you submit to us. However, like other Internet sites, we cannot guarantee that it is completely secure from people who might attempt to evade security measures or intercept transmissions over the Internet.

** Enforcement **

If you believe for any reason that we have not followed these privacy principles, please contact us at apps4av@gmail.com and we will act promptly to investigate, correct as appropriate, and advise you of the correction. Please identify the issue as a Privacy Policy concern in your communication to apps4av@gmail.com.

** Register/Sign This Document **

The development team for this free aviation app is dedicated to empowering pilots with helpful free, open source, ad-free, and safe tools. To that end we have decided to require anonymous Registration of users in order to:
 * Advise users immediately in the event we discover any errors in the app or in the FAA materials we process and provide to our users at no charge.
 * Begin offering additional features useful to pilots, such as local airport info and attractions provided by pilots.
 * Enable the potential for future features such as direct anonymous but verified communication between users or devices such as sharing Waypoints, Tracks, and Plans.
 * Ensure that you assume all liability for your use of our free tools more conveniently, without the need to click an agreement at every launch of the app.
 * File flight plans with the FAA.

Do you agree to ALL the above Terms, Conditions, and Privacy Policy? By clicking "Tap here to sign" below, you agree to, and sign for ALL the above "Terms, Conditions, and Privacy Policy".
"""
            ),
            Padding(padding: const EdgeInsets.all(20), child:TextButton(
              onPressed: () {
                setState(() {
                  Storage().settings.setSign(true);
                  Storage().settings.setEmail(email);
                });
              },
              child: const Padding(padding: EdgeInsets.all(20), child:Text("Tap here to sign", style: TextStyle(fontSize: 20, color: Colors.yellow),)),
            )),
            if(signed)
              const Text("You have signed this document. Please continue on to the next screen.", style: TextStyle(color: Colors.yellow, backgroundColor: Colors.black),)
            else
              const Text("You have not signed this document.", style: TextStyle(color: Colors.red, backgroundColor: Colors.black),)
          ]),
          decoration: pageDecoration,
        ),

        PageViewModel(
          title: "Welcome to AvareX!",
          body: "This introduction will show you the necessary steps to operate the app.",
          image: _buildFullscreenImage('intro.png'),
          decoration: pageDecoration,
        ),
        gpsPage,
        unitsPage,
        PageViewModel(
          title: "Databases and Aviation Maps",
          bodyWidget: Column(children:[
            const Text("You must download Databases.\nPress the Download button below, then select Databases to show the download icon. Select any other maps you wish to download.\nPress the Start button on top right. Wait for the selected items to turn green.\nIf you exit the download screen before the downloading is complete, the app will abort all incomplete downloads."),
            TextButton(onPressed: () {
                Navigator.pushNamed(context, "/download");
              },
              child: const Text("Download"),
            )
          ]),
          image: _buildImage('download.png'),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: "Keep Warnings in Check",
          image: _buildImage('warning.png'),
          bodyWidget: const Text("Any time you see this red warning icon in the app, click on it for troubleshooting. The app may not work properly when this icon is visible."),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: "Turn off the Layers",
          image: _buildImage('layers.png'),
          bodyWidget: const Text("For optimum app performance, turn off unused layers."),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: "File Flight Plans",
          bodyWidget: Column(children:[
            const Text("You may optionally choose to register with Apps4Av Inc. here to file flight plans with the FAA (1800wxbrief.com). Use the same email ID that you use at 1800wxbrief.com."),
            const Padding(padding: EdgeInsets.all(10)),
            TextFormField(
                onChanged: (value) {
                  email = value;
                },
                controller: TextEditingController()..text = email,
                decoration: const InputDecoration(border: UnderlineInputBorder(), labelStyle: TextStyle(color: Colors.yellow), labelText: '1800wxbrief.com Username / Email')
            ),
            const Padding(padding: EdgeInsets.all(20)),
            if(Storage().settings.getEmail().isEmpty)
              TextButton(onPressed: () {
                LmfsInterface interface = LmfsInterface();
                setState(() {
                  _visibleRegister = true;
                });
                interface.register(email).then((value) {
                  Storage().settings.setEmail(email);
                  setState(() {
                    _visibleRegister = false;
                  });
                }); // now register with mongodb
                },
                child: const Text("Register", style: TextStyle(color: Colors.yellow, fontSize: 20)),),
            if(Storage().settings.getEmail().isNotEmpty)
              TextButton(onPressed: () {
                LmfsInterface interface = LmfsInterface();
                setState(() {
                  _visibleRegister = true;
                });
                interface.unregister(email).then((value) {
                  Storage().settings.setEmail("");
                  setState(() {
                    _visibleRegister = false;
                  });
                });
              }, child: const Text("Unregister", style: TextStyle(color: Colors.yellow, fontSize: 20),)),
             Visibility(visible: _visibleRegister, child: const CircularProgressIndicator()),
          ]),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: "Join the Forum",
          bodyWidget: const SelectableText("For 24/7 help, join our forum\n\nhttps://groups.google.com/g/apps4av-forum"),
          image: _buildImage('forum.png'),
          decoration: pageDecoration,
        ),
      ],
      skipOrBackFlex: 0,
      nextFlex: 0,
      freeze: !signed,
      showNextButton: signed,
      showBackButton: signed,
      showDoneButton: signed,
      done: const Text("Done"),
      onDone: () {
        Storage().settings.setIntro(false);
        _onIntroEnd(context);
      },
      //rtl: true, // Display as right-to-left
      back: const Icon(Icons.arrow_back),
      next: const Icon(Icons.arrow_forward),
      curve: Curves.fastLinearToSlowEaseIn,
      controlsMargin: const EdgeInsets.all(16),
      controlsPadding: const EdgeInsets.fromLTRB(8.0, 4.0, 8.0, 4.0),
      dotsDecorator: const DotsDecorator(
        size: Size(10.0, 10.0),
        color: Color(0xFFBDBDBD),
        activeSize: Size(22.0, 10.0),
        activeShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(25.0)),
        ),
      ),
      dotsContainerDecorator: const ShapeDecoration(
        color: Colors.black87,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8.0)),
        ),
      ),
    );
  }
}

