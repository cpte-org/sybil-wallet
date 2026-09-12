import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/layout/app_form_factor.dart';
import '../../core/layout/app_desktop_shell.dart';
import '../../core/layout/app_main_sidebar.dart';
import '../../core/layout/app_pane_scroll_scaffold.dart';
import '../../core/layout/mobile/mobile_top_nav.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/familiar_widgets.dart';
import '../zns/application/zns_controller.dart';
import '../zns/presentation/zns_screen.dart';
import '../zns/presentation/public_name_lookup_card.dart';

class NamesSettingsScreen extends ConsumerWidget {
  const NamesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(znsControllerProvider);
    final pending = data.operation != null && !data.operation!.isComplete;
    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FamiliarPageHeader(
              title: 'Public Zcash names',
              subtitle: 'Your .zec names and the people you find through them.',
            ),
            const SizedBox(height: AppSpacing.md),
            FamiliarCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Register a name, update its address or manage names you own.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: context.colors.text.secondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    variant: AppButtonVariant.secondary,
                    onPressed: () => context.push('/names'),
                    key: const ValueKey('settings_manage_public_names'),
                    child: const Text('Manage my names'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            PublicNameLookupCard(configuration: data.configuration),
            const SizedBox(height: AppSpacing.md),
            if (data.error != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Text(data.error!),
              ),
            if (data.notice != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Text(data.notice!),
              ),
            if (data.isLocked || pending)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: Text(
                  'Unlock the wallet and finish or archive any pending Names operation before changing settings.',
                ),
              ),
            ExpansionTile(
              title: const Text('Connection details'),
              subtitle: const Text('Registry and network settings'),
              initiallyExpanded: data.configuration.registryAddress.isEmpty,
              tilePadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
              ),
              children: [
                ZnsConfigurationForm(
                  key: ValueKey(
                    '${data.configuration.registryAddress}:${data.configuration.chainId}',
                  ),
                  initial: data.configuration,
                  enabled: !data.isBusy && !data.isLocked && !pending,
                  onSave: ref
                      .read(znsControllerProvider.notifier)
                      .saveConfiguration,
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (kAppFormFactor == AppFormFactor.mobile) {
      return Scaffold(
        backgroundColor: context.colors.background.window,
        body: SafeArea(
          child: Column(
            children: [
              MobileTopNav.back(
                title: 'Public Zcash names',
                onBack: () => context.pop(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: content,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: AppPaneScrollScaffold(
          toolbar: const AppPaneToolbar(backLinkMinWidth: 60),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: content,
        ),
      ),
    );
  }
}
