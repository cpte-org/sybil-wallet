import 'package:flutter/foundation.dart';
import '../data/zns_build_defaults.dart';

/// Presentation-only values. The wallet adapter owns validation, authorization,
/// durable state, and all amounts; strings here are already formatted for display.
@immutable
class ZnsViewData {
  const ZnsViewData({
    this.accountId = '',
    this.accountName = 'Your account',
    this.isConfigured = false,
    this.isSoftwareAccount = true,
    this.isLocked = false,
    this.isBusy = false,
    this.walletUnifiedAddress = '',
    this.baseOwnerAddress = '',
    this.baseRecoveryDescription = '',
    this.ethBalance = '—',
    this.cbZecBalance = '—',
    this.claimablePrincipal = '—',
    this.claimableRewards = '—',
    this.canWithdrawClaims = false,
    this.configuration = const ZnsConfigurationInput(),
    this.lookup,
    this.review,
    this.operation,
    this.ownedName,
    this.names = const [],
    this.inventoryOffset = 0,
    this.hasMoreNames = false,
    this.error,
    this.notice,
    this.onDismissError,
    this.onDismissNotice,
  });

  final String accountId;
  final String accountName;
  final bool isConfigured;
  final bool isSoftwareAccount;
  final bool isLocked;
  final bool isBusy;
  final String walletUnifiedAddress;
  final String baseOwnerAddress;
  final String baseRecoveryDescription;
  final String ethBalance;
  final String cbZecBalance;
  final String claimablePrincipal;
  final String claimableRewards;
  final bool canWithdrawClaims;
  final ZnsConfigurationInput configuration;
  final ZnsLookupView? lookup;
  final ZnsReviewView? review;
  final ZnsOperationView? operation;
  final ZnsOwnedNameView? ownedName;
  final List<ZnsNameChoice> names;
  final int inventoryOffset;
  final bool hasMoreNames;
  final String? error;
  final String? notice;

  /// Clears the banner in [error] / [notice] until the next occurrence.
  final VoidCallback? onDismissError;
  final VoidCallback? onDismissNotice;

  bool get canWrite =>
      isConfigured && isSoftwareAccount && !isLocked && !isBusy;
}

@immutable
class ZnsNameChoice {
  const ZnsNameChoice(this.positionId, this.name, {this.expired = false});
  final String positionId, name;
  final bool expired;
}

enum ZnsLookupStatus { available, registered, unavailable, loading, failed }

@immutable
class ZnsLookupView {
  const ZnsLookupView({
    required this.name,
    required this.status,
    this.unifiedAddress = '',
    this.message,
    this.expiresAt,
  });
  final String name;
  final ZnsLookupStatus status;
  final String unifiedAddress;
  final String? message;
  final String? expiresAt;
}

@immutable
class ZnsRegistrationInput {
  const ZnsRegistrationInput({required this.name, this.extraDeposit = '0'});
  final String name, extraDeposit;
}

@immutable
class ZnsReviewView {
  const ZnsReviewView({
    required this.name,
    required this.unifiedAddress,
    required this.maxZec,
    required this.deposit,
    required this.gasReserve,
    required this.estimatedDuration,
    this.kind = ZnsReviewKind.registration,
    this.maxBaseEth,
    this.minimumDeposit,
    this.extraDeposit,
    this.usdTarget,
    this.pricingMode,
    this.minimumFloorApplies = false,
    this.existingCbZecSpend,
    this.existingEthSpend,
    this.quoteExpiresIn,
    this.estimatedZec,
    this.conversionRate,
    this.zcashFee,
    this.canConfirm = false,
    this.blockedReason,
    this.maturityAt,
    this.refreshDueAt,
    this.exitPreview,
    this.rewardsToClaim,
    this.positionId,
    this.recipient,
  });
  final String name;
  final String unifiedAddress;
  final String maxZec;
  final String deposit;
  final String gasReserve;
  final String estimatedDuration;
  final ZnsReviewKind kind;

  /// Maximum ETH spent on Base, including gas and any cbZEC purchase.
  final String? maxBaseEth;
  final String? minimumDeposit, extraDeposit, usdTarget;
  final int? pricingMode;
  final bool minimumFloorApplies;
  final String? existingCbZecSpend;
  final String? existingEthSpend;
  final String? quoteExpiresIn;
  final String? estimatedZec, conversionRate, zcashFee;
  final bool canConfirm;
  final String? blockedReason;
  final String? maturityAt;
  final String? refreshDueAt;
  final ZnsExitPreview? exitPreview;
  final String? rewardsToClaim;
  final String? positionId;
  final String? recipient;
}

