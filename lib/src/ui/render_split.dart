import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart' show internal;

import '../core/foundation/foundation.dart';
import 'collapse.dart';

const _zeroSlop = DeviceGestureSettings(touchSlop: 0);
const _leafDragHandleSize = Size(22, 4);

/// Pixel allocation for [platSizes] within [available] main-axis pixels.
/// Concrete sizes (`FixedSize`, or `FlexibleSize` with a non-auto
/// `initial`) claim pixels up front; the leftover splits equally among
/// auto-initial `FlexibleSize` siblings.
///
/// When no auto siblings exist, `FlexibleSize` claims are scaled to
/// fill the leftover after fixed claims. This keeps the layout intact
/// after a structural mutation that leaves sibling fractions out of
/// balance (closing a sibling so the rest sum below 1, or over-claimed
/// pixel siblings totalling more than `available`).
List<double> _computeSizes(List<PlatSize> platSizes, double available) {
  final claimed = List<double>.filled(platSizes.length, 0);
  final shareIndices = <int>[];
  final flexibleIndices = <int>[];
  var flexibleConsumed = 0.0;
  var fixedConsumed = 0.0;
  for (var i = 0; i < platSizes.length; i++) {
    final size = platSizes[i];
    final pixels = size.claim(available);
    if (pixels == null) {
      shareIndices.add(i);
    } else {
      claimed[i] = pixels;
      if (size is FlexibleSize) {
        flexibleIndices.add(i);
        flexibleConsumed += pixels;
      } else {
        fixedConsumed += pixels;
      }
    }
  }
  if (shareIndices.isNotEmpty) {
    final per =
        (available - fixedConsumed - flexibleConsumed).clamp(0.0, available) /
        shareIndices.length;
    for (final i in shareIndices) {
      claimed[i] = per;
    }
    return claimed;
  }
  if (flexibleIndices.isNotEmpty && flexibleConsumed > 0) {
    final availableForFlexible = (available - fixedConsumed).clamp(
      0.0,
      available,
    );
    if ((flexibleConsumed - availableForFlexible).abs() > 0.5) {
      final scale = availableForFlexible / flexibleConsumed;
      for (final i in flexibleIndices) {
        claimed[i] *= scale;
      }
    }
  }
  return claimed;
}

/// Default collapse threshold when a slot declares no minimum extent.
const _fallbackCollapseThreshold = 20.0;

typedef _Drag = ({
  Offset startGlobal,
  _Slot left,
  _Slot right,
  double available,
});

typedef _PairUpdate = ({PlatSize leftSize, PlatSize rightSize});

/// A content child as of the last layout. [pixels] is the extent it was
/// laid out at (zero while collapsed); [openPixels] is the extent it
/// claims when open, which is what a reopen restores to.
typedef _Slot = ({String id, PlatSize size, double pixels, double openPixels});

/// Commit handler for a finished divider drag. [sizes] carries one entry
/// per content child; [collapsed] carries only the slots whose collapsed
/// state changed.
@internal
typedef SplitCommit =
    void Function(List<PlatSize> sizes, Map<String, bool> collapsed);

class _SplitParentData extends ContainerBoxParentData<RenderBox> {
  // `contentId == null` discriminates a divider from a content child.
  String? contentId;
  PlatSize? platSize;
}

/// Tags a child of [PlatSplit] as a content pane or a divider. Content
/// children carry the [String] and [PlatSize] used by the render
/// object's sizing pass; dividers carry no extra data.
@internal
class PlatSlotData extends ParentDataWidget<_SplitParentData> {
  final String? contentId;
  final PlatSize? platSize;

  const PlatSlotData.content({
    super.key,
    required String this.contentId,
    required PlatSize this.platSize,
    required super.child,
  });

  const PlatSlotData.divider({super.key, required super.child})
    : contentId = null,
      platSize = null;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _SplitParentData;
    if (data.contentId == contentId && data.platSize == platSize) return;
    data.contentId = contentId;
    data.platSize = platSize;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => PlatSplit;
}

