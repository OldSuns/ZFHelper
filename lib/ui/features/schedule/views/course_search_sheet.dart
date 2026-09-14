import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import '../../../core/adaptive_sheet.dart';
import 'course_detail_sheet.dart';

Future<ScheduleEntry?> showScheduleCourseSearch(
  BuildContext context, {
  required ScheduleSnapshot snapshot,
}) => showAdaptiveSheet<ScheduleEntry>(
  context: context,
  builder: (context) => _CourseSearch(snapshot: snapshot),
);

class _CourseSearch extends StatefulWidget {
  const _CourseSearch({required this.snapshot});
  final ScheduleSnapshot snapshot;

  @override
  State<_CourseSearch> createState() => _CourseSearchState();
}

class _CourseSearchState extends State<_CourseSearch> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final words = _query.trim().toLowerCase().split(RegExp(r'\s+'));
    final matches =
        widget.snapshot.entries.where((entry) {
          final text = [
            entry.name,
            entry.teacher,
            entry.location,
            entry.campus,
            entry.courseCode,
            entry.metadata['jxbmc'],
          ].whereType<String>().join(' ').toLowerCase();
          return words.every(text.contains);
        }).toList()..sort((left, right) {
          final name = left.name.compareTo(right.name);
          return name == 0 ? compareScheduleEntries(left, right) : name;
        });
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '查找本学期课程',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭课程搜索',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('schedule-search-input'),
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: '课程、教师、教室',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: 12),
                    Text('共 ${matches.length} 条上课安排，包含本学期所有周次'),
                  ],
                ),
              ),
            ),
            if (matches.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('没有找到匹配的课程'),
                ),
              ),
            SliverList.builder(
              itemCount: matches.length,
              itemBuilder: (context, index) {
                final entry = matches[index];
                return ListTile(
                  title: Text(entry.name),
                  subtitle: Text(
                    [
                      '${scheduleWeekdayText(entry.weekday)} · ${entry.schedulePeriodsText}',
                      entry.scheduleWeeksText,
                      entry.schedulePlaceText,
                      if (entry.teacher != null) entry.teacher!,
                    ].join('\n'),
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).pop(entry),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}
