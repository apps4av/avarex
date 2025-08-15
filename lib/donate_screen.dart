import 'package:flutter/material.dart';

class DonateScreen extends StatefulWidget {
  const DonateScreen({super.key});
  @override
  DonateScreenState createState() => DonateScreenState();
}

class DonateScreenState extends State<DonateScreen> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Donate'),
      ),
      body: Center(
        child: Column(children: [Container(padding: EdgeInsets.all(20), child:const Text(""
            "Hey there, high-flyer! This app runs on passion, caffeine, and the occasional miracle - but mostly on your support. "
            "If you’ve enjoyed soaring through our app, help us keep the engines running. Every donation matters.\n\n"
            "To support this app, please copy the following link and paste in your browser. Thank you!")),
            const SelectableText('apps4av.com/donate', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),]),
      ),
    );
  }
}