/// Hover/drag indices published by [RenderPlatSplit] and read by the
/// divider widgets. Leaves never subscribe.
@internal
class DividerInteraction extends ChangeNotifier {
  int? _hovered;
  int? _dragging;

  int? get hoveredIndex => _hovered;

  int? get draggingIndex => _dragging;

  void setHovered(int? value) {
    if (_hovered == value) return;
    _hovered = value;
    notifyListeners();
  }

  void setDragging(int? value) {
    if (_dragging == value) return;
    _dragging = value;
    notifyListeners();
  }
}

/// Render-object widget for a [PlatSplit] node. Children alternate content
/// and divider via [PlatSlotData].
@internal
class PlatSplit extends MultiChildRenderObjectWidget {
  final Axis axis;
  final double spacing;
  final double hitSlop;
  final bool resizable;
  final DividerInteraction interaction;
  final SplitCommit onCommit;
  final MouseCursor? cursor;

  /// Collapse threshold per collapsible content child, keyed by node id.
  /// A child absent from this map cannot collapse by drag.
  final Map<String, PlatExtent> collapsible;

  /// Ids of the content children that are currently collapsed.
  final Set<String> collapsed;

  /// Ticker source for the collapse/reopen transition.
  final TickerProvider vsync;

  /// Duration of the collapse/reopen transition.
  final Duration collapseDuration;

  /// Curve of the collapse/reopen transition.
  final Curve collapseCurve;

  const PlatSplit({
    super.key,
    required this.axis,
    required this.spacing,
    required this.hitSlop,
    required this.resizable,
    required this.interaction,
    required this.onCommit,
    required this.collapsible,
    required this.collapsed,
    required this.vsync,
    required this.collapseDuration,
    required this.collapseCurve,
    required super.children,
    this.cursor,
  });

  @override
  RenderPlatSplit createRenderObject(BuildContext context) => RenderPlatSplit(
    axis: axis,
    spacing: spacing,
    hitSlop: hitSlop,
    resizable: resizable,
    interaction: interaction,
    onCommit: onCommit,
    collapsible: collapsible,
    collapsed: collapsed,
    vsync: vsync,
    collapseDuration: collapseDuration,
    collapseCurve: collapseCurve,
    cursor: cursor,
  );

  @override
  void updateRenderObject(BuildContext context, RenderPlatSplit renderObject) {
    renderObject
      ..axis = axis
      ..spacing = spacing
      ..hitSlop = hitSlop
      ..resizable = resizable
      ..interaction = interaction
      ..onCommit = onCommit
      ..collapsible = collapsible
      ..vsync = vsync
      ..collapseDuration = collapseDuration
      ..collapseCurve = collapseCurve
      ..collapsed = collapsed
      ..cursor = cursor;
  }
}

