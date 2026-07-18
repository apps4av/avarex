import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../utils/toast.dart';
import 'data/airport_business_repository.dart';
import 'models/airport_business.dart';
import 'models/business_review.dart';
import 'widgets/business_form.dart';
import 'widgets/star_rating.dart';

/// Inline, self-contained view of the crowd-sourced businesses/FBOs for a
/// single airport. It is embedded directly (e.g. in the airport long-press
/// "Business" tab) rather than pushed as a separate screen: the whole
/// browse → view details → review flow happens in place, using modal sheets
/// for add/edit/review actions. No navigation to a new screen occurs here.
///
/// Reading requires a signed-in user (enforced by Firestore rules), so this
/// view should only be shown to authenticated users; callers gate it and send
/// unauthenticated users to sign-in instead.
class AirportBusinessesView extends StatelessWidget {
  final String airport; // LocationID / FAA id
  final LatLng? origin; // airport coordinate, for nearest-first ordering
  const AirportBusinessesView(
      {super.key, required this.airport, this.origin});

  String get _airport => airport.trim().toUpperCase();

  Future<void> _addBusiness(BuildContext context) async {
    final result = await showModalBottomSheet<BusinessFormResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BusinessFormSheet(
        title: "Add Business at $_airport",
        requireName: true,
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      await AirportBusinessRepository.instance.addBusiness(
        airport: _airport,
        name: result.name,
        services: result.services,
        fuelTypes: result.fuelTypes,
        operatingHours: result.operatingHours,
        phoneNumber: result.phoneNumber,
        radioFrequency: result.radioFrequency,
      );
      if (context.mounted) {
        Toast.showToast(context, "Business added. Thank you!",
            const Icon(Icons.check_circle, color: Colors.green), 2);
      }
    } catch (e) {
      if (context.mounted) {
        Toast.showToast(context, "Could not add business: $e",
            const Icon(Icons.error, color: Colors.red), 3);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AirportBusiness>>(
      stream: AirportBusinessRepository.instance
          .watchBusinesses(_airport, origin: origin),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorView(error: snapshot.error.toString());
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "Businesses at $_airport",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _addBusiness(context),
                    icon: const Icon(Icons.add_business, size: 18),
                    label: const Text("Add"),
                  ),
                ],
              ),
            ),
            if (items.isEmpty)
              _EmptyView(airport: _airport)
            else
              for (final b in items) _BusinessTile(business: b),
          ],
        );
      },
    );
  }
}

/// A single business rendered as an expandable tile. Collapsed it shows the
/// name, a summary of fuel/services and its average rating; expanded it shows
/// the full detail card, an edit action, and the inline list of reviews with
/// an add-review action.
class _BusinessTile extends StatefulWidget {
  final AirportBusiness business;
  const _BusinessTile({required this.business});

  @override
  State<_BusinessTile> createState() => _BusinessTileState();
}

