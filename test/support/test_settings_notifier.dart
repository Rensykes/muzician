import 'package:muzician/models/save_system.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/utils/note_utils.dart';

class TestSettingsNotifier extends SettingsNotifier {
  TestSettingsNotifier({this.initialSpelling = NoteSpelling.sharps});

  final NoteSpelling initialSpelling;

  @override
  AppSettings build() => AppSettings(noteSpelling: initialSpelling);

  void changeSpelling(NoteSpelling spelling) {
    state = state.copyWith(noteSpelling: spelling);
  }
}