/// Owns layout, hit-testing, mouse cursor, and drag gestures for a
/// [PlatSplit]. A single drag recognizer per split owns every divider;
/// live drag updates reflow this render object alone — leaves and
/// divider widgets do not rebuild.
@internal
class RenderPlatSplit extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SplitParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SplitParentData>
    implements MouseTrackerAnnotation {
  RenderPlatSplit({
    required this._axis,
    required this._spacing,
    required this.hitSlop,
    required this.resizable,
    required this.interaction,
    required this.onCommit,
    required this.collapsible,
    required this._collapsed,
    required this._vsync,
    required this._collapseDuration,
    required this._collapseCurve,
    this._cursor,
  });

  Axis _axis;
  double _spacing;
  double hitSlop;
  bool resizable;
  DividerInteraction interaction;
  SplitCommit onCommit;
  Map<String, PlatExtent> collapsible;
  MouseCursor? _cursor;

  set cursor(MouseCursor? value) {
    if (_cursor == value) return;
    _cursor = value;
    if (!attached) return;
    markNeedsPaint();

    // TODO(elias8): Need to rework on this.
    // The annotation is reported by this render object directly, not
    // through a paint layer, so the per-frame mouse-tracker sweep does
    // not pick up the new cursor on its own. Force a device update.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) RendererBinding.instance.mouseTracker.updateAllDevices();
    });
  }

  // Plat snapshot, refilled every performLayout.
  final _slots = <_Slot>[];
  final _gutterCenters = <double>[];
  double _availableMain = 0;

  // Drag-only overrides. Setting triggers markNeedsLayout, no rebuild.
  // `_liveCollapsed` is non-null only while dragging a divider next to a
  // collapsible slot, and always starts as a copy of `_collapsed`.
  Map<String, PlatSize>? _liveSizes;
  Set<String>? _liveCollapsed;

  // Per-side collapse tracking for the live drag, keyed by node id.
  final _dragCollapse = <String, CollapseState>{};

  // Committed collapse state, and the in-flight transition toward it.
  // While `_collapseFrom` holds an id, that id's extent is interpolated
  // rather than read straight off `_collapsed`.
  Set<String> _collapsed;
  final _collapseFrom = <String, double>{};
  final _collapseTo = <String, double>{};
  AnimationController? _collapseAnimation;
  TickerProvider _vsync;
  Duration _collapseDuration;
  Curve _collapseCurve;

  // `_pending` is set on PointerDown; the recognizer consumes it in
  // onDragStart. `_drag` is non-null while a drag is live.
  int? _pending;
  _Drag? _drag;

  DragGestureRecognizer? _recognizer;

  set collapsed(Set<String> value) {
    if (setEquals(_collapsed, value)) return;
    // Anchor every id whose target moves — including ones already
    // mid-flight — at the extent it is showing right now, so a change
    // that lands mid-transition continues from where the eye is.
    final touched = {..._collapsed, ...value, ..._collapseTo.keys};
    final from = <String, double>{};
    for (final id in touched) {
      from[id] = _extentFactorFor(id);
    }
    _collapsed = value;
    _collapseFrom
      ..clear()
      ..addAll(from);
    _collapseTo
      ..clear()
      ..addEntries(
        touched.map((id) => MapEntry(id, value.contains(id) ? 0.0 : 1.0)),
      );
    _collapseFrom.removeWhere((id, value) => value == _collapseTo[id]);
    _collapseTo.removeWhere((id, _) => !_collapseFrom.containsKey(id));
    if (_collapseFrom.isEmpty) {
      _collapseAnimation?.stop();
      markNeedsLayout();
      return;
    }
    _startCollapseAnimation();
  }

  set collapseCurve(Curve value) => _collapseCurve = value;

  set collapseDuration(Duration value) {
    if (_collapseDuration == value) return;
    _collapseDuration = value;
    _collapseAnimation?.duration = value;
  }

  set vsync(TickerProvider value) {
    if (_vsync == value) return;
    _vsync = value;
    _collapseAnimation?.resync(value);
  }

  Axis get axis => _axis;

  set axis(Axis value) {
    if (_axis == value) return;
    _axis = value;
    if (attached) _resetRecognizer();
    markNeedsLayout();
  }

  double get spacing => _spacing;

  set spacing(double value) {
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  bool get _isHorizontal => _axis == Axis.horizontal;

  double _mainOf(Offset point) => _isHorizontal ? point.dx : point.dy;

  Offset _mainOffset(double main) =>
      _isHorizontal ? Offset(main, 0) : Offset(0, main);

  BoxConstraints _tightAxis(double main, double cross) =>
      BoxConstraints.tightFor(
        width: _isHorizontal ? main : cross,
        height: _isHorizontal ? cross : main,
      );

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SplitParentData) {
      child.parentData = _SplitParentData();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _resetRecognizer();
  }

  @override
  void detach() {
    _recognizer?.dispose();
    _recognizer = null;
    super.detach();
  }

  @override
  void dispose() {
    _collapseAnimation?.dispose();
    _collapseAnimation = null;
    _recognizer?.dispose();
    _recognizer = null;
    super.dispose();
  }

  void _startCollapseAnimation() {
    final animation = _collapseAnimation ??= AnimationController(
      vsync: _vsync,
      duration: _collapseDuration,
    )..addListener(markNeedsLayout);
    animation
      ..duration = _collapseDuration
      ..forward(from: 0).whenCompleteOrCancel(() {
        // Settled: `_collapsed` alone describes every extent again.
        if (animation.isAnimating) return;
        _collapseFrom.clear();
        _collapseTo.clear();
      });
  }

  /// Fraction of its open extent that [id] currently occupies: `1` when
  /// open, `0` when collapsed, in between mid-transition.
  double _extentFactorFor(String id) {
    final live = _liveCollapsed;
    // A drag owns the extent outright — no transition competes with the
    // pointer.
    if (live != null) return live.contains(id) ? 0.0 : 1.0;
    final from = _collapseFrom[id];
    final to = _collapseTo[id];
    final animation = _collapseAnimation;
    if (from == null || to == null || animation == null) {
      return _collapsed.contains(id) ? 0.0 : 1.0;
    }
    return from + (to - from) * _collapseCurve.transform(animation.value);
  }

  void _resetRecognizer() {
    _recognizer?.dispose();
    _recognizer =
        (_isHorizontal
              ? HorizontalDragGestureRecognizer(debugOwner: this)
              : VerticalDragGestureRecognizer(debugOwner: this))
          ..gestureSettings = _zeroSlop
          ..onStart = _onDragStart
          ..onUpdate = _onDragUpdate
          ..onEnd = (_) {
            _finishDrag();
          }
          ..onCancel = _finishDrag;
  }

  @override
  void performLayout() {
    _slots.clear();
    _gutterCenters.clear();

    final (mainExtent, crossExtent) = _isHorizontal
        ? (constraints.maxWidth, constraints.maxHeight)
        : (constraints.maxHeight, constraints.maxWidth);

    final platSizes = _readContentSizes(overrides: _liveSizes);
    if (platSizes.isEmpty || !mainExtent.isFinite || mainExtent <= 0) {
      size = constraints.smallest;
      return;
    }

    final dividerCount = childCount - platSizes.length;
    _availableMain = (mainExtent - dividerCount * _spacing).clamp(
      0.0,
      mainExtent,
    );
    // `open` is what each child claims with nothing collapsed; it stays
    // the restore extent for a collapsed slot. `laid` scales those claims
    // by the collapse factor and hands the freed pixels to the children
    // that are still fully open.
    final open = _computeSizes(platSizes, _availableMain);
    final laid = _applyCollapse(open);

    var offset = 0.0;
    var contentIndex = 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final data = child.parentData! as _SplitParentData;
      final isContent = data.contentId != null;
      final mainSize = isContent ? laid[contentIndex] : _spacing;
      child.layout(_tightAxis(mainSize, crossExtent));
      data.offset = _mainOffset(offset);
      if (isContent) {
        _slots.add((
          id: data.contentId!,
          size: data.platSize!,
          pixels: mainSize,
          openPixels: open[contentIndex],
        ));
        contentIndex++;
      } else {
        _gutterCenters.add(offset + _spacing / 2);
      }
      offset += mainSize;
    }

    size = constraints.biggest;
  }

  /// Scales [open] by each content child's collapse factor and
  /// redistributes the freed pixels across the children that are still
  /// fully open, proportionally to what they already claim.
  ///
  /// Returns [open] untouched when nothing is collapsing, so a split with
  /// no collapsible slot keeps its existing allocation exactly.
  List<double> _applyCollapse(List<double> open) {
    final factors = <double>[];
    var collapsing = false;
    var index = 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final id = (child.parentData! as _SplitParentData).contentId;
      if (id == null) continue;
      final factor = _extentFactorFor(id);
      if (factor < 1) collapsing = true;
      factors.add(factor);
      index++;
    }
    if (!collapsing || index != open.length) return open;

    final laid = [for (var i = 0; i < open.length; i++) open[i] * factors[i]];
    var freed = 0.0;
    for (var i = 0; i < open.length; i++) {
      freed += open[i] - laid[i];
    }
    if (freed <= 0) return laid;

    final openIndices = [
      for (var i = 0; i < factors.length; i++)
        if (factors[i] == 1) i,
    ];
    if (openIndices.isEmpty) return laid;

    var claimed = 0.0;
    for (final i in openIndices) {
      claimed += laid[i];
    }
    for (final i in openIndices) {
      laid[i] += claimed > 0
          ? freed * (laid[i] / claimed)
          : freed / openIndices.length;
    }
    return laid;
  }

  /// Walk content children and return their [PlatSize]s, with any
  /// [overrides] applied. Used by the layout pass and the drag-end
  /// commit path.
  List<PlatSize> _readContentSizes({Map<String, PlatSize>? overrides}) {
    final result = <PlatSize>[];
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final data = child.parentData! as _SplitParentData;
      final id = data.contentId;
      if (id != null) result.add(overrides?[id] ?? data.platSize!);
    }
    return result;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final data = child.parentData! as _SplitParentData;
      // A fully collapsed child is laid out at zero main extent; its
      // subtree would otherwise paint outside those bounds.
      final main = _isHorizontal ? child.size.width : child.size.height;
      if (main <= 0) continue;
      context.paintChild(child, offset + data.offset);
    }
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    if (_drag != null) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    final gutter = _gutterAt(position);
    final liveGutter = (gutter != null && !_isLockedAt(gutter)) ? gutter : null;
    if (liveGutter != null && _isLeafDragHandleHit(position)) {
      interaction.setHovered(null);
      return hitTestChildren(result, position: position);
    }
    interaction.setHovered(liveGutter);
    if (liveGutter != null) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return hitTestChildren(result, position: position);
  }

  bool _isLeafDragHandleHit(Offset position) {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final data = child.parentData! as _SplitParentData;
      if (data.contentId == null) continue;
      final rect =
          Offset(
            data.offset.dx + (child.size.width - _leafDragHandleSize.width) / 2,
            data.offset.dy,
          ) &
          _leafDragHandleSize;
      if (rect.contains(position)) return true;
    }
    return false;
  }

  int? _gutterAt(Offset position) {
    final main = _mainOf(position);
    final halfHit = _spacing / 2 + hitSlop;
    for (var i = 0; i < _gutterCenters.length; i++) {
      if ((main - _gutterCenters[i]).abs() <= halfHit) return i;
    }
    return null;
  }

  bool _isLockedAt(int dividerIndex) =>
      !resizable ||
      _slots[dividerIndex].size is FixedSize ||
      _slots[dividerIndex + 1].size is FixedSize;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is! PointerDownEvent) return;
    final gutter = _gutterAt(event.localPosition);
    if (gutter == null || _isLockedAt(gutter)) return;
    _pending = gutter;
    _recognizer?.addPointer(event);
  }

  @override
  MouseCursor get cursor {
    return _cursor ??
        (_isHorizontal
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow);
  }

  @override
  PointerEnterEventListener? get onEnter => null;

  @override
  PointerExitEventListener? get onExit {
    return (_) => interaction.setHovered(null);
  }

  @override
  bool get validForMouseTracker => attached;

  void _onDragStart(DragStartDetails details) {
    final pending = _pending;
    if (pending == null || pending >= _gutterCenters.length) return;
    final left = _slots[pending];
    final right = _slots[pending + 1];
    if (left.size is! FlexibleSize || right.size is! FlexibleSize) return;
    _drag = (
      startGlobal: details.globalPosition,
      left: left,
      right: right,
      available: _availableMain,
    );
    _dragCollapse.clear();
    for (final slot in [left, right]) {
      if (!collapsible.containsKey(slot.id)) continue;
      _dragCollapse[slot.id] = CollapseBehavior.beginDrag(
        collapsed: _collapsed.contains(slot.id),
        currentPixels: slot.pixels,
        restorePixels: slot.openPixels,
      );
    }
    if (_dragCollapse.isNotEmpty) _liveCollapsed = {..._collapsed};
    interaction.setDragging(pending);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final drag = _drag;
    if (drag == null) return;
    final delta = _mainOf(details.globalPosition) - _mainOf(drag.startGlobal);
    if (_dragCollapse.isNotEmpty) {
      _updateCollapsibleDrag(drag, delta);
      return;
    }
    _applyPair(drag, _resizePair(drag, drag.left.pixels + delta));
  }

  /// Runs one drag step through the collapse state machine for whichever
  /// side of the divider is a live collapse candidate, falling back to a
  /// plain pair resize when neither is.
  void _updateCollapsibleDrag(_Drag drag, double delta) {
    final live = _liveCollapsed!;
    final target = _collapseTarget(drag, delta, live);
    if (target == null) {
      _applyPair(drag, _resizePair(drag, drag.left.pixels + delta));
      return;
    }

    final isLeft = target.id == drag.left.id;
    final bounds = (target.size as FlexibleSize).bounds(drag.available);
    final outcome = CollapseBehavior.resize(
      state: _dragCollapse[target.id]!,
      requestedPixels: isLeft
          ? drag.left.pixels + delta
          : drag.right.pixels - delta,
      min: bounds.min,
      max: bounds.max,
      threshold: _thresholdFor(target.id, drag.available, bounds.min),
      collapsed: live.contains(target.id),
    );
    _dragCollapse[target.id] = outcome.state;

    switch (outcome) {
      case CollapseHold():
        return;
      case CollapseClose():
        live.add(target.id);
        // Drop the size overrides so the slot commits its declared
        // extent: that is what a reopen restores to.
        _liveSizes = null;
        markNeedsLayout();
      case CollapseReveal(:final pixels):
        live.remove(target.id);
        _applyPair(drag, _resizePair(drag, _wantLeftFor(drag, isLeft, pixels)));
        markNeedsLayout();
      case CollapseResize(:final pixels):
        _applyPair(drag, _resizePair(drag, _wantLeftFor(drag, isLeft, pixels)));
    }
  }

  /// The side of [drag] the collapse machine should drive this step.
  ///
  /// An already-collapsed side wins, so the reveal gesture stays with the
  /// slot the user closed. Otherwise the shrinking side is the candidate.
  _Slot? _collapseTarget(_Drag drag, double delta, Set<String> live) {
    final leftTracked = _dragCollapse.containsKey(drag.left.id);
    final rightTracked = _dragCollapse.containsKey(drag.right.id);
    if (leftTracked && live.contains(drag.left.id)) return drag.left;
    if (rightTracked && live.contains(drag.right.id)) return drag.right;
    if (delta < 0 && leftTracked) return drag.left;
    if (delta > 0 && rightTracked) return drag.right;
    return null;
  }

  /// Translates a desired extent for one side into the left side's extent,
  /// which is what [_resizePair] takes.
  double _wantLeftFor(_Drag drag, bool isLeft, double pixels) =>
      isLeft ? pixels : drag.left.pixels + (drag.right.pixels - pixels);

  /// Collapse threshold for [id] in pixels. [PlatExtent.auto] resolves to
  /// half the slot's minimum, or a flat fallback when it declares none.
  double _thresholdFor(String id, double available, double min) {
    final extent = collapsible[id];
    if (extent == null || extent is AutoExtent) {
      return min > 0 ? min / 2 : _fallbackCollapseThreshold;
    }
    return extent.pixels(available);
  }

  void _applyPair(_Drag drag, _PairUpdate? updated) {
    if (updated == null) return;
    _liveSizes = {
      drag.left.id: updated.leftSize,
      drag.right.id: updated.rightSize,
    };
    markNeedsLayout();
  }

  void _finishDrag() {
    final overrides = _liveSizes;
    final live = _liveCollapsed;
    _drag = null;
    _pending = null;
    _liveSizes = null;
    _liveCollapsed = null;
    _dragCollapse.clear();
    interaction.setDragging(null);

    final changed = <String, bool>{};
    if (live != null) {
      for (final id in {...live, ..._collapsed}) {
        final collapsed = live.contains(id);
        if (collapsed != _collapsed.contains(id)) changed[id] = collapsed;
      }
      // Adopt the drag's result up front so the rebuild it triggers is a
      // no-op for `collapsed` and never animates what the pointer already
      // did.
      if (changed.isNotEmpty) {
        _collapsed = live;
        _collapseFrom.clear();
        _collapseTo.clear();
        _collapseAnimation?.stop();
      }
    }

    if (overrides == null && changed.isEmpty) return;
    markNeedsLayout();
    // A slot that just collapsed keeps its declared size as the extent to
    // restore on reopen, so its override is dropped from the commit.
    final sizes = {...?overrides}..removeWhere((id, _) => changed[id] ?? false);
    onCommit(_readContentSizes(overrides: sizes), changed);
  }

  _PairUpdate? _resizePair(_Drag drag, double wantLeftRaw) {
    final left = drag.left.size as FlexibleSize;
    final right = drag.right.size as FlexibleSize;
    final leftBounds = left.bounds(drag.available);
    final rightBounds = right.bounds(drag.available);

    final wantLeft = wantLeftRaw.clamp(leftBounds.min, leftBounds.max);
    final wantRight = (drag.right.pixels - (wantLeft - drag.left.pixels)).clamp(
      rightBounds.min,
      rightBounds.max,
    );
    final shift = drag.right.pixels - wantRight;
    if (shift == 0) return null;

    return (
      leftSize: left.withPixels(drag.left.pixels + shift, drag.available),
      rightSize: right.withPixels(drag.right.pixels - shift, drag.available),
    );
  }
}

