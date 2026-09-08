import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import 'zns_view_data.dart';

export 'zns_view_data.dart';

/// Shared name-service content. The host supplies its desktop or mobile shell.
class ZnsScreen extends StatefulWidget {
  const ZnsScreen({super.key, required this.data, required this.callbacks});
  final ZnsViewData data;
  final ZnsCallbacks callbacks;

  @override
  State<ZnsScreen> createState() => _ZnsScreenState();
}

class _ZnsScreenState extends State<ZnsScreen> {
  final _name = TextEditingController();
  final _budget = TextEditingController();
  bool _acceptedReview = false;
  bool _showBalances = false;
  bool _showSettings = false;

  ZnsViewData get data => widget.data;
  ZnsCallbacks get actions => widget.callbacks;
  String get _normalizedName {
    final value = _name.text.trim().toLowerCase();
    return value.endsWith('.zec')
        ? value.substring(0, value.length - 4)
        : value;
  }

  bool get _validName => RegExp(
    r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
  ).hasMatch(_normalizedName);
  bool get _validBudget =>
      RegExp(r'^\d+(?:\.\d{1,8})?$').hasMatch(_budget.text.trim());
  bool get _hasPending => data.operation != null && !data.operation!.isComplete;
  bool get _editing => !_hasPending && data.review == null;

