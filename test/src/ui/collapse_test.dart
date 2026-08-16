import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plat/plat.dart';
import 'package:plat/src/ui/collapse.dart';

import 'ui_test_helpers.dart';

void main() {
  group('CollapseBehavior', () {
    test('a resize inside bounds leaves the slot open', () {
      final outcome = CollapseBehavior.resize(
        state: const CollapseOpen(pixels: 200),
        requestedPixels: 180,
        min: 100,
        max: 400,
        threshold: 50,
        collapsed: false,
      );
      expect(outcome, isA<CollapseResize>());
      expect((outcome as CollapseResize).pixels, 180);
      expect(outcome.state, isA<CollapseOpen>());
    });

    test('a resize below min clamps the extent but tracks the pointer', () {
      final outcome = CollapseBehavior.resize(
        state: const CollapseOpen(pixels: 200),
        requestedPixels: 70,
        min: 100,
        max: 400,
        threshold: 50,
        collapsed: false,
      );
      expect(outcome, isA<CollapseResize>());
      expect((outcome as CollapseResize).pixels, 100);
      expect(outcome.state, isA<CollapseBelowMin>());
      expect((outcome.state as CollapseBelowMin).trackedPixels, 70);
    });

    test('crossing the threshold closes the slot and keeps a restore', () {
      final outcome = CollapseBehavior.resize(
        state: const CollapseOpen(pixels: 200),
        requestedPixels: 40,
        min: 100,
        max: 400,
        threshold: 50,
        collapsed: false,
      );
      expect(outcome, isA<CollapseClose>());
      final state = outcome.state as CollapsePendingReveal;
      expect(state.restorePixels, 200);
      expect(state.lowestPixels, 40);
    });

    test('a closed slot holds until the pointer reverses by the threshold', () {
      const state = CollapsePendingReveal(
        restorePixels: 200,
        trackedPixels: 0,
        lowestPixels: 0,
      );
      final held = CollapseBehavior.resize(
        state: state,
        requestedPixels: 30,
        min: 100,
        max: 400,
        threshold: 50,
        collapsed: true,
      );
      expect(held, isA<CollapseHold>());

      final revealed = CollapseBehavior.resize(
        state: held.state,
        requestedPixels: 60,
        min: 100,
        max: 400,
        threshold: 50,
        collapsed: true,
      );
      expect(revealed, isA<CollapseReveal>());
      // Reopening never lands below the slot's own minimum.
      expect((revealed as CollapseReveal).pixels, 100);
    });

    test('reversal is measured from the furthest-closed point, not zero', () {
      // Overshooting the collapse must not make the reopen gesture longer.
      var state = CollapseBehavior.beginDrag(
        collapsed: true,
        currentPixels: 0,
        restorePixels: 200,
      );
      for (final requested in [-40.0, -80.0, -120.0]) {
        state = CollapseBehavior.resize(
          state: state,
          requestedPixels: requested,
          min: 100,
          max: 400,
          threshold: 50,
          collapsed: true,
        ).state;
      }
      final outcome = CollapseBehavior.resize(
        state: state,
        requestedPixels: -70,
        min: 100,
        max: 400,
        threshold: 50,
        collapsed: true,
      );
      expect(outcome, isA<CollapseReveal>());
    });

    test('settle keeps the restore extent across a closed drag', () {
      final settled = CollapseBehavior.settle(
        state: const CollapsePendingReveal(
          restorePixels: 240,
          trackedPixels: -30,
          lowestPixels: -30,
        ),
        collapsed: true,
      );
      expect((settled as CollapseClosed).restorePixels, 240);
    });
  });

  group('collapsible slot layout', () {
    testWidgets('an open collapsible slot claims its declared extent', (
      tester,
    ) async {
      final c = _collapsibleSplit();
      await tester.pumpWidget(_centered(_app(c)));
      expect(_bodyWidth(tester, 'panel'), closeTo(200, 0.5));
      expect(_bodyWidth(tester, 'main'), closeTo(396, 0.5));
    });

    testWidgets('a collapsed slot takes no space and hands it to siblings', (
      tester,
    ) async {
      final c = _collapsibleSplit(collapsed: true);
      await tester.pumpWidget(_centered(_app(c)));
      await tester.pumpAndSettle();
      expect(_bodyWidth(tester, 'main'), closeTo(596, 0.5));
      // The subtree stays mounted so reopening is instant; it just has
      // no extent and is skipped in paint.
      expect(_bodyWidth(tester, 'panel'), 0);
    });

    testWidgets('the divider survives a collapse so the slot can reopen', (
      tester,
    ) async {
      final c = _collapsibleSplit(collapsed: true);
      await tester.pumpWidget(_centered(_app(c)));
      await tester.pumpAndSettle();
      expect(find.byType(PlatDivider), findsOneWidget);
    });

    testWidgets('a hidden slot drops its divider, unlike a collapsed one', (
      tester,
    ) async {
      final c = _collapsibleSplit();
      await tester.pumpWidget(_centered(_app(c)));
      c.setHidden('panel-slot', hidden: true);
      await tester.pumpAndSettle();
      expect(find.byType(PlatDivider), findsNothing);
    });
  });

  group('programmatic collapse', () {
    testWidgets('setCollapsed animates closed and restores the same extent', (
      tester,
    ) async {
      final c = _collapsibleSplit();
      await tester.pumpWidget(_centered(_app(c)));
      final before = _bodyWidth(tester, 'panel');

      expect(c.setCollapsed('panel-slot', collapsed: true), isTrue);
      await tester.pump();
      // Mid-transition the slot is neither fully open nor fully gone.
      await tester.pump(const Duration(milliseconds: 90));
      final mid = _bodyWidth(tester, 'main');
      expect(mid, greaterThan(396));
      expect(mid, lessThan(596));
      await tester.pumpAndSettle();
      expect(_bodyWidth(tester, 'main'), closeTo(596, 0.5));

      expect(c.setCollapsed('panel-slot', collapsed: false), isTrue);
      await tester.pumpAndSettle();
      expect(_bodyWidth(tester, 'panel'), closeTo(before, 0.5));
    });

    testWidgets('setCollapsed is a no-op on a slot that is not collapsible', (
      tester,
    ) async {
      final c = _collapsibleSplit(collapsible: false);
      await tester.pumpWidget(_centered(_app(c)));
      expect(c.setCollapsed('panel-slot', collapsed: true), isFalse);
      await tester.pumpAndSettle();
      expect(_bodyWidth(tester, 'panel'), closeTo(200, 0.5));
    });

    testWidgets('setCollapsed is a no-op on a non-slot id', (tester) async {
      final c = _collapsibleSplit();
      await tester.pumpWidget(_centered(_app(c)));
      expect(c.setCollapsed('main', collapsed: true), isFalse);
    });
  });

  group('drag to collapse and reveal', () {
    testWidgets('dragging past the threshold collapses the slot', (
      tester,
    ) async {
      final c = _collapsibleSplit();
      await tester.pumpWidget(_centered(_app(c)));
      // The panel sits on the right, so dragging right shrinks it.
      await _dragDivider(tester, 170);
      await tester.pumpAndSettle();

      expect(_collapsedFlag(c), isTrue);
      expect(_bodyWidth(tester, 'main'), closeTo(596, 0.5));
    });

    testWidgets('a collapse keeps the pre-drag extent as the restore', (
      tester,
    ) async {
      final c = _collapsibleSplit();
      await tester.pumpWidget(_centered(_app(c)));
      await _dragDivider(tester, 170);
      await tester.pumpAndSettle();

      c.setCollapsed('panel-slot', collapsed: false);
      await tester.pumpAndSettle();
      expect(_bodyWidth(tester, 'panel'), closeTo(200, 0.5));
    });

    testWidgets('stopping short of the threshold clamps at min instead', (
      tester,
    ) async {
      final c = _collapsibleSplit();
      await tester.pumpWidget(_centered(_app(c)));
      await _dragDivider(tester, 90);
      await tester.pumpAndSettle();

      expect(_collapsedFlag(c), isFalse);
      expect(_bodyWidth(tester, 'panel'), closeTo(120, 0.5));
    });

    testWidgets('dragging back past the threshold reopens the slot', (
      tester,
    ) async {
      final c = _collapsibleSplit(collapsed: true);
      await tester.pumpWidget(_centered(_app(c)));
      await tester.pumpAndSettle();

      await _dragDivider(tester, -90);
      await tester.pumpAndSettle();

      expect(_collapsedFlag(c), isFalse);
      expect(_bodyWidth(tester, 'panel'), greaterThan(0));
    });

    testWidgets('a nudge shorter than the threshold leaves it collapsed', (
      tester,
    ) async {
      final c = _collapsibleSplit(collapsed: true);
      await tester.pumpWidget(_centered(_app(c)));
      await tester.pumpAndSettle();

      await _dragDivider(tester, -20);
      await tester.pumpAndSettle();

      expect(_collapsedFlag(c), isTrue);
    });

    testWidgets('a slot without collapsible just clamps at its min', (
      tester,
    ) async {
      final c = _collapsibleSplit(collapsible: false);
      await tester.pumpWidget(_centered(_app(c)));
      await _dragDivider(tester, 170);
      await tester.pumpAndSettle();

      expect(_collapsedFlag(c), isFalse);
      expect(_bodyWidth(tester, 'panel'), closeTo(120, 0.5));
    });
  });
}