extension on PlatExtent {
  double maxBound(double available) =>
      this is AutoExtent ? available : pixels(available);

  double minBound(double available) =>
      this is AutoExtent ? 0 : pixels(available);

  /// Resolve to pixels. [AutoExtent] resolves to 0 — call [minBound] or
  /// [maxBound] when you want auto to mean "no bound".
  double pixels(double available) => switch (this) {
    Pixels(:final value) => value,
    Fraction(:final value) => value * available,
    AutoExtent() => 0,
  };
}

extension on PlatSize {
  /// Pixels claimed up front; `null` when this size shares the leftover
  /// (an auto-initial `FlexibleSize`).
  double? claim(double available) => switch (this) {
    FixedSize(:final extent) => extent.pixels(available),
    FlexibleSize(:final initial, :final min, :final max) =>
      initial is AutoExtent
          ? null
          : initial
                .pixels(available)
                .clamp(min.minBound(available), max.maxBound(available)),
  };
}

extension on FlexibleSize {
  ({double min, double max}) bounds(double available) =>
      (min: min.minBound(available), max: max.maxBound(available));

  /// Rewrite [initial] to reflect [newPixels], preserving the original
  /// unit (`Fraction` stays fractional, anything else becomes `Pixels`).
  FlexibleSize withPixels(double newPixels, double available) {
    final PlatExtent next = switch (initial) {
      Fraction() when available > 0 => .fraction(
        (newPixels / available).clamp(0.0, 1.0),
      ),
      _ => .pixel(newPixels),
    };
    return copyWith(initial: next);
  }
}
