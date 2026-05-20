import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../app_state.dart';
import '../services/image_storage.dart';
import 'collection_defs.dart';

class SyncResult {
  final int pushed;
  final int pulled;
  final List<String> warnings;
  final Object? error;
  const SyncResult({
    required this.pushed,
    required this.pulled,
    required this.warnings,
    this.error,
  });
  bool get ok => error == null;
}

class SyncService extends ChangeNotifier {
  SyncService(this._state);
  final AppState _state;

  bool _running = false;
  bool get isRunning => _running;

  DateTime? _lastSyncAt;
  DateTime? get lastSyncAt => _lastSyncAt;

  String? _lastError;
  String? get lastError => _lastError;

  Future<String?> getServerUrl() => _state.getLocalState('pb_server_url');
  Future<void> setServerUrl(String? url) async {
    final clean = url?.trim();
    await _state.setLocalState(
      'pb_server_url',
      (clean == null || clean.isEmpty) ? null : clean,
    );
    notifyListeners();
  }

  Future<DateTime?> _loadLastSync() async {
    final v = await _state.getLocalState('last_sync_at');
    if (v == null) return null;
    return DateTime.tryParse(v);
  }

  Future<SyncResult> syncNow() async {
    if (_running) {
      return const SyncResult(
        pushed: 0,
        pulled: 0,
        warnings: ['Sync already in progress'],
      );
    }
    _running = true;
    _lastError = null;
    notifyListeners();
    final warnings = <String>[];
    var pushed = 0;
    var pulled = 0;
    try {
      final urlRaw = await getServerUrl();
      if (urlRaw == null || urlRaw.isEmpty) {
        throw StateError('Set the PocketBase server URL in Settings first.');
      }
      final base = _normaliseBase(urlRaw);

      // Pull first so we have the latest FK targets before pushing.
      for (final c in syncCollections) {
        pulled += await _pullCollection(base, c, warnings);
      }
      for (final c in syncCollections) {
        pushed += await _pushCollection(base, c, warnings);
      }

      _lastSyncAt = DateTime.now();
      await _state.setLocalState(
        'last_sync_at',
        _lastSyncAt!.toUtc().toIso8601String(),
      );
      await _state.reloadAll();
    } catch (e, st) {
      _lastError = '$e';
      debugPrint('Sync failed: $e\n$st');
      return SyncResult(
        pushed: pushed,
        pulled: pulled,
        warnings: warnings,
        error: e,
      );
    } finally {
      _running = false;
      notifyListeners();
    }
    _lastSyncAt = DateTime.now();
    notifyListeners();
    return SyncResult(pushed: pushed, pulled: pulled, warnings: warnings);
  }

  Future<void> loadStatus() async {
    _lastSyncAt = await _loadLastSync();
    notifyListeners();
  }

  // ---- pull ----

  Future<int> _pullCollection(
    String base,
    SyncCollection c,
    List<String> warnings,
  ) async {
    final lastPullKey = 'last_pull_${c.localTable}';
    final lastPull = await _state.getLocalState(lastPullKey);
    final filter = lastPull == null
        ? ''
        : '&filter=${Uri.encodeComponent('updated_at>"$lastPull"')}';
    final remotes = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final url = Uri.parse(
        '$base/api/collections/${c.remoteName}/records'
        '?page=$page&perPage=200&sort=updated_at$filter',
      );
      final res = await http.get(url);
      if (res.statusCode != 200) {
        throw HttpException(
          'Pull ${c.remoteName} ${res.statusCode}: ${res.body}',
        );
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final items =
          (body['items'] as List).cast<Map<String, dynamic>>();
      remotes.addAll(items);
      final totalPages = (body['totalPages'] as num).toInt();
      if (page >= totalPages || items.isEmpty) break;
      page++;
    }
    if (remotes.isEmpty) return 0;

    var applied = 0;
    String? maxUpdated;
    for (final r in remotes) {
      try {
        await _applyRemote(c, r, base, warnings);
        applied++;
      } catch (e) {
        warnings.add('Failed to apply ${c.remoteName} ${r['sync_id']}: $e');
      }
      final ru = r['updated_at'] as String?;
      if (ru != null && (maxUpdated == null || ru.compareTo(maxUpdated) > 0)) {
        maxUpdated = ru;
      }
    }
    if (maxUpdated != null) {
      await _state.setLocalState(lastPullKey, maxUpdated);
    }
    return applied;
  }

