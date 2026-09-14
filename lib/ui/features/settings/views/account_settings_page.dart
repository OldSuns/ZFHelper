import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import '../../../core/app_theme.dart';
import '../../auth/view_models/auth_view_model.dart';
import '../../auth/views/auth_notice.dart';
import '../../auth/views/login_page.dart';

class AccountSettingsPage extends StatelessWidget {
  const AccountSettingsPage({required this.viewModel, super.key});

  final AuthViewModel viewModel;

  Future<void> _openLogin(BuildContext context) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (context) => LoginPage(viewModel: viewModel)),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    await viewModel.signOut();
    if (!context.mounted || viewModel.state.storageFailure != null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已清除本机登录信息')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('账号与设置')),
    body: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListenableBuilder(
            listenable: viewModel,
            builder: (context, _) => _content(context, viewModel.state),
          ),
        ),
      ),
    ),
  );

  Widget _content(BuildContext context, AuthSnapshot state) {
    final theme = Theme.of(context);
    final account = state.account;
    final knownAccount = account ?? state.knownIdentity?.account;
    final expired = state.needsSignIn;
    return ListView(
      padding: const EdgeInsets.all(AppLayout.pagePadding),
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
        const SizedBox(height: AppLayout.sectionGap),
        Text('教务账号', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  account != null
                      ? '已连接'
                      : state.isBusy
                      ? '正在恢复登录'
                      : expired && knownAccount != null
                      ? '登录已失效'
                      : knownAccount != null
                      ? '登录待核验'
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
                        : expired
                        ? '教务会话已失效，学校设置和已保存的课表仍然保留。'
                        : '本机登录信息已保留，请恢复网络后重试核验。',
                  ),
                  const SizedBox(height: 12),
                ] else
                  const Text('通过密码、学校网页登录或 Cookie 导入连接教务账号。'),
                if (state.isBusy) ...[
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
                ],
                const SizedBox(height: 20),
                if (state.canRestoreSession) ...[
                  FilledButton.tonal(
                    key: const ValueKey('restore-login'),
                    onPressed: state.isBusy ? null : viewModel.restore,
                    child: const Text('重试恢复登录'),
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton(
                  onPressed: state.isBusy ? null : () => _openLogin(context),
                  child: Text(
                    state.challenge != null
                        ? '继续验证码验证'
                        : account == null
                        ? '登录 / 更换学校'
                        : '切换学校或账号',
                  ),
                ),
                if (account != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: state.isBusy ? null : viewModel.checkSession,
                    child: const Text('验证当前会话'),
                  ),
                ],
                TextButton(
                  onPressed: () => _signOut(context),
                  child: Text(account == null ? '清除本机登录信息' : '退出并清除本机登录'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
