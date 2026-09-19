// Apache-2.0 section 4(b): modified from upstream by the Sigil fork.
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart' show Colors;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../main.dart' show log;
import '../../providers/account_provider.dart';
import '../../providers/privacy_mode_provider.dart';
import '../../providers/receive_address_provider.dart';
import '../../providers/sync_provider.dart';
import '../../rust/api/sync.dart' as rust_sync;
import '../../features/migration/providers/ironwood_migration_coordinator_provider.dart';
import '../../features/migration/models/ironwood_migration_phases.dart';
import '../config/network_config.dart';
import '../formatting/zec_amount.dart';
import '../privacy/privacy_mask.dart';
import '../profile_pictures.dart';
import '../theme/app_theme.dart';
import '../widgets/app_copy_feedback.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_profile_picture.dart';
import '../widgets/app_tappable.dart';
import '../widgets/app_toast.dart';
import 'app_desktop_shell.dart';
import 'desktop_sidebar_spacing.dart';

final _sidebarThousandZatoshi = zatoshiPerZec * BigInt.from(1000);
final _sidebarMillionZatoshi = zatoshiPerZec * BigInt.from(1000000);

String _formatSidebarBalance(BigInt zatoshi) {
  final absolute = zatoshi.abs();
  if (absolute >= _sidebarMillionZatoshi) {
    return _formatSidebarCompactBalance(
      zatoshi,
      unitZatoshi: _sidebarMillionZatoshi,
      suffix: 'M',
    );
  }
  if (absolute >= _sidebarThousandZatoshi) {
    return _formatSidebarCompactBalance(
      zatoshi,
      unitZatoshi: _sidebarThousandZatoshi,
      suffix: 'K',
    );
  }

  final minimumVisibleZatoshi = BigInt.from(10000);
  if (absolute > BigInt.zero && absolute < minimumVisibleZatoshi) {
    return '${zatoshi.isNegative ? '-' : ''}<0.0001';
  }
  return ZecAmount.fromZatoshi(
    zatoshi,
  ).pretty(maxFractionDigits: 4, hideZeroFraction: true).amountText;
}

