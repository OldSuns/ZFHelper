import 'package:flutter/material.dart';
import 'package:zf_core/zf_core.dart';

import '../../../core/app_theme.dart';
import 'auth_notice.dart';

class LoginAdvancedSettingsPage extends StatefulWidget {
  const LoginAdvancedSettingsPage({
    required this.profile,
    required this.onSave,
    super.key,
  });
  final SchoolConnection profile;
  final Future<void> Function(SchoolConnection) onSave;

  @override
  State<LoginAdvancedSettingsPage> createState() =>
      _LoginAdvancedSettingsPageState();
}

class _LoginAdvancedSettingsPageState extends State<LoginAdvancedSettingsPage> {
  late final Map<String, TextEditingController> _paths;
  late final TextEditingController _baseAddress;
  late final TextEditingController _webAddress;
  String? _failure;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _baseAddress = TextEditingController(text: profile.baseUri.toString());
    _paths = {
      '密码登录路径': TextEditingController(text: profile.loginPath),
      'RSA 公钥路径': TextEditingController(text: profile.publicKeyPath),
      '验证码路径': TextEditingController(text: profile.captchaPath),
      '身份查询路径': TextEditingController(text: profile.accountPath),
      '课表页面路径': TextEditingController(text: profile.schedulePagePath),
      '课表查询路径': TextEditingController(text: profile.scheduleQueryPath),
      '作息查询路径（选填）': TextEditingController(text: profile.schedulePeriodsPath),
    };
    _webAddress = TextEditingController(text: profile.webLoginUri?.toString());
  }

  @override
  void dispose() {
    for (final controller in [..._paths.values, _baseAddress, _webAddress]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _restoreDefaults() {
    final defaults = SchoolConnection(
      name: widget.profile.name,
      baseUri: widget.profile.baseUri,
    );
    _paths['密码登录路径']!.text = defaults.loginPath;
    _paths['RSA 公钥路径']!.text = defaults.publicKeyPath;
    _paths['验证码路径']!.text = defaults.captchaPath;
    _paths['身份查询路径']!.text = defaults.accountPath;
    _paths['课表页面路径']!.text = defaults.schedulePagePath;
    _paths['课表查询路径']!.text = defaults.scheduleQueryPath;
    _paths['作息查询路径（选填）']!.clear();
    _webAddress.clear();
    setState(() => _failure = null);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _failure = null;
    });
    try {
      final profile = SchoolConnection(
        name: widget.profile.name,
        baseUri: Uri.parse(_baseAddress.text.trim()),
        loginPath: _paths['密码登录路径']!.text.trim(),
        publicKeyPath: _paths['RSA 公钥路径']!.text.trim(),
        captchaPath: _paths['验证码路径']!.text.trim(),
        accountPath: _paths['身份查询路径']!.text.trim(),
        schedulePagePath: _paths['课表页面路径']!.text.trim(),
        scheduleQueryPath: _paths['课表查询路径']!.text.trim(),
        schedulePeriodsPath: _paths['作息查询路径（选填）']!.text.trim().isEmpty
            ? null
            : _paths['作息查询路径（选填）']!.text.trim(),
        webLoginUri: _webAddress.text.trim().isEmpty
            ? null
            : Uri.parse(_webAddress.text.trim()),
      );
      await widget.onSave(profile);
      if (!mounted) return;
      Navigator.of(context).pop(profile);
    } on FormatException catch (error) {
      if (mounted) setState(() => _failure = error.message);
    } on LoginFailure catch (error) {
      if (mounted) setState(() => _failure = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('高级设置')),
    body: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(AppLayout.pagePadding),
            children: [
              Text(
                widget.profile.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(widget.profile.baseUri.toString()),
              const SizedBox(height: 16),
              const Text('常见新正方系统可直接使用默认设置。学校使用不同接口或统一认证时，在这里修改。'),
              const SizedBox(height: 24),
              TextField(
                key: const ValueKey('advanced-base-address'),
                controller: _baseAddress,
                enabled: !_saving,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '教务系统根地址',
                  helperText: '可手动指定完整根网址，不包含具体功能页',
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              for (final entry in _paths.entries) ...[
                TextField(
                  controller: entry.value,
                  enabled: !_saving,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: entry.key,
                    helperText: entry.key == '作息查询路径（选填）'
                        ? '留空时从学校课表页面识别作息接口；也可导入后手工设置时间。'
                        : entry.key == '课表查询路径'
                        ? '默认使用新正方标准课表接口；填写后始终使用这个地址。'
                        : null,
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                key: const ValueKey('web-login-address'),
                controller: _webAddress,
                enabled: !_saving,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: '独立网页登录地址（选填）',
                  helperText: '填写完整的统一认证网址，留空则打开教务登录页',
                  helperMaxLines: 3,
                  border: OutlineInputBorder(),
                ),
              ),
              if (_failure != null) ...[
                const SizedBox(height: 16),
                AuthNotice(message: _failure!),
              ],
              const SizedBox(height: 24),
              FilledButton(
                key: const ValueKey('advanced-save'),
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '正在保存…' : '保存设置'),
              ),
              TextButton(
                onPressed: _saving ? null : _restoreDefaults,
                child: const Text('恢复默认设置'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
