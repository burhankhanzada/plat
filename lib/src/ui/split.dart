import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart' show internal;

import '../controller/controller.dart';
import '../core/foundation/foundation.dart';
import '../model/plat_snapshot.dart';
import 'divider.dart';
import 'render_split.dart';
import 'theme.dart';

/// Renders a [SplitSnapshot] via [PlatSplit]. Owns the per-split
/// [DividerInteraction] and forwards drag-end commits to the controller.
@internal
class SplitRender extends StatefulWidget {
  /// Snapshot of the split node.
  final SplitSnapshot view;
  final PlatController controller;
  final Widget Function(BuildContext, PlatSnapshot) childBuilder;

  const SplitRender({
    super.key,
    required this.view,
    required this.controller,
    required this.childBuilder,
  });

  @override
  State<SplitRender> createState() => _SplitRenderState();
}

class _SplitRenderState extends State<SplitRender>
    with SingleTickerProviderStateMixin {
  final _interaction = DividerInteraction();

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    // Collapsed children stay in the layout, unlike hidden ones: they are
    // laid out at zero extent so their divider survives and can reopen
    // them.
    final visible = [
      for (final child in view.children)
        if (!child.hidden) child,
    ];
    if (visible.isEmpty) return const SizedBox.shrink();

    final theme = PlatTheme.of(context);
    final dividerTheme = theme.divider;
    final margin = dividerTheme.margin;
    final isHorizontal = view.axis == .horizontal;
    final spacing =
        dividerTheme.thickness +
        (margin != null
            ? (isHorizontal ? margin.horizontal : margin.vertical)
            : 0.0);
    return PlatSplit(
      vsync: this,
      interaction: _interaction,
      cursor: dividerTheme.cursor,
      resizable: view.resizable,
      hitSlop: dividerTheme.hitSlop,
      spacing: spacing,
      axis: view.axis == .horizontal ? .horizontal : .vertical,
      collapsible: {
        for (final child in visible)
          if (child is SlotSnapshot && child.collapsible)
            child.id: child.collapseThreshold,
      },
      collapsed: {
        for (final child in visible)
          if (child is SlotSnapshot && child.collapsible && child.collapsed)
            child.id,
      },
      collapseDuration: theme.collapse.duration,
      collapseCurve: theme.collapse.curve,
      onCommit: (sizes, collapsed) => _commit(view, sizes, collapsed),
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) _divider(i - 1),
          _content(visible[i]),
        ],
      ],
    );
  }

  void _commit(
    SplitSnapshot view,
    List<PlatSize> sizes,
    Map<String, bool> collapsed,
  ) {
    widget.controller.resizeSplit(
      view.id,
      _mergeVisibleSizes(view.children, sizes),
    );
    for (final entry in collapsed.entries) {
      widget.controller.setCollapsed(entry.key, collapsed: entry.value);
    }
  }

  @override
  void dispose() {
    _interaction.dispose();
    super.dispose();
  }

  Widget _content(PlatSnapshot child) => PlatSlotData.content(
    contentId: child.id,
    platSize: child.size,
    child: RepaintBoundary(child: widget.childBuilder(context, child)),
  );

  Widget _divider(int index) => PlatSlotData.divider(
    child: ListenableBuilder(
      listenable: _interaction,
      builder: (context, _) {
        final states = <WidgetState>{
          if (_interaction.hoveredIndex == index) .hovered,
          if (_interaction.draggingIndex == index) .dragged,
        };
        return PlatDivider(states: states);
      },
    ),
  );
}

List<PlatSize> _mergeVisibleSizes(
  List<PlatSnapshot> children,
  List<PlatSize> visibleSizes,
) {
  if (children.length == visibleSizes.length) return visibleSizes;

  final merged = <PlatSize>[];
  var visibleIndex = 0;
  for (final child in children) {
    if (child.hidden) {
      merged.add(child.size);
      continue;
    }
    if (visibleIndex >= visibleSizes.length) return visibleSizes;
    merged.add(visibleSizes[visibleIndex]);
    visibleIndex++;
  }
  return visibleIndex == visibleSizes.length ? merged : visibleSizes;
}