Widget _app(PlatController c) => testHost(
  PlatTheme(
    data: const PlatThemeData(divider: PlatDividerTheme(thickness: 4)),
    child: PlatView(
      controller: c,
      leafBuilder: (_, p) => Center(child: Text('body:${p.id}')),
    ),
  ),
);

double _bodyWidth(WidgetTester tester, String id) => tester
    .getSize(
      find
          .ancestor(of: find.text('body:$id'), matching: find.byType(Center))
          .first,
    )
    .width;

Widget _centered(Widget child) =>
    Center(child: SizedBox(width: 600, height: 200, child: child));

bool _collapsedFlag(PlatController c) =>
    (c.snapshot('panel-slot')! as SlotSnapshot).collapsed;

/// Builds a 600 px-wide row: a flexible `main` pane and a 200 px `panel`
/// slot with a 120 px minimum, so the default collapse threshold is 60 px.
PlatController _collapsibleSplit({
  bool collapsible = true,
  bool collapsed = false,
}) => PlatController(
  initialPlat: PlatSplit.row(
    id: 'root',
    children: [
      const PlatLeaf(id: 'main'),
      PlatSlot(
        id: 'panel-slot',
        size: const .resizable(initial: .pixel(200), min: .pixel(120)),
        collapsible: collapsible,
        collapsed: collapsed,
        child: const PlatLeaf(id: 'panel'),
      ),
    ],
  ),
);

/// Drags the split's single divider by [dx] logical pixels in steps, so
/// the collapse state machine sees a realistic stream of updates.
Future<void> _dragDivider(WidgetTester tester, double dx) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(PlatDivider)),
  );
  const steps = 12;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(dx / steps, 0));
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}
