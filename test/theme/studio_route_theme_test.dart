import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muzician/features/_mockup_shell.dart';
import 'package:muzician/main.dart';
import 'package:muzician/models/app_theme_variant.dart';
import 'package:muzician/models/project_config.dart';
import 'package:muzician/store/piano_store.dart';
import 'package:muzician/store/save_system_store.dart';
import 'package:muzician/store/settings_store.dart';
import 'package:muzician/theme/studio_theme.dart';
import 'package:muzician/ui/glass_snackbar.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Root extends ConsumerWidget {
  const _Root();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variant = ref.watch(settingsProvider.select((s) => s.themeVariant));
    return StudioThemeSource(
      variant: variant,
      child: MaterialApp(
        theme: StudioTheme.data(variant),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showWidgetSheet(
                context: context,
                title: 'Shared sheet',
                scrollBody: false,
                child: const _SheetProbe(),
              ),
              child: const Text('Open sheet'),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetProbe extends StatefulWidget {
  const _SheetProbe();
  @override
  State<_SheetProbe> createState() => _SheetProbeState();
}

class _SheetProbeState extends State<_SheetProbe> {
  final input = TextEditingController();
  final scroll = ScrollController();
  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ColoredBox(
        key: const Key('sheet-palette'),
        color: StudioPalette.of(context).dialogBg,
      ),
      TextField(key: const Key('sheet-input'), controller: input),
      TextButton(
        onPressed: () => showStudioDialog<void>(
          context: context,
          builder: (context) => const _NestedInput(),
        ),
        child: const Text('Nested dialog'),
      ),
      Expanded(
        child: ListView.builder(
          key: const Key('sheet-scroll'),
          controller: scroll,
          itemCount: 50,
          itemBuilder: (_, i) => ListTile(title: Text('Item $i')),
        ),
      ),
    ],
  );
}

class _NestedInput extends StatelessWidget {
  const _NestedInput();
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nested dialog'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ColoredBox(
          key: const Key('nested-palette'),
          color: StudioPalette.of(context).dialogBg,
        ),
        const TextField(key: Key('nested-input')),
      ],
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'open shared sheet and nested modal change live without losing edits or scroll',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(saveSystemProvider.notifier).hydrate();
      final saves = container.read(saveSystemProvider.notifier);
      final project = saves.createProject(
        'Retained project',
        const ProjectConfig(),
      )!;
      saves.selectProject(project);
      container.read(pianoProvider.notifier).loadExactMidis([60, 64, 67]);
      final pianoBefore = container.read(pianoProvider);
      final savesBefore = container.read(saveSystemProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const _Root()),
      );
      await tester.tap(find.text('Open sheet'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('sheet-input')),
        'Unfinished phrase',
      );
      tester.testTextInput.hide();
      await tester.drag(
        find.byKey(const Key('sheet-scroll')),
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      final state = tester.state<_SheetProbeState>(find.byType(_SheetProbe));
      final offset = state.scroll.offset;
      expect(offset, greaterThan(0));
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(
        tester.getBottomRight(find.byKey(const Key('sheet-input'))).dy,
        lessThanOrEqualTo(
          tester.view.physicalSize.height / tester.view.devicePixelRatio - 200,
        ),
      );
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await container
          .read(settingsProvider.notifier)
          .setThemeVariant(AppThemeVariant.studioMuzician);
      await tester.pumpAndSettle();
      expect(
        tester.widget<ColoredBox>(find.byKey(const Key('sheet-palette'))).color,
        StudioPalette.studioMuzician.dialogBg,
      );
      expect(tester.state(find.byType(_SheetProbe)), same(state));
      expect(state.input.text, 'Unfinished phrase');
      expect(state.scroll.offset, offset);
      await tester.tap(find.text('Nested dialog'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('nested-input')),
        'Nested draft',
      );
      final nestedInput = tester.state(find.byType(EditableText).last);
      await container
          .read(settingsProvider.notifier)
          .setThemeVariant(AppThemeVariant.studio);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ColoredBox>(find.byKey(const Key('nested-palette')))
            .color,
        StudioPalette.studio.dialogBg,
      );
      expect(tester.state(find.byType(EditableText).last), same(nestedInput));
      expect(find.text('Nested draft'), findsOneWidget);
      Navigator.of(tester.element(find.byKey(const Key('nested-input')))).pop();
      await tester.pumpAndSettle();
      expect(state.input.text, 'Unfinished phrase');
      expect(state.scroll.offset, offset);
      expect(container.read(pianoProvider), same(pianoBefore));
      expect(container.read(saveSystemProvider), same(savesBefore));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Studio notification stays live and its action remains usable', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const _Root()),
    );
    var actions = 0;
    showGlassSnackbar(
      tester.element(find.text('Open sheet')),
      title: 'Idea saved',
      message: 'Your phrase is ready.',
      contentType: ContentType.success,
      actionLabel: 'Open',
      onAction: () => actions++,
    );
    await tester.pumpAndSettle();
    expect(find.byType(AwesomeSnackbarContent), findsNothing);
    await container
        .read(settingsProvider.notifier)
        .setThemeVariant(AppThemeVariant.studioMuzician);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('Idea saved')).style!.color,
      StudioPalette.studioMuzician.textPrimary,
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(actions, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final viewport in [const Size(320, 844), const Size(1024, 768)]) {
    testWidgets(
      'real app Appearance switches in place and Settings scales at $viewport',
      (tester) async {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MuzicianApp(),
          ),
        );
        for (
          var i = 0;
          i < 30 && find.byType(IndexedStack).evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.tap(find.byKey(const ValueKey('nav_Settings')));
        await tester.pumpAndSettle();
        final shellElement = tester.element(find.byType(IndexedStack).first);
        final choice = find.byKey(
          const ValueKey('settings_theme_studioMuzician'),
        );
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(
          container.read(settingsProvider).themeVariant,
          AppThemeVariant.studioMuzician,
        );
        expect(
          StudioPalette.of(tester.element(choice)),
          StudioPalette.studioMuzician,
        );
        expect(
          tester.element(find.byType(IndexedStack).first),
          same(shellElement),
        );
        expect(tester.takeException(), isNull);
        // Isolate Settings scale from the offstage legacy Writer header, which
        // has its own scale migration and regression gate in P4.
        final settingsScreen = tester.widget(
          find.byKey(const ValueKey('settings_screen')),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: StudioTheme.data(AppThemeVariant.studioMuzician),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
              home: Scaffold(body: settingsScreen),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Settings'), findsOneWidget);
        expect(find.text('Appearance'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
