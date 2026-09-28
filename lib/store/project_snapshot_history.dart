import 'package:flutter/foundation.dart';

/// Bounded in-memory history for immutable project snapshots.
///
/// The current snapshot is owned by the project notifier. This class stores at
/// most [maxUndoSteps] previous snapshots plus a redo branch. Callers report
/// state changes through [recordChange] and suppress that reporting while
/// applying an undo or redo with [restore].
class ProjectSnapshotHistory<T> {
  ProjectSnapshotHistory({this.maxUndoSteps = 50}) : assert(maxUndoSteps > 0);

  final int maxUndoSteps;
  final List<T> _undo = [];
  final List<T> _redo = [];
  final ValueNotifier<int> revisionListenable = ValueNotifier(0);
  T? _groupStart;
  int _groupDepth = 0;
  bool _restoring = false;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get undoCount => _undo.length;
  int get redoCount => _redo.length;
  int get revision => revisionListenable.value;

  /// Snapshots still reachable through undo, redo, or an active history group.
  Iterable<T> get retainedSnapshots => [..._undo, ..._redo, ?_groupStart];

  void recordChange(T before, T after) {
    if (_restoring || identical(before, after)) return;
    if (_groupDepth > 0) {
      _groupStart ??= before;
      return;
    }
    _commit(before);
  }

  /// Coalesces all changes until the matching [endGroup] into one undo step.
  void beginGroup() {
    if (_groupDepth == 0) _groupStart = null;
    _groupDepth++;
  }

  void endGroup(T current) {
    if (_groupDepth == 0) return;
    _groupDepth--;
    if (_groupDepth != 0) return;
    final start = _groupStart;
    _groupStart = null;
    if (start != null && !identical(start, current)) _commit(start);
  }

  T? takeUndo(T current) {
    if (_undo.isEmpty) return null;
    _redo.add(current);
    final previous = _undo.removeLast();
    _bumpRevision();
    return previous;
  }

  T? takeRedo(T current) {
    if (_redo.isEmpty) return null;
    _undo.add(current);
    if (_undo.length > maxUndoSteps) _undo.removeAt(0);
    final next = _redo.removeLast();
    _bumpRevision();
    return next;
  }

  /// Applies a historical snapshot without creating a new history entry.
  void restore(VoidCallback action) {
    _restoring = true;
    try {
      action();
    } finally {
      _restoring = false;
    }
  }

  /// Drops both branches. Revision still changes so stale undo affordances can
  /// be invalidated after project switches, loads, or New.
  void clear() {
    _undo.clear();
    _redo.clear();
    _groupStart = null;
    _groupDepth = 0;
    _bumpRevision();
  }

  bool isCurrentRevision(int expected) => revision == expected;

  void dispose() => revisionListenable.dispose();

  void _commit(T previous) {
    _undo.add(previous);
    if (_undo.length > maxUndoSteps) _undo.removeAt(0);
    _redo.clear();
    _bumpRevision();
  }

  void _bumpRevision() {
    revisionListenable.value++;
  }
}