enum ZnsReviewKind {
  registration,
  refresh,
  claimRewards,
  addressUpdate,
  transfer,
  release,
  withdrawClaims,
}

@immutable
class ZnsExitPreview {
  const ZnsExitPreview({
    required this.early,
    required this.principalReturned,
    required this.rewardsReturned,
    required this.principalForfeited,
    required this.rewardsForfeited,
  });
  final bool early;
  final String principalReturned;
  final String rewardsReturned;
  final String principalForfeited;

  /// Display formatting must preserve any fractional reward credit.
  final String rewardsForfeited;
}

enum ZnsStepStatus { upcoming, active, complete, paused, failed }

@immutable
class ZnsProgressStep {
  const ZnsProgressStep({
    required this.title,
    required this.status,
    this.detail,
  });
  final String title;
  final ZnsStepStatus status;
  final String? detail;
}

@immutable
class ZnsOperationView {
  const ZnsOperationView({
    required this.name,
    required this.title,
    required this.description,
    required this.steps,
    this.isPaused = false,
    this.isFailed = false,
    this.isComplete = false,
    this.canPause = false,
    this.canResume = false,
    this.remainingWait,
    this.recoveryMessage,
    this.transactionId,
  });
  final String name;
  final String title;
  final String description;
  final List<ZnsProgressStep> steps;
  final bool isPaused;
  final bool isFailed;
  final bool isComplete;
  final bool canPause;
  final bool canResume;
  final String? remainingWait;
  final String? recoveryMessage;
  final String? transactionId;
}

@immutable
class ZnsOwnedNameView {
  const ZnsOwnedNameView({
    required this.name,
    required this.unifiedAddress,
    required this.positionId,
    required this.maturityAt,
    required this.refreshDueAt,
    required this.graceEndsAt,
    required this.deposit,
    required this.accruedRewards,
    required this.claimableRewards,
    this.isMature = false,
    this.isInGrace = false,
    this.canClaimRewards = false,
    this.isExpired = false,
  });
  final String name;
  final String unifiedAddress;
  final String positionId;
  final String maturityAt;
  final String refreshDueAt;
  final String graceEndsAt;
  final String deposit;
  final String accruedRewards;
  final String claimableRewards;
  final bool isMature;
  final bool isInGrace;
  final bool canClaimRewards;
  final bool isExpired;
}

@immutable
class ZnsConfigurationInput {
  const ZnsConfigurationInput({
    this.rpcUrl = znsDefaultRpc,
    this.registryAddress = znsDefaultRegistry,
    this.chainId = znsDefaultChainId,
    this.tokenAddress = znsDefaultToken,
    this.delegateAddress = znsDefaultDelegate,
  });
  final String rpcUrl;
  final String registryAddress;
  final int chainId;
  final String tokenAddress;
  final String delegateAddress;
}

/// Callbacks request wallet actions. Rendering never signs or submits anything.
@immutable
class ZnsCallbacks {
  const ZnsCallbacks({
    this.onLookup,
    this.onPrepareRegistration,
    this.onConfirmRegistration,
    this.onCancelReview,
    this.onPause,
    this.onResume,
    this.onRefresh,
    this.onRefreshName,
    this.onClaimRewards,
    this.onRelease,
    this.onTransfer,
    this.onSelectName,
    this.onNamesPage,
    this.onWithdrawClaims,
    this.onUpdateAddress,
    this.onSaveConfiguration,
    this.onShowRecovery,
    this.onSendToName,
    this.onDismissError,
    this.onDismissNotice,
  });
  final ValueChanged<String>? onLookup;
  final ValueChanged<ZnsRegistrationInput>? onPrepareRegistration;
  final VoidCallback? onConfirmRegistration;
  final VoidCallback? onCancelReview;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  /// Completes when the refresh settles, so callers can await it
  /// (pull-to-refresh) or fire it (buttons).
  final Future<void> Function()? onRefresh;

  /// Management callbacks open a bounded review, never authorize signing.
  final VoidCallback? onRefreshName;
  final VoidCallback? onClaimRewards;
  final VoidCallback? onRelease;
  final ValueChanged<String>? onTransfer;
  final ValueChanged<String>? onSelectName;
  final ValueChanged<int>? onNamesPage;
  final VoidCallback? onWithdrawClaims;

  /// Opens the adapter's address / gas review; this is not an authorization.
  final ValueChanged<String>? onUpdateAddress;
  final ValueChanged<ZnsConfigurationInput>? onSaveConfiguration;
  final VoidCallback? onShowRecovery;

  /// Requests the host's normal send flow after it validates the lookup.
  final ValueChanged<ZnsLookupView>? onSendToName;
  final VoidCallback? onDismissError;
  final VoidCallback? onDismissNotice;
}
