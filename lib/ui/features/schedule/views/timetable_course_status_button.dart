import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

class TimetableCourseStatusButton extends StatelessWidget {
  const TimetableCourseStatusButton({
    required this.countdown,
    required this.onPressed,
    super.key,
  });

  static const _height = 48.0;
  static const _titleSize = 13.0;
  static const _timeSize = 12.0;
  static const _lineHeight = 1.2;
  static const _lineGap = 2.0;
  static const _iconSize = 18.0;
  static const _arrowGap = 4.0;
  static const _clockGap = 8.0;

  final ScheduleCountdown countdown;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final multiple = countdown.lessons.length > 1;
    final course = multiple
        ? '${countdown.lessons.length} 项课程'
        : countdown.lessons.single.entry.name;
    final units = countdown.remainingUnits!;
    final time = '$units ${countdown.showSeconds ? '秒' : '分钟'}';
    final shortTime = '$units${countdown.showSeconds ? '秒' : '分'}';
    final countdownLabel = multiple ? '最近下课 $shortTime' : '距下课 $time';
    final description =
        '${countdown.lessons.map((lesson) => lesson.entry.name).join('、')}，'
        '正在上课，${multiple ? '距最近一节下课' : '距下课'} $time';
    const titleStyle = TextStyle(
      fontSize: _titleSize,
      height: _lineHeight,
      fontWeight: FontWeight.w600,
    );
    const timeStyle = TextStyle(
      fontSize: _timeSize,
      height: _lineHeight,
      fontWeight: FontWeight.w600,
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: SizedBox(
        height: _height,
        child: Tooltip(
          message: '$description\n点击选择学期',
          excludeFromSemantics: true,
          child: TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              foregroundColor: colors.onPrimaryContainer,
              backgroundColor: colors.primaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: const Size(48, _height),
              visualDensity: VisualDensity.standard,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Semantics(
              label: description,
              hint: '选择学期',
              child: ExcludeSemantics(
                child: ListenableBuilder(
                  // Font loading can relayout labels without changing constraints.
                  listenable: PaintingBinding.instance.systemFonts,
                  builder: (context, _) => LayoutBuilder(
                    builder: (context, constraints) {
                      final scaler = MediaQuery.textScalerOf(context);
                      final titleHeight = _textHeight(
                        context,
                        '$course · 上课中',
                        titleStyle,
                      );
                      final timeHeight = _textHeight(
                        context,
                        countdownLabel,
                        timeStyle,
                      );
                      final compact =
                          titleHeight + timeHeight + _lineGap >
                          constraints.maxHeight;
                      final showClock = !compact && constraints.maxWidth >= 168;
                      final textWidth =
                          constraints.maxWidth -
                          _iconSize -
                          _arrowGap -
                          (showClock ? _iconSize + _clockGap : 0);
                      final compactText =
                          textWidth >= scaler.scale(_timeSize) * 6
                          ? '下课 $shortTime'
                          : shortTime;
                      return Row(
                        children: [
                          if (showClock) ...[
                            const Icon(Icons.schedule, size: _iconSize),
                            const SizedBox(width: _clockGap),
                          ],
                          Expanded(
                            child: compact
                                ? Text(
                                    compactText,
                                    style: timeStyle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              course,
                                              style: titleStyle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Text(' · 上课中', style: titleStyle),
                                        ],
                                      ),
                                      const SizedBox(height: _lineGap),
                                      Text(
                                        countdownLabel,
                                        style: timeStyle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                          ),
                          const SizedBox(width: _arrowGap),
                          const Icon(Icons.expand_more, size: _iconSize),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _textHeight(BuildContext context, String text, TextStyle style) {
    final defaults = DefaultTextStyle.of(context);
    var effectiveStyle = defaults.style.merge(style);
    if (MediaQuery.boldTextOf(context)) {
      effectiveStyle = effectiveStyle.copyWith(fontWeight: FontWeight.bold);
    }
    // Font fallback and scaling can make actual line boxes taller than
    // fontSize * height, so use the same paragraph metrics as the label.
    final painter = TextPainter(
      text: TextSpan(text: text, style: effectiveStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      textHeightBehavior:
          defaults.textHeightBehavior ??
          DefaultTextHeightBehavior.maybeOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }
}
