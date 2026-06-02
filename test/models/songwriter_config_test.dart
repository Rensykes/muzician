import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/songwriter.dart';

void main() {
  test('SongwriterConfig round-trips with nullable key', () {
    const a = SongwriterConfig(tempo: 120, beatsPerBar: 4, beatUnit: 4);
    expect(a.keyRoot, isNull);
    final back = SongwriterConfig.fromJson(a.toJson());
    expect(back.tempo, 120);
    expect(back.beatsPerBar, 4);
    expect(back.keyRoot, isNull);

    final keyed = a.copyWith(keyRoot: 0, keyScaleName: 'major');
    final back2 = SongwriterConfig.fromJson(keyed.toJson());
    expect(back2.keyRoot, 0);
    expect(back2.keyScaleName, 'major');
  });
}
