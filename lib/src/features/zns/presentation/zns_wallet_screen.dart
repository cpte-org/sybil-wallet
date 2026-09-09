import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/clipboard/sensitive_clipboard.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../core/theme/app_theme.dart';
import '../../send/models/send_prefill_args.dart';
import '../application/zns_controller.dart';
import 'zns_screen.dart';

class ZnsWalletScreen extends ConsumerWidget {
  const ZnsWalletScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(znsControllerProvider.notifier);
    final content = ZnsScreen(
      data: ref.watch(znsControllerProvider),
      callbacks: controller.callbacks(
        onShowRecovery: () => _recovery(context, controller),
        onSendToName: (lookup) async {
          try {
            late final String address;
            try {
              address = await controller.resolvedAddressForSend();
            } on ZnsRecipientChanged catch (changed) {
              if (!context.mounted) return;
              final accepted = await showDialog<bool>(
                context: context,
                builder: (dialog) => AlertDialog(
                  title: const Text('Name registration changed'),
                  content: SingleChildScrollView(
                    child: Text(
                      '${changed.name} now has a different registration. Verify that this is the person you intend to pay.\n\nCurrent Zcash address:\n${changed.address}',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('Use this recipient'),
                    ),
                  ],
                ),
              );
              if (accepted != true || !context.mounted) return;
              address = await controller.resolvedAddressForSend(
                acceptedRecipient: changed.fingerprint,
              );
            }
            if (context.mounted) {
              context.push(
                '/send',
                extra: kAppFormFactor == AppFormFactor.mobile
                    ? address
                    : SendPrefillArgs(
                        id: 'zns-${DateTime.now().microsecondsSinceEpoch}',
                        source: 'zns',
                        address: address,
                        label: lookup.name,
                      ),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.maybeOf(
                context,
              )?.showSnackBar(SnackBar(content: Text(znsFriendlyError(e))));
            }
          }
        },
      ),
    );
    if (kAppFormFactor == AppFormFactor.mobile) {
      return Scaffold(
        backgroundColor: context.colors.background.window,
        body: SafeArea(
          child: Column(
            children: [
              MobileTopNav.back(title: 'Names', onBack: () => context.pop()),
              Expanded(child: content),
            ],
          ),
        ),
      );
    }
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(padding: EdgeInsets.zero, child: content),
    );
  }

  Future<void> _recovery(BuildContext context, ZnsController controller) async {
    final input = TextEditingController();
    String? message;
    var messageIsError = false, busy = false, acknowledged = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          Future<void> run(Future<void> Function() action) async {
            update(() => busy = true);
            try {
              await action();
            } catch (e) {
              message = znsFriendlyError(e);
              messageIsError = true;
            } finally {
              if (context.mounted) update(() => busy = false);
            }
          }

          return AlertDialog(
            title: const Text('Registration recovery'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Save a private copy of the commitment and progress. This contains no wallet key. Keep your seed and BIP39 passphrase backup separately.',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => run(() async {
                              await SensitiveClipboard.copyText(
                                controller.exportRecovery(),
                              );
                              message =
                                  'Recovery copied. Save it privately before the clipboard clears.';
                              messageIsError = false;
                            }),
                      child: const Text('Copy recovery'),
                    ),
                    TextField(
                      controller: input,
                      maxLines: 4,
                      onChanged: (_) => update(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Paste a recovery JSON file',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: busy || input.text.trim().isEmpty
                          ? null
                          : () => run(() async {
                              await controller.importRecovery(input.text);
                              message = 'Recovery restored.';
                              messageIsError = false;
                            }),
                      child: const Text('Restore recovery'),
                    ),
                    CheckboxListTile(
                      value: acknowledged,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Archiving does not cancel transactions, refund conversions, release a name or revoke approvals. I saved the recovery data.',
                      ),
                      onChanged: busy
                          ? null
                          : (v) => update(() => acknowledged = v ?? false),
                    ),
                    OutlinedButton(
                      onPressed: busy || !acknowledged
                          ? null
                          : () => run(() async {
                              await controller.archiveOperation();
                              message =
                                  'Operation archived; pending chain activity was checked.';
                              messageIsError = false;
                            }),
                      child: const Text('Archive resolved operation'),
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        message!,
                        style: AppTypography.bodySmall.copyWith(
                          color: messageIsError
                              ? context.colors.text.destructive
                              : context.colors.text.positiveStrong,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
    input.dispose();
  }
}
