import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import '../../../core/app_theme.dart';
import '../../auth/view_models/auth_view_model.dart';
import '../../auth/views/auth_notice.dart';
import '../../auth/views/login_page.dart';

class AccountSettingsPage extends StatelessWidget {
  const AccountSettingsPage({required this.viewModel, super.key});

  static const _accountRowMinWidth = 720.0;

  final AuthViewModel viewModel;

  Future<void> _openLogin(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => LoginPage(viewModel: viewModel)),
    );
  }

  Future<void> _signOut(BuildContext context, [AccountScope? scope]) async {
    if (scope == null) {
      await viewModel.signOut();
    } else if (!await viewModel.signOutAccount(scope)) {
      return;
    }
    if (!context.mounted || viewModel.state.storageFailure != null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已退出账号，学校和离线数据仍然保留')));
  }

  Future<void> _remove(BuildContext context, AuthAccountSummary account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除本机账号'),
        content: Text(
          '删除 ${account.profile.name} · ${account.account.loginName} 的登录信息与本地缓存。'
          '\n\n已发送的选课请求可能已被学校接受，删除账号不会退课。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await viewModel.removeAccount(account.scope);
    if (!removed || !context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已删除本机账号及缓存')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('账号与设置')),
    body: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= AppLayout.workspaceMinWidth;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: wide ? AppLayout.workspaceMaxWidth : 640,
              ),
              child: ListenableBuilder(
                listenable: viewModel,
                builder: (context, _) =>
                    _content(context, viewModel.state, wide: wide),
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _content(
    BuildContext context,
    AuthSnapshot state, {
    required bool wide,
  }) {
    final others = state.accounts.where(
      (entry) => entry.scope != state.selectedScope,
    );
    final accounts = [
      Text('教务账号', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      _accountCard(context, state, wide: wide),
      if (others.isNotEmpty) ...[
        const SizedBox(height: AppLayout.sectionGap),
        Text('其他账号', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final saved in others)
          _savedAccount(
            context,
            saved,
            busy: state.isBusy || viewModel.isManagingAccounts,
          ),
      ],
    ];
    if (!wide) {
      return ListView(
        padding: const EdgeInsets.all(AppLayout.pagePadding),
        children: [
          _schoolSection(context, state),
          const SizedBox(height: AppLayout.sectionGap),
          ...accounts,
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppLayout.workspacePadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: AppLayout.detailPaneWidth,
            child: ListView(
              primary: false,
              children: [_schoolSection(context, state)],
            ),
          ),
          const SizedBox(width: AppLayout.paneGap),
          Expanded(child: ListView(children: accounts)),
        ],
      ),
    );
  }

  Widget _schoolSection(BuildContext context, AuthSnapshot state) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('教务系统', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.profile?.name ?? '尚未设置学校',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (state.profile != null)
                  Text(state.profile!.baseUri.toString()),
                const SizedBox(height: 8),
                const Text('支持自定义学校与新正方教务地址'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _accountCard(
    BuildContext context,
    AuthSnapshot state, {
    required bool wide,
  }) {
    final theme = Theme.of(context);
    final account = state.account;
    final selected = state.accounts
        .where((entry) => entry.scope == state.selectedScope)
        .firstOrNull;
    final knownAccount =
        account ?? state.knownIdentity?.account ?? selected?.account;
    final expired = state.needsSignIn;
    final busy = state.isBusy || viewModel.isManagingAccounts;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              account != null
                  ? '已连接'
                  : busy
                  ? '正在恢复登录'
                  : expired && knownAccount != null
                  ? '登录已失效'
                  : state.knownIdentity != null
                  ? '登录待核验'
                  : selected != null
                  ? '已退出登录'
                  : '尚未连接',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (knownAccount != null) ...[
              Text(
                knownAccount.displayName,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text('账号 ${knownAccount.loginName}'),
              const SizedBox(height: 12),
              Text(
                account != null
                    ? state.remembered
                          ? '登录信息已加密保存在本机，重启后自动恢复'
                          : '当前登录仅在本次运行中有效'
                    : state.knownIdentity == null
                    ? '账号名称和离线数据已保留，可重新登录后更新教务数据。'
                    : expired
                    ? '教务会话已失效，学校设置和已保存的课表仍然保留。'
                    : '本机登录信息已保留，请恢复网络后重试核验。',
              ),
              const SizedBox(height: 12),
            ] else
              const Text('通过密码、学校网页登录或 Cookie 导入连接教务账号。'),
            if (busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(semanticsLabel: '正在验证登录信息'),
            ],
            if (state.failure case final failure?) ...[
              const SizedBox(height: 16),
              AuthNotice(message: failure.message),
            ],
            if (state.storageFailure case final failure?) ...[
              const SizedBox(height: 16),
              AuthNotice(message: failure.message),
              TextButton(
                onPressed: busy ? null : viewModel.retryStorage,
                child: Text(state.accounts.isEmpty ? '重试读取本机账号' : '重试保存账号信息'),
              ),
            ],
            if (viewModel.accountActionFailure case final failure?) ...[
              const SizedBox(height: 16),
              AuthNotice(message: failure),
            ],
            const SizedBox(height: 20),
            _accountActions(context, state, selected: selected, wide: wide),
          ],
        ),
      ),
    );
  }

  Widget _accountActions(
    BuildContext context,
    AuthSnapshot state, {
    required AuthAccountSummary? selected,
    required bool wide,
  }) {
    final busy = state.isBusy || viewModel.isManagingAccounts;
    final actions = <Widget>[
      if (state.canRestoreSession)
        FilledButton.tonal(
          key: const ValueKey('restore-login'),
          onPressed: busy ? null : viewModel.restore,
          child: const Text('重试恢复登录'),
        ),
      FilledButton(
        onPressed: busy ? null : () => _openLogin(context),
        child: Text(
          state.challenge != null
              ? '继续验证码验证'
              : state.account == null
              ? '登录 / 更换学校'
              : '切换学校或账号',
        ),
      ),
      if (state.account != null)
        OutlinedButton(
          onPressed: busy ? null : viewModel.checkSession,
          child: const Text('验证当前会话'),
        ),
      if (state.knownIdentity != null)
        TextButton(
          onPressed: viewModel.isManagingAccounts
              ? null
              : () => _signOut(context),
          child: const Text('退出并清除本机登录'),
        ),
      if (selected != null)
        TextButton.icon(
          onPressed: busy ? null : () => _remove(context, selected),
          icon: const Icon(Icons.delete_outline),
          label: const Text('删除账号与本地缓存'),
        ),
    ];
    return wide
        ? Wrap(spacing: 8, runSpacing: 8, children: actions)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < actions.length; index++) ...[
                if (index > 0) const SizedBox(height: 8),
                actions[index],
              ],
            ],
          );
  }

  Widget _savedAccount(
    BuildContext context,
    AuthAccountSummary saved, {
    required bool busy,
  }) {
    final theme = Theme.of(context);
    final status = saved.isSignedIn
        ? saved.remembered
              ? '会话可用'
              : '仅本次运行可用'
        : saved.phase == AuthPhase.captcha
        ? '需要验证码'
        : saved.remembered
        ? saved.failure?.message ?? '登录信息已保存'
        : '已退出登录';
    return Card(
      key: ValueKey(saved.scope),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= _accountRowMinWidth;
            final information = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(saved.profile.name, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  '${saved.account.displayName} · ${saved.account.loginName}',
                ),
                const SizedBox(height: 4),
                Text(status, style: theme.textTheme.bodySmall),
              ],
            );
            final actions = Wrap(
              alignment: horizontal ? WrapAlignment.end : WrapAlignment.start,
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonal(
                  onPressed: busy
                      ? null
                      : () => viewModel.selectAccount(saved.scope),
                  child: const Text('切换到此账号'),
                ),
                if (saved.remembered || saved.isSignedIn)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => _signOut(context, saved.scope),
                    child: const Text('退出'),
                  ),
                IconButton(
                  tooltip: '删除 ${saved.account.loginName}',
                  onPressed: busy ? null : () => _remove(context, saved),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            );
            return horizontal
                ? Row(
                    children: [
                      Expanded(flex: 3, child: information),
                      const SizedBox(width: AppLayout.paneGap),
                      Expanded(flex: 2, child: actions),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [information, const SizedBox(height: 8), actions],
                  );
          },
        ),
      ),
    );
  }
}
