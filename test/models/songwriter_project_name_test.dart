import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('SongwriterProjectSnapshot default name is "Untitled song"', () {
    const p = SongwriterProjectSnapshot(
      config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
      sections: [],
    );
    expect(p.name, 'Untitled song');
  });

  test('copyWith replaces name', () {
    const p = SongwriterProjectSnapshot(
      name: 'Old',
      config: SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4),
      sections: [],
    );
    expect(p.copyWith(name: 'New').name, 'New');
    expect(p.copyWith().name, 'Old');
  });

  test('toJson includes name; fromJson round-trips it', () {
    const p = SongwriterProjectSnapshot(
      name: 'Song A',
      config: SongwriterConfig(tempo: 110, beatsPerBar: 3, beatUnit: 4),
      sections: [],
    );
    final j = jsonEncode(p.toJson());
    final back = SongwriterProjectSnapshot.fromJson(
      jsonDecode(j) as Map<String, dynamic>,
    );
    expect(back.name, 'Song A');
    expect(back.config.tempo, 110);
  });

  test('fromJson defaults missing name to "Untitled song"', () {
    final old = {
      'config': {'tempo': 120, 'beatsPerBar': 4, 'beatUnit': 4},
      'sections': <dynamic>[],
    };
    final back = SongwriterProjectSnapshot.fromJson(old);
    expect(back.name, 'Untitled song');
  });
}
