// Development-only fixture. No wallet bootstrap, storage, Rust, or network.
import 'package:flutter/material.dart';

import 'src/core/theme/app_theme.dart';
import 'src/features/zns/presentation/zns_screen.dart';

void main() => runApp(const ZnsPreviewApp());

abstract final class ZnsPreviewFixtures {
  static const address =
      'u1previewonly000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000';
  static const owned = ZnsOwnedNameView(
    positionId: '7',
    name: 'river',
    unifiedAddress: address,
    maturityAt: '8 September 2027',
    refreshDueAt: '8 September 2027',
    graceEndsAt: '7 December 2027',
    deposit: '0.1',
    accruedRewards: '0.0034',
    claimableRewards: '0',
  );
  static const active = ZnsViewData(
    accountId: 'preview',
    accountName: 'Development fixture',
    isConfigured: true,
    walletUnifiedAddress: address,
    baseOwnerAddress: '0x1111111111111111111111111111111111111111',
    cbZecBalance: '0.012',
    ethBalance: '0.00014',
    claimablePrincipal: '0.1',
    claimableRewards: '0.002',
    canWithdrawClaims: true,
    ownedName: owned,
    names: [ZnsNameChoice('7', 'river'), ZnsNameChoice('9', 'zooko')],
    baseRecoveryDescription:
        'Development fixture only. No real wallet or funds are connected.',
  );
  static const transfer = ZnsViewData(
    accountId: 'preview',
    isConfigured: true,
    review: ZnsReviewView(
      name: 'river',
      unifiedAddress: '',
      deposit: '0.1',
      maxZec: '0',
      gasReserve: '0.00001',
      estimatedDuration: 'A few seconds',
      kind: ZnsReviewKind.transfer,
      positionId: '7',
      recipient: '0x3333333333333333333333333333333333333333',
      rewardsToClaim: '0.00340000000000000000000000000001',
      maturityAt: '8 September 2027',
      refreshDueAt: '8 September 2027',
      canConfirm: true,
    ),
  );
  static const received = ZnsViewData(
    accountId: 'preview',
    isConfigured: true,
    walletUnifiedAddress: address,
    names: [ZnsNameChoice('9', 'zooko')],
    ownedName: ZnsOwnedNameView(
      positionId: '9',
      name: 'zooko',
      unifiedAddress: '',
      maturityAt: '8 September 2027',
      refreshDueAt: '8 September 2027',
      graceEndsAt: '7 December 2027',
      deposit: '0.1',
      accruedRewards: '0',
      claimableRewards: '0',
    ),
  );
  static const registration = ZnsViewData(
    accountId: 'preview',
    isConfigured: true,
    walletUnifiedAddress: address,
    review: ZnsReviewView(
      name: 'river',
      unifiedAddress: address,
      deposit: '0.1',
      maxZec: '0.12',
      gasReserve: '0.0001',
      maxBaseEth: '0.005',
      existingCbZecSpend: '0.012',
      existingEthSpend: '0.00004',
      estimatedDuration: 'About 8 minutes',
      canConfirm: false,
      blockedReason: 'Development fixture — signing is disabled.',
    ),
  );
  static const earlyRelease = ZnsViewData(
    accountId: 'preview',
    isConfigured: true,
    review: ZnsReviewView(
      name: 'river',
      unifiedAddress: address,
      deposit: '0.1',
      maxZec: '0',
      gasReserve: '0.00001',
      maxBaseEth: '0.00001',
      estimatedDuration: 'A few seconds',
      kind: ZnsReviewKind.release,
      maturityAt: '8 September 2027',
      exitPreview: ZnsExitPreview(
        early: true,
        principalReturned: '0',
        rewardsReturned: '0',
        principalForfeited: '0.1',
        rewardsForfeited: '0.0034',
      ),
    ),
  );
  static const paused = ZnsViewData(
    accountId: 'preview',
    isConfigured: true,
    operation: ZnsOperationView(
      name: 'river',
      title: 'Ready when you are',
      description:
          'Funding arrived. Resume to continue within your approved limit.',
      isPaused: true,
      canResume: true,
      recoveryMessage:
          'Your commitment and progress are saved. No new transactions are signed while paused.',
      steps: [
        ZnsProgressStep(
          title: 'Fund your Base account',
          status: ZnsStepStatus.complete,
        ),
        ZnsProgressStep(
          title: 'Commit your name',
          status: ZnsStepStatus.paused,
        ),
        ZnsProgressStep(
          title: 'Wait for commitment',
          status: ZnsStepStatus.upcoming,
        ),
        ZnsProgressStep(
          title: 'Deposit cbZEC and register',
          status: ZnsStepStatus.upcoming,
        ),
      ],
    ),
  );
}

class ZnsPreviewApp extends StatefulWidget {
  const ZnsPreviewApp({super.key});
  @override
  State<ZnsPreviewApp> createState() => _ZnsPreviewAppState();
}

class _ZnsPreviewAppState extends State<ZnsPreviewApp> {
  int scenario = 0;
  final fixtures = const [
    ZnsPreviewFixtures.active,
    ZnsPreviewFixtures.registration,
    ZnsPreviewFixtures.earlyRelease,
    ZnsPreviewFixtures.paused,
    ZnsViewData(),
  ];
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    builder: (context, child) =>
        AppTheme(data: AppThemeData.dark, child: child!),
    home: Scaffold(
      backgroundColor: AppThemeData.dark.colors.background.ground,
      appBar: AppBar(
        title: const Text('ZNS development preview · no wallet connected'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: DropdownButton<int>(
              value: scenario,
              isExpanded: true,
              items:
                  const [
                        'Active name',
                        'Registration review',
                        'Early exit review',
                        'Paused registration',
                        'Not configured',
                      ].indexed
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.$1,
                          child: Text(entry.$2),
                        ),
                      )
                      .toList(),
              onChanged: (value) => setState(() => scenario = value ?? 0),
            ),
          ),
          Expanded(
            child: ZnsScreen(
              key: ValueKey(scenario),
              data: fixtures[scenario],
              callbacks: const ZnsCallbacks(),
            ),
          ),
        ],
      ),
    ),
  );
}
