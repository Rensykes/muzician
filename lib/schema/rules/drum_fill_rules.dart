/// Pure tick generators for drum-lane "fill" utilities.
///
/// Both functions return a sorted list of active ticks in `[0, lengthTicks)`.
/// They have no Flutter dependency and are the single source of truth for the
/// sequencer fill menu in the drum machine editor.
library;

/// Active ticks at [offset], [offset]+[step], [offset]+2·[step], … while
/// `< lengthTicks`. Returns empty when [lengthTicks] or [step] is non-positive,
/// or when [offset] is at/beyond [lengthTicks].
List<int> everyN(int lengthTicks, int step, {int offset = 0}) {
  if (lengthTicks <= 0 || step <= 0) return const [];
  final start = offset < 0 ? 0 : offset;
  final out = <int>[];
  for (var t = start; t < lengthTicks; t += step) {
    out.add(t);
  }
  return out;
}

/// Euclidean rhythm: distributes [hits] pulses as evenly as possible across
/// [lengthTicks] slots using Bjorklund's algorithm, then rotates the result by
/// [rotation] slots. Returns sorted active ticks. Negative [rotation] values
/// rotate left (e.g. `rotation: -1` on a 16-slot pattern equals `rotation: 15`).
///
/// `euclid(8, 3) == [0, 3, 6]`, `euclid(16, 4) == [0, 4, 8, 12]`.
List<int> euclid(int lengthTicks, int hits, {int rotation = 0}) {
  if (lengthTicks <= 0 || hits <= 0) return const [];
  if (hits >= lengthTicks) {
    return [for (var i = 0; i < lengthTicks; i++) i];
  }

  // Bjorklund: repeatedly fold the remainder groups into the front groups
  // until at most one remainder group is left.
  var groups = <List<int>>[for (var i = 0; i < hits; i++) <int>[1]];
  var remainders = <List<int>>[
    for (var i = 0; i < lengthTicks - hits; i++) <int>[0],
  ];

  while (remainders.length > 1) {
    final count = groups.length < remainders.length
        ? groups.length
        : remainders.length;
    final newGroups = <List<int>>[];
    for (var i = 0; i < count; i++) {
      newGroups.add(<int>[...groups[i], ...remainders[i]]);
    }
    final newRemainders = <List<int>>[];
    if (groups.length > count) {
      newRemainders.addAll(groups.sublist(count));
    } else if (remainders.length > count) {
      newRemainders.addAll(remainders.sublist(count));
    }
    groups = newGroups;
    remainders = newRemainders;
  }

  final pattern = <int>[
    for (final g in [...groups, ...remainders]) ...g,
  ];

  final ticks = <int>[];
  for (var i = 0; i < pattern.length; i++) {
    if (pattern[i] == 1) ticks.add(i);
  }

  if (rotation != 0 && ticks.isNotEmpty) {
    final shift = rotation % lengthTicks;
    if (shift == 0) return ticks; // exact-multiple rotation is a no-op
    return ticks.map((t) => (t + shift) % lengthTicks).toList()..sort();
  }
  return ticks;
}
