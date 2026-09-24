library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const dataRecoveryStoragePrefix = '@muzician/data-recovery/v1/';
final _uuid = Uuid();

/// A malformed persisted value kept intact until the user chooses to recover.
class MalformedPersistedPayload {
  const MalformedPersistedPayload({
    required this.storageKey,
    required this.raw,
  });

  final String storageKey;
  final String raw;
}

/// Indicates that startup found malformed data that must not be overwritten.
class StartupRecoveryRequired implements Exception {
  const StartupRecoveryRequired(this.payloads);

  final List<MalformedPersistedPayload> payloads;
}

/// Indicates an I/O failure while reading or writing startup data.
class StartupStorageFailure implements Exception {
  const StartupStorageFailure(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class DataRecoveryBackup {
  const DataRecoveryBackup({
    required this.storageKey,
    required this.sourceKey,
    required this.raw,
  });

  final String storageKey;
  final String sourceKey;
  final String raw;

  String get backupId =>
      storageKey.substring(dataRecoveryStoragePrefix.length).split(':').first;

  String get label => switch (sourceKey) {
    '@muzician/save-system/v3' => 'Project and save system',
    '@muzician/song_sessions/v1' => 'Song drafts',
    '@muzician/songwriter_sessions/v1' => 'Writer drafts',
    '@muzician/writer_save_bindings/v1' => 'Writer save links',
    _ => sourceKey,
  };
}

class DataRecoveryNotifier extends Notifier<List<DataRecoveryBackup>> {
  @override
  List<DataRecoveryBackup> build() => const [];

  Future<void> hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final backups = <DataRecoveryBackup>[];
      for (final storageKey in prefs.getKeys().where(
        (key) => key.startsWith(dataRecoveryStoragePrefix),
      )) {
        final raw = prefs.getString(storageKey);
        if (raw == null) continue;
        backups.add(
          DataRecoveryBackup(
            storageKey: storageKey,
            sourceKey: _decodeSourceKey(storageKey),
            raw: raw,
          ),
        );
      }
      backups.sort((a, b) => a.storageKey.compareTo(b.storageKey));
      state = backups;
    } catch (error) {
      throw StartupStorageFailure(
        'Could not read Data Recovery backups.',
        error,
      );
    }
  }

  /// Copies every malformed value first, then removes only those source keys.
  /// If any copy fails, no source value is removed.
  Future<void> preserveAndClear(
    List<MalformedPersistedPayload> payloads,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final writtenKeys = <String>[];
      for (var index = 0; index < payloads.length; index++) {
        final payload = payloads[index];
        final storageKey = _recoveryKey(payload.storageKey, index);
        final didWrite = await prefs.setString(storageKey, payload.raw);
        if (!didWrite || prefs.getString(storageKey) != payload.raw) {
          throw StateError(
            'Could not verify recovery copy for ${payload.storageKey}.',
          );
        }
        writtenKeys.add(storageKey);
      }

      for (final payload in payloads) {
        await prefs.remove(payload.storageKey);
      }

      final backups = [
        ...state.where((backup) => !writtenKeys.contains(backup.storageKey)),
        for (var i = 0; i < payloads.length; i++)
          DataRecoveryBackup(
            storageKey: writtenKeys[i],
            sourceKey: payloads[i].storageKey,
            raw: payloads[i].raw,
          ),
      ]..sort((a, b) => a.storageKey.compareTo(b.storageKey));
      state = backups;
    } on StartupStorageFailure {
      rethrow;
    } catch (error) {
      throw StartupStorageFailure('Could not preserve malformed data.', error);
    }
  }

  Future<void> deleteBackup(String storageKey) async {
    if (!storageKey.startsWith(dataRecoveryStoragePrefix)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
      state = state.where((backup) => backup.storageKey != storageKey).toList();
    } catch (error) {
      throw StartupStorageFailure(
        'Could not delete this recovery backup.',
        error,
      );
    }
  }

  static String _recoveryKey(String sourceKey, int index) {
    final encoded = base64Url
        .encode(utf8.encode(sourceKey))
        .replaceAll('=', '');
    return '$dataRecoveryStoragePrefix${_uuid.v4()}:$index:$encoded';
  }

  static String _decodeSourceKey(String storageKey) {
    try {
      final encoded = storageKey.split(':').last;
      final padding = '=' * ((4 - encoded.length % 4) % 4);
      return utf8.decode(base64Url.decode('$encoded$padding'));
    } catch (_) {
      return 'Unknown persisted data';
    }
  }
}

final dataRecoveryProvider =
    NotifierProvider<DataRecoveryNotifier, List<DataRecoveryBackup>>(
      DataRecoveryNotifier.new,
    );
