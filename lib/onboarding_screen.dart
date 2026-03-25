import 'package:avaremp/plan/plan_lmfs.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/unit_conversion.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'main_screen.dart';

import 'package:introduction_screen/introduction_screen.dart';

class OnBoardingScreen extends StatefulWidget {
  const OnBoardingScreen({super.key});

  @override
  OnBoardingScreenState createState() => OnBoardingScreenState();
}

class OnBoardingScreenState extends State<OnBoardingScreen>
    with SingleTickerProviderStateMixin {
  final _introKey = GlobalKey<IntroductionScreenState>();
  bool _visibleRegister = false;
  late AnimationController _bounceController;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _bounceAnimation = Tween<double>(begin: 0, end: 12).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  void _onIntroEnd(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainScreen()),
    );
  }

  Widget _buildImage(String assetName, [double width = 350]) {
    return Image.asset('assets/images/$assetName', width: width);
  }

  Widget _buildFullscreenImage(String assetName) {
    return Image.asset(
      'assets/images/$assetName',
      fit: BoxFit.cover,
      height: double.infinity,
      width: double.infinity,
      alignment: Alignment.center,
    );
  }

  Widget _buildTermsSection(String title, String content) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withAlpha(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            textAlign: TextAlign.left,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.yellow,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            content,
            textAlign: TextAlign.left,
            style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(220)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
      {required IconData icon,
      required String title,
      required String description}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                      fontSize: 13, color: Colors.white.withAlpha(200)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGpsOption(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(number,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: Colors.white.withAlpha(220), fontSize: 13)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool signed = Storage().settings.isSigned();
    String email = Storage().settings.getEmail();
    const bodyStyle = TextStyle(fontSize: 17.0, height: 1.4);

    const pageDecoration = PageDecoration(
      titleTextStyle: TextStyle(
          fontSize: 26.0, fontWeight: FontWeight.bold, color: Colors.white),
      bodyTextStyle: bodyStyle,
      bodyPadding: EdgeInsets.fromLTRB(20.0, 0.0, 20.0, 16.0),
      pageColor: Colors.blueAccent,
      imagePadding: EdgeInsets.zero,
    );

    String gpsEnabledMessage = Storage().gpsDisabled
        ? "Make sure the GPS is enabled on this device."
        : "";
    String gpsDeniedMessage = Storage().gpsNotPermitted
        ? "Make sure the app has permissions to use this device's GPS."
        : "";

    // make GPS page, this requires logic.
    PageViewModel gpsPage = PageViewModel(
      title: "Internet and GPS",
      bodyWidget: Column(
        children: [
          _buildInfoCard(
            icon: Icons.wifi,
            title: "Internet Connection",
            description:
                "Required to download charts and weather. Can be turned off during flight.",
          ),
          _buildInfoCard(
            icon: Icons.gps_fixed,
            title: "GPS Signal",
            description:
                "Make sure you are in an area where GPS signals are strong.",
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.settings_input_antenna,
                        color: Colors.yellow.shade300),
                    const SizedBox(width: 8),
                    const Text(
                      "GPS Sources",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildGpsOption("1", "Grant GPS permissions to the app"),
                _buildGpsOption("2",
                    "External GPS/ADS-B via UDP port 4000, 43211, or 49002"),
                _buildGpsOption("3",
                    "Tap SRC to cycle: Auto → Internal (green) → External (blue)"),
              ],
            ),
          ),

          // GPS status warnings
          if (Storage().gpsNotPermitted || Storage().gpsDisabled)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade700.withAlpha(150),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  if (gpsDeniedMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.warning, color: Colors.yellow),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(gpsDeniedMessage,
                                  style: const TextStyle(color: Colors.white))),
                        ],
                      ),
                    ),
                  if (gpsEnabledMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.warning, color: Colors.yellow),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(gpsEnabledMessage,
                                  style: const TextStyle(color: Colors.white))),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (Storage().gpsNotPermitted)
                        ElevatedButton.icon(
                          onPressed: () => Geolocator.openAppSettings(),
                          icon: const Icon(Icons.settings),
                          label: const Text("GPS Permissions"),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white),
                        ),
                      if (Storage().gpsDisabled)
                        ElevatedButton.icon(
                          onPressed: () => Geolocator.openLocationSettings(),
                          icon: const Icon(Icons.location_on),
                          label: const Text("Enable GPS"),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
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
          bodyWidget:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Scroll indicator at the top (only if not signed)
            if (!signed)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade700,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(60),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.touch_app, color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: const [
                          Text(
                            "Scroll down to sign",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16),
                          ),
                          SizedBox(height: 2),
                          Text(
                            "Press the Sign button at the bottom to proceed",
                            textAlign: TextAlign.center,
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Terms content in a card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                "This is not an FAA certified GPS. You must assume this software will fail when life and/or property are at risk. The authors of this software are not liable for any injuries to persons, or damages to aircraft or property including devices, related to its use.",
                textAlign: TextAlign.left,
                style: TextStyle(fontSize: 15, color: Colors.white),
              ),
            ),
            const SizedBox(height: 16),

            // Privacy sections
            _buildTermsSection("What Information We Collect",
                "The Apps4Av online service collects identifiable account set-up information in the form of account username (e-mail address). This information must be provided in order to register and use our platform."),
            _buildTermsSection("Sharing Your Personal Information",
                "We do not sell or share your personal information to third parties for marketing purposes unless you have granted us permission to do so."),
            _buildTermsSection("Security",
                "We utilize generally accepted security measures (such as encryption / HTTPS) to protect against the misuse or unauthorized disclosure of any personal information you submit to us."),
            _buildTermsSection("Enforcement",
                "If you believe for any reason that we have not followed these privacy principles, please contact us at apps4av@gmail.com."),

            const SizedBox(height: 24),

            // Sign button with animated pointer
            if (!signed)
              Center(
                child: AnimatedBuilder(
                  animation: _bounceAnimation,
                  builder: (context, child) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Transform.translate(
                          offset: Offset(0, -_bounceAnimation.value),
                          child: const Icon(Icons.arrow_downward,
                              color: Colors.yellow, size: 32),
                        ),
                        const SizedBox(height: 8),
                        child!,
                      ],
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.green.shade600, Colors.green.shade800],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withAlpha(100),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(30),
                        onTap: () {
                          setState(() {
                            Storage().settings.setSign(true);
                            Storage().settings.setEmail(email);
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 16),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.check_circle,
                                  color: Colors.white, size: 24),
                              SizedBox(width: 12),
                              Text(
                                "I Agree & Sign",
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Status indicator
            if (signed)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.green.shade700,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      "Signed! Swipe to continue →",
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              )
            else
              Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700.withAlpha(200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    "You must sign to continue",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
          ]),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: "Welcome to AvareX!",
          bodyWidget: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  "This introduction will guide you through the necessary steps to get started with the app.",
                  style: TextStyle(fontSize: 16, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),

              // Theme selection card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withAlpha(40)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.brightness_6, color: Colors.yellow.shade300),
                        const SizedBox(width: 8),
                        const Text(
                          "Display Theme",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.dark_mode,
                            color: !Storage().settings.isLightMode()
                                ? Colors.yellow
                                : Colors.white54),
                        const SizedBox(width: 8),
                        const Text("Night",
                            style: TextStyle(color: Colors.white)),
                        Switch(
                          value: Storage().settings.isLightMode(),
                          activeThumbColor: Colors.yellow,
                          onChanged: (value) {
                            setState(() {
                              Storage().settings.setLightMode(
                                  !Storage().settings.isLightMode());
                              Storage().themeNotifier.value =
                                  Storage().settings.isLightMode()
                                      ? ThemeData.light()
                                      : ThemeData.dark();
                            });
                          },
                        ),
                        const Text("Day",
                            style: TextStyle(color: Colors.white)),
                        const SizedBox(width: 8),
                        Icon(Icons.light_mode,
                            color: Storage().settings.isLightMode()
                                ? Colors.yellow
                                : Colors.white54),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Units selection card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withAlpha(40)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.straighten, color: Colors.yellow.shade300),
                        const SizedBox(width: 8),
                        const Text(
                          "Measurement Units",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Column(
                          children: [
                            Text(
                              "NM / Knots",
                              style: TextStyle(
                                color:
                                    Storage().settings.getUnits() != "Imperial"
                                        ? Colors.yellow
                                        : Colors.white54,
                                fontWeight:
                                    Storage().settings.getUnits() != "Imperial"
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                              ),
                            ),
                            Text("(Maritime)",
                                style: TextStyle(
                                    fontSize: 10, color: Colors.white54)),
                          ],
                        ),
                        Switch(
                          value: Storage().settings.getUnits() == "Imperial",
                          activeThumbColor: Colors.yellow,
                          onChanged: (value) {
                            setState(() {
                              Storage()
                                  .settings
                                  .setUnits(value ? "Imperial" : "Maritime");
                              Storage().units =
                                  UnitConversion(Storage().settings.getUnits());
                            });
                          },
                        ),
                        Column(
                          children: [
                            Text(
                              "SM / MPH",
                              style: TextStyle(
                                color:
                                    Storage().settings.getUnits() == "Imperial"
                                        ? Colors.yellow
                                        : Colors.white54,
                                fontWeight:
                                    Storage().settings.getUnits() == "Imperial"
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                              ),
                            ),
                            Text("(Imperial)",
                                style: TextStyle(
                                    fontSize: 10, color: Colors.white54)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          image: _buildFullscreenImage('intro.png'),
          decoration: pageDecoration,
        ),
        gpsPage,
        PageViewModel(
          title: "Databases and Maps",
          bodyWidget: Column(
            children: [
              _buildInfoCard(
                icon: Icons.download,
                title: "Download Required",
                description:
                    "You must download Databases before using the app.",
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "How to download:",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.yellow,
                          fontSize: 15),
                    ),
                    const SizedBox(height: 12),
                    _buildGpsOption("1", "Press the Download button below"),
                    _buildGpsOption(
                        "2", "Select Databases and any maps you need"),
                    _buildGpsOption("3", "Press Download button (top right)"),
                    _buildGpsOption("4", "Wait for items to turn green"),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(context, "/download"),
                icon: const Icon(Icons.download),
                label: const Text("Open Downloads"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
          image: _buildImage('download.png'),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: "Keep Warnings in Check",
          image: _buildImage('warning.png'),
          bodyWidget: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withAlpha(60),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withAlpha(100)),
            ),
            child: Row(
              children: const [
                Icon(Icons.error, color: Colors.red, size: 32),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "When you see the red warning icon, tap it for troubleshooting. The app may not work properly while warnings are active.",
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: "Optimize Performance",
          image: _buildImage('layers.png'),
          bodyWidget: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: const [
                Icon(Icons.speed, color: Colors.yellow, size: 32),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "For best app performance, turn off unused map layers. Access layers from the layers icon on the map screen.",
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: "File Flight Plans",
          bodyWidget: Column(
            children: [
              _buildInfoCard(
                icon: Icons.flight_takeoff,
                title: "FAA Flight Plans (Optional)",
                description:
                    "Register to file flight plans with the FAA via 1800wxbrief.com. Use the same email you use at 1800wxbrief.com.",
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    TextFormField(
                      onChanged: (value) {
                        email = value;
                      },
                      controller: TextEditingController()..text = email,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              BorderSide(color: Colors.white.withAlpha(100)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.yellow),
                        ),
                        labelStyle: const TextStyle(color: Colors.yellow),
                        labelText: '1800wxbrief.com Email',
                        prefixIcon:
                            const Icon(Icons.email, color: Colors.white54),
                        filled: true,
                        fillColor: Colors.white.withAlpha(10),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (Storage().settings.getEmail().isEmpty)
                      ElevatedButton.icon(
                        onPressed: () {
                          LmfsInterface interface = LmfsInterface();
                          setState(() {
                            _visibleRegister = true;
                          });
                          interface.register(email).then((value) {
                            Storage().settings.setEmail(email);
                            setState(() {
                              _visibleRegister = false;
                            });
                          });
                        },
                        icon: const Icon(Icons.person_add),
                        label: const Text("Register"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                      ),
                    if (Storage().settings.getEmail().isNotEmpty)
                      Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.green.withAlpha(60),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.check_circle,
                                    color: Colors.green, size: 18),
                                SizedBox(width: 8),
                                Text("Registered",
                                    style: TextStyle(color: Colors.white)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () {
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
                            },
                            child: const Text("Unregister",
                                style: TextStyle(color: Colors.yellow)),
                          ),
                        ],
                      ),
                    if (_visibleRegister)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: CircularProgressIndicator(color: Colors.yellow),
                      ),
                  ],
                ),
              ),
            ],
          ),
          decoration: pageDecoration,
        ),
        PageViewModel(
          title: "Join the Community",
          bodyWidget: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(20),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.forum, color: Colors.yellow, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      "Get 24/7 Help & Support",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Join our community forum for tips, help, and discussions with other pilots.",
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const SelectableText(
                        "https://groups.google.com/g/apps4av-forum",
                        style: TextStyle(color: Colors.yellow, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
