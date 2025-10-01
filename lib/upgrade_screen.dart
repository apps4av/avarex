import 'package:avaremp/revenuecat_service.dart';
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class UpgradeScreen extends StatefulWidget {
  const UpgradeScreen({super.key});

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  Offerings? _offerings;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    try {
      final Offerings offerings = await Purchases.getOfferings();
      setState(() {
        _offerings = offerings;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _purchase(Package package) async {
    try {
      await Purchases.purchasePackage(package);
      await RevenueCatService().refreshCustomerInfo();
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upgrade to Pro')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _offerings == null
                  ? const Center(child: Text('No offerings available'))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (_offerings!.current != null)
                          ..._offerings!.current!.availablePackages.map((p) {
                            final product = p.storeProduct;
                            return Card(
                              child: ListTile(
                                title: Text(product.title),
                                subtitle: Text(product.description),
                                trailing: Text(product.priceString),
                                onTap: () => _purchase(p),
                              ),
                            );
                          })
                        else
                          const Text('No current offering configured')
                      ],
                    ),
    );
  }
}

