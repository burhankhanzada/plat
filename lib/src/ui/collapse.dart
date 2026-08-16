import 'package:meta/meta.dart' show immutable, internal;

/// Position of a collapsible slot within a live resize.
///
/// A drag that pushes a slot toward zero does not simply clamp at the
/// slot's minimum: the state machine keeps tracking a *virtual*
/// position past the clamp so the gesture that reverses the collapse
/// feels one-to-one with the pointer. These variants name every
/// position that virtual tracking can be in.
@internal
@immutable
sealed class CollapseState {
  const CollapseState();

  /// Position used for delta bookkeeping. May sit below the slot's
  /// minimum, or below zero, while [displayPixels] stays clamped.
  double? get virtualPixels;

  /// Main-axis extent to lay the slot out at, or `null` when the slot
  /// is collapsed and occupies no space.
  double? get displayPixels;
}

/// The slot is open and inside its declared bounds.
@internal
@immutable
final class CollapseOpen extends CollapseState {
  /// Current main-axis extent, or `null` before the first update.
  final double? pixels;

  const CollapseOpen({this.pixels});

  @override
  double? get displayPixels => pixels;

  @override
  double? get virtualPixels => pixels;
}

/// The slot is being dragged below its minimum but has not yet crossed
/// the collapse threshold.
///
/// Layout clamps to the minimum while [virtualPixels] keeps tracking the
/// pointer, so continuing the drag reaches the threshold at the position
/// the pointer actually is.
@internal
@immutable
final class CollapseBelowMin extends CollapseState {
  /// Extent laid out, clamped to the slot's minimum.
  final double clampedPixels;

  /// Untracked pointer position, below the minimum.
  final double trackedPixels;

  const CollapseBelowMin({
    required this.clampedPixels,
    required this.trackedPixels,
  });

  @override
  double? get displayPixels => clampedPixels;

  @override
  double? get virtualPixels => trackedPixels;
}

/// The slot is collapsed and no drag is tracking it.
@internal
@immutable
final class CollapseClosed extends CollapseState {
  /// Extent to lay the slot out at when it reopens.
  final double? restorePixels;

  const CollapseClosed({this.restorePixels});

  @override
  double? get displayPixels => null;

  @override
  double? get virtualPixels => null;
}

/// The slot is collapsed and a drag is tracking it back toward open.
///
/// The slot reopens once the pointer reverses by the collapse threshold
/// from [lowestPixels], the furthest-closed point of this drag. Tracking
/// the low-water mark rather than the raw position means a user who
/// overshoots the collapse does not have to drag all the way back before
/// the slot responds.
@internal
@immutable
final class CollapsePendingReveal extends CollapseState {
  /// Extent to reopen at, subject to the slot's bounds.
  final double restorePixels;

  /// Current pointer position. Negative while dragging further closed.
  final double trackedPixels;

  /// Furthest-closed position reached during this drag.
  final double lowestPixels;

  const CollapsePendingReveal({
    required this.restorePixels,
    required this.trackedPixels,
    required this.lowestPixels,
  });

  @override
  double? get displayPixels => null;

  @override
  double? get virtualPixels => trackedPixels;
}

/// What a resize step asks the split to do with a collapsible slot.
@internal
@immutable
sealed class CollapseOutcome {
  /// State to carry into the next resize step.
  final CollapseState state;

  const CollapseOutcome(this.state);
}

/// Lay the slot out at [pixels]; it stays open.
@internal
@immutable
final class CollapseResize extends CollapseOutcome {
  /// New main-axis extent.
  final double pixels;

  const CollapseResize({required CollapseState state, required this.pixels})
    : super(state);
}

/// Collapse the slot to zero extent.
@internal
@immutable
final class CollapseClose extends CollapseOutcome {
  const CollapseClose({required CollapseState state}) : super(state);
}

/// Reopen the slot at [pixels].
@internal
@immutable
final class CollapseReveal extends CollapseOutcome {
  /// Extent to reopen at, already clamped to the slot's bounds.
  final double pixels;

  const CollapseReveal({required CollapseState state, required this.pixels})
    : super(state);
}

