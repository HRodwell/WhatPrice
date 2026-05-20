import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../sync/sync_service.dart';

class SyncSettings extends StatefulWidget {
  const SyncSettings({super.key});

  @override
  State<SyncSettings> createState() => _SyncSettingsState();
}

class _SyncSettingsState extends State<SyncSettings> {
  final _url = TextEditingController();
  bool _loaded = false;

  Future<void> _hydrate(SyncService sync) async {
    if (_loaded) return;
    _loaded = true;
    final stored = await sync.getServerUrl();
    if (!mounted) return;
    setState(() => _url.text = stored ?? '');
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _saveUrl(SyncService sync) async {
    await sync.setServerUrl(_url.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Server URL saved')),
    );
  }

  Future<void> _runSync(SyncService sync) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await sync.syncNow();
    if (!mounted) return;
    if (!result.ok) {
      messenger.showSnackBar(
        SnackBar(content: Text('Sync failed: ${result.error}')),
      );
      return;
    }
    final extra = result.warnings.isEmpty
        ? ''
        : ' (${result.warnings.length} warnings)';
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Synced — pushed ${result.pushed}, pulled ${result.pulled}$extra',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    _hydrate(sync);
    final lastSync = sync.lastSyncAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _url,
          decoration: const InputDecoration(
            labelText: 'PocketBase server URL',
            helperText: 'e.g. http://10.144.1.5:8090',
          ),
          keyboardType: TextInputType.url,
          autocorrect: false,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: sync.isRunning ? null : () => _saveUrl(sync),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save URL'),
          ),
        ),
        const Divider(),
        Text(
          lastSync == null
              ? 'Never synced'
              : 'Last synced ${DateFormat.yMd().add_jm().format(lastSync)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: sync.isRunning ? null : () => _runSync(sync),
          icon: sync.isRunning
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
          label: Text(sync.isRunning ? 'Syncing…' : 'Sync now'),
        ),
        if (sync.lastError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              sync.lastError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
