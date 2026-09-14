import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import '../../../core/app_theme.dart';
import '../../auth/view_models/auth_view_model.dart';
import '../../auth/views/auth_notice.dart';
import '../../auth/views/login_advanced_settings_page.dart';
import '../../auth/views/login_page.dart';
import '../../auth/views/school_connection_page.dart';

class AccountSettingsPage extends StatelessWidget {
  const AccountSettingsPage({required this.viewModel, super.key});

  static const _maxWidth = 1200.0;
  static const _schoolPaneWidth = 280.0;
  static const _twoPaneMinWidth = 960.0;

  final AuthViewModel viewModel;

  bool get _busy => viewModel.state.isBusy || viewModel.isManagingAccounts;

  Future<void> _editSchool(BuildContext context, [SchoolConnection? profile]) =>
      Navigator.of(context).push<SchoolConnection>(
        MaterialPageRoute(
          builder: (context) => SchoolConnectionPage(
            profile: profile,
            isNewSchool: profile == null,
            onSave: viewModel.configureSchool,
          ),
        ),
      );

  Future<void> _advanced(BuildContext context, SchoolConnection profile) =>
      Navigator.of(context).push<SchoolConnection>(
        MaterialPageRoute(
          builder: (context) => LoginAdvancedSettingsPage(
            profile: profile,
            onSave: viewModel.configureSchool,
          ),
        ),
      );

