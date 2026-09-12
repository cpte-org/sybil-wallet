import '../../address_book/models/address_book_contact.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../../contacts/domain/familiar_person.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/network_config.dart';
import '../../../core/formatting/sync_status_label.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/mobile/app_mobile_tab_bar.dart';
import '../../../core/privacy/privacy_mask.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/familiar_widgets.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/network_privacy_provider.dart';
import '../../activity/models/activity_row_data.dart';
import '../../activity/widgets/activity_feed.dart';
import '../../contacts/application/contact_exchange_controller.dart';
import '../../contacts/application/familiar_people_metadata_provider.dart';
import '../../contacts/domain/contact_models.dart';
import '../../send/models/send_prefill_args.dart';

/// The real wallet's Familiar home. Balances, recipients and transaction rows
/// come from the existing wallet services; this widget grants no new authority.
class FamiliarHomeDashboard extends StatelessWidget {
  const FamiliarHomeDashboard({
    super.key,
    required this.sync,
    required this.privacyModeEnabled,
    required this.activityRows,
    required this.isActivityLoading,
    required this.onSend,
    required this.onReceive,
    required this.onActivity,
    required this.onTogglePrivacyMode,
    this.onShield,
    this.notice,
    this.ironwoodOnly = false,
    this.networkPrivacy = const NetworkPrivacyState.off(),
  });

  final SyncState sync;
  final bool privacyModeEnabled, isActivityLoading;
  final List<ActivityRowData> activityRows;
  final VoidCallback onSend, onReceive, onActivity, onTogglePrivacyMode;
  final VoidCallback? onShield;
  final Widget? notice;
  final bool ironwoodOnly;
  final NetworkPrivacyState networkPrivacy;

  String amount(BigInt value) => hideAmountIfPrivacyMode(
    '${ZecAmount.fromZatoshi(value).compactBalance.amountText} $kZcashDefaultCurrencyTicker',
    privacyModeEnabled: privacyModeEnabled,
  );

