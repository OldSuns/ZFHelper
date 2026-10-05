import 'package:flutter/material.dart';

import '../../../../data/storage/appearance_store.dart';
import '../../../core/app_theme.dart';
import '../view_models/appearance_view_model.dart';
import '../widgets/settings_section.dart';

class DisplaySettingsPage extends StatelessWidget {
  const DisplaySettingsPage({required this.viewModel, super.key});

  final AppearanceViewModel viewModel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) => SettingsPageScaffold(
      title: '显示',
      children: [
        RadioGroup<AppAppearance>(
          groupValue: viewModel.initialized ? viewModel.appearance : null,
          onChanged: (value) async {
            if (value != null) await viewModel.select(value);
          },
          child: SettingsSection(
            title: '外观',
            children: [
              for (final value in AppAppearance.values)
                RadioListTile<AppAppearance>(
                  value: value,
                  enabled: !viewModel.busy,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  title: Text(AppearanceViewModel.labelFor(value)),
                  subtitle: value == AppAppearance.system
                      ? const Text('随设备的浅色或深色模式切换')
                      : null,
                ),
            ],
          ),
        ),
        if (viewModel.busy) ...[
          const SizedBox(height: AppLayout.sectionGap),
          const LinearProgressIndicator(),
        ],
        if (viewModel.failure != null) ...[
          const SizedBox(height: AppLayout.sectionGap),
          Semantics(
            liveRegion: true,
            child: Text(
              viewModel.failure!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          if (!viewModel.initialized)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: viewModel.busy ? null : viewModel.initialize,
                child: const Text('重试读取外观'),
              ),
            ),
        ],
      ],
    ),
  );
}
