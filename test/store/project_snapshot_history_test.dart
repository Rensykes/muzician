import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/store/project_snapshot_history.dart';

void main() {
  test('records prior snapshots and supports undo and redo', () {
    final history = ProjectSnapshotHistory<String>();
    addTearDown(history.dispose);
    var current = 'first';

    history.recordChange(current, 'second');
    current = 'second';
    expect(history.takeUndo(current), 'first');
    history.restore(() => current = 'first');
    expect(history.canRedo, isTrue);

    expect(history.takeRedo(current), 'second');
    history.restore(() => current = 'second');
    expect(current, 'second');
    expect(history.canUndo, isTrue);
  });

  test('coalesces a group into one prior snapshot', () {
    final history = ProjectSnapshotHistory<String>();
    addTearDown(history.dispose);
    var current = 'start';

    history.beginGroup();
    history.recordChange(current, 'middle');
    current = 'middle';
    history.recordChange(current, 'end');
    current = 'end';
    history.endGroup(current);

    expect(history.undoCount, 1);
    expect(history.takeUndo(current), 'start');
  });

  test('a new edit after undo clears the redo branch', () {
    final history = ProjectSnapshotHistory<String>();
    addTearDown(history.dispose);
    var current = 'a';

    history.recordChange(current, 'b');
    current = 'b';
    final previous = history.takeUndo(current)!;
    history.restore(() => current = previous);
    expect(history.canRedo, isTrue);

    history.recordChange(current, 'c');
    current = 'c';
    expect(history.canRedo, isFalse);
  });

  test('keeps 50 undo snapshots plus the current snapshot', () {
    final history = ProjectSnapshotHistory<String>();
    addTearDown(history.dispose);
    var current = '0';
    for (var i = 1; i <= 60; i++) {
      final next = '$i';
      history.recordChange(current, next);
      current = next;
    }

    expect(history.undoCount, 50);
    for (var i = 0; i < 50; i++) {
      current = history.takeUndo(current)!;
    }
    expect(current, '10');
    expect(history.canUndo, isFalse);
  });

  test('clear resets both branches and invalidates revision tokens', () {
    final history = ProjectSnapshotHistory<String>();
    addTearDown(history.dispose);
    history.recordChange('a', 'b');
    final revision = history.revision;

    history.clear();

    expect(history.canUndo, isFalse);
    expect(history.canRedo, isFalse);
    expect(history.isCurrentRevision(revision), isFalse);
  });
}
