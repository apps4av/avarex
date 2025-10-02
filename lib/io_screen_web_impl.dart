import 'package:flutter/material.dart';

class IoScreen extends StatelessWidget {
  const IoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      appBar: AppBar(title: Text('IO (Bluetooth)')),
      body: Center(child: Text('Bluetooth SPP is not supported on web.')),
    );
  }
}