String _formatSidebarCompactBalance(
  BigInt zatoshi, {
  required BigInt unitZatoshi,
  required String suffix,
}) {
  final scaledThousandths = (zatoshi.abs() * BigInt.from(1000)) ~/ unitZatoshi;
  final whole = scaledThousandths ~/ BigInt.from(1000);
  var fraction = (scaledThousandths % BigInt.from(1000))
      .toString()
      .padLeft(3, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  if (fraction.isNotEmpty) fraction = '.$fraction';
  return '${zatoshi.isNegative ? '-' : ''}$whole$fraction$suffix';
}

class AppMainSidebar extends ConsumerStatefulWidget {
  const AppMainSidebar({
    this.disabledRoutePaths = const {},
    this.suppressActiveSelection = false,
    super.key,
  });

  final Set<String> disabledRoutePaths;

  /// Keeps navigation interactive while rendering every section inactive.
  final bool suppressActiveSelection;

  @override
  ConsumerState<AppMainSidebar> createState() => _AppMainSidebarState();
}

class _AppMainSidebarState extends ConsumerState<AppMainSidebar> {
  final LayerLink _accountMenuLink = LayerLink();

  bool _isCopyingAddress = false;
  OverlayEntry? _accountMenuEntry;

  String get _matchedLocation => GoRouterState.of(context).matchedLocation;

  bool _matches(String routePath) =>
      _matchedLocation == routePath ||
      _matchedLocation.startsWith('$routePath/');

  bool get _isHomeRoute => _matches('/home');

  bool _routeShouldBeActive(String routePath) =>
      !widget.suppressActiveSelection && _matches(routePath);

  bool get _homeShouldBeActive =>
      !widget.suppressActiveSelection &&
      (_isHomeRoute ||
          _matches('/send') ||
          _matches('/receive') ||
          _matches('/migration'));

  bool get _settingsShouldBeActive =>
      !widget.suppressActiveSelection &&
      (_matches('/settings') || _matches('/payment-links'));

  bool get _isAccountMenuOpen => _accountMenuEntry != null;

  @override
  void dispose() {
    _closeAccountMenu(rebuild: false);
    super.dispose();
  }

  void _navigateTo(String routePath) {
    if (widget.disabledRoutePaths.contains(routePath)) return;
    if (_matches(routePath)) return;
    context.go(routePath);
  }

  void _openAccounts() {
    _closeAccountMenu();
    _navigateTo('/accounts');
  }

  void _openAddAccount() {
    _closeAccountMenu();
    context.go('/add-account');
  }

  void _openActivity() {
    if (widget.disabledRoutePaths.contains('/activity') ||
        _matchedLocation == '/activity') {
      return;
    }
    context.go('/activity');
  }

  void _openSettings() {
    if (widget.disabledRoutePaths.contains('/settings') ||
        _matchedLocation == '/settings') {
      return;
    }
    context.go('/settings');
  }

  void _toggleAccountMenu({
    required List<AccountInfo> accounts,
    required String? activeAccountUuid,
  }) {
    if (_isAccountMenuOpen) {
      _closeAccountMenu();
    } else {
      _openAccountMenu(
        accounts: accounts,
        activeAccountUuid: activeAccountUuid,
      );
    }
  }

  void _openAccountMenu({
    required List<AccountInfo> accounts,
    required String? activeAccountUuid,
  }) {
    final overlay = Overlay.of(context);
    final appTheme = AppTheme.of(context);
    _accountMenuEntry = OverlayEntry(
      builder: (_) => AppTheme(
        data: appTheme,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('sidebar_accounts_popover_backdrop'),
                behavior: HitTestBehavior.translucent,
                onTap: _closeAccountMenu,
              ),
            ),
            CompositedTransformFollower(
              link: _accountMenuLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.bottomLeft,
              offset: const Offset(0, -8),
              child: _SidebarAccountsPopover(
                accounts: accounts,
                activeAccountUuid: activeAccountUuid,
                onSelectAccount: (uuid) => unawaited(_switchAccount(uuid)),
                onCopyAccountAddress: (account) =>
                    unawaited(_copyShieldedAddressForAccount(account)),
                onManageAccounts: _openAccounts,
                onAddAccount: _openAddAccount,
              ),
            ),
          ],
        ),
      ),
    );
    overlay.insert(_accountMenuEntry!);
    setState(() {});
  }

  void _closeAccountMenu({bool rebuild = true}) {
    final entry = _accountMenuEntry;
    if (entry == null) return;
    _accountMenuEntry = null;
    entry.remove();
    if (rebuild && mounted) setState(() {});
  }

  Future<void> _switchAccount(String uuid) async {
    final activeAccountUuid = ref
        .read(accountProvider)
        .value
        ?.activeAccountUuid;
    _closeAccountMenu();
    if (uuid == activeAccountUuid) return;

    final accountNotifier = ref.read(accountProvider.notifier);
    final syncNotifier = ref.read(syncProvider.notifier);
    await accountNotifier.switchAccount(uuid);
    if (mounted) {
      context.go('/home');
    }
    unawaited(_refreshAfterAccountSwitch(syncNotifier));
  }

  Future<void> _refreshAfterAccountSwitch(SyncNotifier syncNotifier) async {
    try {
      await syncNotifier.refreshAfterAccountSwitch();
    } catch (e) {
      log('AppMainSidebar: refresh after account switch failed: $e');
    }
  }

  Future<void> _copyShieldedAddress() async {
    if (_isCopyingAddress) return;

    final accountState = ref.read(accountProvider).value;
    final accountUuid = accountState?.activeAccountUuid;
    if (accountUuid == null) {
      showAppToast(context, "Address couldn't be copied");
      return;
    }

    setState(() {
      _isCopyingAddress = true;
    });

    try {
      final address = await ref
          .read(receiveAddressServiceProvider)
          .loadShieldedAddress(
            accountUuid: accountUuid,
            currentShieldedAddress: accountState?.activeAddress,
          );
      if (!mounted) return;
      if (ref.read(accountProvider).value?.activeAccountUuid != accountUuid) {
        return;
      }
      if (address.trim().isEmpty) {
        showAppToast(context, "Address couldn't be copied");
        return;
      }

      if (!mounted) return;
      copyTextWithToast(context, text: address, toastMessage: 'Address copied');
    } catch (e) {
      log('AppMainSidebar: ERROR copying shielded address: $e');
      if (!mounted) return;
      showAppToast(context, "Address couldn't be copied");
    } finally {
      if (mounted) {
        setState(() {
          _isCopyingAddress = false;
        });
      }
    }
  }

  Future<void> _copyShieldedAddressForAccount(AccountInfo account) async {
    if (_isCopyingAddress) return;
    setState(() => _isCopyingAddress = true);

    try {
      final accountState = ref.read(accountProvider).value;
      final currentShieldedAddress =
          accountState?.activeAccountUuid == account.uuid
          ? accountState?.activeAddress
          : null;
      final address = await ref
          .read(receiveAddressServiceProvider)
          .loadShieldedAddress(
            accountUuid: account.uuid,
            currentShieldedAddress: currentShieldedAddress,
          );
      if (!mounted) return;
      if (address.trim().isEmpty) {
        showAppToast(context, "Address couldn't be copied");
        return;
      }

      if (!mounted) return;
      copyTextWithToast(
        context,
        text: address,
        toastMessage: 'Shielded address copied',
      );
    } catch (e) {
      log('AppMainSidebar: ERROR copying account shielded address: $e');
      if (!mounted) return;
      showAppToast(context, "Address couldn't be copied");
    } finally {
      if (mounted) {
        setState(() => _isCopyingAddress = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountAsync = ref.watch(accountProvider);
    final accounts = [
      ...(accountAsync.value?.accounts ?? const <AccountInfo>[]),
    ];
    accounts.sort((a, b) => a.order.compareTo(b.order));
    final activeAccountUuid = accountAsync.value?.activeAccountUuid;
    AccountInfo? activeAccount;
    if (activeAccountUuid != null) {
      for (final account in accounts) {
        if (account.uuid == activeAccountUuid) {
          activeAccount = account;
          break;
        }
      }
    }
    final accountName = activeAccount?.name ?? 'Username';
    final sync = ref.watch(syncProvider).value ?? SyncState();
    final accountSync = sync.scopedToAccount(activeAccountUuid);
    final isImporting =
        activeAccountUuid != null &&
        !accountSync.hasAccountScopedData &&
        accountSync.failure == null;
    final balanceText =
        '${_formatSidebarBalance(accountSync.displayTotalBalance)} '
        '$kZcashDefaultCurrencyTicker';
    final privacyModeEnabled = ref.watch(privacyModeProvider);
    final balanceLabel = hideAmountIfPrivacyMode(
      balanceText,
      privacyModeEnabled: privacyModeEnabled,
    );
    final migrationCoordinator = ref.watch(
      ironwoodMigrationCoordinatorProvider,
    );
    final migrationStatus = activeAccountUuid == null
        ? null
        : migrationCoordinator.statuses[activeAccountUuid];

    return AppTheme(
      data: AppThemeData.dark,
      child: AppDesktopSidebarSurface(
        backgroundColor: AppThemeData.dark.colors.background.window,
        glass: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 640;
            final topPadding = mainSidebarTopPadding(compact: compact);

            final bottomPadding = compact ? AppSpacing.xs : AppSpacing.md;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    top: topPadding,
                    left: AppSpacing.sm,
                    right: AppSpacing.sm,
                    bottom: bottomPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!compact)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 38),
                          child: Text(
                            'sigil.',
                            style: AppTypography.headlineLarge.copyWith(
                              fontFamily: 'Young Serif',
                              fontSize: 40,
                              letterSpacing: -2,
                              color: context.colors.text.primary,
                            ),
                          ),
                        ),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (migrationStatus?.activeRunId != null &&
                                  migrationStatus?.phase !=
                                      kIronwoodMigrationWaitingDenomConfirmationsPhase)
                                _SidebarMigrationHomeSection(
                                  status: migrationStatus!,
                                  isHardware:
                                      activeAccount?.isHardware ?? false,
                                  orchardBalance:
                                      accountSync.displayOrchardHoldingsBalance,
                                  ironwoodBalance:
                                      accountSync.displayIronwoodBalance +
                                      accountSync.displayIronwoodPendingBalance,
                                  privacyModeEnabled: privacyModeEnabled,
                                  active: _homeShouldBeActive,
                                  onHome: () => _navigateTo('/home'),
                                  onMigration: () =>
                                      _navigateTo('/migration/private/status'),
                                )
                              else
                                AppSidebarItem(
                                  key: const ValueKey('sidebar_home_button'),
                                  label: isImporting
                                      ? 'Importing...'
                                      : 'Wallet',
                                  iconName: isImporting
                                      ? AppIcons.loader
                                      : AppIcons.home,
                                  iconAnimated: !isImporting,
                                  active: _homeShouldBeActive,
                                  onTap: isImporting
                                      ? null
                                      : () => _navigateTo('/home'),
                                ),
                              const SizedBox(height: AppSpacing.xs),
                              AppSidebarItem(
                                key: const ValueKey('sidebar_people_button'),
                                label: 'People',
                                iconName: AppIcons.users,
                                active:
                                    _routeShouldBeActive('/people') ||
                                    _routeShouldBeActive('/contacts'),
                                onTap:
                                    widget.disabledRoutePaths.contains(
                                      '/people',
                                    )
                                    ? null
                                    : () => _navigateTo('/people'),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              AppSidebarItem(
                                key: const ValueKey('sidebar_activity_button'),
                                label: 'Activity',
                                iconName: AppIcons.history,
                                active: _routeShouldBeActive('/activity'),
                                // Stays tappable on detail subroutes (tx/swap status)
                                // as a way back to the main activity feed.
                                onTap:
                                    isImporting ||
                                        widget.disabledRoutePaths.contains(
                                          '/activity',
                                        )
                                    ? null
                                    : _openActivity,
                              ),
                            ],
                          ),
                        ),
                      ),
                      CompositedTransformTarget(
                        link: _accountMenuLink,
                        child: _SidebarAccountHeader(
                          key: const ValueKey('sidebar_accounts_button'),
                          accountName: accountName,
                          profilePictureId:
                              activeAccount?.profilePictureId ??
                              kDefaultProfilePictureId,
                          balanceLabel: balanceLabel,
                          showsKeystone: activeAccount?.isHardware ?? false,
                          privacyModeEnabled: privacyModeEnabled,
                          onTogglePrivacyMode: () =>
                              ref.read(privacyModeProvider.notifier).toggle(),
                          onCopyAddress:
                              activeAccountUuid == null || _isCopyingAddress
                              ? null
                              : () => unawaited(_copyShieldedAddress()),
                          onTap: accounts.isEmpty
                              ? null
                              : () => _toggleAccountMenu(
                                  accounts: accounts,
                                  activeAccountUuid: activeAccountUuid,
                                ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      AppSidebarItem(
                        key: const ValueKey('sidebar_settings_button'),
                        label: 'Settings',
                        iconName: AppIcons.cog,
                        active:
                            _settingsShouldBeActive ||
                            _routeShouldBeActive('/names'),
                        onTap: widget.disabledRoutePaths.contains('/settings')
                            ? null
                            : _openSettings,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SidebarMigrationHomeSection extends StatelessWidget {
  const _SidebarMigrationHomeSection({
    required this.status,
    required this.isHardware,
    required this.orchardBalance,
    required this.ironwoodBalance,
    required this.privacyModeEnabled,
    required this.active,
    required this.onHome,
    required this.onMigration,
  });

  final rust_sync.MigrationStatus status;
  final bool isHardware;
  final BigInt orchardBalance;
  final BigInt ironwoodBalance;
  final bool privacyModeEnabled;
  final bool active;
  final VoidCallback onHome;
  final VoidCallback onMigration;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final signingPartIndices = status.currentSigningPartIndices;
    final needsInput =
        isHardware &&
        status.phase == kIronwoodMigrationReadyToMigratePhase &&
        (signingPartIndices == null || signingPartIndices.isNotEmpty);
    final orchardLabel = hideAmountIfPrivacyMode(
      '${_formatSidebarBalance(orchardBalance)} ZEC',
      privacyModeEnabled: privacyModeEnabled,
    );
    final ironwoodLabel = hideAmountIfPrivacyMode(
      '${_formatSidebarBalance(ironwoodBalance)} ZEC',
      privacyModeEnabled: privacyModeEnabled,
    );

    return SizedBox(
      height: 120,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: AppSidebarItem(
              key: ValueKey('sidebar_orchard_home_row'),
              label: 'Wallet',
              iconName: AppIcons.home,
              onTap: onHome,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    orchardLabel,
                    key: ValueKey('sidebar_orchard_balance'),
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.secondary.withValues(alpha: 0.5),
                    ),
                  ),
                  SizedBox(width: AppSpacing.xxs),
                  AppIcon(
                    AppIcons.lock,
                    size: 16,
                    color: colors.icon.regular.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: _SidebarMigrationGlow.left,
            top: _SidebarMigrationGlow.top,
            child: _SidebarMigrationGlow(),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 40,
            child: AppSidebarItem(
              key: ValueKey('sidebar_migration_progress_button'),
              label: needsInput ? 'Needs input' : 'Migrating...',
              leading: SizedBox(
                width: _SidebarMigrationGlow.visualWidth,
                height: _SidebarMigrationGlow.visualHeight,
              ),
              leadingGap: AppSpacing.sm,
              inactiveOpacity: 0.64,
              onTap: onMigration,
              trailing: AppIcon(
                needsInput ? AppIcons.warning : AppIcons.loader,
                size: 20,
                color: needsInput ? colors.icon.warning : colors.icon.regular,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 80,
            child: AppSidebarItem(
              key: ValueKey('sidebar_home_button'),
              label: 'Ironwood',
              iconName: AppIcons.home,
              active: active,
              onTap: onHome,
              trailing: Text(
                ironwoodLabel,
                key: ValueKey('sidebar_ironwood_balance'),
                style: AppTypography.labelLarge.copyWith(
                  color: active
                      ? colors.navPanel.activeLabel.withValues(alpha: 0.8)
                      : colors.text.secondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarMigrationGlow extends StatefulWidget {
  const _SidebarMigrationGlow();

  static const visualWidth = 20.0;
  static const visualHeight = 32.0;
  static const left = 14.0;
  static const top = 6.0;
  static const _outerWidth = 24.0;
  static const _outerHeight = 108.0;
  static const _innerWidth = 14.0;
  static const _innerHeight = 92.0;
  static const _radius = 13.0;
  static const _midAlpha = 0.15;
  static const _glowColor = Color(0xFF00A460);
  static const _flowBandHeight = 34.0;
  static const _flowPeriod = Duration(milliseconds: 1800);

  @override
  State<_SidebarMigrationGlow> createState() => _SidebarMigrationGlowState();
}

class _SidebarMigrationGlowState extends State<_SidebarMigrationGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _SidebarMigrationGlow._flowPeriod,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animate = !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    if (animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!animate && _controller.isAnimating) {
      _controller.stop();
    }

    return SizedBox(
      width: _SidebarMigrationGlow._outerWidth,
      height: _SidebarMigrationGlow._outerHeight,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          const _SidebarMigrationGlowPill(
            width: _SidebarMigrationGlow._outerWidth,
            height: _SidebarMigrationGlow._outerHeight,
          ),
          const _SidebarMigrationGlowPill(
            width: _SidebarMigrationGlow._innerWidth,
            height: _SidebarMigrationGlow._innerHeight,
          ),
          if (animate)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return _SidebarMigrationFlowHighlight(t: _controller.value);
              },
            ),
        ],
      ),
    );
  }
}

class _SidebarMigrationFlowHighlight extends StatelessWidget {
  const _SidebarMigrationFlowHighlight({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final bandHeight = _SidebarMigrationGlow._flowBandHeight;
    final travel = _SidebarMigrationGlow._outerHeight + (bandHeight * 2);
    final y = -bandHeight + (travel * t);

    return ClipRRect(
      borderRadius: BorderRadius.circular(_SidebarMigrationGlow._radius),
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x00FFFFFF),
            Color(0xFFFFFFFF),
            Color(0xFFFFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: [0, 0.22, 0.78, 1],
        ).createShader(bounds),
        child: SizedBox(
          width: _SidebarMigrationGlow._outerWidth,
          height: _SidebarMigrationGlow._outerHeight,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                top: y,
                child: const _SidebarMigrationFlowBand(
                  width: _SidebarMigrationGlow._outerWidth,
                  height: _SidebarMigrationGlow._flowBandHeight,
                  alpha: 0.13,
                ),
              ),
              Positioned(
                top: y + 5,
                child: const _SidebarMigrationFlowBand(
                  width: _SidebarMigrationGlow._innerWidth,
                  height: _SidebarMigrationGlow._flowBandHeight,
                  alpha: 0.26,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarMigrationFlowBand extends StatelessWidget {
  const _SidebarMigrationFlowBand({
    required this.width,
    required this.height,
    required this.alpha,
  });

  final double width;
  final double height;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_SidebarMigrationGlow._radius),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _SidebarMigrationGlow._glowColor.withValues(alpha: 0),
              _SidebarMigrationGlow._glowColor.withValues(alpha: alpha),
              _SidebarMigrationGlow._glowColor.withValues(alpha: alpha * 0.72),
              _SidebarMigrationGlow._glowColor.withValues(alpha: 0),
            ],
            stops: const [0, 0.42, 0.62, 1],
          ),
        ),
      ),
    );
  }
}

class _SidebarMigrationGlowPill extends StatelessWidget {
  const _SidebarMigrationGlowPill({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_SidebarMigrationGlow._radius),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _SidebarMigrationGlow._glowColor.withValues(alpha: 0),
              _SidebarMigrationGlow._glowColor.withValues(
                alpha: _SidebarMigrationGlow._midAlpha,
              ),
              _SidebarMigrationGlow._glowColor.withValues(alpha: 0),
            ],
            stops: const [0, 0.5, 1],
          ),
        ),
      ),
    );
  }
}