  @override
  void didUpdateWidget(ZnsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.accountId != data.accountId) {
      _name.clear();
      _budget.clear();
      _acceptedReview = false;
      _showBalances = false;
    }
    if (_approvalKey(oldWidget.data.review) != _approvalKey(data.review)) {
      _acceptedReview = false;
    }
  }

  String _approvalKey(ZnsReviewView? review) => review == null
      ? ''
      : [
          review.kind,
          review.name,
          review.positionId,
          review.unifiedAddress,
          review.maxZec,
          review.deposit,
          review.maxBaseEth,
          review.gasReserve,
          review.existingCbZecSpend,
          review.existingEthSpend,
          review.maturityAt,
          review.refreshDueAt,
          review.rewardsToClaim,
          review.exitPreview?.early,
          review.exitPreview?.principalReturned,
          review.exitPreview?.rewardsReturned,
          review.exitPreview?.principalForfeited,
          review.exitPreview?.rewardsForfeited,
        ].join('\u0000');

  @override
  void dispose() {
    _name.dispose();
    _budget.dispose();
    super.dispose();
  }

  void _lookup() {
    if (_validName && data.isConfigured && !data.isBusy && _editing) {
      actions.onLookup?.call(_normalizedName);
    }
  }

  @override
  Widget build(BuildContext context) {
    const mobile = kAppFormFactor == AppFormFactor.mobile;
    return Material(
      color: Colors.transparent,
      child: DefaultTextStyle(
        style: AppTypography.bodyMedium.copyWith(
          color: context.colors.text.primary,
        ),
        child: SingleChildScrollView(
          key: const Key('zns-scroll'),
          padding: const EdgeInsets.all(
            mobile ? AppSpacing.sm : AppSpacing.base,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Names',
                          style: AppTypography.headlineLarge.copyWith(
                            color: context.colors.text.accent,
                          ),
                        ),
                      ),
                      AppButton(
                        key: const Key('zns-settings'),
                        onPressed: data.isBusy || _hasPending
                            ? null
                            : () => setState(
                                () => _showSettings = !_showSettings,
                              ),
                        variant: AppButtonVariant.ghost,
                        size: AppButtonSize.small,
                        leading: const AppIcon(AppIcons.cog),
                        child: const Text('Settings'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.s),
                  Text(
                    'A familiar name for your Zcash address.',
                    style: AppTypography.bodyLarge.copyWith(
                      color: context.colors.text.secondary,
                    ),
                  ),
                  if (actions.onShowRecovery != null && data.isConfigured) ...[
                    const SizedBox(height: AppSpacing.s),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: AppButton(
                        key: const Key('zns-recovery'),
                        onPressed: data.isLocked || data.isBusy
                            ? null
                            : actions.onShowRecovery,
                        variant: AppButtonVariant.ghost,
                        size: AppButtonSize.small,
                        leading: const AppIcon(AppIcons.history),
                        child: const Text('Recovery'),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  if (_showSettings) ...[
                    _ConfigurationForm(
                      key: ValueKey(
                        '${data.configuration.registryAddress}:${data.configuration.chainId}',
                      ),
                      initial: data.configuration,
                      enabled: !data.isBusy && !_hasPending,
                      onSave: actions.onSaveConfiguration,
                      onClose: () => setState(() => _showSettings = false),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (!data.isConfigured) ...[
                    const _Notice(
                      icon: AppIcons.endpoint,
                      title: 'Name service is not configured',
                      text:
                          'Add a verified registry in Settings to look up or register names. Registration stays unavailable until the connection is verified.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (!data.isSoftwareAccount) ...[
                    const _Notice(
                      icon: AppIcons.keystone,
                      title: 'Choose a software account to register',
                      text:
                          'Keystone registration will be supported separately. You can still look up names.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (data.isLocked) ...[
                    const _Notice(
                      icon: AppIcons.lock,
                      title: 'Registration is paused while locked',
                      text:
                          'Unlock your wallet to review or resume. Transactions already sent can still confirm.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (data.error case final error?) ...[
                    _Notice(
                      icon: AppIcons.help,
                      title: 'Action needed',
                      text: error,
                      isError: true,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (data.notice case final notice?) ...[
                    _Notice(
                      icon: AppIcons.help,
                      title: 'Before you continue',
                      text: notice,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (data.operation case final operation?) ...[
                    _operationCard(operation),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (data.review case final review?) ...[
                    _reviewCard(review),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (data.ownedName case final owned?) ...[
                    _ownedCard(owned),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (_editing) _searchCard(),
                  const SizedBox(height: AppSpacing.md),
                  if (data.baseOwnerAddress.isNotEmpty ||
                      data.canWithdrawClaims)
                    _balancesCard(),
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchCard() {
    final lookup = data.lookup;
    final matchesLookup = lookup?.name == _normalizedName;
    final available =
        matchesLookup && lookup?.status == ZnsLookupStatus.available;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _title('Find your name'),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            key: const Key('zns-name'),
            label: 'Name',
            controller: _name,
            hintText: 'your-name',
            inlineSuffixText: '.zec',
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _lookup(),
            messageText: _name.text.isNotEmpty && !_validName
                ? 'Use 1–63 letters, numbers or hyphens. Start and end with a letter or number.'
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: const Key('zns-lookup'),
            onPressed:
                _validName &&
                    data.isConfigured &&
                    !data.isBusy &&
                    actions.onLookup != null
                ? _lookup
                : null,
            variant: AppButtonVariant.secondary,
            leading: const AppIcon(AppIcons.search),
            child: Text(
              lookup?.status == ZnsLookupStatus.loading
                  ? 'Checking name…'
                  : 'Check availability',
            ),
          ),
          if (matchesLookup && lookup != null) ...[
            const SizedBox(height: AppSpacing.md),
            _lookupResult(lookup),
          ],
          if (available &&
              (data.ownedName == null || data.ownedName!.isExpired)) ...[
            const SizedBox(height: AppSpacing.md),
            _divider(),
            const SizedBox(height: AppSpacing.md),
            const _Notice(
              icon: AppIcons.lock,
              title: 'One deposit. A name that stays yours.',
              text:
                  'Deposit cbZEC once and keep your name active with an annual refresh. Exit after 365 days to receive your deposit back. Earlier exit forfeits the entire deposit and unvested rewards.',
            ),
            const SizedBox(height: AppSpacing.md),
            _Address(
              label: 'Receives Zcash at',
              address: data.walletUnifiedAddress,
              emptyText: 'Your wallet address is loading.',
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              key: const Key('zns-budget'),
              label: 'Maximum ZEC to spend',
              controller: _budget,
              hintText: '0.00',
              inlineSuffixText: 'ZEC',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              messageText:
                  'Includes funding and network fees. Enter 0 to use existing Base funds only. Your review will show the deposit and all spending limits.',
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: const Key('zns-prepare'),
              onPressed:
                  data.canWrite &&
                      _validBudget &&
                      data.walletUnifiedAddress.isNotEmpty &&
                      actions.onPrepareRegistration != null
                  ? () => actions.onPrepareRegistration!(
                      ZnsRegistrationInput(
                        name: _normalizedName,
                        maxZec: _budget.text.trim(),
                      ),
                    )
                  : null,
              expand: true,
              child: const Text('Review registration'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _lookupResult(ZnsLookupView lookup) {
    final available = lookup.status == ZnsLookupStatus.available;
    final registered = lookup.status == ZnsLookupStatus.registered;
    final title = switch (lookup.status) {
      ZnsLookupStatus.available => '${lookup.name}.zec is available',
      ZnsLookupStatus.registered => '${lookup.name}.zec is registered',
      ZnsLookupStatus.unavailable => '${lookup.name}.zec is unavailable',
      ZnsLookupStatus.loading => 'Checking ${lookup.name}.zec…',
      ZnsLookupStatus.failed => 'Could not check this name',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIcon(
              available
                  ? AppIcons.checkCircle
                  : registered
                  ? AppIcons.book
                  : AppIcons.help,
              color: available
                  ? context.colors.text.positiveStrong
                  : context.colors.text.secondary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: Text(title, style: AppTypography.bodyMediumStrong)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        _small(
          lookup.message ??
              (available
                  ? 'Availability can change. A commitment does not reserve the name.'
                  : registered
                  ? 'This is the public address currently recorded for this name.'
                  : 'Try another name or check again.'),
        ),
        if (registered && lookup.unifiedAddress.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _Address(label: 'Registered address', address: lookup.unifiedAddress),
          if (actions.onSendToName != null) ...[
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              key: const Key('zns-send-to-name'),
              onPressed: data.isLocked || data.isBusy
                  ? null
                  : () => actions.onSendToName!(lookup),
              child: const Text('Send ZEC'),
            ),
          ],
        ],
        if (lookup.expiresAt case final expiry?) ...[
          const SizedBox(height: AppSpacing.xs),
          _small('Expires $expiry'),
        ],
      ],
    );
  }

  Widget _reviewCard(ZnsReviewView review) {
    final action = switch (review.kind) {
      ZnsReviewKind.registration => 'registration',
      ZnsReviewKind.refresh => 'name refresh',
      ZnsReviewKind.claimRewards => 'reward claim',
      ZnsReviewKind.addressUpdate => 'address update',
      ZnsReviewKind.release => 'name release',
      ZnsReviewKind.withdrawClaims => 'old claims withdrawal',
    };
    final registering = review.kind == ZnsReviewKind.registration;
    final release = review.kind == ZnsReviewKind.release;
    final withdrawing = review.kind == ZnsReviewKind.withdrawClaims;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _eyebrow('Review $action'),
          const SizedBox(height: AppSpacing.s),
          Text(
            withdrawing ? 'Your old claims' : '${review.name}.zec',
            style: AppTypography.headlineLarge.copyWith(
              color: context.colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (registering || withdrawing)
            _detail(
              withdrawing ? 'Principal to withdraw' : 'Registration deposit',
              '${review.deposit} cbZEC',
            ),
          if (review.maturityAt case final date?)
            _detail('Original deposit maturity', date),
          if (registering && review.maturityAt == null)
            _detail('Deposit maturity', '365 days after registration confirms'),
          if (review.refreshDueAt case final date?)
            _detail('Next refresh due', date),
          if (review.rewardsToClaim case final rewards?)
            _detail('Rewards to receive', '$rewards cbZEC'),
          if (review.exitPreview case final exit?) ...[
            _detail(
              'Deposit returned',
              '${exit.principalReturned} cbZEC',
              strong: true,
            ),
            _detail('Rewards returned', '${exit.rewardsReturned} cbZEC'),
            _detail(
              'Deposit forfeited',
              '${exit.principalForfeited} cbZEC',
              strong: exit.early,
            ),
            _detail(
              'Unvested rewards forfeited',
              '${exit.rewardsForfeited} cbZEC',
              strong: exit.early,
            ),
          ],
          _detail('Gas reserve', '${review.gasReserve} ETH'),
          _detail(
            'Maximum new ZEC funding',
            '${review.maxZec} ZEC',
            strong: true,
          ),
          if (review.maxBaseEth case final maximum?)
            _detail('Maximum Base ETH spend', '$maximum ETH', strong: true),
          if (review.existingCbZecSpend case final existing?)
            _detail('From existing cbZEC', '$existing cbZEC'),
          if (review.existingEthSpend case final existing?)
            _detail('From existing ETH', '$existing ETH'),
          _detail('Estimated duration', review.estimatedDuration),
          if (review.quoteExpiresIn case final expiry?)
            _detail('Quote expires', expiry),
          const SizedBox(height: AppSpacing.sm),
          if (!release && !withdrawing)
            _Address(
              label: 'Public receiving address',
              address: review.unifiedAddress,
            ),
          const SizedBox(height: AppSpacing.md),
          if (release)
            _Notice(
              icon: AppIcons.help,
              isError: review.exitPreview?.early ?? false,
              title: review.exitPreview?.early == true
                  ? 'Early exit forfeits your entire deposit'
                  : 'Your name will be released',
              text: review.exitPreview?.early == true
                  ? 'You will receive no deposit or unvested rewards. Both are allocated to other eligible names, or held in the contract reserve if none remain. Another person can register your released name.'
                  : 'Your deposit and vested rewards will return to your Base account. Another person can register your released name. Network and conversion costs are not refunded.',
            )
          else if (withdrawing)
            const _Notice(
              icon: AppIcons.checkCircle,
              title: 'Your current name stays yours',
              text:
                  'This withdraws principal and earned rewards from expired registrations. It does not release or refresh a current name.',
            )
          else
            _Notice(
              icon: AppIcons.eye,
              title: 'Your name and address will be public',
              text: registering
                  ? 'The record also links to your Base account. The funding service uses a transparent Zcash deposit. Your name is secured only when registration confirms.'
                  : 'The record links this receiving address to your name and Base account.',
            ),
          const SizedBox(height: AppSpacing.sm),
          if (registering) ...[
            const _Notice(
              icon: AppIcons.lock,
              title: 'Your initial holding period is 365 days',
              text:
                  'Earlier exit forfeits the entire deposit and all unvested rewards. Refreshes, address updates and reward claims never restart this period. Rewards accrue immediately, may be zero, and can be claimed after your original maturity.',
            ),
            const SizedBox(height: AppSpacing.s),
            _small(
              'Vizor will convert ZEC, keep ETH for network fees, and deposit cbZEC. If the name becomes unavailable, converted funds remain in your Base account; the conversion cannot be undone automatically.',
            ),
          ],
          if (review.kind == ZnsReviewKind.refresh ||
              review.kind == ZnsReviewKind.claimRewards ||
              review.kind == ZnsReviewKind.addressUpdate)
            _small(
              'This owner-authorized action keeps an active name for one rolling year from confirmation, followed by 90 days of grace. Your original deposit maturity does not change.',
            ),
          if (release || withdrawing)
            _small(
              'Withdrawals return cbZEC to your Base account. They do not convert it to shielded ZEC.',
            ),
          const SizedBox(height: AppSpacing.s),
          CheckboxListTile(
            key: const Key('zns-review-consent'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _acceptedReview,
            onChanged: data.canWrite
                ? (value) => setState(() => _acceptedReview = value ?? false)
                : null,
            title: Text(
              release
                  ? 'I approve releasing this name, the displayed returns and forfeitures, and this spending limit.'
                  : withdrawing
                  ? 'I approve withdrawing these old claims and this spending limit.'
                  : 'I approve this action, public address and spending limit.',
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.primary,
              ),
            ),
          ),
          if (review.blockedReason case final reason?) ...[
            _small(reason),
            const SizedBox(height: AppSpacing.sm),
          ],
          AppButton(
            key: const Key('zns-confirm'),
            onPressed:
                data.canWrite &&
                    review.canConfirm &&
                    _acceptedReview &&
                    (!release || review.exitPreview != null)
                ? actions.onConfirmRegistration
                : null,
            variant: release
                ? AppButtonVariant.destructive
                : AppButtonVariant.primary,
            expand: true,
            child: Text('Confirm $action'),
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            onPressed: data.isBusy ? null : actions.onCancelReview,
            variant: AppButtonVariant.ghost,
            child: const Text('Cancel review'),
          ),
          const SizedBox(height: AppSpacing.s),
          _small(
            'Progress is saved to this wallet. New signing pauses when the wallet locks; unlock and resume to continue.',
          ),
        ],
      ),
    );
  }

  Widget _operationCard(ZnsOperationView operation) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${operation.name}.zec',
              style: AppTypography.headlineMedium.copyWith(
                color: context.colors.text.accent,
              ),
            ),
            _Badge(
              label: operation.isComplete
                  ? 'Complete'
                  : operation.isFailed
                  ? 'Needs attention'
                  : operation.isPaused
                  ? 'Paused'
                  : 'In progress',
              positive: operation.isComplete,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _title(operation.title),
        const SizedBox(height: AppSpacing.xs),
        Text(operation.description),
        if (operation.remainingWait case final wait?) ...[
          const SizedBox(height: AppSpacing.sm),
          _Badge(label: wait),
        ],
        const SizedBox(height: AppSpacing.md),
        for (final (index, step) in operation.steps.indexed) _step(index, step),
        if (operation.recoveryMessage case final recovery?) ...[
          const SizedBox(height: AppSpacing.sm),
          _Notice(
            icon: AppIcons.history,
            title: 'Saved progress',
            text: recovery,
            isError: operation.isFailed,
          ),
        ],
        if (operation.transactionId case final txid?) ...[
          const SizedBox(height: AppSpacing.sm),
          _Address(label: 'Latest transaction', address: txid),
        ],
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            if (operation.canResume)
              AppButton(
                key: const Key('zns-resume'),
                onPressed: data.canWrite ? actions.onResume : null,
                leading: const AppIcon(AppIcons.play),
                child: const Text('Resume'),
              ),
            if (operation.canPause)
              AppButton(
                key: const Key('zns-pause'),
                onPressed: actions.onPause,
                variant: AppButtonVariant.secondary,
                leading: const AppIcon(AppIcons.pause),
                child: const Text('Pause after current step'),
              ),
            AppButton(
              onPressed: data.isBusy ? null : actions.onRefresh,
              variant: AppButtonVariant.ghost,
              child: const Text('Refresh status'),
            ),
          ],
        ),
        if (!operation.isComplete) ...[
          const SizedBox(height: AppSpacing.sm),
          _small(
            'Transactions already sent can still confirm while paused. A commitment does not reserve the name.',
          ),
        ],
      ],
    ),
  );

  Widget _step(int index, ZnsProgressStep step) {
    final color = switch (step.status) {
      ZnsStepStatus.complete => context.colors.text.positiveStrong,
      ZnsStepStatus.failed => context.colors.text.destructive,
      ZnsStepStatus.upcoming => context.colors.text.secondary,
      _ => context.colors.text.accent,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.colors.background.raised,
              border: Border.all(color: context.colors.border.subtle),
            ),
            alignment: Alignment.center,
            child: step.status == ZnsStepStatus.complete
                ? AppIcon(AppIcons.check, size: 16, color: color)
                : step.status == ZnsStepStatus.failed
                ? AppIcon(AppIcons.help, size: 16, color: color)
                : Text(
                    '${index + 1}',
                    style: AppTypography.labelSmall.copyWith(color: color),
                  ),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: AppTypography.bodyMediumStrong.copyWith(color: color),
                ),
                if (step.detail case final detail?) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  _small(detail),
                ],
              ],
            ),
          ),
          if (step.status == ZnsStepStatus.paused)
            const _Badge(label: 'Paused'),
        ],
      ),
    );
  }

  Widget _ownedCard(ZnsOwnedNameView owned) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _eyebrow('Your name'),
        const SizedBox(height: AppSpacing.s),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${owned.name}.zec',
              style: AppTypography.headlineLarge.copyWith(
                color: context.colors.text.accent,
              ),
            ),
            _Badge(
              label: owned.isExpired
                  ? 'Expired'
                  : owned.isInGrace
                  ? 'In grace'
                  : 'Active',
              positive: !owned.isExpired && !owned.isInGrace,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _detail('Registration deposit', '${owned.deposit} cbZEC'),
        _detail('Original deposit maturity', owned.maturityAt),
        _detail('Refresh due', owned.refreshDueAt),
        _detail('Final grace deadline', owned.graceEndsAt),
        _detail('Accrued rewards', '${owned.accruedRewards} cbZEC'),
        _detail('Claimable rewards', '${owned.claimableRewards} cbZEC'),
        if (owned.isExpired)
          const _Notice(
            icon: AppIcons.history,
            title: 'This registration has expired',
            text:
                'Ownership, resolution and new rewards have ended. Your deposit and earned rewards remain available through old claims, even if someone else registers this name.',
          )
        else if (owned.isInGrace)
          const _Notice(
            icon: AppIcons.calendar,
            title: 'Keep your name before grace ends',
            text:
                'Your name still receives payments and earns rewards during grace. Refresh before the final deadline to keep it.',
          )
        else
          _small(
            owned.isMature
                ? 'Your initial holding period is complete. Releasing now returns your full deposit and vested rewards.'
                : 'Rewards accrue now and become claimable at your original maturity. Releasing early forfeits your entire deposit and all unvested rewards.',
          ),
        const SizedBox(height: AppSpacing.sm),
        _small(
          'Refreshes, address updates and reward claims never restart your initial holding period. Rewards may be zero; there is no guaranteed yield.',
        ),
        const SizedBox(height: AppSpacing.md),
        _Address(label: 'Registered address', address: owned.unifiedAddress),
        if (!owned.isExpired) ...[
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              AppButton(
                key: const Key('zns-refresh-name'),
                onPressed: data.canWrite && !_hasPending
                    ? actions.onRefreshName
                    : null,
                variant: AppButtonVariant.secondary,
                child: const Text('Keep name'),
              ),
              AppButton(
                key: const Key('zns-claim-rewards'),
                onPressed:
                    data.canWrite &&
                        !_hasPending &&
                        owned.isMature &&
                        owned.canClaimRewards
                    ? actions.onClaimRewards
                    : null,
                variant: AppButtonVariant.secondary,
                child: const Text('Claim rewards'),
              ),
              AppButton(
                onPressed: data.canWrite && !_hasPending
                    ? actions.onUpdateAddress
                    : null,
                variant: AppButtonVariant.secondary,
                child: const Text('Update address'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            key: const Key('zns-release-review'),
            onPressed: data.canWrite && !_hasPending ? actions.onRelease : null,
            variant: AppButtonVariant.ghost,
            child: const Text('Review name release'),
          ),
        ],
      ],
    ),
  );

  Widget _balancesCard() => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _title('Your funds on Base')),
            AppButton(
              key: const Key('zns-balances-toggle'),
              onPressed: () => setState(() => _showBalances = !_showBalances),
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.small,
              child: Text(_showBalances ? 'Hide details' : 'Show details'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s),
        _detail('Available cbZEC', '${data.cbZecBalance} cbZEC'),
        _detail('Network fees', '${data.ethBalance} ETH'),
        _detail('Old deposits to withdraw', '${data.claimablePrincipal} cbZEC'),
        _detail('Old rewards to withdraw', '${data.claimableRewards} cbZEC'),
        _small(
          'Remaining cbZEC and ETH stay in your Base account. Withdrawals return cbZEC on Base, not shielded ZEC.',
        ),
        if (_showBalances) ...[
          const SizedBox(height: AppSpacing.md),
          _Address(label: 'Name owner on Base', address: data.baseOwnerAddress),
          const SizedBox(height: AppSpacing.s),
          _small(
            data.baseRecoveryDescription.isEmpty
                ? 'Keep the recovery information for the account that owns your name. Losing access to this Base account can prevent name management and withdrawals.'
                : data.baseRecoveryDescription,
          ),
        ],
        if (data.canWithdrawClaims) ...[
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            key: const Key('zns-withdraw-claims'),
            onPressed: data.canWrite && !_hasPending
                ? actions.onWithdrawClaims
                : null,
            variant: AppButtonVariant.secondary,
            child: const Text('Withdraw old claims'),
          ),
          const SizedBox(height: AppSpacing.xs),
          _small(
            'Withdrawing old claims keeps your current name and its deposit in place.',
          ),
        ],
      ],
    ),
  );

  Widget _title(String text) => Text(
    text,
    style: AppTypography.bodyLarge.copyWith(
      color: context.colors.text.accent,
      fontWeight: FontWeight.w600,
    ),
  );
  Widget _eyebrow(String text) => Text(
    text.toLowerCase().replaceRange(0, 1, text[0]),
    style: AppTypography.labelSmall.copyWith(
      color: context.colors.text.secondary,
    ),
  );
  Widget _small(String text) => Text(
    text,
    style: AppTypography.bodySmall.copyWith(
      color: context.colors.text.secondary,
    ),
  );
  Widget _divider() => ColoredBox(
    color: context.colors.border.subtle,
    child: const SizedBox(height: 1),
  );
  Widget _detail(String label, String value, {bool strong = false}) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.s),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style:
                (strong
                        ? AppTypography.bodyMediumStrong
                        : AppTypography.bodyMedium)
                    .copyWith(color: context.colors.text.accent),
          ),
        ),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(
      kAppFormFactor == AppFormFactor.mobile ? AppSpacing.sm : AppSpacing.md,
    ),
    decoration: BoxDecoration(
      color: context.colors.background.base,
      borderRadius: BorderRadius.circular(AppRadii.large),
      border: Border.all(color: context.colors.border.subtle),
    ),
    child: child,
  );
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.text,
    this.isError = false,
  });
  final String icon;
  final String title;
  final String text;
  final bool isError;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: isError,
    child: Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: isError
            ? context.colors.background.utilityDestructiveSubtle
            : context.colors.background.raised,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(
            icon,
            size: 20,
            color: isError
                ? context.colors.text.destructive
                : context.colors.text.secondary,
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: context.colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  text,
                  style: AppTypography.bodySmall.copyWith(
                    color: context.colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.positive = false});
  final String label;
  final bool positive;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.s,
      vertical: AppSpacing.xxs,
    ),
    decoration: BoxDecoration(
      color: context.colors.background.raised,
      borderRadius: BorderRadius.circular(AppRadii.full),
    ),
    child: Text(
      label,
      style: AppTypography.labelSmall.copyWith(
        color: positive
            ? context.colors.text.positiveStrong
            : context.colors.text.secondary,
      ),
    ),
  );
}

