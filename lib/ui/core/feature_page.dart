import 'package:flutter/material.dart';

import 'app_theme.dart';

class FeaturePage extends StatelessWidget {
  const FeaturePage({
    required this.title,
    required this.schoolName,
    required this.onOpenSettings,
    required this.children,
    super.key,
  });

  final String title;
  final String schoolName;
  final VoidCallback onOpenSettings;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppLayout.contentMaxWidth,
          ),
          child: ListView(
            key: PageStorageKey(title),
            padding: const EdgeInsets.all(AppLayout.pagePadding),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          schoolName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: '账号与设置',
                    onPressed: onOpenSettings,
                    icon: const Icon(Icons.person_outline_rounded),
                  ),
                ],
              ),
              const SizedBox(height: AppLayout.sectionGap),
              ...children,
              const SizedBox(height: AppLayout.sectionGap),
            ],
          ),
        ),
      ),
    );
  }
}