/// Nothing visible changes; only virtual tracking advanced.
@internal
@immutable
final class CollapseHold extends CollapseOutcome {
  const CollapseHold({required CollapseState state}) : super(state);
}

/// Pure state machine driving drag-to-collapse and drag-to-reveal.
///
/// Every method is static and free of side effects: the caller owns the
/// [CollapseState] and feeds it back in on the next step.
@internal
final class CollapseBehavior {
  const CollapseBehavior._();

  /// State to start a drag from.
  ///
  /// [currentPixels] is the slot's laid-out extent, which is zero when
  /// [collapsed]. [restorePixels] is the extent to reopen at.
  static CollapseState beginDrag({
    required bool collapsed,
    required double currentPixels,
    required double restorePixels,
  }) {
    if (collapsed) {
      return CollapsePendingReveal(
        restorePixels: restorePixels,
        trackedPixels: 0,
        lowestPixels: 0,
      );
    }
    return CollapseOpen(pixels: currentPixels);
  }

  /// Advances the machine one step.
  ///
  /// [requestedPixels] is the extent the pointer is asking for, which may
  /// be below [min] or below zero. [threshold] is the extent at which an
  /// open slot collapses, and the reverse distance at which a collapsed
  /// slot reopens.
  static CollapseOutcome resize({
    required CollapseState state,
    required double requestedPixels,
    required double min,
    required double max,
    required double threshold,
    required bool collapsed,
  }) => switch (state) {
    final CollapsePendingReveal pending => _reveal(
      pending,
      requestedPixels,
      min,
      max,
      threshold,
    ),
    _ when !collapsed => _shrink(state, requestedPixels, min, max, threshold),
    _ => CollapseHold(state: state),
  };

  /// Resting state to settle into when the drag ends.
  static CollapseState settle({
    required CollapseState state,
    required bool collapsed,
  }) {
    if (!collapsed) return CollapseOpen(pixels: state.displayPixels);
    return CollapseClosed(
      restorePixels: switch (state) {
        CollapsePendingReveal(:final restorePixels) => restorePixels,
        CollapseOpen(:final pixels) => pixels,
        CollapseBelowMin(:final clampedPixels) => clampedPixels,
        CollapseClosed(:final restorePixels) => restorePixels,
      },
    );
  }

  static CollapseOutcome _reveal(
    CollapsePendingReveal state,
    double requestedPixels,
    double min,
    double max,
    double threshold,
  ) {
    final lowest = requestedPixels < state.lowestPixels
        ? requestedPixels
        : state.lowestPixels;
    if (requestedPixels - lowest >= threshold) {
      final pixels = requestedPixels.clamp(min, max);
      return CollapseReveal(
        state: CollapseOpen(pixels: pixels),
        pixels: pixels,
      );
    }
    return CollapseHold(
      state: CollapsePendingReveal(
        restorePixels: state.restorePixels,
        trackedPixels: requestedPixels,
        lowestPixels: lowest,
      ),
    );
  }

  static CollapseOutcome _shrink(
    CollapseState state,
    double requestedPixels,
    double min,
    double max,
    double threshold,
  ) {
    if (requestedPixels < threshold) {
      final restore = switch (state) {
        CollapseOpen(:final pixels) => pixels ?? min,
        CollapseBelowMin(:final clampedPixels) => clampedPixels,
        CollapsePendingReveal(:final restorePixels) => restorePixels,
        CollapseClosed(:final restorePixels) => restorePixels ?? min,
      };
      return CollapseClose(
        state: CollapsePendingReveal(
          restorePixels: restore,
          trackedPixels: requestedPixels,
          lowestPixels: requestedPixels,
        ),
      );
    }
    if (requestedPixels < min) {
      return CollapseResize(
        state: CollapseBelowMin(
          clampedPixels: min,
          trackedPixels: requestedPixels,
        ),
        pixels: min,
      );
    }
    final pixels = requestedPixels.clamp(min, max);
    return CollapseResize(
      state: CollapseOpen(pixels: pixels),
      pixels: pixels,
    );
  }
}