  Future<void> _applyRemote(
    SyncCollection c,
    Map<String, dynamic> remote,
    String base,
    List<String> warnings,
  ) async {
    final syncId = remote['sync_id'] as String;
    final remoteUpdatedAt = remote['updated_at'] as String;
    final raw = _state.db.raw;
    final existing = await raw.query(
      c.localTable,
      where: 'sync_id = ?',
      whereArgs: [syncId],
    );

    if (existing.isNotEmpty) {
      final localUpdated = existing.first['updated_at'] as String?;
      if (localUpdated != null &&
          localUpdated.compareTo(remoteUpdatedAt) > 0) {
        // Local is newer, skip.
        return;
      }
    }

    final localValues = <String, Object?>{
      'sync_id': syncId,
      'updated_at': remoteUpdatedAt,
      'deleted_at': remote['deleted_at'] as String?,
    };
    for (final f in c.fields) {
      localValues[f.name] = _fromRemoteScalar(remote[f.name], f);
    }
    for (final fk in c.fkFields) {
      final refSyncId = remote[fk.remoteCol] as String?;
      if (refSyncId == null) {
        localValues[fk.localCol] = null;
        continue;
      }
      final refLocalId = await _localIdFromSyncId(fk.refTable, refSyncId);
      if (refLocalId == null) {
        throw StateError(
          'Pulled ${c.remoteName} ${remote['id']} references unknown '
          '${fk.refTable} sync_id=$refSyncId. Pull dependency missing?',
        );
      }
      localValues[fk.localCol] = refLocalId;
    }

    // Files: download if remote has one and local doesn't already have a path.
    for (final ff in c.fileFields) {
      final remoteFile = remote[ff.remoteFileCol] as String?;
      final hasRemoteFile = remoteFile != null && remoteFile.isNotEmpty;
      String? localPath;
      if (existing.isNotEmpty) {
        localPath = existing.first[ff.localPathCol] as String?;
      }
      if (hasRemoteFile && (localPath == null || localPath.isEmpty)) {
        try {
          localPath = await _downloadFile(
            base: base,
            collection: c.remoteName,
            recordId: remote['id'] as String,
            filename: remoteFile,
          );
        } catch (e) {
          warnings.add(
            'Image download failed for ${c.remoteName} '
            '${remote['id']}: $e',
          );
          localPath = null;
        }
      }
      localValues[ff.localPathCol] = localPath ?? '';
    }

    if (existing.isEmpty) {
      await raw.insert(c.localTable, localValues);
    } else {
      await raw.update(
        c.localTable,
        localValues,
        where: 'sync_id = ?',
        whereArgs: [syncId],
      );
    }
  }

  Future<int?> _localIdFromSyncId(String refTable, String syncId) async {
    final rows = await _state.db.raw.query(
      refTable,
      columns: ['id'],
      where: 'sync_id = ?',
      whereArgs: [syncId],
    );
    if (rows.isEmpty) return null;
    return (rows.first['id'] as num).toInt();
  }

  Future<String?> _syncIdFromLocalId(String refTable, int localId) async {
    final rows = await _state.db.raw.query(
      refTable,
      columns: ['sync_id'],
      where: 'id = ?',
      whereArgs: [localId],
    );
    if (rows.isEmpty) return null;
    return rows.first['sync_id'] as String?;
  }