class _BusinessTileState extends State<_BusinessTile> {
  final _repo = AirportBusinessRepository.instance;
  BusinessStats? _stats;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final stats = await _repo.fetchStats(widget.business.id);
    if (mounted) setState(() => _stats = stats);
  }

  Future<void> _editDetails(AirportBusiness biz) async {
    final result = await showModalBottomSheet<BusinessFormResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BusinessFormSheet(
        title: "Edit ${biz.name}",
        requireName: false,
        initialName: biz.name,
        initialServices: biz.services,
        initialFuelTypes: biz.fuelTypes,
        initialHours: biz.operatingHours,
        initialPhone: biz.phoneNumber,
        initialFrequency: biz.radioFrequency,
      ),
    );
    if (result == null || !mounted) return;
    try {
      await _repo.updateDetails(
        biz.id,
        services: result.services,
        fuelTypes: result.fuelTypes,
        operatingHours: result.operatingHours,
        phoneNumber: result.phoneNumber,
        radioFrequency: result.radioFrequency,
      );
      if (mounted) {
        Toast.showToast(context, "Details updated. Thank you!",
            const Icon(Icons.check_circle, color: Colors.green), 2);
      }
    } catch (e) {
      if (mounted) {
        Toast.showToast(context, "Could not update: $e",
            const Icon(Icons.error, color: Colors.red), 3);
      }
    }
  }

  Future<void> _setFuelPrices(AirportBusiness biz) async {
    final result = await showModalBottomSheet<Map<String, double>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FuelPriceSheet(business: biz),
    );
    if (result == null || !mounted) return;
    try {
      await _repo.setFuelPrices(
        biz.id,
        prices: result,
        previous: biz.fuelPrices,
      );
      if (mounted) {
        Toast.showToast(context, "Fuel prices updated. Thank you!",
            const Icon(Icons.check_circle, color: Colors.green), 2);
      }
    } catch (e) {
      if (mounted) {
        Toast.showToast(context, "Could not update prices: $e",
            const Icon(Icons.error, color: Colors.red), 3);
      }
    }
  }

  Future<void> _addReview(AirportBusiness biz) async {
    final result = await showModalBottomSheet<_ReviewInput>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ReviewSheet(),
    );
    if (result == null || !mounted) return;
    try {
      await _repo.addReview(biz.id, rating: result.rating, text: result.text);
      // Refresh the collapsed-summary rating after a successful post.
      await _loadStats();
      if (mounted) {
        Toast.showToast(context, "Review posted. Thank you!",
            const Icon(Icons.check_circle, color: Colors.green), 2);
      }
    } catch (e) {
      if (mounted) {
        final msg = e is StateError ? e.message : e.toString();
        Toast.showToast(context, "Could not post review: $msg",
            const Icon(Icons.error, color: Colors.red), 3);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final biz = widget.business;
    final scheme = Theme.of(context).colorScheme;
    final stats = _stats;

    final summaryBits = <String>[];
    if (biz.fuelTypes.isNotEmpty) {
      summaryBits.add("Fuel: ${biz.fuelTypes.join(", ")}");
    }
    if (biz.services.isNotEmpty) {
      summaryBits.add("${biz.services.length} service(s)");
    }

    return Card(
      child: Theme(
        // Remove ExpansionTile's default divider lines for a cleaner card.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(Icons.business, color: scheme.primary),
          title: Row(
            children: [
              Flexible(
                child: Text(biz.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ),
              if (biz.hasUserActivity) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: "Created, updated or reviewed by a pilot",
                  child: Icon(Icons.verified_user,
                      size: 15, color: scheme.primary),
                ),
              ],
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (summaryBits.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(summaryBits.join("  •  "),
                      style: const TextStyle(fontSize: 12)),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    StarRating(rating: stats?.averageRating ?? 0, size: 15),
                    const SizedBox(width: 6),
                    Text(
                      stats == null
                          ? "…"
                          : (stats.hasReviews
                              ? "${stats.averageRating.toStringAsFixed(1)} (${stats.reviewCount})"
                              : "No reviews"),
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  ],
                ),
              ),
            ],
          ),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("${biz.airport}  •  added by ${biz.createdByName}",
                style: TextStyle(fontSize: 12, color: scheme.outline)),
            if (biz.lastEditedByName != null &&
                biz.lastEditedByName!.isNotEmpty)
              Text("Details last updated by ${biz.lastEditedByName}",
                  style: TextStyle(fontSize: 12, color: scheme.outline)),
            const SizedBox(height: 8),
            _detailCard(biz),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => _editDetails(biz),
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text("Edit details"),
                ),
                TextButton.icon(
                  onPressed: () => _setFuelPrices(biz),
                  icon: const Icon(Icons.local_gas_station, size: 18),
                  label: const Text("Set fuel prices"),
                ),
              ],
            ),
            const Divider(),
            _reviews(biz),
          ],
        ),
      ),
    );
  }

  Widget _detailCard(AirportBusiness biz) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailRow(Icons.local_gas_station, "Fuel",
            biz.fuelTypes.isEmpty ? null : biz.fuelTypes.join(", ")),
        _fuelPricesRow(biz),
        _detailRow(Icons.build, "Services",
            biz.services.isEmpty ? null : biz.services.join(", ")),
        _detailRow(Icons.schedule, "Operating hours",
            biz.operatingHours.isEmpty ? null : biz.operatingHours),
        _detailRow(Icons.phone, "Phone",
            biz.phoneNumber.isEmpty ? null : biz.phoneNumber),
        _detailRow(Icons.radio, "Radio frequency",
            biz.radioFrequency.isEmpty ? null : biz.radioFrequency),
      ],
    );
  }

  Widget _fuelPricesRow(AirportBusiness biz) {
    final scheme = Theme.of(context).colorScheme;
    final entries = biz.fuelPrices.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.attach_money, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Fuel prices",
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                if (entries.isEmpty)
                  Text(
                    "Not provided — use “Set fuel prices” to add",
                    style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: scheme.outline),
                  )
                else
                  for (final e in entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: RichText(
                        text: TextSpan(
                          style: DefaultTextStyle.of(context).style,
                          children: [
                            TextSpan(
                                text: "${e.key}: ",
                                style: const TextStyle(fontSize: 13)),
                            TextSpan(
                                text:
                                    "\$${e.value.price.toStringAsFixed(2)}",
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            TextSpan(
                              text: e.value.updatedAt == null
                                  ? "  (set just now)"
                                  : "  (set ${_formatDate(e.value.updatedAt!)})",
                              style: TextStyle(
                                  fontSize: 11, color: scheme.outline),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String? value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  value ?? "Not provided — use “Edit details” to add",
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: value == null ? FontStyle.italic : null,
                    color: value == null ? scheme.outline : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviews(AirportBusiness biz) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<List<BusinessReview>>(
      stream: _repo.watchReviews(biz.id),
      builder: (context, snap) {
        final reviews = snap.data ?? const <BusinessReview>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text("Reviews",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(width: 6),
                Text("(${reviews.length})",
                    style: TextStyle(color: scheme.outline)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _addReview(biz),
                  icon: const Icon(Icons.rate_review, size: 18),
                  label: const Text("Add"),
                ),
              ],
            ),
            if (snap.connectionState == ConnectionState.waiting &&
                reviews.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (reviews.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text("No reviews yet. Be the first!",
                    style: TextStyle(color: scheme.outline)),
              )
            else
              for (final r in reviews) _reviewCard(r),
          ],
        );
      },
    );
  }

  Widget _reviewCard(BusinessReview r) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StarRating(rating: r.rating.toDouble(), size: 16),
                const Spacer(),
                Text(_formatDate(r.createdAt),
                    style: TextStyle(fontSize: 11, color: scheme.outline)),
              ],
            ),
            if (r.text.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(r.text),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.person, size: 14, color: scheme.outline),
                const SizedBox(width: 4),
                Text(r.authorName,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: scheme.outline)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final l = d.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return "${l.year}-${two(l.month)}-${two(l.day)}";
  }
}

