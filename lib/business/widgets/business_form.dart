import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/airport_business.dart';

/// Result returned by [BusinessFormSheet].
class BusinessFormResult {
  final String name;
  final List<String> services;
  final List<String> fuelTypes;
  final String operatingHours;
  final String phoneNumber;
  final String radioFrequency;

  const BusinessFormResult({
    required this.name,
    required this.services,
    required this.fuelTypes,
    required this.operatingHours,
    required this.phoneNumber,
    required this.radioFrequency,
  });
}

/// Bottom-sheet form for creating a business or editing its details.
///
/// When [requireName] is true the name field is shown and required (adding a
/// new listing). When false the name is fixed/immutable and only the
/// crowd-sourced detail fields are editable.
class BusinessFormSheet extends StatefulWidget {
  final String title;
  final bool requireName;
  final String? initialName;
  final List<String> initialServices;
  final List<String> initialFuelTypes;
  final String initialHours;
  final String initialPhone;
  final String initialFrequency;

  const BusinessFormSheet({
    super.key,
    required this.title,
    this.requireName = true,
    this.initialName,
    this.initialServices = const [],
    this.initialFuelTypes = const [],
    this.initialHours = "",
    this.initialPhone = "",
    this.initialFrequency = "",
  });

  @override
  State<BusinessFormSheet> createState() => _BusinessFormSheetState();
}

class _BusinessFormSheetState extends State<BusinessFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _hoursCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _freqCtrl;
  late final Set<String> _services;
  late final Set<String> _fuel;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? "");
    _hoursCtrl = TextEditingController(text: widget.initialHours);
    _phoneCtrl = TextEditingController(text: widget.initialPhone);
    _freqCtrl = TextEditingController(text: widget.initialFrequency);
    _services = {...widget.initialServices};
    _fuel = {...widget.initialFuelTypes};
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hoursCtrl.dispose();
    _phoneCtrl.dispose();
    _freqCtrl.dispose();
    super.dispose();
  }

  // Present the known options plus anything already chosen that isn't a
  // preset (e.g. imported/custom values), so custom entries aren't dropped.
  List<String> _chipOptions(List<String> presets, Set<String> selected) {
    final out = [...presets];
    for (final s in selected) {
      if (!out.contains(s)) out.add(s);
    }
    return out;
  }

  void _submit() {
    if (widget.requireName && !_formKey.currentState!.validate()) {
      return;
    }
    Navigator.pop(
      context,
      BusinessFormResult(
        name: _nameCtrl.text.trim(),
        services: _services.toList(),
        fuelTypes: _fuel.toList(),
        operatingHours: _hoursCtrl.text.trim(),
        phoneNumber: _phoneCtrl.text.trim(),
        radioFrequency: _freqCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Form(
            key: _formKey,
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(widget.title,
                          style: Theme.of(context).textTheme.titleLarge),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (widget.requireName) ...[
                  TextFormField(
                    controller: _nameCtrl,
                    maxLength: AirportBusiness.maxNameLength,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: "Business name",
                      hintText: "e.g. Signature Flight Support",
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? "Please enter a name"
                        : null,
                  ),
                  const SizedBox(height: 8),
                ],
                _SectionLabel("Services"),
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    for (final s in _chipOptions(
                        AirportBusiness.serviceOptions, _services))
                      FilterChip(
                        label: Text(s),
                        selected: _services.contains(s),
                        onSelected: (sel) => setState(() {
                          sel ? _services.add(s) : _services.remove(s);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _SectionLabel("Fuel available"),
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    for (final f
                        in _chipOptions(AirportBusiness.fuelOptions, _fuel))
                      FilterChip(
                        label: Text(f),
                        selected: _fuel.contains(f),
                        onSelected: (sel) => setState(() {
                          sel ? _fuel.add(f) : _fuel.remove(f);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _SectionLabel("Operating hours"),
                TextFormField(
                  controller: _hoursCtrl,
                  maxLength: AirportBusiness.maxHoursLength,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(
                    hintText: "e.g. Mon–Fri 0800–1800, Sat 0900–1700, "
                        "Sun closed",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                _SectionLabel("Phone number"),
                TextFormField(
                  controller: _phoneCtrl,
                  maxLength: AirportBusiness.maxPhoneLength,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9+\-() ]')),
                  ],
                  decoration: const InputDecoration(
                    hintText: "e.g. (555) 123-4567",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                _SectionLabel("Radio frequency"),
                TextFormField(
                  controller: _freqCtrl,
                  maxLength: AirportBusiness.maxFrequencyLength,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9. ]')),
                  ],
                  decoration: const InputDecoration(
                    hintText: "e.g. 122.95",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.save),
                  label: Text(widget.requireName ? "Add Business" : "Save"),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }
}