  Future<String> _downloadFile({
    required String base,
    required String collection,
    required String recordId,
    required String filename,
  }) async {
    final url = Uri.parse('$base/api/files/$collection/$recordId/$filename');
    final res = await http.get(url);
    if (res.statusCode != 200) {
      throw HttpException('Download $filename ${res.statusCode}');
    }
    final dir = await ImageStorage.instance.ensureDir();
    final ext = p.extension(filename).toLowerCase();
    final localName =
        '${DateTime.now().microsecondsSinceEpoch}${ext.isEmpty ? '.jpg' : ext}';
    final dest = File(p.join(dir.path, localName));
    await dest.writeAsBytes(res.bodyBytes, flush: true);
    return localName;
  }

  // ---- push ----

  Future<int> _pushCollection(
    String base,
    SyncCollection c,
    List<String> warnings,
  ) async {
    final lastPushKey = 'last_push_${c.localTable}';
    final lastPush = await _state.getLocalState(lastPushKey);

    final whereParts = <String>[];
    final whereArgs = <Object?>[];
    if (lastPush != null) {
      whereParts.add('updated_at > ?');
      whereArgs.add(lastPush);
    }
    final dirty = await _state.db.raw.query(
      c.localTable,
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
    );
    if (dirty.isEmpty) return 0;

    // Index existing remote records by sync_id (single fetch).
    final remoteIndex = await _fetchRemoteSyncIndex(base, c);

    var pushed = 0;
    String? maxUpdated;
    for (final row in dirty) {
      try {
        await _pushRow(base, c, row, remoteIndex);
        pushed++;
      } catch (e) {
        warnings.add('Failed to push ${c.remoteName}: $e');
      }
      final ru = row['updated_at'] as String?;
      if (ru != null && (maxUpdated == null || ru.compareTo(maxUpdated) > 0)) {
        maxUpdated = ru;
      }
    }
    if (maxUpdated != null) {
      await _state.setLocalState(lastPushKey, maxUpdated);
    }
    return pushed;
  }

