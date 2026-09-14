import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zf_core/zf_core.dart';

import '../../../core/app_theme.dart';
import '../view_models/school_address_view_model.dart';
import 'auth_notice.dart';

class SchoolConnectionPage extends StatefulWidget {
  const SchoolConnectionPage({
    this.profile,
    this.isNewSchool = false,
    required this.onSave,
    this.onSelected,
    super.key,
  });

  final SchoolConnection? profile;
  final bool isNewSchool;
  final Future<void> Function(SchoolConnection) onSave;
  final ValueChanged<SchoolConnection>? onSelected;

  @override
  State<SchoolConnectionPage> createState() => _SchoolConnectionPageState();
}

class _SchoolConnectionPageState extends State<SchoolConnectionPage> {
  late final TextEditingController _address;
  late final TextEditingController _name;
  late final SchoolAddressViewModel _viewModel;
  Object? _pendingPaste;
  bool _saving = false;
  String? _saveFailure;

  @override
  void initState() {
    super.initState();
    _address = TextEditingController(
      text: widget.isNewSchool ? '' : widget.profile?.baseUri.toString() ?? '',
    );
    _name = TextEditingController(
      text: widget.isNewSchool ? '' : widget.profile?.name ?? '',
    );
    _viewModel = SchoolAddressViewModel(
      initialProfile: widget.profile,
      address: widget.isNewSchool ? '' : null,
    );
  }

  @override
  void dispose() {
    _address.dispose();
    _name.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _pasteAddress() async {
    final paste = Object();
    _pendingPaste = paste;
    try {
      final value = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted || !identical(_pendingPaste, paste)) return;
      final text = value?.text;
      if (text == null || text.trim().isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('剪贴板中没有网址')));
        return;
      }
      _address.text = text.trim();
      _changeAddress(_address.text);
    } on PlatformException {
      if (!mounted || !identical(_pendingPaste, paste)) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法读取剪贴板，请手动粘贴网址')));
    }
  }

  void _changeAddress(String value) {
    _pendingPaste = null;
    _viewModel.changeAddress(value);
  }

  Future<void> _save() async {
    if (_saving) return;
    final profile = _viewModel.submit(_name.text);
    if (profile == null) return;
    setState(() {
      _saving = true;
      _saveFailure = null;
    });
    try {
      _pendingPaste = null;
      await widget.onSave(profile);
      if (!mounted) return;
      final selected = widget.onSelected;
      if (selected != null) {
        selected(profile);
      } else {
        Navigator.of(context).pop(profile);
      }
    } on LoginFailure catch (failure) {
      if (mounted) setState(() => _saveFailure = failure.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.isNewSchool ? '添加学校' : '学校与网址')),
    body: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= AppLayout.workspaceMinWidth;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: wide
                    ? AppLayout.detailPaneWidth + AppLayout.paneGap + 560
                    : 560,
              ),
              child: ListenableBuilder(
                listenable: _viewModel,
                builder: (context, _) => wide
                    ? SingleChildScrollView(
                        padding: const EdgeInsets.all(
                          AppLayout.workspacePadding,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: AppLayout.detailPaneWidth,
                              child: _information(context, showPreview: true),
                            ),
                            const SizedBox(width: AppLayout.paneGap),
                            Expanded(
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(
                                    AppLayout.workspacePadding,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: _fields(wide: true),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(AppLayout.pagePadding),
                        children: [
                          _information(context, showPreview: false),
                          const SizedBox(height: 24),
                          ..._fields(wide: false),
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _information(BuildContext context, {required bool showPreview}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '智能识别网址',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('粘贴登录、课表或成绩页的网址，自动提取网站地址和教务目录。'),
          if (showPreview) ..._addressDetails(),
        ],
      );

  List<Widget> _addressDetails() => [
    if (_viewModel.recognizedAddress case final address?) ...[
      const SizedBox(height: 16),
      _AddressPreview(address: address),
    ],
    if (_viewModel.resetsCustomSettings) ...[
      const SizedBox(height: 16),
      const AuthNotice(
        message: '更换教务系统后将使用标准接口。如需自定义，可从登录页齿轮进入高级设置。',
        isError: false,
      ),
    ],
  ];

  List<Widget> _fields({required bool wide}) => [
    TextField(
      key: const ValueKey('school-address'),
      controller: _address,
      enabled: !_saving,
      keyboardType: TextInputType.url,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.next,
      onChanged: _changeAddress,
      decoration: InputDecoration(
        labelText: '教务系统网址',
        hintText: 'jw.example.edu.cn/jwglxt/…',
        border: const OutlineInputBorder(),
        errorText: _viewModel.addressError,
        errorMaxLines: 4,
        suffixIcon: IconButton(
          tooltip: '粘贴网址',
          onPressed: _saving ? null : _pasteAddress,
          icon: const Icon(Icons.content_paste_rounded),
        ),
      ),
    ),
    if (!wide) ..._addressDetails(),
    const SizedBox(height: 24),
    TextField(
      key: const ValueKey('school-name'),
      controller: _name,
      enabled: !_saving,
      textInputAction: TextInputAction.done,
      onChanged: _viewModel.changeName,
      onSubmitted: (_) => _save(),
      decoration: InputDecoration(
        labelText: '学校名称',
        errorText: _viewModel.nameError,
        border: const OutlineInputBorder(),
      ),
    ),
    const SizedBox(height: 28),
    if (_saveFailure case final message?) ...[
      AuthNotice(message: message),
      const SizedBox(height: 16),
    ],
    Align(
      alignment: wide ? Alignment.centerLeft : Alignment.center,
      child: SizedBox(
        width: wide ? null : double.infinity,
        child: FilledButton(
          key: const ValueKey('school-save'),
          onPressed: _saving ? null : _save,
          child: Text(
            _saving
                ? '正在保存…'
                : widget.isNewSchool
                ? '使用这所学校'
                : '保存学校设置',
          ),
        ),
      ),
    ),
  ];
}

class _AddressPreview extends StatelessWidget {
  const _AddressPreview({required this.address});
  final Uri address;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Card(
        color: theme.colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('网址识别结果', style: theme.textTheme.titleSmall),
              const SizedBox(height: 16),
              Text(
                '网站地址',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(address.origin, key: const ValueKey('recognized-origin')),
              const SizedBox(height: 12),
              Text(
                '教务目录',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(address.path, key: const ValueKey('recognized-base-path')),
              if (address.scheme == 'http') ...[
                const SizedBox(height: 12),
                const Text('当前为 HTTP 连接，未使用 HTTPS 加密。'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
