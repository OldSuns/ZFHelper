import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

class TeachingWeekSelector extends StatefulWidget {
  const TeachingWeekSelector({
    super.key,
    required this.value,
    required this.weekCount,
    required this.onChanged,
    this.currentWeek,
    this.enabled = true,
    this.semanticLabel,
    this.keyPrefix = 'teaching-week',
  }) : assert(weekCount > 0),
       assert(currentWeek == null || currentWeek > 0);

  final Set<int> value;
  final int weekCount;
  final ValueChanged<Set<int>> onChanged;
  final int? currentWeek;
  final bool enabled;
  final String? semanticLabel;
  final String keyPrefix;

  @override
  State<TeachingWeekSelector> createState() => _TeachingWeekSelectorState();
}

class _TeachingWeekSelectorState extends State<TeachingWeekSelector> {
  // Pagination bounds rendering work without limiting valid week numbers.
  static const _pageSize = 42;
  static const _gap = 8.0;
  static const _minimumTarget = 48.0;
  final _weekKeys = <int, GlobalKey>{};
  int _page = 0;
  int? _dragStart;
  Set<int> _dragWeeks = const {};
  String? _rangeError;

  int get _lastWeek => widget.value.fold(
    math.max(widget.weekCount, widget.currentWeek ?? 1),
    math.max,
  );

