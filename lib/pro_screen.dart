import 'package:avaremp/revenuecat_service.dart';
import 'package:flutter/material.dart';

class ProScreen extends StatefulWidget {
  const ProScreen({super.key});

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _guardAccess();
  }

  Future<void> _guardAccess() async {
    final bool pro = await RevenueCatService().isProUser();
    if (!pro && mounted) {
      Navigator.pushReplacementNamed(context, '/upgrade');
    } else if (mounted) {
      setState(() {
        _checked = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('AvareX Pro'),
      ),
      body: const Center(
        child: Text('Welcome to AvareX Pro features'),
      ),
    );
  }
}