  @override
  Widget build(BuildContext context) {
    final palette = FamiliarPalette.of(context);
    final mobile = kAppFormFactor == AppFormFactor.mobile;
    final hasBalance = sync.hasBalanceData;
    final current = hasBalance && !sync.isUsingCompletedSpendableSnapshot;
    final availableBalance = ironwoodOnly
        ? sync.displayIronwoodBalance
        : sync.displaySpendableBalance;
    final balance = FamiliarCard(
      color: palette.lime,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: FamiliarBalanceSyncStatus(
                  sync: sync,
                  networkPrivacy: networkPrivacy,
                ),
              ),
              IconButton(
                tooltip: privacyModeEnabled ? 'Show balances' : 'Hide balances',
                onPressed: onTogglePrivacyMode,
                icon: Icon(
                  privacyModeEnabled
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: palette.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            sync.isUsingCompletedSpendableSnapshot && hasBalance
                ? 'Last available balance'
                : ironwoodOnly
                ? 'Yours to spend (Ironwood)'
                : 'Yours to spend',
            style: AppTypography.bodyMedium.copyWith(color: palette.ink),
          ),
          const SizedBox(height: 8),
          Text(
            hasBalance ? amount(availableBalance) : 'Loading…',
            key: const ValueKey('familiar_available_balance'),
            style: appSerifDisplayStyle(
              color: palette.ink,
            ).copyWith(fontSize: mobile ? 38 : 52, height: 1.12),
          ),
          const SizedBox(height: 12),
          Text(
            !hasBalance
                ? 'Loading your balance…'
                : sync.isUsingCompletedSpendableSnapshot
                ? 'Balances from the last completed sync'
                : '${amount(sync.pendingBalance)} awaiting confirmations',
            style: AppTypography.bodySmall.copyWith(color: palette.ink),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              AppButton(
                key: const ValueKey('familiar_home_send'),
                onPressed: onSend,
                leading: const Icon(Icons.north_east, size: 18),
                child: const Text('Send'),
              ),
              AppButton(
                key: const ValueKey('familiar_home_receive'),
                onPressed: onReceive,
                variant: AppButtonVariant.secondary,
                leading: const Icon(Icons.south_west, size: 18),
                child: const Text('Receive'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasBalance)
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  'Balance details',
                  style: AppTypography.bodySmall.copyWith(color: palette.ink),
                ),
                iconColor: palette.ink,
                collapsedIconColor: palette.ink,
                children: [
                  _BalanceLine(
                    'Total holdings',
                    amount(sync.displayTotalBalance),
                  ),
                  _BalanceLine(
                    'Available shielded funds',
                    amount(availableBalance),
                  ),
                  if (!sync.isUsingCompletedSpendableSnapshot) ...[
                    _BalanceLine(
                      'Awaiting confirmations',
                      amount(sync.pendingBalance),
                    ),
                    _BalanceLine(
                      'Locked Orchard funds',
                      amount(sync.orchardLockedBalance),
                    ),
                    _BalanceLine(
                      'Transparent funds',
                      amount(
                        sync.transparentBalance +
                            sync.transparentPendingBalance,
                      ),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'The breakdown updates after syncing.',
                        style: AppTypography.bodySmall,
                      ),
                    ),
                  if (onShield != null && current)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppButton(
                        onPressed: onShield,
                        variant: AppButtonVariant.ghost,
                        child: const Text('Shield transparent funds'),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    return Material(
      type: MaterialType.transparency,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          mobile ? 16 : 32,
          24,
          mobile ? 16 : 32,
          mobile ? kMobileTabBarHeight + 48 : 40,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!mobile) ...[
                    const FamiliarPageHeader(title: 'Wallet'),
                    const SizedBox(height: 28),
                  ],
                  if (notice != null) ...[notice!, const SizedBox(height: 20)],
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (mobile || constraints.maxWidth < 760) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            balance,
                            const SizedBox(height: 24),
                            const FamiliarPeoplePocket(),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: balance),
                          const SizedBox(width: 32),
                          const Expanded(child: FamiliarPeoplePocket()),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'The latest',
                          style: AppTypography.headlineSmall.copyWith(
                            color: palette.ink,
                          ),
                        ),
                      ),
                      AppButton(
                        onPressed: onActivity,
                        variant: AppButtonVariant.ghost,
                        child: const Text('All activity'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FamiliarCard(
                    padding: const EdgeInsets.all(8),
                    child: isActivityLoading
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : activityRows.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Your payments will appear here.',
                              style: AppTypography.bodyMedium.copyWith(
                                color: palette.muted,
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              for (final row in activityRows)
                                ActivityFeedRow(row: row, compact: true),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Balance freshness and network progress belong next to the amount they qualify.
/// Never infer completion from an idle sync or a cached 100% progress value.
class FamiliarBalanceSyncStatus extends StatelessWidget {
  const FamiliarBalanceSyncStatus({
    super.key,
    required this.sync,
    this.networkPrivacy = const NetworkPrivacyState.off(),
  });

  final SyncState sync;
  final NetworkPrivacyState networkPrivacy;

  @override
  Widget build(BuildContext context) {
    final palette = FamiliarPalette.of(context);
    final status = SyncStatusLabel.from(sync, networkPrivacy: networkPrivacy);
    final waitingOnTor = syncIsWaitingOnTor(networkPrivacy, sync);
    final failed = status.kind == SyncStatusKind.failed || sync.error != null;
    final synced = !failed && !waitingOnTor && sync.isSyncedToTip;
    final progressing =
        !failed && !waitingOnTor && (sync.isSyncing || sync.isBackgroundMode);
    final label = failed
        ? 'Sync needs attention'
        : waitingOnTor
        ? 'Connecting to Tor…'
        : synced
        ? 'Synced'
        : progressing
        ? 'Syncing · ${formatSyncStatusPercentage(sync.percentage)}%'
        : 'Waiting to sync';
    final details = failed
        ? status.kind == SyncStatusKind.failed
              ? status.semanticsLabel
              : 'Could not update the wallet. Check your connection.'
        : sync.chainTipHeight > 0
        ? 'Scanned block ${sync.scannedHeight} of ${sync.chainTipHeight}'
        : label;
    return Tooltip(
      message: details,
      child: Semantics(
        label: '$label. $details',
        child: ExcludeSemantics(
          child: Row(
            key: const ValueKey('familiar_balance_sync'),
            children: [
              Icon(
                failed
                    ? Icons.error_outline
                    : synced
                    ? Icons.check_circle_outline
                    : Icons.sync,
                size: 16,
                color: palette.ink,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: AppTypography.bodySmall.copyWith(color: palette.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceLine extends StatelessWidget {
  const _BalanceLine(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label, style: AppTypography.bodySmall)),
        const SizedBox(width: 14),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: AppTypography.bodySmall,
          ),
        ),
      ],
    ),
  );
}

/// People are identified by the authenticated record, never by initials or a
/// public registry name. The send controller revalidates the pinned snapshot.
class FamiliarPeoplePocket extends ConsumerWidget {
  const FamiliarPeoplePocket({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = FamiliarPalette.of(context);
    final available = ref.watch(contactExchangeAvailableProvider);
    final data = ref.watch(contactExchangeProvider);
    final metadata = ref.watch(familiarPeopleMetadataProvider).asData?.value;
    final contacts = available && data.available && !data.loading
        ? data.contacts
        : const <VerifiedContact>[];
    final saved = ref.watch(addressBookProvider);
    final payable = [
      ...contacts.where((c) => c.canPay).map(FamiliarPerson.connected),
      ...?saved.value?.contacts
          .where((c) => c.network == AddressBookNetwork.zcash)
          .map(FamiliarPerson.saved),
    ];
    payable.sort((a, b) {
      final aPin =
          a.saved?.pinned ?? metadata?[a.connected!.identity]?.pinned ?? false;
      final bPin =
          b.saved?.pinned ?? metadata?[b.connected!.identity]?.pinned ?? false;
      return aPin == bPin
          ? a.label.compareTo(b.label)
          : aPin
          ? -1
          : 1;
    });
    final restored = contacts
        .where((c) => c.status == ContactTrustStatus.restored)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Who’s it for?',
                style: appSerifDisplayStyle(color: palette.ink),
              ),
            ),
            AppButton(
              onPressed: () => context.go('/people'),
              variant: AppButtonVariant.ghost,
              child: const Text('Everyone'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (data.loading && available) const LinearProgressIndicator(),
        if (payable.isEmpty)
          Text(
            'Start with someone you know.',
            style: AppTypography.bodyMedium.copyWith(color: palette.muted),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 16,
          children: [
            for (final c in payable.take(3))
              SizedBox(
                width: 94,
                child: TextButton(
                  onPressed: data.busy
                      ? null
                      : () {
                          try {
                            final recipient = c.connected == null
                                ? null
                                : ref
                                      .read(contactExchangeProvider.notifier)
                                      .recipientFor(c.connected!.id);
                            context.push(
                              '/send',
                              extra: SendPrefillArgs(
                                id: 'contact-${DateTime.now().microsecondsSinceEpoch}',
                                source: recipient == null
                                    ? 'address-book'
                                    : 'contact',
                                address: recipient?.address ?? c.address,
                                label: recipient?.label ?? c.label,
                                contactRecipient: recipient,
                              ),
                            );
                          } catch (_) {
                            showAppToast(
                              context,
                              'This person changed. Open People and check their address.',
                            );
                          }
                        },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 4,
                    ),
                  ),
                  child: Column(
                    children: [
                      FamiliarAvatar(
                        label: c.label,
                        identity: c.avatarIdentity,
                        size: 68,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        c.label,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodySmall.copyWith(
                          color: palette.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            SizedBox(
              width: 94,
              child: TextButton(
                onPressed: () => context.push('/people/add'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 4,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.line),
                      ),
                      child: Icon(Icons.add, color: palette.muted),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Add someone',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(
                        color: palette.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (restored > 0)
          FamiliarCard(
            color: palette.peach,
            padding: const EdgeInsets.all(16),
            child: Text(
              '$restored ${restored == 1 ? 'person needs' : 'people need'} a fresh address check.',
              style: AppTypography.bodyMedium.copyWith(color: palette.ink),
            ),
          ),
        if (available) ...[
          const SizedBox(height: 18),
          FamiliarCard(
            color: palette.lilac,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Someone in common?',
                  style: AppTypography.bodyLarge.copyWith(color: palette.ink),
                ),
                const SizedBox(height: 8),
                AppButton(
                  onPressed: () => context.push('/contacts/introductions'),
                  variant: AppButtonVariant.ghost,
                  child: const Text('Invitations & introductions'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
