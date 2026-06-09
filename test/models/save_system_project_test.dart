import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/models/save_system.dart';

void main() {
  group('ProjectConfig', () {
    test('defaults: tempo=120, beatsPerBar=4, beatUnit=4, key fields null', () {
      const cfg = ProjectConfig();
      expect(cfg.tempo, 120);
      expect(cfg.beatsPerBar, 4);
      expect(cfg.beatUnit, 4);
      expect(cfg.keyRootPc, isNull);
      expect(cfg.keyScaleName, isNull);
    });

    test('toJson / fromJson roundtrip preserves all fields', () {
      const original = ProjectConfig(
        keyRootPc: 9,
        keyScaleName: 'minor',
        tempo: 96,
        beatsPerBar: 3,
        beatUnit: 8,
      );
      final restored = ProjectConfig.fromJson(original.toJson());
      expect(restored.keyRootPc, 9);
      expect(restored.keyScaleName, 'minor');
      expect(restored.tempo, 96);
      expect(restored.beatsPerBar, 3);
      expect(restored.beatUnit, 8);
    });

    test('copyWith updates only specified fields; clearKey nulls both key fields', () {
      const original = ProjectConfig(
        keyRootPc: 0,
        keyScaleName: 'major',
        tempo: 120,
      );
      final patched = original.copyWith(tempo: 140);
      expect(patched.tempo, 140);
      expect(patched.keyRootPc, 0);

      final cleared = original.copyWith(clearKey: true);
      expect(cleared.keyRootPc, isNull);
      expect(cleared.keyScaleName, isNull);
      expect(cleared.tempo, 120);
    });
  });

  _additionalGroups();
}

void _additionalGroups() {
  group('SaveFolder.kind + projectConfig', () {
    test('default kind is normal; projectConfig null; roundtrip', () {
      const folder = SaveFolder(
        id: 'f1',
        name: 'verse',
        parentId: null,
        createdAt: 1,
        order: 0,
      );
      expect(folder.kind, SaveFolderKind.normal);
      expect(folder.projectConfig, isNull);
      final restored = SaveFolder.fromJson(folder.toJson());
      expect(restored.kind, SaveFolderKind.normal);
      expect(restored.projectConfig, isNull);
    });

    test('project kind + ProjectConfig roundtrip', () {
      final folder = SaveFolder(
        id: 'p1',
        name: 'My song',
        parentId: null,
        createdAt: 1,
        order: 0,
        kind: SaveFolderKind.project,
        projectConfig: const ProjectConfig(keyRootPc: 2, keyScaleName: 'major', tempo: 100),
      );
      final restored = SaveFolder.fromJson(folder.toJson());
      expect(restored.kind, SaveFolderKind.project);
      expect(restored.projectConfig?.tempo, 100);
      expect(restored.projectConfig?.keyRootPc, 2);
    });

    test('dump kind roundtrip', () {
      const folder = SaveFolder(
        id: 'd1',
        name: 'Dump',
        parentId: null,
        createdAt: 1,
        order: 0,
        kind: SaveFolderKind.dump,
      );
      final restored = SaveFolder.fromJson(folder.toJson());
      expect(restored.kind, SaveFolderKind.dump);
      expect(restored.projectConfig, isNull);
    });
  });

  group('SaveSystemState.selectedProjectId', () {
    test('default is null; copyWith updates it', () {
      const state = SaveSystemState(folders: [], saves: [], hydrated: true);
      expect(state.selectedProjectId, isNull);
      final next = state.copyWith(selectedProjectId: () => 'abc');
      expect(next.selectedProjectId, 'abc');
      final cleared = next.copyWith(selectedProjectId: () => null);
      expect(cleared.selectedProjectId, isNull);
    });
  });
}