class _EmptyView extends StatelessWidget {
  final String airport;
  const _EmptyView({required this.airport});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(Icons.storefront_outlined, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text("No businesses listed for $airport yet.",
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline)),
          const SizedBox(height: 4),
          Text("Tap “Add” to be the first to contribute.",
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView({required this.error});

  bool get _isPermissionDenied =>
      error.toLowerCase().contains("permission-denied") ||
      error.toLowerCase().contains("permission denied");

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text(
              _isPermissionDenied
                  ? "You need to be signed in to view airport businesses."
                  : "Could not load businesses.\n$error",
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet for setting a price per fuel type. All standard fuel types
/// (plus any the business already lists or has a price for) are offered.
/// Returns the fuel-type -> price map to keep, or null when cancelled.
class _FuelPriceSheet extends StatefulWidget {
  final AirportBusiness business;
  const _FuelPriceSheet({required this.business});

  @override
  State<_FuelPriceSheet> createState() => _FuelPriceSheetState();
}

class _FuelPriceSheetState extends State<_FuelPriceSheet> {
  late final List<String> _types;
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    // Offer every standard fuel type plus anything this listing already has.
    final seen = <String>{};
    _types = [];
    for (final t in [
      ...AirportBusiness.fuelOptions,
      ...widget.business.fuelTypes,
      ...widget.business.fuelPrices.keys,
    ]) {
      final v = t.trim();
      if (v.isNotEmpty && seen.add(v.toLowerCase())) _types.add(v);
    }
    _controllers = {
      for (final t in _types)
        t: TextEditingController(
          text: widget.business.fuelPrices[t] != null
              ? widget.business.fuelPrices[t]!.price.toStringAsFixed(2)
              : "",
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _formatDate(DateTime d) {
    final l = d.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return "${l.year}-${two(l.month)}-${two(l.day)}";
  }

  void _submit() {
    final out = <String, double>{};
    _controllers.forEach((type, ctrl) {
      final raw = ctrl.text.trim();
      if (raw.isEmpty) return;
      final v = double.tryParse(raw);
      if (v != null && v >= 0 && v <= 100) {
        out[type] = double.parse(v.toStringAsFixed(2));
      }
    });
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text("Set fuel prices",
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Text(
                "Enter a price per gallon for any fuel type. Leave blank to "
                "clear. Each price shows the date it was last set.",
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
              const SizedBox(height: 12),
              for (final type in _types) _priceField(type, scheme),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.save),
                label: const Text("Save prices"),
              ),
              const SizedBox(height: 12),
            ],
          );
        },
      ),
    );
  }

  Widget _priceField(String type, ColorScheme scheme) {
    final existing = widget.business.fuelPrices[type];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                if (existing?.updatedAt != null)
                  Text("Last set ${_formatDate(existing!.updatedAt!)}",
                      style: TextStyle(fontSize: 11, color: scheme.outline)),
              ],
            ),
          ),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _controllers[type],
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                prefixText: "\$",
                hintText: "0.00",
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewInput {
  final int rating;
  final String text;
  const _ReviewInput(this.rating, this.text);
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet();

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  int _rating = 0;
  final _textCtrl = TextEditingController();

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding:
          EdgeInsets.only(bottom: bottomInset, left: 16, right: 16, top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text("Write a review",
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Center(
            child: StarRatingInput(
              value: _rating,
              onChanged: (v) => setState(() => _rating = v),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _textCtrl,
            maxLength: BusinessReview.maxTextLength,
            maxLines: 5,
            minLines: 2,
            decoration: const InputDecoration(
              labelText: "Your review (optional)",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _rating == 0
                ? null
                : () => Navigator.pop(
                    context, _ReviewInput(_rating, _textCtrl.text.trim())),
            icon: const Icon(Icons.send),
            label: const Text("Post Review"),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