class _Address extends StatelessWidget {
  const _Address({
    required this.label,
    required this.address,
    this.emptyText = 'Unavailable',
  });
  final String label;
  final String address;
  final String emptyText;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ),
          if (address.isNotEmpty)
            AppButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: address));
                if (context.mounted) {
                  ScaffoldMessenger.maybeOf(
                    context,
                  )?.showSnackBar(const SnackBar(content: Text('Copied')));
                }
              },
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.small,
              child: const Text('Copy'),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.xxs),
      SelectableText(
        address.isEmpty ? emptyText : address,
        style: AppTypography.codeSmall.copyWith(
          color: context.colors.text.primary,
        ),
      ),
    ],
  );
}

class _ConfigurationForm extends StatefulWidget {
  const _ConfigurationForm({
    super.key,
    required this.initial,
    required this.enabled,
    required this.onSave,
    required this.onClose,
  });
  final ZnsConfigurationInput initial;
  final bool enabled;
  final ValueChanged<ZnsConfigurationInput>? onSave;
  final VoidCallback onClose;
  @override
  State<_ConfigurationForm> createState() => _ConfigurationFormState();
}

class _ConfigurationFormState extends State<_ConfigurationForm> {
  late final _rpc = TextEditingController(text: widget.initial.rpcUrl);
  late final _registry = TextEditingController(
    text: widget.initial.registryAddress,
  );
  late final _chain = TextEditingController(text: '${widget.initial.chainId}');
  late final _token = TextEditingController(text: widget.initial.tokenAddress);
  late final _delegate = TextEditingController(
    text: widget.initial.delegateAddress,
  );
  bool get _valid {
    final uri = Uri.tryParse(_rpc.text.trim());
    final address = RegExp(r'^0x[a-fA-F0-9]{40}$');
    return uri != null &&
        uri.host.isNotEmpty &&
        ['http', 'https'].contains(uri.scheme) &&
        (int.tryParse(_chain.text) ?? 0) > 0 &&
        address.hasMatch(_registry.text.trim()) &&
        address.hasMatch(_token.text.trim()) &&
        (_delegate.text.trim().isEmpty ||
            address.hasMatch(_delegate.text.trim()));
  }

