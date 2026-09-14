import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zf_core/zf_core.dart';

import '../view_models/auth_view_model.dart';
import 'auth_notice.dart';
import 'login_advanced_settings_page.dart';
import 'school_connection_page.dart';
import 'web_login_page.dart';

enum _LoginMode { password, cookie }

enum _LoginSetting { school, advanced }

class LoginPage extends StatefulWidget {
  const LoginPage({required this.viewModel, super.key});
  final AuthViewModel viewModel;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  SchoolConnection? _profile;
  late final TextEditingController _username;
  final _password = TextEditingController();
  final _cookie = TextEditingController();
  final _captcha = TextEditingController();
  _LoginMode _mode = _LoginMode.password;
  bool _rememberPassword = false;
  bool _showPassword = false;
  bool _webOpen = false;
  String? _formFailure;
  Object? _submission;

  bool get _locked =>
      widget.viewModel.state.isBusy ||
      widget.viewModel.state.challenge != null ||
      _webOpen;

  @override
  void initState() {
    super.initState();
    final state = widget.viewModel.state;
    _profile = state.configuredProfile ?? state.profile;
    _username = TextEditingController(
      text:
          state.pendingUsername ??
          (state.knownIdentity?.profile.school.id == _profile?.school.id
              ? state.knownIdentity?.account.loginName
              : null),
    );
  }

