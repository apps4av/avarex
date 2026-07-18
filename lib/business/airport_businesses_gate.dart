import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../services/login_screen.dart';
import 'airport_businesses_view.dart';
import 'data/airport_business_repository.dart';
import 'models/airport_business.dart';

/// Single home for the Firebase-backed "Airport Businesses" logic so the
/// plate and long-press screens don't have to touch FirebaseAuth / Firestore
/// directly.
///
/// None of this is gated by Pro — only by whether the cloud backend exists on
/// the platform (Firebase is initialized on iOS/Android only, see main.dart)
/// and whether the pilot is signed in.
class AirportBusinessesGate {
  AirportBusinessesGate._();

  /// Whether the cloud businesses feature can run on this platform.
  static bool get available => Constants.firebaseAvailable;

  /// True when the businesses feature is usable right now (platform supports
  /// the cloud backend and a pilot is signed in).
  static bool get isReady =>
      available && FirebaseAuth.instance.currentUser != null;

  /// Businesses with a map coordinate for the plate airport-diagram overlay.
  /// Best-effort: returns an empty list when the feature isn't available, the
  /// pilot isn't signed in, or the lookup fails.
  static Future<List<AirportBusiness>> businessesForPlate(
      String airport, {LatLng? origin}) async {
    if (!isReady) {
      return const [];
    }
    return AirportBusinessRepository.instance
        .fetchBusinessesWithLocation(airport, origin: origin);
  }
}

/// Content for the airport long-press "Business" tab. When signed in it shows
/// the crowd-sourced businesses/reviews inline (browse, view and review in
/// place); when not signed in it shows a prompt that sends the pilot to
/// sign-in — the only time this feature navigates away. It reacts to auth
/// state so it refreshes in place after signing in.
class AirportBusinessesTab extends StatelessWidget {
  final String airport; // LocationID / FAA id
  final LatLng? origin; // airport coordinate, for nearest-first ordering

  const AirportBusinessesTab({super.key, required this.airport, this.origin});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, _) {
        final signedIn = FirebaseAuth.instance.currentUser != null;
        if (signedIn) {
          return AirportBusinessesView(airport: airport, origin: origin);
        }
        final scheme = Theme.of(context).colorScheme;
        return ListView(
          padding: const EdgeInsets.all(8),
          children: [
            Card(
              color: scheme.primaryContainer,
              child: ListTile(
                leading:
                    Icon(Icons.storefront, color: scheme.onPrimaryContainer),
                title: Text("Businesses & Reviews",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: scheme.onPrimaryContainer)),
                subtitle: Text(
                    "Pilot-contributed FBOs, services, fuel, hours & reviews. Sign in to view and contribute.",
                    style: TextStyle(
                        fontSize: 12, color: scheme.onPrimaryContainer)),
                trailing: Icon(Icons.login, color: scheme.onPrimaryContainer),
                onTap: () =>
                    LoginScreenState.requireSignInThen(context, (_) {}),
              ),
            ),
          ],
        );
      },
    );
  }
}