class _SidebarAccountHeader extends StatelessWidget {
  const _SidebarAccountHeader({
    required this.accountName,
    required this.profilePictureId,
    required this.balanceLabel,
    required this.showsKeystone,
    required this.privacyModeEnabled,
    required this.onTogglePrivacyMode,
    this.onCopyAddress,
    this.onTap,
    super.key,
  });

  final String accountName;
  final String profilePictureId;
  final String balanceLabel;
  final bool showsKeystone;
  final bool privacyModeEnabled;
  final VoidCallback onTogglePrivacyMode;
  final VoidCallback? onCopyAddress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final row = SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxs),
        child: Row(
          children: [
            _SidebarAccountAvatar(
              profilePictureId: profilePictureId,
              showsKeystone: showsKeystone,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          accountName,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      _SidebarCopyAddressButton(onTap: onCopyAddress),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Row(
                    children: [
                      Flexible(
                        fit: FlexFit.loose,
                        child: Text(
                          balanceLabel,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.secondary,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      _SidebarHideBalanceButton(
                        enabled: true,
                        privacyModeEnabled: privacyModeEnabled,
                        onTap: onTogglePrivacyMode,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return onTap == null
        ? row
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: row,
            ),
          );
  }
}

class _SidebarAccountAvatar extends StatelessWidget {
  const _SidebarAccountAvatar({
    required this.profilePictureId,
    required this.showsKeystone,
  });

  final String profilePictureId;
  final bool showsKeystone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AppProfilePicture(
            profilePictureId: profilePictureId,
            size: AppProfilePictureSize.large,
          ),
          if (showsKeystone)
            Positioned(
              right: -5,
              bottom: 0,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: colors.background.inverse,
                  borderRadius: BorderRadius.circular(4),
                  // The ring sits OUTSIDE the 16px badge like the Figma
                  // stroke, leaving the full box to the 14px logo.
                  border: Border.all(
                    color: colors.background.ground,
                    width: 2,
                    strokeAlign: BorderSide.strokeAlignOutside,
                  ),
                ),
                child: Center(
                  child: AppIcon(
                    AppIcons.keystone,
                    size: 14,
                    color: colors.text.inverse,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SidebarHideBalanceButton extends StatelessWidget {
  const _SidebarHideBalanceButton({
    required this.enabled,
    required this.privacyModeEnabled,
    required this.onTap,
  });

  final bool enabled;
  final bool privacyModeEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      enabled: enabled,
      label: privacyModeEnabled ? 'Show balance' : 'Hide balance',
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 16,
            height: 16,
            child: Center(
              child: AppIcon(
                privacyModeEnabled ? AppIcons.eyeClosed : AppIcons.eye,
                size: 16,
                color: colors.icon.regular.withValues(
                  alpha: enabled ? 0.72 : 0.38,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarCopyAddressButton extends StatelessWidget {
  const _SidebarCopyAddressButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null;
    final iconColor = colors.icon.regular.withValues(
      alpha: enabled ? 0.72 : 0.38,
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Copy shielded address',
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 16,
            height: 16,
            child: Center(
              child: AppIcon(AppIcons.copy, size: 16, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarAccountsPopover extends StatefulWidget {
  const _SidebarAccountsPopover({
    required this.accounts,
    required this.activeAccountUuid,
    required this.onSelectAccount,
    required this.onCopyAccountAddress,
    required this.onManageAccounts,
    required this.onAddAccount,
  });

  final List<AccountInfo> accounts;
  final String? activeAccountUuid;
  final ValueChanged<String> onSelectAccount;
  final ValueChanged<AccountInfo> onCopyAccountAddress;
  final VoidCallback onManageAccounts;
  final VoidCallback onAddAccount;

  @override
  State<_SidebarAccountsPopover> createState() =>
      _SidebarAccountsPopoverState();
}

class _SidebarAccountsPopoverState extends State<_SidebarAccountsPopover> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final showScrollbar = widget.accounts.length > 3;
    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 17.5, sigmaY: 17.5),
          child: Container(
            key: const ValueKey('sidebar_accounts_popover'),
            width: 221,
            height: 254,
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: colors.surface.nav,
              borderRadius: BorderRadius.circular(20),
              // Figma's dropdown shadow stack (no stroke): 0/14/28 @ 8%,
              // 0/-6/12 @ 3%, 0/2/8 @ 6%.
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 28,
                  offset: Offset(0, 14),
                ),
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 12,
                  offset: Offset(0, -6),
                ),
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxs),
                  child: Text(
                    'My accounts',
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.muted,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  key: const ValueKey('sidebar_accounts_list'),
                  height: 153,
                  child: RawScrollbar(
                    key: const ValueKey('sidebar_accounts_scrollbar'),
                    controller: _scrollController,
                    thumbVisibility: showScrollbar,
                    radius: const Radius.circular(AppRadii.full),
                    thickness: 6,
                    mainAxisMargin: 6,
                    crossAxisMargin: 6,
                    thumbColor: colors.surface.scrollbarThumb,
                    child: Padding(
                      key: const ValueKey('sidebar_accounts_list_gutter'),
                      padding: const EdgeInsets.only(right: 18),
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(
                          context,
                        ).copyWith(scrollbars: false),
                        child: ListView.separated(
                          controller: _scrollController,
                          physics: const ClampingScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          itemCount: widget.accounts.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.xxs),
                          itemBuilder: (context, index) {
                            final account = widget.accounts[index];
                            return _SidebarAccountPopoverRow(
                              key: ValueKey(
                                'sidebar_account_popover_row_${account.uuid}',
                              ),
                              account: account,
                              selected:
                                  account.uuid == widget.activeAccountUuid,
                              onTap: () => widget.onSelectAccount(account.uuid),
                              onCopyAddress:
                                  account.uuid == widget.activeAccountUuid
                                  ? null
                                  : () => widget.onCopyAccountAddress(account),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                const _SidebarAccountsActionsDivider(),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  height: 36,
                  child: Row(
                    children: [
                      _SidebarPopoverHoverTarget(
                        onTap: widget.onManageAccounts,
                        builder: (context, hovered) => Container(
                          key: const ValueKey('sidebar_accounts_manage'),
                          width: 153,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: hovered
                                ? colors.button.secondary.bgHover
                                : colors.button.secondary.bg,
                            borderRadius: BorderRadius.circular(AppRadii.full),
                          ),
                          child: Text(
                            'Manage',
                            style: AppTypography.labelLarge.copyWith(
                              color: colors.button.secondary.label,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      _SidebarPopoverHoverTarget(
                        onTap: widget.onAddAccount,
                        builder: (context, hovered) => Container(
                          key: const ValueKey('sidebar_accounts_add'),
                          width: 48,
                          height: 32,
                          decoration: BoxDecoration(
                            color: hovered
                                ? colors.button.primary.bgHover
                                : colors.button.primary.bg,
                            borderRadius: BorderRadius.circular(AppRadii.full),
                            border: Border.all(
                              color: colors.border.subtleOpacity,
                              strokeAlign: BorderSide.strokeAlignInside,
                            ),
                          ),
                          child: Center(
                            child: AppIcon(
                              AppIcons.addNew,
                              size: 16,
                              color: colors.button.primary.label,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarAccountsActionsDivider extends StatelessWidget {
  const _SidebarAccountsActionsDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('sidebar_accounts_actions_divider'),
      height: 1,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(color: context.colors.border.subtle),
      ),
    );
  }
}

class _SidebarAccountPopoverRow extends StatelessWidget {
  const _SidebarAccountPopoverRow({
    super.key,
    required this.account,
    required this.selected,
    required this.onTap,
    this.onCopyAddress,
  });

  final AccountInfo account;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onCopyAddress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppTappable(
      onTap: onTap,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: selected ? colors.state.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxs),
          child: Row(
            children: [
              _SidebarAccountAvatar(
                profilePictureId: account.profilePictureId,
                showsKeystone: account.isHardware,
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Text(
                  account.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              if (onCopyAddress != null)
                _SidebarCopyAddressButton(onTap: onCopyAddress)
              else if (selected)
                AppIcon(AppIcons.check, size: 16, color: colors.icon.regular),
            ],
          ),
        ),
      ),
    );
  }
}

/// Click target that also tracks hover, for the popover's pill buttons.
class _SidebarPopoverHoverTarget extends StatefulWidget {
  const _SidebarPopoverHoverTarget({
    required this.onTap,
    required this.builder,
  });

  final VoidCallback onTap;
  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<_SidebarPopoverHoverTarget> createState() =>
      _SidebarPopoverHoverTargetState();
}

class _SidebarPopoverHoverTargetState
    extends State<_SidebarPopoverHoverTarget> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: widget.builder(context, _hovered),
        ),
      ),
    );
  }
}
