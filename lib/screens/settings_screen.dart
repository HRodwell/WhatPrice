import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import '../widgets/pantry_manager.dart';
import '../widgets/sync_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _elec;
  late TextEditingController _ovenKw;
  late TextEditingController _wage;
  late TextEditingController _symbol;
  bool _initialized = false;

  void _hydrate(AppSettings s) {
    _elec = TextEditingController(text: s.electricityRatePerKwh.toString());
    _ovenKw = TextEditingController(text: s.ovenKw.toString());
    _wage = TextEditingController(text: s.hourlyWage.toString());
    _symbol = TextEditingController(text: s.currencySymbol);
    _initialized = true;
  }

  @override
  void dispose() {
    if (_initialized) {
      _elec.dispose();
      _ovenKw.dispose();
      _wage.dispose();
      _symbol.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final current = context.read<AppState>().settings;
    final s = current.copyWith(
      electricityRatePerKwh: double.parse(_elec.text),
      ovenKw: double.parse(_ovenKw.text),
      hourlyWage: double.parse(_wage.text),
      currencySymbol: _symbol.text.trim().isEmpty ? '\$' : _symbol.text.trim(),
    );
    await context.read<AppState>().saveSettings(s);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppState>().settings;
    if (!_initialized) _hydrate(settings);

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _Section(
            title: 'Currency',
            child: TextFormField(
              controller: _symbol,
              decoration: const InputDecoration(labelText: 'Symbol'),
            ),
          ),
          _Section(
            title: 'Energy',
            child: Column(children: [
              TextFormField(
                controller: _elec,
                decoration: const InputDecoration(
                    labelText: 'Electricity rate (per kWh)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: _nonNegative,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ovenKw,
                decoration:
                    const InputDecoration(labelText: 'Oven power (kW)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: _nonNegative,
              ),
            ]),
          ),
          _Section(
            title: 'Labour',
            child: TextFormField(
              controller: _wage,
              decoration: const InputDecoration(
                labelText: 'Hourly wage',
                helperText:
                    'Include-labour toggle and margin live in the Calculate tab.',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: _nonNegative,
            ),
          ),
          const _Section(
            title: 'Pantries',
            child: PantryManager(),
          ),
          const _Section(
            title: 'Cloud sync',
            child: SyncSettings(),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Save settings'),
          ),
        ],
      ),
    );
  }

  String? _nonNegative(String? v) {
    final n = double.tryParse(v ?? '');
    if (n == null) return 'Number';
    if (n < 0) return '≥ 0';
    return null;
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(title.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 1,
                      color: Theme.of(context).colorScheme.primary,
                    )),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