  @override
  void dispose() {
    for (final controller in [_rpc, _registry, _chain, _token, _delegate]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Name service settings',
          style: AppTypography.headlineMedium.copyWith(
            color: context.colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        Text(
          'Use the verified deployment for your network. Settings are checked before registration becomes available.',
          style: AppTypography.bodySmall.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _field('Registry address', _registry, hint: '0x…'),
        _field('RPC URL', _rpc),
        _field('Chain ID', _chain, numeric: true),
        _field('cbZEC token address', _token),
        _field(
          'Delegated executor address (optional)',
          _delegate,
          hint: 'Leave empty for ordinary transactions',
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton(
          key: const Key('zns-save-settings'),
          onPressed: widget.enabled && _valid && widget.onSave != null
              ? () => widget.onSave!(
                  ZnsConfigurationInput(
                    rpcUrl: _rpc.text.trim(),
                    registryAddress: _registry.text.trim(),
                    chainId: int.parse(_chain.text),
                    tokenAddress: _token.text.trim(),
                    delegateAddress: _delegate.text.trim(),
                  ),
                )
              : null,
          expand: true,
          child: const Text('Verify & save settings'),
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton(
          onPressed: widget.onClose,
          variant: AppButtonVariant.ghost,
          child: const Text('Close settings'),
        ),
      ],
    ),
  );
  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: AppTextField(
      label: label,
      controller: controller,
      hintText: hint,
      enabled: widget.enabled,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      onChanged: (_) => setState(() {}),
    ),
  );
}
