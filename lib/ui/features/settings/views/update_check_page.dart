import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_community/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../data/repositories/release_repository.dart';
import '../../../core/app_theme.dart';
import '../view_models/update_check_view_model.dart';

class UpdateCheckPage extends StatefulWidget {
  const UpdateCheckPage({required this.viewModel, super.key});

  final UpdateCheckViewModel viewModel;

  @override
  State<UpdateCheckPage> createState() => _UpdateCheckPageState();
}

class _UpdateCheckPageState extends State<UpdateCheckPage> {
  bool _openingDownload = false;

  String _downloadLabel(ReleaseAsset asset) =>
      asset.name.toLowerCase().endsWith('.apk') ? '下载 APK' : '下载 Windows 版';

  @override
  void initState() {
    super.initState();
    unawaited(widget.viewModel.check());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('检查更新')),
    body: ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) => SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppLayout.contentMaxWidth,
                ),
                child: _buildContent(context),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _buildContent(BuildContext context) {
    final model = widget.viewModel;
    if (model.isBusy) {
      return const Center(child: CircularProgressIndicator());
    }
    if (model.failure != null) {
      return _MessageCard(
        icon: Icons.cloud_off_outlined,
        message: model.failure!,
        action: FilledButton.icon(
          onPressed: model.check,
          icon: const Icon(Icons.refresh),
          label: const Text('重试'),
        ),
      );
    }
    if (model.latest == null ||
        model.currentVersion == null ||
        model.updateAvailable == null ||
        (model.updateAvailable == false && model.currentRelease == null)) {
      return const _MessageCard(
        icon: Icons.system_update_alt_rounded,
        message: '准备检查更新…',
      );
    }

    final hasUpdate = model.updateAvailable!;
    final release = hasUpdate ? model.latest! : model.currentRelease!;
    final colorScheme = Theme.of(context).colorScheme;
    final accent = Color.alphaBlend(
      (hasUpdate ? const Color(0xFF2563EB) : const Color(0xFF16A34A))
          .withValues(alpha: 0.10),
      colorScheme.surface,
    );
    final foreground = colorScheme.onSurface;

    final status = _StatusCard(
      hasUpdate: hasUpdate,
      currentVersion: model.currentVersion!,
      latestVersion: model.latest!.tagName,
      background: accent,
      foreground: foreground,
    );
    final notes = _ReleaseNotesCard(release: release, foreground: foreground);
    final downloadAsset = switch (Theme.of(context).platform) {
      TargetPlatform.android => release.assetWithExtension('.apk'),
      TargetPlatform.windows => release.assetWithExtension('.zip'),
      _ => null,
    };
    final actions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (downloadAsset != null) ...[
          FilledButton.icon(
            onPressed: _openingDownload
                ? null
                : () => _openDownload(context, downloadAsset),
            icon: _openingDownload
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            label: Text(_downloadLabel(downloadAsset)),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: () => _openRelease(context, release.htmlUrl),
          icon: const Icon(Icons.open_in_new),
          label: const Text('打开发布页'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: model.check,
          icon: const Icon(Icons.refresh),
          label: const Text('重新检查'),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 860) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              status,
              const SizedBox(height: 20),
              notes,
              const SizedBox(height: 20),
              actions,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 300, child: status),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [notes, const SizedBox(height: 20), actions],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openDownload(BuildContext context, ReleaseAsset asset) async {
    setState(() => _openingDownload = true);
    final url = await widget.viewModel.repository.resolveDownloadUrl(asset);
    if (!mounted || !context.mounted) return;
    var opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened && url != asset.url) {
      opened = await launchUrl(asset.url, mode: LaunchMode.externalApplication);
    }
    if (!mounted || !context.mounted) return;
    setState(() => _openingDownload = false);
    if (!opened) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法打开下载地址，请打开发布页下载')));
    }
  }

  Future<void> _openRelease(BuildContext context, Uri url) async {
    if (await launchUrl(url, mode: LaunchMode.externalApplication) ||
        !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('无法打开 GitHub 发布页')));
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    required this.background,
    required this.foreground,
  });

  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Card(
    color: background,
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hasUpdate ? Icons.system_update_alt_rounded : Icons.check_circle,
            color: foreground,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasUpdate ? '发现新版本' : '当前已是最新版本',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hasUpdate
                      ? '当前版本 $currentVersion · 最新版本 $latestVersion'
                      : '当前版本 $currentVersion',
                  style: TextStyle(color: foreground),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ReleaseNotesCard extends StatelessWidget {
  const _ReleaseNotesCard({required this.release, required this.foreground});

  final ReleaseInfo release;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '版本说明',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            release.name,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: foreground),
          ),
          const SizedBox(height: 4),
          Text(
            '${release.tagName} · 发布于 ${_formatDate(release.publishedAt)}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: foreground),
          ),
          const SizedBox(height: 16),
          SelectionArea(
            child: MarkdownBody(
              data: release.body.isEmpty ? '此次发布未提供更新说明。' : release.body,
              onTapLink: (text, href, title) {
                final uri = href == null ? null : Uri.tryParse(href);
                if (uri != null &&
                    const ['http', 'https'].contains(uri.scheme)) {
                  unawaited(
                    launchUrl(uri, mode: LaunchMode.externalApplication),
                  );
                }
              },
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(
                    p: TextStyle(color: foreground, height: 1.5),
                    h1: TextStyle(color: foreground),
                    h2: TextStyle(color: foreground),
                    h3: TextStyle(color: foreground),
                    h4: TextStyle(color: foreground),
                    h5: TextStyle(color: foreground),
                    h6: TextStyle(color: foreground),
                    em: TextStyle(
                      color: foreground,
                      fontStyle: FontStyle.italic,
                    ),
                    strong: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                    listBullet: TextStyle(color: foreground),
                    blockquote: TextStyle(color: foreground),
                    blockquoteDecoration: BoxDecoration(
                      color: foreground.withValues(alpha: 0.08),
                      border: Border(
                        left: BorderSide(
                          color: foreground.withValues(alpha: 0.45),
                          width: 3,
                        ),
                      ),
                    ),
                    code: TextStyle(
                      color: foreground,
                      backgroundColor: foreground.withValues(alpha: 0.08),
                      fontFamily: 'monospace',
                    ),
                    codeblockDecoration: BoxDecoration(
                      color: foreground.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    a: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
            ),
          ),
        ],
      ),
    ),
  );

  static String _formatDate(DateTime date) =>
      '${date.year}/${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}';
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Icon(icon, size: 48),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    ),
  );
}
