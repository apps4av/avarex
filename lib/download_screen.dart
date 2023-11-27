import 'package:flutter/material.dart';
import 'download_list.dart';

class DownloadScreen extends StatelessWidget {
  const DownloadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: DownloadList()),
    );
  }
}