  @override
  Widget build(BuildContext context) {
    final lastWeek = _lastWeek;
    final page = math.min(_page, (lastWeek - 1) ~/ _pageSize);
    final start = page * _pageSize + 1;
    final end = start + math.min(_pageSize - 1, lastWeek - start);
    final otherSelected =
        widget.value.where((week) => week < start || week > end).toList()
          ..sort();
    final shortcutStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(_minimumTarget, _minimumTarget),
      visualDensity: VisualDensity.standard,
    );
    final navigationStyle = IconButton.styleFrom(
      minimumSize: const Size(_minimumTarget, _minimumTarget),
      visualDensity: VisualDensity.standard,
    );
    _weekKeys.removeWhere((week, _) => week < start || week > end);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.semanticLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: _gap,
            runSpacing: _gap,
            children: [
              if (widget.currentWeek case final week?)
                OutlinedButton(
                  key: ValueKey('${widget.keyPrefix}-current-week'),
                  style: shortcutStyle,
                  onPressed: widget.enabled ? () => _change({week}) : null,
                  child: const Text('当前周'),
                ),
              OutlinedButton(
                key: ValueKey('${widget.keyPrefix}-all-weeks'),
                style: shortcutStyle,
                onPressed: widget.enabled ? () => _selectRange() : null,
                child: Text('1–${widget.weekCount} 周'),
              ),
              OutlinedButton(
                key: ValueKey('${widget.keyPrefix}-odd-weeks'),
                style: shortcutStyle,
                onPressed: widget.enabled ? () => _selectRange('单') : null,
                child: const Text('单周'),
              ),
              OutlinedButton(
                key: ValueKey('${widget.keyPrefix}-even-weeks'),
                style: shortcutStyle,
                onPressed: widget.enabled && widget.weekCount >= 2
                    ? () => _selectRange('双')
                    : null,
                child: const Text('双周'),
              ),
            ],
          ),
          if (_rangeError case final error?) ...[
            const SizedBox(height: _gap),
            Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text('点击切换周次；触屏长按后滑动或鼠标拖动，可连续追加选择。'),
          if (lastWeek > _pageSize) ...[
            const SizedBox(height: _gap),
            Row(
              children: [
                IconButton(
                  tooltip: '前一组周次',
                  style: navigationStyle,
                  onPressed: widget.enabled && page > 0
                      ? () => setState(() => _page = page - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text('显示 $start–$end 周', textAlign: TextAlign.center),
                ),
                IconButton(
                  tooltip: '后一组周次',
                  style: navigationStyle,
                  onPressed: widget.enabled && end < lastWeek
                      ? () => setState(() => _page = page + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (otherSelected.isNotEmpty)
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.standard,
                ),
                onPressed: widget.enabled
                    ? () => setState(
                        () => _page = (otherSelected.first - 1) ~/ _pageSize,
                      )
                    : null,
                child: const Text('查看其他已选周次'),
              ),
          ],
          const SizedBox(height: _gap),
          GestureDetector(
            excludeFromSemantics: true,
            supportedDevices: const {PointerDeviceKind.mouse},
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: widget.enabled
                ? (details) => _startDrag(details.globalPosition)
                : null,
            onPanUpdate: widget.enabled
                ? (details) => _extendDrag(details.globalPosition)
                : null,
            onPanEnd: widget.enabled ? (_) => _endDrag() : null,
            onPanCancel: widget.enabled ? _endDrag : null,
            child: GestureDetector(
              excludeFromSemantics: true,
              supportedDevices: const {
                PointerDeviceKind.touch,
                PointerDeviceKind.stylus,
                PointerDeviceKind.invertedStylus,
              },
              onLongPressStart: widget.enabled
                  ? (details) => _startDrag(details.globalPosition)
                  : null,
              onLongPressMoveUpdate: widget.enabled
                  ? (details) => _extendDrag(details.globalPosition)
                  : null,
              onLongPressEnd: widget.enabled ? (_) => _endDrag() : null,
              onLongPressCancel: widget.enabled ? _endDrag : null,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textWidth = TextPainter(
                    text: TextSpan(
                      text: '$end',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                  )..layout();
                  final targetWidth = math.max(
                    _minimumTarget,
                    textWidth.width + 40,
                  );
                  textWidth.dispose();
                  final columns = math.max(
                    1,
                    ((constraints.maxWidth + _gap) / (targetWidth + _gap))
                        .floor(),
                  );
                  final width =
                      (constraints.maxWidth - (columns - 1) * _gap) / columns;
                  return Wrap(
                    spacing: _gap,
                    runSpacing: _gap,
                    children: [
                      for (var offset = 0; offset <= end - start; offset++)
                        SizedBox(
                          key: _weekKeys.putIfAbsent(
                            start + offset,
                            GlobalKey.new,
                          ),
                          width: width,
                          child: _weekButton(context, start + offset),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _weekButton(BuildContext context, int week) {
    final selected = widget.value.contains(week);
    final colors = Theme.of(context).colorScheme;
    return OutlinedButton(
      key: ValueKey('${widget.keyPrefix}-week-$week'),
      onPressed: widget.enabled
          ? () => _change({
              ...widget.value.where((value) => value != week),
              if (!selected) week,
            })
          : null,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(_minimumTarget, _minimumTarget),
        visualDensity: VisualDensity.standard,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        backgroundColor: selected ? colors.primaryContainer : null,
        foregroundColor: selected
            ? colors.onPrimaryContainer
            : colors.onSurface,
        side: BorderSide(color: selected ? colors.primary : colors.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Semantics(
        selected: selected,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              child: selected
                  ? const ExcludeSemantics(child: Icon(Icons.check, size: 16))
                  : null,
            ),
            const SizedBox(width: 4),
            Flexible(child: Text('$week', semanticsLabel: '第 $week 周')),
          ],
        ),
      ),
    );
  }

  void _selectRange([String? parity]) {
    final Set<int> weeks;
    try {
      weeks = parseTeachingWeeks(
        '1-${widget.weekCount}${parity == null ? '' : '($parity)'}',
      );
    } on ScheduleParseException {
      setState(() => _rangeError = '周次范围过大，请通过文字输入或分段点选。');
      return;
    }
    _change(weeks);
  }

  void _change(Set<int> weeks) {
    if (_rangeError != null) setState(() => _rangeError = null);
    widget.onChanged(Set.unmodifiable(weeks));
  }

  int? _weekAt(Offset globalPosition) {
    for (final entry in _weekKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box != null &&
          (Offset.zero & box.size).contains(
            box.globalToLocal(globalPosition),
          )) {
        return entry.key;
      }
    }
    return null;
  }

  void _startDrag(Offset position) {
    _dragStart = _weekAt(position);
    _dragWeeks = widget.value;
    _extendDrag(position);
  }

  void _extendDrag(Offset position) {
    final start = _dragStart;
    final end = _weekAt(position);
    if (start == null || end == null) return;
    final first = math.min(start, end);
    final last = math.max(start, end);
    final selected = {
      ..._dragWeeks,
      for (var offset = 0; offset <= last - first; offset++) first + offset,
    };
    if (selected.length == _dragWeeks.length) return;
    _dragWeeks = selected;
    _change(selected);
  }

  void _endDrag() {
    _dragStart = null;
    _dragWeeks = const {};
  }
}
