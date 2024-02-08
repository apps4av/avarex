
import 'package:avaremp/storage.dart';
import 'package:avaremp/terms_screen.dart';
import 'package:flutter/material.dart';
import 'download_screen.dart';
import 'main_screen.dart';

import 'package:introduction_screen/introduction_screen.dart';

void main()  {

  Storage().init().then((accentColor) {
    runApp(const MainApp());
  });

}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => Storage().settings.showIntro() ? const OnBoardingPage() : const MainScreen(),
        '/download': (context) => const DownloadScreen(),
        '/terms': (context) => const TermsScreen(),
      },
      theme : ThemeData(
        brightness: Brightness.dark,
      ),
    );
  }
}



class OnBoardingPage extends StatefulWidget {
  const OnBoardingPage({super.key});

  @override
  OnBoardingPageState createState() => OnBoardingPageState();
}

class OnBoardingPageState extends State<OnBoardingPage> {
  final introKey = GlobalKey<IntroductionScreenState>();

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
    const bodyStyle = TextStyle(fontSize: 19.0);

    const pageDecoration = PageDecoration(
      titleTextStyle: TextStyle(fontSize: 28.0, fontWeight: FontWeight.w700),
      bodyTextStyle: bodyStyle,
      bodyPadding: EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 16.0),
      pageColor: Colors.blueAccent,
      imagePadding: EdgeInsets.zero,
    );

    return IntroductionScreen(
      key: introKey,
      globalBackgroundColor: Colors.white,
      allowImplicitScrolling: false,
      pages: [
        PageViewModel(
          title: "Welcome to AvareMP!",
          body: "This introduction will show you the necessary steps to operate the app in the most effective manner.",
          image: _buildFullscreenImage('intro.png'),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: "GPS",
          body: "Make sure the app has permissions to use this device's GPS, GPS is enabled on this device, and you are in an area where GPS signals are strong.\n If you do not know how to setup the GPS, click on the red warnings icon.",
          image: _buildImage('warnings.png'),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: "Internet",
          body: "Connect this device to Internet.\nOn the Wi-Fi setting, choose the Wi-Fi network you want, connect to it.\nMake sure the Internet is available on this network.",
          image: _buildImage('wifi.png'),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: "Databases and Aviation Maps",
          body: "Click the Menu button, then select Download.\nSelect Databases to show the download icon. Select any other maps you wish to download.\nPress the download button on top right. Wait for the selected items to turn green. ",
          image: _buildImage('download.png'),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: "Sign the Terms of Use",
          body: "You must sign the Terms of Use to use this app.\nClick the red warnings icon, then select Sign Terms of Use. Review the document, then click Register. If you do not agree with the document, do not continue, then uninstall this app.",
          image: _buildImage('terms.png'),
          decoration: pageDecoration,
        ),
      ],
      onDone: () {_onIntroEnd(context); },
      skipOrBackFlex: 0,
      nextFlex: 0,
      showBackButton: true,
      //rtl: true, // Display as right-to-left
      back: const Icon(Icons.arrow_back),
      next: const Icon(Icons.arrow_forward),
      done: const Text('Done', style: TextStyle(fontWeight: FontWeight.w600)),
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