  Future<Map<String, Map<String, dynamic>>> _fetchRemoteSyncIndex(
    String base,
    SyncCollection c,
  ) async {
    final index = <String, Map<String, dynamic>>{};
    var page = 1;
    while (true) {
      final url = Uri.parse(
        '$base/api/collections/${c.remoteName}/records'
        '?page=$page&perPage=200&fields=id,sync_id,${c.fileFields.map((f) => f.remoteFileCol).join(',')}',
      );
      final res = await http.get(url);
      if (res.statusCode != 200) {
        throw HttpException(
          'Index ${c.remoteName} ${res.statusCode}: ${res.body}',
        );
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (body['items'] as List).cast<Map<String, dynamic>>();
      for (final r in items) {
        final sid = r['sync_id'] as String?;
        if (sid != null) index[sid] = r;
      }
      final totalPages = (body['totalPages'] as num).toInt();
      if (page >= totalPages || items.isEmpty) break;
      page++;
    }
    return index;
  }

  Future<void> _pushRow(
    String base,
    SyncCollection c,
    Map<String, dynamic> row,
    Map<String, Map<String, dynamic>> remoteIndex,
  ) async {
    final syncId = row['sync_id'] as String;
    final payload = <String, dynamic>{
      'sync_id': syncId,
      'updated_at': row['updated_at'],
      'deleted_at': row['deleted_at'],
    };
    for (final f in c.fields) {
      payload[f.name] = _toRemoteScalar(row[f.name], f);
    }
    for (final fk in c.fkFields) {
      final localId = row[fk.localCol];
      if (localId == null) {
        payload[fk.remoteCol] = null;
        continue;
      }
      final refSyncId =
          await _syncIdFromLocalId(fk.refTable, (localId as num).toInt());
      payload[fk.remoteCol] = refSyncId;
    }

    final existingRemote = remoteIndex[syncId];
    final fileToUpload = <SyncFileField, File>{};
    if (c.fileFields.isNotEmpty) {
      for (final ff in c.fileFields) {
        final localPath = row[ff.localPathCol] as String?;
        if (localPath == null || localPath.isEmpty) continue;
        final hasRemote = existingRemote != null &&
            (existingRemote[ff.remoteFileCol] as String?)?.isNotEmpty == true;
        if (!hasRemote) {
          final f = await ImageStorage.instance.resolveAsync(localPath);
          if (await f.exists()) fileToUpload[ff] = f;
        }
      }
    }

    if (existingRemote == null) {
      await _createRemoteRecord(base, c, payload, fileToUpload);
    } else {
      final pbId = existingRemote['id'] as String;
      await _updateRemoteRecord(base, c, pbId, payload, fileToUpload);
    }
  }

  Future<void> _createRemoteRecord(
    String base,
    SyncCollection c,
    Map<String, dynamic> payload,
    Map<SyncFileField, File> files,
  ) async {
    final url = Uri.parse('$base/api/collections/${c.remoteName}/records');
    if (files.isEmpty) {
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (res.statusCode != 200 && res.statusCode != 201) {
        throw HttpException(
          'Create ${c.remoteName} ${res.statusCode}: ${res.body}',
        );
      }
    } else {
      final req = http.MultipartRequest('POST', url);
      payload.forEach((k, v) {
        if (v == null) return;
        req.fields[k] = v.toString();
      });
      for (final e in files.entries) {
        req.files.add(await http.MultipartFile.fromPath(
          e.key.remoteFileCol,
          e.value.path,
        ));
      }
      final streamed = await req.send();
      if (streamed.statusCode != 200 && streamed.statusCode != 201) {
        final body = await streamed.stream.bytesToString();
        throw HttpException(
          'Create ${c.remoteName} ${streamed.statusCode}: $body',
        );
      }
    }
  }

  Future<void> _updateRemoteRecord(
    String base,
    SyncCollection c,
    String pbId,
    Map<String, dynamic> payload,
    Map<SyncFileField, File> files,
  ) async {
    final url =
        Uri.parse('$base/api/collections/${c.remoteName}/records/$pbId');
    if (files.isEmpty) {
      final res = await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      if (res.statusCode != 200) {
        throw HttpException(
          'Update ${c.remoteName} ${res.statusCode}: ${res.body}',
        );
      }
    } else {
      final req = http.MultipartRequest('PATCH', url);
      payload.forEach((k, v) {
        if (v == null) return;
        req.fields[k] = v.toString();
      });
      for (final e in files.entries) {
        req.files.add(await http.MultipartFile.fromPath(
          e.key.remoteFileCol,
          e.value.path,
        ));
      }
      final streamed = await req.send();
      if (streamed.statusCode != 200) {
        final body = await streamed.stream.bytesToString();
        throw HttpException(
          'Update ${c.remoteName} ${streamed.statusCode}: $body',
        );
      }
    }
  }

  Object? _toRemoteScalar(Object? value, SyncField f) {
    if (value == null) return null;
    switch (f.type) {
      case SyncFieldType.int_:
        return (value as num).toInt();
      case SyncFieldType.real:
        return (value as num).toDouble();
      case SyncFieldType.bool_:
        return value == 1 || value == true;
      case SyncFieldType.text:
        return value.toString();
    }
  }

  Object? _fromRemoteScalar(Object? value, SyncField f) {
    if (value == null) return null;
    switch (f.type) {
      case SyncFieldType.int_:
        return value is bool ? (value ? 1 : 0) : (value as num).toInt();
      case SyncFieldType.real:
        return (value as num).toDouble();
      case SyncFieldType.bool_:
        return value == true || value == 1 ? 1 : 0;
      case SyncFieldType.text:
        if (value is String && value.isEmpty && f.nullable) return null;
        return value.toString();
    }
  }

  String _normaliseBase(String url) {
    var u = url.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'http://$u';
    }
    return u;
  }
}