  Future<void> _login(
    BuildContext context,
    SchoolConnection profile, {
    AuthAccountSummary? account,
  }) async {
    final resume =
        account?.scope == viewModel.state.selectedScope &&
        viewModel.state.challenge != null;
    if (!resume) viewModel.cancelSignIn();
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => LoginPage(
          viewModel: viewModel,
          profile: profile,
          usernameHint: account?.account.loginName ?? '',
          rememberPassword: account?.hasSavedPassword ?? false,
        ),
      ),
    );
  }

  Future<void> _signOut(BuildContext context, AccountScope scope) async {
    if (!await viewModel.signOutAccount(scope) || !context.mounted) return;
    _showMessage(context, '已退出账号，学校和离线数据仍然保留');
  }

  Future<void> _removeAccount(
    BuildContext context,
    AuthAccountSummary account,
  ) async {
    final confirmed = await _confirmRemoval(
      context,
      title: '移除本机账号？',
      message:
          '将移除 ${account.account.loginName} 的登录信息、课表、成绩、课程缓存和本地选课记录。学校配置会保留。',
    );
    if (!confirmed) return;
    if (!await viewModel.removeAccount(account.scope) || !context.mounted) {
      return;
    }
    _showMessage(context, '已移除本机账号及其数据');
  }

  Future<void> _removeSchool(
    BuildContext context,
    SchoolConnection profile,
  ) async {
    final confirmed = await _confirmRemoval(
      context,
      title: '移除学校？',
      message: '将移除「${profile.name}」及其所有本机账号、登录信息、课表、成绩、课程缓存和本地选课记录。其他学校不受影响。',
    );
    if (!confirmed) return;
    if (!await viewModel.removeSchool(profile.school.id) || !context.mounted) {
      return;
    }
    _showMessage(context, '已移除学校及其本机账号数据');
  }

  Future<bool> _confirmRemoval(
    BuildContext context, {
    required String title,
    required String message,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text('$message\n\n后续选课尝试会停止。已发送的请求可能已被学校接受，移除本机数据不会退课。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('移除'),
            ),
          ],
        ),
      ) ??
      false;

  void _showMessage(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('账号与学校')),
    body: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              final wide =
                  constraints.maxWidth >= _twoPaneMinWidth &&
                  constraints.maxWidth >= _twoPaneMinWidth * scale;
              return ListenableBuilder(
                listenable: viewModel,
                builder: (context, _) => _content(context, wide: wide),
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _content(BuildContext context, {required bool wide}) {
    final state = viewModel.state;
    final profile = state.profile;
    final accounts = profile == null
        ? <AuthAccountSummary>[]
        : viewModel.accountsForSchool(profile.school.id);
    final detail = <Widget>[
      ..._notices(state),
      if (profile == null)
        _emptySchools(context)
      else ...[
        _schoolDetails(context, profile),
        const SizedBox(height: AppLayout.sectionGap),
        _SectionHeading(
          title: '教务账号 · ${accounts.length}',
          action: _SettingsAction(
            '添加账号',
            onPressed: _busy ? null : () => _login(context, profile),
            primary: true,
            key: const ValueKey('add-account'),
          ),
        ),
        const SizedBox(height: 12),
        if (accounts.isEmpty)
          _emptyAccounts(context, profile)
        else
          for (final account in accounts) ...[
            _accountCard(context, state, account),
            const SizedBox(height: 12),
          ],
      ],
    ];
    if (!wide || state.schools.isEmpty) {
      return ListView(
        key: const PageStorageKey('account-settings-mobile'),
        padding: const EdgeInsets.all(AppLayout.pagePadding),
        children: [
          if (state.schools.isNotEmpty) ...[
            _schoolPicker(context, state),
            const SizedBox(height: AppLayout.sectionGap),
          ],
          ...detail,
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppLayout.workspacePadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _schoolPaneWidth,
            child: ListView(
              key: const PageStorageKey('settings-schools'),
              primary: false,
              children: [
                _SectionHeading(title: '学校 · ${state.schools.length}'),
                const SizedBox(height: 12),
                for (final school in state.schools) ...[
                  _schoolTile(context, state, school),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 4),
                _SettingsButton(
                  action: _SettingsAction(
                    '添加学校',
                    onPressed: _busy ? null : () => _editSchool(context),
                    key: const ValueKey('add-school'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppLayout.paneGap),
          Expanded(
            child: ListView(
              key: const PageStorageKey('settings-accounts'),
              children: detail,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _notices(AuthSnapshot state) => [
    if (_busy) ...[
      const LinearProgressIndicator(semanticsLabel: '正在处理账号信息'),
      const SizedBox(height: 16),
    ],
    if (state.failure case final failure?) ...[
      AuthNotice(message: failure.message),
      const SizedBox(height: 12),
    ],
    if (state.storageFailure case final failure?) ...[
      AuthNotice(message: failure.message),
      const SizedBox(height: 8),
      _SettingsActions(
        actions: [
          _SettingsAction(
            state.accountsLoaded ? '重试保存' : '重试读取',
            onPressed: _busy ? null : viewModel.retryStorage,
          ),
        ],
      ),
      const SizedBox(height: 12),
    ],
    if (viewModel.accountActionFailure case final failure?) ...[
      AuthNotice(message: failure),
      const SizedBox(height: 12),
    ],
  ];

  Widget _schoolPicker(BuildContext context, AuthSnapshot state) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SectionHeading(
        title: '学校管理',
        action: _SettingsAction(
          '添加学校',
          onPressed: _busy ? null : () => _editSchool(context),
          key: const ValueKey('add-school'),
        ),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: ValueKey('school-picker-${state.profile?.school.id}'),
        initialValue: state.profile?.school.id,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: '当前学校',
          border: OutlineInputBorder(),
        ),
        items: [
          for (final school in state.schools)
            DropdownMenuItem(
              value: school.profile.school.id,
              child: Text(school.profile.name, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: _busy
            ? null
            : (value) {
                if (value != null) viewModel.selectSchool(value);
              },
      ),
    ],
  );

  Widget _schoolTile(
    BuildContext context,
    AuthSnapshot state,
    StoredSchool school,
  ) {
    final selected = state.profile?.school.id == school.profile.school.id;
    final count = state.accounts
        .where((account) => account.scope.schoolId == school.profile.school.id)
        .length;
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
      child: ListTile(
        key: ValueKey('school-${school.profile.school.id}'),
        selected: selected,
        enabled: !_busy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(school.profile.name),
        subtitle: Text(
          '$count 个账号 · ${school.profile.baseUri.host}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(
          selected ? Icons.check_circle_outline : Icons.chevron_right,
          size: 20,
        ),
        onTap: selected
            ? null
            : () => viewModel.selectSchool(school.profile.school.id),
      ),
    );
  }

  Widget _schoolDetails(BuildContext context, SchoolConnection profile) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(profile.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          SelectableText(
            profile.baseUri.toString(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _SettingsActions(
            actions: [
              _SettingsAction(
                '编辑学校',
                onPressed: _busy ? null : () => _editSchool(context, profile),
              ),
              _SettingsAction(
                '接口设置',
                onPressed: _busy ? null : () => _advanced(context, profile),
              ),
              _SettingsAction(
                '移除学校',
                onPressed: _busy ? null : () => _removeSchool(context, profile),
                danger: true,
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _accountCard(
    BuildContext context,
    AuthSnapshot state,
    AuthAccountSummary account,
  ) {
    final selected = account.scope == state.selectedScope;
    final theme = Theme.of(context);
    final status = _accountStatus(account);
    return Semantics(
      selected: selected,
      child: Card(
        key: ValueKey(account.scope),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                  final compact = constraints.maxWidth < 300 * scale;
                  return Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2, right: 12),
                        child: Icon(Icons.person_outline),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              account.account.displayName,
                              style: theme.textTheme.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '账号 ${account.account.loginName}',
                              style: theme.textTheme.bodyMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (selected && account.isSignedIn) ...[
                        const SizedBox(width: 8),
                        if (compact)
                          IconButton(
                            tooltip: '验证会话',
                            onPressed: _busy ? null : viewModel.checkSession,
                            icon: const Icon(
                              Icons.verified_user_outlined,
                              size: 20,
                            ),
                          )
                        else
                          TextButton(
                            style: TextButton.styleFrom(
                              minimumSize: const Size(0, 32),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              textStyle: theme.textTheme.labelMedium,
                            ),
                            onPressed: _busy ? null : viewModel.checkSession,
                            child: const Text('验证会话'),
                          ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (selected) const _StatusLabel('当前账号', emphasis: true),
                  _StatusLabel(status, emphasis: account.isSignedIn),
                  if (account.hasSavedPassword) const _StatusLabel('已保存密码'),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                account.remembered
                    ? account.isSignedIn
                          ? '登录状态已保存在本机，学校会话有效时自动恢复。'
                          : '已保留本机登录信息，可重试验证或重新登录。'
                    : account.isSignedIn
                    ? '登录信息尚未保存，仅本次运行有效。'
                    : '账号和离线数据已保留，重新登录后可更新。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (!selected && account.failure != null) ...[
                const SizedBox(height: 12),
                AuthNotice(message: account.failure!.message),
              ],
              const SizedBox(height: 16),
              _SettingsActions(
                actions: _accountActions(context, state, account),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _accountStatus(AuthAccountSummary account) {
    if (account.phase == AuthPhase.captcha) return '需要验证码';
    if (account.phase != AuthPhase.idle) return '正在验证';
    if (account.isSignedIn) return '已连接';
    if (account.failure?.code == LoginFailureCode.expired ||
        account.failure?.code == LoginFailureCode.invalidCredentials ||
        account.failure?.code == LoginFailureCode.accountLocked ||
        account.failure?.code == LoginFailureCode.browserRequired) {
      return '需要重新登录';
    }
    if (!account.remembered) return '已退出登录';
    return '登录待核验';
  }

  List<_SettingsAction> _accountActions(
    BuildContext context,
    AuthSnapshot state,
    AuthAccountSummary account,
  ) {
    final selected = account.scope == state.selectedScope;
    final continueCaptcha = selected && state.challenge != null;
    final canRestore = selected && state.canRestoreSession;
    return [
      if (!selected)
        _SettingsAction(
          '切换账号',
          onPressed: _busy
              ? null
              : () => viewModel.selectAccount(account.scope),
          primary: true,
        )
      else if (!account.isSignedIn)
        _SettingsAction(
          continueCaptcha
              ? '继续验证'
              : canRestore
              ? '恢复登录'
              : '重新登录',
          key: canRestore ? const ValueKey('restore-login') : null,
          onPressed: _busy
              ? null
              : canRestore
              ? viewModel.restore
              : () => _login(context, account.profile, account: account),
          primary: true,
        ),
      if (!selected && !account.isSignedIn)
        _SettingsAction(
          '登录账号',
          onPressed: _busy
              ? null
              : () => _login(context, account.profile, account: account),
        ),
      if (account.remembered || account.isSignedIn)
        _SettingsAction(
          '退出登录',
          onPressed: _busy ? null : () => _signOut(context, account.scope),
        ),
      _SettingsAction(
        '移除账号',
        onPressed: _busy ? null : () => _removeAccount(context, account),
        danger: true,
      ),
    ];
  }

  Widget _emptySchools(BuildContext context) => _EmptyPanel(
    icon: Icons.school_outlined,
    title: '先添加你的学校',
    message: '填写学校名称和教务系统网址。每所学校的账号与数据分别保存。',
    action: _SettingsAction(
      '添加学校',
      onPressed: _busy ? null : () => _editSchool(context),
      primary: true,
      key: const ValueKey('first-school'),
    ),
  );

  Widget _emptyAccounts(BuildContext context, SchoolConnection profile) =>
      const _EmptyPanel(
        icon: Icons.person_add_alt,
        title: '这所学校还没有账号',
        message: '点击“添加账号”登录教务系统。可以在同一学校保存多个账号，之后直接切换。',
      );
}

class _SettingsAction {
  const _SettingsAction(
    this.label, {
    required this.onPressed,
    this.primary = false,
    this.danger = false,
    this.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;
  final Key? key;
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.action});
  final _SettingsAction action;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      foregroundColor: action.danger
          ? Theme.of(context).colorScheme.error
          : null,
    );
    final label = Text(action.label, textAlign: TextAlign.center);
    return action.primary
        ? FilledButton.tonal(
            key: action.key,
            style: style,
            onPressed: action.onPressed,
            child: label,
          )
        : OutlinedButton(
            key: action.key,
            style: style,
            onPressed: action.onPressed,
            child: label,
          );
  }
}

class _SettingsActions extends StatelessWidget {
  const _SettingsActions({required this.actions});
  final List<_SettingsAction> actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      const gap = 8.0;
      final columns = ((constraints.maxWidth + gap) / (112 * scale + gap))
          .floor()
          .clamp(1, 3);
      final width = math.min(
        140 * scale,
        (constraints.maxWidth - gap * (columns - 1)) / columns,
      );
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final action in actions)
            SizedBox(
              width: width,
              child: _SettingsButton(action: action),
            ),
        ],
      );
    },
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.action});
  final String title;
  final _SettingsAction? action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final label = Text(title, style: Theme.of(context).textTheme.titleMedium);
      if (action == null) return label;
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final button = SizedBox(
        width: math.min(140 * scale, constraints.maxWidth),
        child: _SettingsButton(action: action!),
      );
      if (constraints.maxWidth < 300 * scale) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [label, const SizedBox(height: 10), button],
        );
      }
      return Row(
        children: [
          Expanded(child: label),
          const SizedBox(width: 12),
          button,
        ],
      );
    },
  );
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel(this.label, {this.emphasis = false});
  final String label;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: emphasis
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: emphasis
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final _SettingsAction? action;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(message),
          if (action != null) ...[
            const SizedBox(height: 20),
            _SettingsActions(actions: [action!]),
          ],
        ],
      ),
    ),
  );
}
