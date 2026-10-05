import 'package:flutter/material.dart';

import '../../../../data/repositories/grade_repository.dart';
import '../../../../data/repositories/schedule_repository.dart';
import '../../../../data/storage/academic_account.dart';
import '../../../core/app_theme.dart';
import '../../courses/view_models/courses_view_model.dart';
import '../../grades/view_models/grades_view_model.dart';
import '../../schedule/view_models/timetable_view_model.dart';

class LocalDataPage extends StatelessWidget {
  const LocalDataPage({
    required this.timetable,
    required this.grades,
    required this.courses,
    super.key,
  });

  final TimetableViewModel timetable;
  final GradesViewModel grades;
  final CoursesViewModel courses;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('本地数据')),
    body: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListenableBuilder(
            listenable: Listenable.merge([timetable, grades, courses]),
            builder: (context, _) => ListView(
              padding: const EdgeInsets.all(AppLayout.workspacePadding),
              children: [
                const Text(
                  '已获取的数据按学校和账号保存在本机，直到你主动更新或清除。退出登录会保留离线数据；在“账号与学校”中移除账号或学校会同时移除其本机数据。',
                ),
                const SizedBox(height: AppLayout.sectionGap),
                _CacheSection(
                  title: '课表与日程',
                  loading: timetable.data.loading,
                  failure:
                      timetable.data.failure?.kind ==
                          ScheduleFailureKind.storage
                      ? timetable.data.failure?.message
                      : null,
                  onRetry: timetable.retryLocalLoad,
                  children: [
                    for (final saved in timetable.data.library.accounts)
                      _CacheAccount(
                        account: saved.account,
                        summary:
                            '${saved.schedules.length} 个学期的课表 · ${saved.events.length} 项个人日程',
                        updates: saved.schedules.values.map(
                          (item) => item.fetchedAt,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppLayout.sectionGap),
                _CacheSection(
                  title: '成绩',
                  loading: grades.data.loading,
                  failure: grades.data.failure?.kind == GradeFailureKind.storage
                      ? grades.data.failure?.message
                      : null,
                  onRetry: grades.retryLocalLoad,
                  children: [
                    for (final saved in grades.data.library.accounts)
                      _CacheAccount(
                        account: saved.account,
                        summary: saved.snapshot == null
                            ? '尚未查询成绩'
                            : '${saved.snapshot!.records.length} 条成绩',
                        updates: [
                          if (saved.snapshot case final snapshot?)
                            snapshot.fetchedAt,
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: AppLayout.sectionGap),
                _CacheSection(
                  title: '选课',
                  loading: courses.data.loading,
                  failure: courses.data.failure,
                  onRetry: courses.data.accountSyncPending
                      ? courses.retryAccountSync
                      : !courses.data.initialized
                      ? courses.initialize
                      : null,
                  children: [
                    for (final saved in courses.data.library.accounts)
                      _CacheAccount(
                        account: saved.account,
                        summary:
                            '${saved.catalogs.length} 个选课轮次的课程 · '
                            '${courses.data.operations.where((operation) => operation.target.scope == saved.account.scope).length} 条操作记录',
                        updates: [
                          ?saved.roundsFetchedAt,
                          for (final cache in saved.catalogs) ...[
                            cache.fetchedAt,
                            ?cache.selectedFetchedAt,
                          ],
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _CacheSection extends StatelessWidget {
  const _CacheSection({
    required this.title,
    required this.loading,
    required this.failure,
    required this.onRetry,
    required this.children,
  });

  final String title;
  final bool loading;
  final String? failure;
  final VoidCallback? onRetry;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 10),
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (loading) const LinearProgressIndicator(),
              if (failure != null) ...[
                Text(
                  failure!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                if (onRetry != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: loading ? null : onRetry,
                      child: const Text('重试读取'),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
              if (children.isEmpty && !loading && failure == null)
                const Text('尚无本地数据'),
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) const Divider(height: 24),
                children[index],
              ],
            ],
          ),
        ),
      ),
    ],
  );
}

class _CacheAccount extends StatelessWidget {
  const _CacheAccount({
    required this.account,
    required this.summary,
    required this.updates,
  });

  final AcademicAccountRecord account;
  final String summary;
  final Iterable<DateTime> updates;

  @override
  Widget build(BuildContext context) {
    final sorted = updates.toList()..sort();
    final updated = sorted.lastOrNull?.toLocal();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(account.schoolName, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text('${account.accountName} · ${account.loginName}'),
        const SizedBox(height: 8),
        Text(summary),
        if (updated != null) ...[
          const SizedBox(height: 4),
          Text(
            '最近获取 ${updated.year}/${updated.month}/${updated.day} '
            '${updated.hour.toString().padLeft(2, '0')}:'
            '${updated.minute.toString().padLeft(2, '0')}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
