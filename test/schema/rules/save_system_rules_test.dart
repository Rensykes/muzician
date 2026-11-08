import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/schema/rules/save_system_rules.dart';

void main() {
  test('deserialiseState drops persisted Song saves', () {
    final raw = jsonEncode({
      'folders': [],
      'saves': [
        {
          'id': 'song-1',
          'name': 'Old Song',
          'folderId': 'f',
          'snapshot': {'type': 'song', 'instrument': 'song', 'project': {}},
          'createdAt': 0,
          'updatedAt': 0,
          'order': 0,
        },
        {
          'id': 'keep-1',
          'name': 'Keep',
          'folderId': 'f',
          'snapshot': {
            'type': 'fretboard',
            'instrument': 'fretboard',
            'tuning': 'standard',
            'numFrets': 12,
            'capo': 0,
            'selectedCells': [],
            'selectedNotes': [],
            'viewMode': 'exact',
          },
          'createdAt': 0,
          'updatedAt': 0,
          'order': 1,
        },
      ],
    });

    final parsed = deserialiseState(raw);

    expect(parsed, isNotNull);
    expect(parsed!.saves.map((save) => save.id), ['keep-1']);
  });
}
