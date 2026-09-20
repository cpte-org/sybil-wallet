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
  final _recipient = TextEditingController();
  final _extraDeposit = TextEditingController(text: '0');
  bool _showExtraDeposit = false;
  final _receivingAddress = TextEditingController();
  final _operationKey = GlobalKey();
  final _reviewKey = GlobalKey();
  final _errorKey = GlobalKey();
  bool _showAddressEditor = false;
  bool _acceptedReview = false;
  bool _showBalances = false;

  @override
  void initState() {
    super.initState();
    if (data.operation != null) _scrollTo(_operationKey);
  }

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
  bool get _hasPending => data.operation != null && !data.operation!.isComplete;
  bool get _editing => !_hasPending && data.review == null;

  @override
  void didUpdateWidget(ZnsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.accountId != data.accountId) {
      _name.clear();
      _extraDeposit.text = '0';
      _showExtraDeposit = false;
      _acceptedReview = false;
      _showBalances = false;
    }
    if (oldWidget.data.accountId != data.accountId ||
        oldWidget.data.baseOwnerAddress != data.baseOwnerAddress ||
        oldWidget.data.ownedName?.positionId != data.ownedName?.positionId) {
      _recipient.clear();
      _receivingAddress.clear();
      _showAddressEditor = false;
    }
    if (_approvalKey(oldWidget.data.review) != _approvalKey(data.review)) {
      _acceptedReview = false;
    }
    if (oldWidget.data.operation == null && data.operation != null) {
      _name.clear();
      _extraDeposit.text = '0';
      _showExtraDeposit = false;
      _scrollTo(_operationKey);
    } else if (oldWidget.data.operation?.isComplete != true &&
        data.operation?.isComplete == true) {
      _name.clear();
      _extraDeposit.text = '0';
      _showExtraDeposit = false;
      _scrollTo(_operationKey);
    } else if (oldWidget.data.operation?.isComplete == true &&
        data.operation?.isComplete == false) {
      // A new operation replaced a completed one without the card ever
      // leaving the tree (confirm ran while the old card was still shown).
      _scrollTo(_operationKey);
    }
    if (oldWidget.data.review != null &&
        data.review == null &&
        data.operation != null) {
      // Confirming a review over an existing operation swaps the review card
      // for the new progress card.
      _scrollTo(_operationKey);
    }
    if (oldWidget.data.review == null && data.review != null) {
      _scrollTo(_reviewKey);
    }
    if (data.review == null &&
        data.error != null &&
        (oldWidget.data.error != data.error ||
            (oldWidget.data.isBusy && !data.isBusy))) {
      _scrollTo(_errorKey);
    }
  }

  void _scrollTo(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = key.currentContext;
      if (!mounted || context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        alignment: 0.05,
      );
    });
  }

  Future<void> _pullRefresh() async {
    final refresh = actions.onRefresh;
    if (refresh == null || data.isBusy || !_editing) return;
    await refresh();
  }

  String _approvalKey(ZnsReviewView? review) => review == null
      ? ''
      : [
          review.kind,
          review.name,
          review.positionId,
          review.recipient,
          review.unifiedAddress,
          review.maxZec,
          review.deposit,
          review.minimumDeposit,
          review.extraDeposit,
          review.usdTarget,
          review.pricingMode,
          review.minimumFloorApplies,
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
    _recipient.dispose();
    _extraDeposit.dispose();
    _receivingAddress.dispose();
    super.dispose();
  }

  String _ethDisplay(String exact) {
    final parts = exact.split('.');
    if (parts.length != 2 || parts[1].length <= 8) return '$exact ETH';
    final wei = BigInt.tryParse('${parts[0]}${parts[1].padRight(18, '0')}');
    if (wei == null) return '$exact ETH';
    final unit = BigInt.from(10000000000);
    final rounded = ((wei + unit - BigInt.one) ~/ unit).toString().padLeft(
      9,
      '0',
    );
    return '≈ ${rounded.substring(0, rounded.length - 8)}.${rounded.substring(rounded.length - 8)} ETH';
  }

  void _lookup() {
    if (_validName && data.isConfigured && !data.isBusy && _editing) {
      actions.onLookup?.call(_normalizedName);
    }
  }

  @override
  Widget build(BuildContext context) {
    const mobile = kAppFormFactor == AppFormFactor.mobile;
    Widget content = SingleChildScrollView(
      key: const Key('zns-scroll'),
      padding: const EdgeInsets.all(mobile ? AppSpacing.sm : AppSpacing.base),
      physics: mobile ? const AlwaysScrollableScrollPhysics() : null,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!mobile) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Manage my names',
                        style: AppTypography.headlineLarge.copyWith(
                          color: context.colors.text.accent,
                        ),
                      ),
                    ),
                    AppButton(
                      key: const Key('zns-refresh-balances'),
                      onPressed: data.isBusy || !_editing
                          ? null
                          : actions.onRefresh,
                      variant: AppButtonVariant.ghost,
                      size: AppButtonSize.small,
                      child: const Text('Refresh'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s),
              ],
              Text(
                'Register a name or manage the ones you own.',
                style: AppTypography.bodyLarge.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
              if (data.isBusy) ...[
                const SizedBox(height: AppSpacing.s),
                Semantics(
                  liveRegion: true,
                  child: Row(
                    children: [
                      const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: AppSpacing.s),
                      Flexible(
                        child: Text(
                          data.isPreparingRegistration
                              ? 'Preparing your registration review…'
                              : 'Checking name service…',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
              if (!data.isConfigured) ...[
                const _Notice(
                  icon: AppIcons.endpoint,
                  title: 'Name service is not configured',
                  text:
                      'Add a verified registry in Settings → Public Zcash names before registering a name.',
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (!data.isSoftwareAccount) ...[
                const _Notice(
                  icon: AppIcons.keystone,
                  title: 'Choose a software account to register',
                  text:
                      'Keystone registration will be supported separately. Public name lookups are available in Settings.',
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
                KeyedSubtree(
                  key: _errorKey,
                  child: _Notice(
                    icon: AppIcons.warningCircle,
                    title: 'Action needed',
                    text: error,
                    isError: true,
                    onDismiss: actions.onDismissError,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (data.notice case final notice?) ...[
                _Notice(
                  icon: AppIcons.help,
                  title: 'Before you continue',
                  text: notice,
                  onDismiss: actions.onDismissNotice,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (data.operation case final operation?) ...[
                KeyedSubtree(
                  key: _operationKey,
                  child: _operationCard(operation),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (data.review case final review?) ...[
                KeyedSubtree(key: _reviewKey, child: _reviewCard(review)),
                const SizedBox(height: AppSpacing.md),
              ],
              if (data.names.isNotEmpty) ...[
                _inventoryCard(),
                const SizedBox(height: AppSpacing.md),
              ],
              if (data.ownedName case final owned?) ...[
                _ownedCard(owned),
                const SizedBox(height: AppSpacing.md),
              ],
              if (_editing) _searchCard(),
              const SizedBox(height: AppSpacing.md),
              if (data.baseOwnerAddress.isNotEmpty || data.canWithdrawClaims)
                _balancesCard(),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
    if (!mobile) {
      return Material(
        color: Colors.transparent,
        child: DefaultTextStyle(
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.primary,
          ),
          child: content,
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      child: DefaultTextStyle(
        style: AppTypography.bodyMedium.copyWith(
          color: context.colors.text.primary,
        ),
        child: RefreshIndicator(
          color: context.colors.text.accent,
          onRefresh: _pullRefresh,
          child: content,
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
            tone: _name.text.isNotEmpty && !_validName
                ? AppTextFieldTone.destructive
                : AppTextFieldTone.neutral,
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
            leading: lookup?.status == ZnsLookupStatus.loading
                ? const AppIcon(AppIcons.loader)
                : const AppIcon(AppIcons.search),
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
          if (available) ...[
            const SizedBox(height: AppSpacing.md),
            _divider(),
            const SizedBox(height: AppSpacing.md),
            const _Notice(
              icon: AppIcons.lock,
              title: 'One deposit. A name that stays yours.',
              text:
                  'Deposit cbZEC once and keep your name active with an annual refresh. Exit after 365 days to receive your deposit back. The early-exit fee starts at 10% and falls to zero over the original 365 days. Early release pays the elapsed fraction of accrued rewards.',
            ),
            const SizedBox(height: AppSpacing.md),
            _Address(
              label: 'Zcash receiving address',
              address: data.walletUnifiedAddress,
              emptyText: 'Your wallet address is loading.',
            ),
            const SizedBox(height: AppSpacing.md),
            _small(
              'Existing Base funds are used first. If more funds are needed, your review shows the ZEC estimate and maximum spend before you approve.',
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: const Key('zns-extra-toggle'),
              variant: AppButtonVariant.secondary,
              onPressed: () =>
                  setState(() => _showExtraDeposit = !_showExtraDeposit),
              child: const Text('Optional extra bond'),
            ),
            if (_showExtraDeposit) ...[
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                key: const Key('zns-extra-deposit'),
                controller: _extraDeposit,
                label: 'Extra cbZEC',
                hintText: '0',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _small(
                'Add cbZEC only when registering. Rewards are proportional to the actual total bond. The same maturity and exit terms apply to the full bond.',
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: const Key('zns-prepare'),
              onPressed:
                  data.canWrite &&
                      data.walletUnifiedAddress.isNotEmpty &&
                      actions.onPrepareRegistration != null
                  ? () => actions.onPrepareRegistration!(
                      ZnsRegistrationInput(
                        name: _normalizedName,
                        extraDeposit: _extraDeposit.text.trim().isEmpty
                            ? '0'
                            : _extraDeposit.text.trim(),
                      ),
                    )
                  : null,
              expand: true,
              leading: data.isPreparingRegistration
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              child: Text(
                data.isPreparingRegistration
                    ? 'Preparing review…'
                    : 'Review registration',
              ),
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
              switch (lookup.status) {
                ZnsLookupStatus.available => AppIcons.checkCircle,
                ZnsLookupStatus.registered => AppIcons.book,
                ZnsLookupStatus.failed => AppIcons.warningCircle,
                _ => AppIcons.help,
              },
              color: switch (lookup.status) {
                ZnsLookupStatus.available => context.colors.text.positiveStrong,
                ZnsLookupStatus.failed => context.colors.text.destructive,
                _ => context.colors.text.secondary,
              },
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
                  ? 'Someone has already registered this name.'
                  : 'Try another name or check again.'),
        ),
        if (registered &&
            actions.onSendToName != null &&
            lookup.unifiedAddress.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _Address(label: 'Registered address', address: lookup.unifiedAddress),
          if (actions.onSendToName != null &&
              lookup.unifiedAddress.isNotEmpty) ...[
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
      ZnsReviewKind.transfer => 'NFT transfer',
      ZnsReviewKind.withdrawClaims => 'old claims withdrawal',
    };
    final registering = review.kind == ZnsReviewKind.registration;
    final release = review.kind == ZnsReviewKind.release;
    final transferring = review.kind == ZnsReviewKind.transfer;
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
          if (registering && review.usdTarget != null) ...[
            _detail('Length-based bond target', '\$${review.usdTarget} USD'),
            _detail(
              'Pricing mode',
              review.pricingMode == 1
                  ? 'Fixed cbZEC fallback'
                  : review.minimumFloorApplies
                  ? 'USD pricing · minimum bond floor'
                  : 'USD oracle quote',
            ),
            if (review.minimumDeposit != null)
              _detail('Minimum bond', '${review.minimumDeposit} cbZEC'),
            if (review.minimumFloorApplies)
              const Text(
                'The minimum cbZEC floor applies before any optional extra. '
                'Its USD value may exceed the target.',
              ),
            if (review.extraDeposit != null)
              _detail('Optional extra bond', '${review.extraDeposit} cbZEC'),
          ],
          if (registering || withdrawing || transferring)
            _detail(
              withdrawing
                  ? 'Principal to withdraw'
                  : transferring
                  ? 'Deposit transferred'
                  : 'Maximum registration bond',
              '${review.deposit} cbZEC',
            ),
          if (review.maturityAt case final date?)
            _detail('Original deposit maturity', date),
          if (registering && review.maturityAt == null)
            _detail('Deposit maturity', '365 days after registration confirms'),
          if (!release && !withdrawing && review.refreshDueAt != null)
            _detail('Next refresh due', review.refreshDueAt!),
          if ((transferring ||
                  withdrawing ||
                  review.kind == ZnsReviewKind.claimRewards) &&
              review.rewardsToClaim != null)
            _detail(
              transferring
                  ? 'Unclaimed rewards transferred'
                  : 'Rewards to receive',
              '${review.rewardsToClaim} cbZEC',
            ),
          if (review.exitPreview case final exit?) ...[
            _detail(
              'Deposit returned',
              '${exit.principalReturned} cbZEC',
              strong: true,
            ),
            _detail('Rewards returned', '${exit.rewardsReturned} cbZEC'),
            _detail(
              'Early-release fee',
              '${exit.principalForfeited} cbZEC',
              strong: exit.early,
            ),
            _detail(
              'Unvested rewards forfeited',
              '${exit.rewardsForfeited} cbZEC',
              strong: exit.early,
            ),
          ],
          _detail('Maximum network fee', _ethDisplay(review.gasReserve)),
          if (review.maxZec != '0') ...[
            if (review.estimatedZec != null)
              _detail(
                'Estimated ZEC including fees',
                '${review.estimatedZec} ZEC',
              ),
            if (review.conversionRate != null)
              _detail('Estimated conversion rate', review.conversionRate!),
            if (review.zcashFee != null)
              _detail('Zcash network fee (included)', '${review.zcashFee} ZEC'),
            _detail(
              'Maximum total ZEC spend',
              '${review.maxZec} ZEC',
              strong: true,
            ),
            _small(
              'The maximum includes a price-movement allowance. Only the quoted funding amount is sent. Unused ETH stays in your Base account for later fees. A quote above this limit requires another review.',
            ),
          ] else
            _detail('ZEC funding needed', 'None — using existing Base funds'),
          if (review.maxBaseEth case final maximum?)
            _detail(
              'Maximum Base ETH spend',
              _ethDisplay(maximum),
              strong: true,
            ),
          if (review.existingCbZecSpend case final existing?)
            _detail('From existing cbZEC', '$existing cbZEC'),
          if (review.existingEthSpend case final existing?)
            _detail('From existing ETH', _ethDisplay(existing)),
          _detail('Estimated duration', review.estimatedDuration),
          if (review.quoteExpiresIn case final expiry?)
            _detail('Quote expires', expiry),
          const SizedBox(height: AppSpacing.sm),
          if (transferring)
            _Address(
              label: 'Recipient Base address',
              address: review.recipient ?? '',
            ),
          if (!release && !withdrawing && !transferring)
            _Address(
              label: 'Zcash receiving address',
              address: review.unifiedAddress,
            ),
          const SizedBox(height: AppSpacing.md),
          if (release)
            _Notice(
              icon: AppIcons.help,
              isError: review.exitPreview?.early ?? false,
              title: review.exitPreview?.early == true
                  ? 'Early release fee: 10%'
                  : 'Your name will be released',
              text: review.exitPreview?.early == true
                  ? 'The early-release fee declines linearly from 10% to zero over your original 365 days, rounded up to the smallest cbZEC unit. You receive the elapsed fraction of accrued rewards. The remainder and fee go to other eligible bonds proportionally, or the reserve if none remain. Another person can register your released name.'
                  : 'Your deposit and vested rewards will return to your Base account. Another person can register your released name. Network and conversion costs are not refunded.',
            )
          else if (transferring)
            const _Notice(
              icon: AppIcons.help,
              title: 'Transfer the name and its funds',
              text:
                  'The recipient receives this NFT, its locked deposit and all unclaimed rewards. You receive no refund. Maturity and refresh deadlines stay unchanged. The payment address clears until the recipient sets theirs. There is no transfer penalty; network fees still apply.',
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
              text: registering && review.maxZec != '0'
                  ? 'The record also links to your Base account. The funding service uses a transparent Zcash deposit. Your name is secured only when registration confirms.'
                  : 'The record links this receiving address to your name and Base account.',
            ),
          const SizedBox(height: AppSpacing.sm),
          if (registering) ...[
            const _Notice(
              icon: AppIcons.lock,
              title: 'Your initial holding period is 365 days',
              text:
                  'The early-exit fee starts at 10% and declines to zero over the original 365 days. Early release pays the elapsed fraction of accrued rewards and forfeits the rest. Rewards are proportional to your actual bond, may be zero, and become separately claimable at maturity. Refreshes and transfers keep the original clocks. No top-ups or automatic compounding.',
            ),
            const SizedBox(height: AppSpacing.s),
            _small(
              review.maxZec == '0'
                  ? 'Registration uses your existing Base funds. Your name is secured when registration confirms.'
                  : 'If funding is needed, Vizor converts ZEC within your approved limit and keeps ETH for network fees. If the name becomes unavailable, converted funds remain in your Base account; conversion cannot be undone automatically.',
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
              transferring
                  ? 'I approve transferring this name, its deposit and all unclaimed rewards to the displayed Base address.'
                  : release
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
            Semantics(
              liveRegion: operation.isComplete || operation.isFailed,
              child: _Badge(
                label: operation.isComplete
                    ? 'Complete'
                    : operation.isFailed
                    ? 'Needs attention'
                    : operation.isPaused
                    ? 'Paused'
                    : 'In progress',
                positive: operation.isComplete,
              ),
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
                ? AppIcon(AppIcons.warning, size: 16, color: color)
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

  Widget _inventoryCard() => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title('Your names'),
        const SizedBox(height: AppSpacing.s),
        ...data.names.map(
          (item) => ListTile(
            key: Key('zns-select-${item.positionId}'),
            title: Text(
              '${item.name}.zec',
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.primary,
              ),
            ),
            subtitle: Text(
              item.expired
                  ? 'Expired — funds withdrawable'
                  : 'Active registration',
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
            selected: item.positionId == data.ownedName?.positionId,
            onTap: data.canWrite && _editing
                ? () => actions.onSelectName?.call(item.positionId)
                : null,
          ),
        ),
        Wrap(
          spacing: AppSpacing.s,
          children: [
            AppButton(
              onPressed: data.canWrite && _editing && data.inventoryOffset > 0
                  ? () => actions.onNamesPage?.call(data.inventoryOffset - 20)
                  : null,
              variant: AppButtonVariant.ghost,
              child: const Text('Previous names'),
            ),
            AppButton(
              onPressed: data.canWrite && _editing && data.hasMoreNames
                  ? () => actions.onNamesPage?.call(data.inventoryOffset + 20)
                  : null,
              variant: AppButtonVariant.ghost,
              child: const Text('Next names'),
            ),
          ],
        ),
      ],
    ),
  );

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
                'Name rights, resolution and new rewards have ended. Withdraw this registration to receive its deposit and earned rewards. If another person registers the label first, your funds move to old claims.',
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
                : 'Rewards accrue proportionally to your bond and become separately claimable at the original maturity. The exit fee declines from 10% to zero over 365 days; early release pays the elapsed fraction of accrued rewards.',
          ),
        const SizedBox(height: AppSpacing.sm),
        _small(
          'Refreshes, address updates and reward claims never restart your initial holding period. Rewards may be zero; there is no guaranteed yield.',
        ),
        const SizedBox(height: AppSpacing.md),
        if (owned.unifiedAddress.isEmpty)
          const _Notice(
            icon: AppIcons.help,
            title: 'Set your payment address',
            text:
                'This transferred name cannot receive payments until you set your own Zcash address.',
          )
        else
          _Address(
            label: 'Zcash receiving address',
            address: owned.unifiedAddress,
          ),
        if (owned.isExpired)
          AppButton(
            key: const Key('zns-withdraw-expired'),
            onPressed: data.canWrite && !_hasPending ? actions.onRelease : null,
            child: const Text('Withdraw expired registration'),
          ),
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
                child: const Text('Refresh name'),
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
                key: const Key('zns-edit-address'),
                onPressed: data.canWrite && _editing
                    ? () => setState(() {
                        _showAddressEditor = !_showAddressEditor;
                        if (_showAddressEditor) {
                          _receivingAddress.text = owned.unifiedAddress.isEmpty
                              ? data.walletUnifiedAddress
                              : owned.unifiedAddress;
                        }
                      })
                    : null,
                variant: AppButtonVariant.secondary,
                child: Text(
                  owned.unifiedAddress.isEmpty
                      ? 'Set payment address'
                      : 'Update address',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          if (_showAddressEditor) ...[
            AppTextField(
              key: const Key('zns-receiving-address'),
              controller: _receivingAddress,
              label: 'Zcash receiving address',
              hintText: 'Paste a Unified Address',
              enabled: data.canWrite && _editing,
              onChanged: (_) => setState(() {}),
            ),
            _small(
              'Use a Unified Address for this wallet’s Zcash network. This address will be public; payments will go to its owner.',
            ),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                AppButton(
                  key: const Key('zns-use-wallet-address'),
                  onPressed:
                      data.canWrite &&
                          _editing &&
                          data.walletUnifiedAddress.isNotEmpty
                      ? () => setState(
                          () => _receivingAddress.text =
                              data.walletUnifiedAddress,
                        )
                      : null,
                  variant: AppButtonVariant.ghost,
                  child: const Text('Use this wallet’s address'),
                ),
                AppButton(
                  key: const Key('zns-review-address'),
                  onPressed:
                      data.canWrite &&
                          _editing &&
                          _receivingAddress.text.trim().isNotEmpty &&
                          actions.onUpdateAddress != null
                      ? () => actions.onUpdateAddress!(
                          _receivingAddress.text.trim(),
                        )
                      : null,
                  child: const Text('Review address update'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
          ],
          AppTextField(
            key: const Key('zns-transfer-recipient'),
            controller: _recipient,
            label: 'Recipient Base address',
            hintText: '0x…',
            enabled: data.canWrite && _editing,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            key: const Key('zns-transfer-review'),
            onPressed:
                data.canWrite &&
                    _editing &&
                    RegExp(
                      r'^0x[0-9a-fA-F]{40}$',
                    ).hasMatch(_recipient.text.trim())
                ? () => actions.onTransfer?.call(_recipient.text.trim())
                : null,
            variant: AppButtonVariant.secondary,
            child: const Text('Review name transfer'),
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
    text.isEmpty
        ? text
        : text
              .toLowerCase()
              .replaceRange(0, 1, text[0])
              .replaceAll('nft', 'NFT'),
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
    this.onDismiss,
  });
  final String icon;
  final String title;
  final String text;
  final bool isError;
  final VoidCallback? onDismiss;
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
          if (onDismiss != null)
            IconButton(
              onPressed: onDismiss,
              tooltip: 'Dismiss',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: AppIcon(
                AppIcons.cross,
                size: 16,
                color: isError
                    ? context.colors.text.destructive
                    : context.colors.text.secondary,
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

class ZnsConfigurationForm extends StatefulWidget {
  const ZnsConfigurationForm({
    super.key,
    required this.initial,
    required this.enabled,
    required this.onSave,
    this.onClose,
    this.showRpcEndpoint = true,
  });
  final ZnsConfigurationInput initial;
  final bool enabled;
  final ValueChanged<ZnsConfigurationInput>? onSave;
  final VoidCallback? onClose;
  final bool showRpcEndpoint;
  @override
  State<ZnsConfigurationForm> createState() => ZnsConfigurationFormState();
}

class ZnsConfigurationFormState extends State<ZnsConfigurationForm> {
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
        if (widget.showRpcEndpoint) _field('RPC URL', _rpc),
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
        if (widget.onClose != null)
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