  @override
  void dispose() {
    for (final controller in [_username, _password, _cookie, _captcha]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _editSchool({bool isNewSchool = false}) async {
    if (_locked) return;
    final updated = await Navigator.of(context).push<SchoolConnection>(
      MaterialPageRoute(
        builder: (context) => SchoolConnectionPage(
          profile: _profile,
          isNewSchool: isNewSchool,
          onSave: widget.viewModel.configureSchool,
        ),
      ),
    );
    _applyProfile(updated);
  }

  Future<void> _openSettings(_LoginSetting setting) async {
    if (setting == _LoginSetting.school) {
      await _editSchool();
      return;
    }
    if (_locked) return;
    final profile = _profile;
    if (profile == null) {
      await _editSchool(isNewSchool: true);
      return;
    }
    final updated = await Navigator.of(context).push<SchoolConnection>(
      MaterialPageRoute(
        builder: (context) => LoginAdvancedSettingsPage(
          profile: profile,
          onSave: widget.viewModel.configureSchool,
        ),
      ),
    );
    _applyProfile(updated);
  }

  void _applyProfile(SchoolConnection? profile) {
    if (!mounted || profile == null) return;
    _submission = null;
    if (profile.baseUri != _profile?.baseUri) {
      _username.clear();
      _password.clear();
      _cookie.clear();
      _captcha.clear();
    }
    setState(() {
      _profile = profile;
      _formFailure = null;
    });
  }

  Future<void> _submit() async {
    final viewModel = widget.viewModel;
    final profile = _profile;
    if (profile == null) return;
    if (viewModel.state.isBusy || _webOpen) return;
    final submission = Object();
    _submission = submission;
    setState(() => _formFailure = null);
    FocusScope.of(context).unfocus();
    if (viewModel.state.challenge != null) {
      if (_captcha.text.trim().isEmpty) {
        setState(() => _formFailure = '请输入图片验证码');
        return;
      }
      _finish(await viewModel.submitCaptcha(_captcha.text), submission);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    try {
      final success = switch (_mode) {
        _LoginMode.password => await viewModel.signInPassword(
          profile,
          LoginCredentials(username: _username.text, password: _password.text),
          rememberPassword: _rememberPassword,
        ),
        _LoginMode.cookie => await viewModel.signInCookies(
          profile,
          parseLoginCookies(_cookie.text, profile.baseUri),
          method: LoginMethod.cookie,
          usernameHint: _username.text.trim(),
        ),
      };
      _finish(success, submission);
    } on LoginFailure catch (error) {
      if (mounted) setState(() => _formFailure = error.message);
    }
  }

  Future<void> _openWebLogin() async {
    if (_locked) return;
    final profile = _profile;
    if (profile == null) return;
    FocusScope.of(context).unfocus();
    final submission = Object();
    _submission = submission;
    setState(() {
      _webOpen = true;
      _formFailure = null;
    });
    final success = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => WebLoginPage(
          profile: profile,
          viewModel: widget.viewModel,
          usernameHint: '',
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _webOpen = false);
    _finish(success ?? false, submission);
  }

  void _finish(bool success, Object submission) {
    if (!mounted || !identical(_submission, submission)) return;
    if (!success) {
      _captcha.clear();
      return;
    }
    TextInput.finishAutofillContext(shouldSave: false);
    Navigator.of(context).pop(true);
  }

  void _changeMode(_LoginMode mode) {
    if (_locked) return;
    _submission = null;
    widget.viewModel.cancelSignIn();
    setState(() {
      _mode = mode;
      _formFailure = null;
      _username.clear();
      _captcha.clear();
    });
  }

  @override
  Widget build(BuildContext context) => _profile == null
      ? SchoolConnectionPage(
          isNewSchool: true,
          onSave: widget.viewModel.configureSchool,
          onSelected: _applyProfile,
        )
      : PopScope(
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) {
              _submission = null;
              widget.viewModel.cancelSignIn();
            }
          },
          child: Scaffold(
            appBar: AppBar(),
            body: SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: (constraints.maxHeight - 36).clamp(
                        0,
                        double.infinity,
                      ),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: ListenableBuilder(
                          listenable: widget.viewModel,
                          builder: (context, _) => Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const _LoginBrand(),
                              const SizedBox(height: 24),
                              _loginCard(context),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

  Widget _loginCard(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.viewModel.state;
    final challenge = state.challenge;
    final failure = _formFailure ?? state.failure?.message;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: AutofillGroup(
            onDisposeAction: AutofillContextAction.cancel,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _mode == _LoginMode.password ? '登录教务系统' : 'Cookie 登录',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    PopupMenuButton<_LoginSetting>(
                      key: const ValueKey('login-settings'),
                      tooltip: '登录设置',
                      enabled: !_locked,
                      onSelected: _openSettings,
                      icon: const Icon(Icons.settings_outlined),
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: _LoginSetting.school,
                          child: Text('学校与网址'),
                        ),
                        PopupMenuItem(
                          value: _LoginSetting.advanced,
                          child: Text('高级设置'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _mode == _LoginMode.password
                      ? '使用学校教务系统的账号与密码登录'
                      : '使用已登录教务页面的会话 Cookie',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                Text('选择学校', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                _SchoolSelector(
                  profile: _profile!,
                  onTap: _locked ? null : () => _editSchool(isNewSchool: true),
                ),
                if (_profile!.baseUri.scheme == 'http') ...[
                  const SizedBox(height: 8),
                  Text(
                    'HTTP 连接（未使用 HTTPS 加密）',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('密码登录'),
                      selected: _mode == _LoginMode.password,
                      onSelected: _locked
                          ? null
                          : (_) => _changeMode(_LoginMode.password),
                    ),
                    ChoiceChip(
                      label: const Text('Cookie 导入'),
                      selected: _mode == _LoginMode.cookie,
                      onSelected: _locked
                          ? null
                          : (_) => _changeMode(_LoginMode.cookie),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ..._credentialFields(),
                if (challenge != null) ...[
                  const SizedBox(height: 16),
                  _captchaFields(challenge, state.isBusy),
                ] else if (_mode == _LoginMode.password)
                  CheckboxListTile(
                    key: const ValueKey('remember-password'),
                    value: _rememberPassword,
                    onChanged: _locked
                        ? null
                        : (value) => setState(() => _rememberPassword = value!),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('记住密码，用于登录过期后续期'),
                    subtitle: const Text('可选，密码加密保存在本机'),
                  ),
                if (challenge == null) ...[
                  const SizedBox(height: 8),
                  const Text('登录状态会自动保存在本机，重启后可继续使用。'),
                ],
                if (failure != null) ...[
                  const SizedBox(height: 12),
                  AuthNotice(message: failure),
                ],
                const SizedBox(height: 20),
                if (state.isBusy) ...[
                  const LinearProgressIndicator(semanticsLabel: '正在连接教务系统'),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  key: const ValueKey('login-submit'),
                  onPressed: state.isBusy || _webOpen ? null : _submit,
                  child: Text(_submitLabel(state)),
                ),
                if (state.isBusy || challenge != null)
                  TextButton(
                    onPressed: () {
                      _submission = null;
                      widget.viewModel.cancelSignIn();
                      setState(() => _formFailure = null);
                    },
                    child: const Text('取消并重新填写'),
                  )
                else ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey('web-login-open'),
                    onPressed: _webOpen ? null : _openWebLogin,
                    icon: const Icon(Icons.open_in_browser_rounded, size: 20),
                    label: const Text('网页登录'),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '统一身份认证可使用网页登录',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _credentialFields() => [
    TextFormField(
      key: const ValueKey('login-username'),
      controller: _username,
      enabled: !_locked,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: _mode == _LoginMode.password
          ? const [AutofillHints.username]
          : null,
      decoration: InputDecoration(
        labelText: _mode == _LoginMode.password ? '账号或学号' : '账号或学号（选填）',
        prefixIcon: const Icon(Icons.person_outline_rounded),
        border: const OutlineInputBorder(),
      ),
      textInputAction: TextInputAction.next,
      validator: _mode == _LoginMode.password ? _required : null,
    ),
    const SizedBox(height: 12),
    if (_mode == _LoginMode.password)
      TextFormField(
        key: const ValueKey('login-password'),
        controller: _password,
        enabled: !_locked,
        obscureText: !_showPassword,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: const [AutofillHints.password],
        decoration: InputDecoration(
          labelText: '教务密码',
          prefixIcon: const Icon(Icons.lock_outline_rounded),
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: _showPassword ? '隐藏密码' : '显示密码',
            onPressed: () => setState(() => _showPassword = !_showPassword),
            icon: Icon(
              _showPassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ),
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _submit(),
        validator: (value) => value == null || value.isEmpty ? '请输入教务密码' : null,
      )
    else
      TextFormField(
        key: const ValueKey('cookie-input'),
        controller: _cookie,
        enabled: !_locked,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(
          labelText: 'Cookie 请求头',
          helperText: '粘贴 Cookie 请求头，导入后会核验教务账号',
          helperMaxLines: 3,
          prefixIcon: Icon(Icons.key_outlined),
          border: OutlineInputBorder(),
        ),
        validator: _required,
      ),
  ];

  Widget _captchaFields(CaptchaRequired challenge, bool busy) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AuthNotice(message: challenge.message, isError: challenge.rejected),
      const SizedBox(height: 12),
      Image.memory(
        challenge.image,
        height: 72,
        fit: BoxFit.contain,
        semanticLabel: '学校登录验证码',
        errorBuilder: (context, error, stackTrace) =>
            const Text('验证码图片无法显示，请刷新验证码。'),
      ),
      TextButton.icon(
        onPressed: busy
            ? null
            : () async {
                _captcha.clear();
                await widget.viewModel.refreshCaptcha();
              },
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('换一张验证码'),
      ),
      TextFormField(
        key: const ValueKey('login-captcha'),
        controller: _captcha,
        enabled: !busy,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: '图片验证码',
          border: OutlineInputBorder(),
        ),
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _submit(),
      ),
    ],
  );

  String _submitLabel(AuthSnapshot state) {
    if (state.phase == AuthPhase.saving) return '正在保存登录…';
    if (state.isBusy) return '正在连接教务系统…';
    if (state.challenge != null) return '验证并登录';
    return _mode == _LoginMode.password ? '登录' : '导入并验证';
  }

  static String? _required(String? value) =>
      value == null || value.trim().isEmpty ? '请填写此项' : null;
}

class _LoginBrand extends StatelessWidget {
  const _LoginBrand();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        ExcludeSemantics(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.school_outlined,
              color: theme.colorScheme.onPrimaryContainer,
              size: 34,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'ZFHelper',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '新正方教务助手',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SchoolSelector extends StatelessWidget {
  const _SchoolSelector({required this.profile, required this.onTap});
  final SchoolConnection profile;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '添加或更换学校',
    child: OutlinedButton(
      key: const ValueKey('school-selector'),
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(14),
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Row(
        children: [
          const Icon(Icons.school_outlined, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  profile.baseUri.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.expand_more_rounded),
        ],
      ),
    ),
  );
}
