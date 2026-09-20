import 'dart:async';
import '../domain/zns_operation.dart';
import '../data/zns_transaction_preflight.dart';
import 'zns_journal.dart';

/// A funding failure proven to have happened before any signing or broadcast.
/// Ambiguous provider or network errors must never use this classification.
class ZnsFundingNotSent implements Exception {
  const ZnsFundingNotSent(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Aging may improve an exit while the user reviews it. Only admit changes
/// that preserve the reviewed maturity status and do not worsen any amount.
bool znsExitWithinReview(
  Map<String, dynamic>? reviewed,
  Map<String, dynamic> current,
) {
  if (reviewed == null || reviewed['early'] != current['early']) return false;
  for (final key in const [
    'principalReturned',
    'rewardsReturned',
    'principalForfeited',
    'rewardsForfeitedScaled',
  ]) {
    final before = BigInt.tryParse('${reviewed[key]}');
    final after = BigInt.tryParse('${current[key]}');
    if (before == null ||
        after == null ||
        before.isNegative ||
        after.isNegative) {
      return false;
    }
    if (key == 'principalReturned' || key == 'rewardsReturned') {
      if (after < before) return false;
    } else if (after > before) {
      return false;
    }
  }
  return true;
}

void znsCheckRegistrationQuote(ZnsOperation op, ZnsRegistrationQuote quote) {
  if (op.registrationQuote == null ||
      quote.pricingMode != op.registrationQuote!.pricingMode ||
      quote.minimumDeposit + op.extraDeposit > op.requiredTokenUnits) {
    throw StateError(
      'Registration pricing changed. Review the updated bond and pricing mode before continuing.',
    );
  }
}

class ZnsRecord {
  const ZnsRecord({
    required this.name,
    required this.owner,
    required this.unifiedAddress,
    required this.expiresAt,
    required this.deposit,
    required this.positionId,
    required this.maturityAt,
    required this.refreshDueAt,
    required this.participating,
    required this.retired,
    required this.rewardCreditScaled,
  });
  final String name, owner, unifiedAddress;
  final int expiresAt, maturityAt, refreshDueAt;
  final BigInt deposit, positionId, rewardCreditScaled;
  final bool participating, retired;
}

class ZnsChainView {
  const ZnsChainView({
    required this.timestamp,
    required this.deposit,
    required this.eth,
    required this.token,
    required this.allowance,
    required this.claimablePrincipal,
    required this.claimableRewardsScaled,
    required this.minAge,
    required this.maxAge,
    required this.commitAt,
    this.position,
  });
  final int timestamp, minAge, maxAge, commitAt;
  final BigInt deposit,
      eth,
      token,
      allowance,
      claimablePrincipal,
      claimableRewardsScaled;
  final ZnsRecord? position;
  ZnsRecord? get owned => position?.participating == true ? position : null;
}

abstract interface class ZnsEngineGateway {
  Future<ZnsChainView> snapshot(
    String? commitment, {
    BigInt? positionId,
    String? registrationName,
  });
  Future<ZnsRecord?> lookup(String name);
  Future<ZnsRegistrationQuote> quoteRegistration(String name);
  Future<Map<String, dynamic>> exitPreview(BigInt positionId);
  Future<Map<String, dynamic>> swapQuote(BigInt neededToken, BigInt? maxWei);
  Future<Map<String, dynamic>> fundingQuote(
    BigInt requiredWei, {
    required bool dry,
  });
  Future<String?> sendFunding(
    Map<String, dynamic> quote, {
    required void Function() ensureAuthorized,
  });
  Future<Map<String, dynamic>> fundingStatus(Map<String, dynamic> quote);
  Future<Map<String, dynamic>> sign(
    ZnsOperation intent,
    Map<String, dynamic> operation, {
    required void Function() ensureAuthorized,
  });
  Future<void> broadcast(String rawTransaction, String expectedHash);
  Future<Map<String, dynamic>?> receipt(String hash);
  Future<BigInt> gasBudget(String kind);
  Future<String> secret();
  Future<String> commitment(String name, String ua, String secret);
  bool get supportsAtomic;
}

/// A sequential durable coordinator: one user approval may authorize several
/// signatures, but it never survives a wallet lock/restart or account change.
class ZnsEngine {
  ZnsEngine({
    required this.accountUuid,
    required this.scope,
    required this.gateway,
    required this.journal,
    required this.canSign,
    required this.onChange,
  });
  final String accountUuid;
  final ZnsScope scope;
  final ZnsEngineGateway gateway;
  final ZnsJournal journal;
  final bool Function() canSign;
  final void Function() onChange;
  ZnsOperation? operation;
  ZnsChainView? chain;
  bool authorized = false;
  bool busy = false;
  bool _disposed = false;
  String? error;
  String? progressMessage;
  Timer? _timer;

  Future<void> load() async {
    operation = await journal.load(scope);
    // Never infer permission from persisted progress.
    authorized = false;
    await refresh();
  }

  void pause() {
    authorized = false;
    _timer?.cancel();
    onChange();
  }

  void dispose() {
    _disposed = true;
    pause();
  }

  void _guard() {
    if (_disposed || !authorized || !canSign()) {
      authorized = false;
      throw StateError(
        'Names operation paused. Unlock this account and review to continue.',
      );
    }
  }

  Future<void> _save() => journal.save(operation!, accountUuid);

  Future<void> refresh() async {
    final op = operation;
    chain = await gateway.snapshot(
      op?.commitment,
      positionId:
          op != null && !['register', 'withdrawClaims'].contains(op.kind)
          ? op.positionId
          : null,
      registrationName: op?.kind == 'register' ? op!.name : null,
    );
    onChange();
  }

  Future<void> archive() async {
    pause();
    if (busy) {
      throw StateError(
        'Wait for the current operation to finish before archiving.',
      );
    }
    final op = operation;
    if (op == null) return;
    if (op.pending != null) {
      final receipt = await gateway.receipt(op.pending!['hash'] as String);
      if (receipt == null || receipt['confirmed'] != true) {
        throw StateError(
          'This signed transaction may still confirm. Reconcile it before archiving.',
        );
      }
      op.transactions = [
        ...op.transactions,
        {...op.pending!, ...receipt},
      ];
      op.pending = null;
      await _save();
    }
    if (op.funding?['attempted'] == true) {
      final funding = await gateway.fundingStatus(op.funding!);
      if (funding['complete'] != true && funding['failed'] != true) {
        throw StateError(
          'Funding is still pending. Resolve it before archiving.',
        );
      }
    }
    await journal.archive(op);
    operation = null;
    error = null;
    onChange();
  }

  Future<ZnsOperation> prepare({
    required String name,
    required String ua,
    BigInt? maxZatoshi,
    String kind = 'register',
    String recipient = '',
    BigInt? extraDeposit,
    ZnsOperation? continuation,
  }) async {
    if (busy) throw StateError('An operation is already being prepared.');
    if (operation != null &&
        !operation!.isComplete &&
        !identical(continuation, operation)) {
      throw StateError('Resume the saved operation before starting another.');
    }
    if (![
      'register',
      'refresh',
      'claimRewards',
      'update',
      'release',
      'withdrawClaims',
      'transfer',
    ].contains(kind)) {
      throw const FormatException('Unsupported Names operation.');
    }
    if (continuation != null &&
        (continuation.kind != 'register' ||
            kind != 'register' ||
            continuation.name != name ||
            continuation.unifiedAddress != ua ||
            continuation.pending != null ||
            continuation.isComplete)) {
      throw StateError(
        'Only the unchanged pending registration can be repriced.',
      );
    }
    if (kind != 'withdrawClaims') znsValidateLabel(name);
    if (maxZatoshi?.isNegative == true) {
      throw const FormatException('Invalid funding budget.');
    }
    if (operation?.isComplete == true) await archive();
    await refresh();
    final state = chain!;
    if (kind == 'register') {
      final record = await gateway.lookup(name);
      if (record?.participating == true) {
        throw StateError('This name is already registered.');
      }
    } else if (kind == 'withdrawClaims') {
      if (state.claimablePrincipal == BigInt.zero &&
          state.claimableRewardsScaled < znsRewardScale) {
        throw StateError(
          'There are no old refunds or rewards available to withdraw.',
        );
      }
    } else {
      final position = state.position;
      if (position == null ||
          position.retired ||
          position.name != name ||
          position.owner.toLowerCase() != scope.owner.toLowerCase()) {
        throw StateError(
          'This registration is no longer controlled by this account.',
        );
      }
      if (kind != 'release' && !position.participating) {
        throw StateError(
          'The grace period ended. Withdraw the old deposit and rewards instead.',
        );
      }
      if (kind == 'claimRewards' && state.timestamp < position.maturityAt) {
        throw StateError(
          'Rewards become available after the initial holding period.',
        );
      }
    }
    if (kind == 'transfer' &&
        (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(recipient) ||
            BigInt.parse(recipient.substring(2), radix: 16) == BigInt.zero ||
            recipient.toLowerCase() == scope.owner.toLowerCase() ||
            recipient.toLowerCase() == scope.registry.toLowerCase())) {
      throw const FormatException(
        'Enter a different valid Base recipient address.',
      );
    }
    final extra = extraDeposit ?? BigInt.zero;
    if (extra.isNegative ||
        extra.bitLength > 256 ||
        (kind != 'register' && extra != BigInt.zero)) {
      throw const FormatException(
        'Extra bond is only available at registration.',
      );
    }
    final quote = kind == 'register'
        ? await gateway.quoteRegistration(name)
        : null;
    final amount = quote == null ? BigInt.zero : quote.minimumDeposit + extra;
    if (amount.bitLength > 256) {
      throw const FormatException('Registration bond overflow.');
    }
    final reserve = await gateway.gasBudget(kind);
    final priorGas =
        continuation?.transactions.fold(
          BigInt.zero,
          (sum, tx) => sum + BigInt.parse(tx['feeCeiling'] as String? ?? '0'),
        ) ??
        BigInt.zero;
    final priorValue =
        continuation?.transactions
            .where((tx) => tx['success'] == true)
            .fold(
              BigInt.zero,
              (sum, tx) => sum + BigInt.parse(tx['value'] as String? ?? '0'),
            ) ??
        BigInt.zero;
    final shortfall = amount > state.token ? amount - state.token : BigInt.zero;
    final swap = shortfall > BigInt.zero
        ? await gateway.swapQuote(shortfall, null)
        : null;
    final swapWei = swap == null
        ? BigInt.zero
        : BigInt.parse(swap['value'] as String);
    // A bounded 5% movement margin is shown in the review; fresh quotes cannot
    // silently expand this budget later.
    final maxEth = swapWei * BigInt.from(105) ~/ BigInt.from(100) + reserve;
    final neededEth = maxEth > state.eth ? maxEth - state.eth : BigInt.zero;
    var approvedZatoshi = maxZatoshi ?? BigInt.zero;
    BigInt? estimatedZatoshi, rateZatoshi, zcashFeeZatoshi;
    if (neededEth > BigInt.zero) {
      final funding = await gateway.fundingQuote(neededEth, dry: true);
      final zec = BigInt.parse(funding['maxZatoshi'] as String);
      estimatedZatoshi = zec;
      zcashFeeZatoshi = BigInt.tryParse('${funding['zecFee']}');
      // Indicative combined route rate; excludes Zcash miner fees and the
      // separately budgeted Base gas, but includes quoted conversion costs.
      final plan = funding['plan'];
      if (shortfall > BigInt.zero &&
          plan is Map &&
          plan['depositZatoshi'] is String) {
        final deposit = BigInt.parse(plan['depositZatoshi'] as String);
        rateZatoshi =
            deposit *
            swapWei *
            BigInt.from(100000000) ~/
            (neededEth * shortfall);
      }
      if (maxZatoshi == null) {
        approvedZatoshi =
            (zec * BigInt.from(105) + BigInt.from(99)) ~/ BigInt.from(100);
      } else if (zec > maxZatoshi) {
        throw StateError(
          'Funding needs up to ${znsFormatAmount(zec, 8)} ZEC including its network fee. Increase the reviewed budget.',
        );
      }
    }
    final salt = continuation?.secret ?? await gateway.secret();
    final commitment = kind == 'register'
        ? continuation?.commitment ?? await gateway.commitment(name, ua, salt)
        : '0x${List.filled(64, '0').join()}';
    final positionId = ['register', 'withdrawClaims'].contains(kind)
        ? BigInt.zero
        : state.position!.positionId;
    final preview = kind == 'release'
        ? await gateway.exitPreview(positionId)
        : null;
    return ZnsOperation(
      recipient: recipient.toLowerCase(),
      scope: scope,
      name: name,
      unifiedAddress: ua,
      positionId: positionId,
      secret: salt,
      commitment: commitment,
      kind: kind,
      maxZatoshi:
          continuation != null && continuation.maxZatoshi > approvedZatoshi
          ? continuation.maxZatoshi
          : approvedZatoshi,
      estimatedZatoshi: estimatedZatoshi,
      rateZatoshi: rateZatoshi,
      zcashFeeZatoshi: zcashFeeZatoshi,
      maxEthWei:
          continuation != null &&
              continuation.maxEthWei > maxEth + priorGas + priorValue
          ? continuation.maxEthWei
          : maxEth + priorGas + priorValue,
      requiredTokenUnits: amount,
      registrationQuote: quote,
      extraDeposit: extra,
      maxGasFeeWei:
          continuation != null && continuation.maxGasFeeWei > reserve + priorGas
          ? continuation.maxGasFeeWei
          : reserve + priorGas,
      createdAt: continuation?.createdAt ?? DateTime.now().toUtc(),
      phase: continuation?.phase ?? 'ready',
      pending: continuation?.pending,
      funding: continuation?.funding?['notRequired'] == true
          ? null
          : continuation?.funding,
      transactions: continuation?.transactions ?? const [],
      baselineExpiry: state.position?.expiresAt ?? 0,
      maturityAt: kind == 'register'
          ? state.timestamp + znsHoldingSeconds
          : state.position?.maturityAt ?? 0,
      exitPreview: preview,
    );
  }

  Future<void> authorize(ZnsOperation reviewed) async {
    if (!canSign()) {
      throw StateError('Unlock the software account to continue.');
    }
    if (reviewed.scope.key != scope.key) {
      throw StateError('Account changed. Review again.');
    }
    if (operation != null &&
        !operation!.isComplete &&
        reviewed.secret != operation!.secret) {
      throw StateError('Another registration is already pending.');
    }
    if (reviewed.kind == 'register' &&
        reviewed.pending == null &&
        !reviewed.transactions.any(
          (tx) =>
              tx['success'] == true &&
              ['register', 'atomicRegister'].contains(tx['kind']),
        )) {
      znsCheckRegistrationQuote(
        reviewed,
        await gateway.quoteRegistration(reviewed.name),
      );
    }
    reviewed.message = null;
    operation = reviewed;
    await _save(); // Durable secret and spend limits precede all external actions.
    authorized = true;
    error = null;
    await advance();
  }

  bool _matchesCompleted(ZnsOperation op, ZnsChainView state) {
    final owned = state.owned;
    if (op.kind == 'withdrawClaims') {
      return state.claimablePrincipal == BigInt.zero &&
          state.claimableRewardsScaled < znsRewardScale;
    }
    if (op.kind == 'transfer') {
      return state.position?.positionId == op.positionId &&
          state.position?.owner.toLowerCase() == op.recipient.toLowerCase();
    }
    if (op.kind == 'release') {
      return state.position?.positionId != op.positionId ||
          state.position?.retired == true;
    }
    if (owned == null ||
        owned.owner.toLowerCase() != scope.owner.toLowerCase() ||
        owned.name != op.name) {
      return false;
    }
    if (op.kind == 'register' &&
        (owned.deposit <= op.extraDeposit ||
            owned.deposit > op.requiredTokenUnits)) {
      return false;
    }
    if (op.kind != 'register' && owned.positionId != op.positionId) {
      return false;
    }
    if (['refresh', 'claimRewards'].contains(op.kind)) {
      return owned.expiresAt >= op.baselineExpiry;
    }
    return owned.unifiedAddress == op.unifiedAddress &&
        owned.expiresAt > state.timestamp;
  }

  Future<bool> _settlePending(ZnsOperation op) async {
    final pending = op.pending;
    if (pending == null) return true;
    final hash = pending['hash'] as String;
    final receipt = await gateway.receipt(hash);
    if (receipt == null) {
      // Re-submit only the identical signed bytes. An uncertain send never
      // creates a new nonce, quote, signature or payment.
      _guard();
      if (pending['raw'] is String) {
        await gateway.broadcast(pending['raw'] as String, hash);
      }
      return false;
    }
    if (receipt['confirmed'] != true) return false;
    _checkReceiptIntent(op, receipt);
    op.transactions = [
      ...op.transactions,
      {...pending, ...receipt},
    ];
    op.pending = null;
    await _save();
    if (receipt['success'] != true) {
      throw StateError(
        'The Base transaction reverted. Network fees were spent, but its swap and name changes were rolled back. Review before retrying.',
      );
    }
    return true;
  }

  Future<void> _send(
    ZnsOperation op,
    Map<String, dynamic> intent, {
    Future<Map<String, dynamic>> Function()? refreshSwap,
  }) async {
    _guard();
    if (intent['kind'] == 'release' &&
        !znsExitWithinReview(
          op.exitPreview,
          await gateway.exitPreview(op.positionId),
        )) {
      throw StateError(
        'The release refund or forfeiture changed. Review the updated release amounts before continuing.',
      );
    }
    _guard();
    op.phase = intent['kind'] as String;
    progressMessage = 'Checking transaction before signing…';
    onChange();
    Map<String, dynamic> signed;
    try {
      signed = await gateway.sign(op, intent, ensureAuthorized: _guard);
    } on ZnsUnsignedSwapRejected {
      if (refreshSwap == null ||
          intent['kind'] != 'atomicRegister' ||
          intent['swap'] == null) {
        rethrow;
      }
      _guard();
      progressMessage = 'Refreshing the swap route…';
      onChange();
      final fresh = await refreshSwap();
      _guard();
      progressMessage = 'Checking the refreshed route…';
      onChange();
      // Exactly one unsigned retry. Journal writes and broadcasts are outside
      // this catch, so even a misclassified broadcast error cannot re-sign.
      signed = await gateway.sign(op, {
        ...intent,
        'swap': fresh,
      }, ensureAuthorized: _guard);
    }
    _guard();
    op.pending = {...signed, 'kind': intent['kind']};
    op.phase = intent['kind'] as String;
    await _save();
    _guard();
    await gateway.broadcast(signed['raw'] as String, signed['hash'] as String);
  }

  void _checkReceiptIntent(ZnsOperation op, Map<String, dynamic> receipt) {
    // Production gateways reconstruct this metadata from canonical transaction
    // calldata. A recovered journal cannot redefine what a past signature did.
    if (receipt['verifiedIntent'] != true) return;
    final kind = receipt['kind'];
    if (op.kind == 'register') {
      if (![
            'commit',
            'approve',
            'swap',
            'register',
            'atomicRegister',
          ].contains(kind) ||
          (kind == 'commit' && receipt['commitment'] != op.commitment) ||
          (['register', 'atomicRegister'].contains(kind) &&
              (receipt['name'] != op.name ||
                  receipt['unifiedAddress'] != op.unifiedAddress ||
                  receipt['secret'] != op.secret ||
                  (receipt['success'] == true &&
                      (receipt['maxDeposit'] !=
                              op.requiredTokenUnits.toString() ||
                          receipt['extraDeposit'] !=
                              op.extraDeposit.toString() ||
                          receipt['expectedPricingMode'] !=
                              op.registrationQuote?.pricingMode))))) {
        throw StateError(
          'A recovered transaction does not match this registration intent. Recovery was retained.',
        );
      }
    } else if (kind != op.kind ||
        (kind != 'withdrawClaims' &&
            receipt['positionId'] != op.positionId.toString()) ||
        (kind == 'transfer' && receipt['recipient'] != op.recipient) ||
        (kind == 'update' && receipt['unifiedAddress'] != op.unifiedAddress)) {
      throw StateError(
        'A recovered transaction targets a different name operation. Recovery was retained.',
      );
    }
  }

  Future<void> advance() async {
    if (busy || _disposed || operation == null || !authorized) return;
    busy = true;
    progressMessage = 'Checking saved progress…';
    onChange();
    try {
      _guard();
      final op = operation!;
      if (!await _settlePending(op)) return;
      // Check prior receipts again before a new state-changing step. A reorg
      // pauses the operation while keeping exact signed bytes and the secret.
      for (final tx in op.transactions) {
        final current = await gateway.receipt(tx['hash'] as String);
        if (current == null ||
            current['confirmed'] != true ||
            current['blockHash'] != tx['blockHash']) {
          throw StateError(
            'A previous transaction changed after a chain reorganization. Saved recovery data was retained; refresh before continuing.',
          );
        }
        _checkReceiptIntent(op, current);
        final correctedFailure =
            tx['success'] == true && current['success'] == false;
        tx.addAll(current);
        if (correctedFailure) {
          await _save();
          throw StateError(
            'A saved successful transaction actually reverted. Review the corrected history before retrying.',
          );
        }
      }
      if (op.transactions.isNotEmpty) await _save();
      await refresh();
      _guard();
      final state = chain!;
      final hadFinalTx = op.transactions.any(
        (tx) =>
            tx['success'] == true &&
            [op.kind, 'atomicRegister'].contains(tx['kind']),
      );
      if (_matchesCompleted(op, state) && hadFinalTx) {
        op.phase = 'complete';
        op.completedAt = DateTime.now().toUtc();
        await _save();
        authorized = false;
        return;
      }
      if (hadFinalTx) {
        throw StateError(
          'The final transaction succeeded but the current record differs. Refresh or inspect its receipt; it will not be sent again.',
        );
      }
      if (op.isComplete) {
        throw StateError(
          'The saved completion no longer matches current chain state. Recovery data is retained.',
        );
      }
      if (op.kind == 'register') {
        znsCheckRegistrationQuote(op, await gateway.quoteRegistration(op.name));
        final occupied = await gateway.lookup(op.name);
        if (occupied?.participating == true) {
          throw StateError(
            'This name was registered before your reveal. Converted assets remain in your Base account.',
          );
        }
      } else if (op.kind != 'withdrawClaims') {
        final position = state.position;
        if (position == null ||
            position.positionId != op.positionId ||
            position.retired ||
            position.owner.toLowerCase() != scope.owner.toLowerCase() ||
            (op.kind != 'release' && !position.participating)) {
          throw StateError(
            'This registration changed or expired. Review its current state before continuing.',
          );
        }
      }
      // Funding is performed at most once for an intent. An additional payment
      // requires a new explicitly reviewed operation, never a timeout retry.
      if (op.funding != null && op.funding!['attempted'] == true) {
        final funding = await gateway.fundingStatus(op.funding!);
        op.funding = {...op.funding!, ...funding};
        await _save();
        if (funding['failed'] == true) {
          throw StateError(
            funding['message'] as String? ??
                'Funding was refunded or failed. Inspect the saved deposit before retrying.',
          );
        }
        if (funding['complete'] != true) {
          op.phase = 'funding';
          return;
        }
      } else if (op.funding == null && state.eth < op.maxEthWei) {
        final funding = await gateway.fundingQuote(
          op.maxEthWei - state.eth,
          dry: false,
        );
        if (BigInt.parse(funding['maxZatoshi'] as String) > op.maxZatoshi) {
          throw StateError(
            'The fresh funding quote exceeds your approved ZEC budget.',
          );
        }
        if (op.kind == 'register') {
          znsCheckRegistrationQuote(
            op,
            await gateway.quoteRegistration(op.name),
          );
        }
        _guard();
        op.funding = {...funding, 'attempted': true};
        op.phase = 'funding';
        await _save();
        _guard();
        late final String? hash;
        try {
          hash = await gateway.sendFunding(
            op.funding!,
            ensureAuthorized: _guard,
          );
        } on ZnsFundingNotSent {
          op.funding = null;
          await _save();
          rethrow;
        }
        op.funding = {...op.funding!, 'txHash': hash};
        await _save();
        return;
      }
      if (op.funding == null) {
        op.funding = {'notRequired': true, 'complete': true};
        await _save();
      }
      if (op.kind == 'register' && state.commitAt == 0) {
        await _send(op, {
          'kind': 'commit',
          'name': op.name,
          'unifiedAddress': op.unifiedAddress,
          'secret': op.secret,
        });
        return;
      }
      if (op.kind == 'register' &&
          state.timestamp < state.commitAt + state.minAge) {
        op.phase = 'waiting';
        await _save();
        return;
      }
      if (op.kind == 'register' &&
          state.timestamp > state.commitAt + state.maxAge) {
        throw StateError(
          'The commitment expired. Your assets remain in your Base account; recover or start a new commitment explicitly.',
        );
      }
      final shortfall = op.requiredTokenUnits > state.token
          ? op.requiredTokenUnits - state.token
          : BigInt.zero;
      final spentEth = op.transactions
          .where((tx) => tx['success'] == true)
          .fold(
            BigInt.zero,
            (sum, tx) => sum + BigInt.parse(tx['value'] as String? ?? '0'),
          );
      final budget = op.maxEthWei - op.maxGasFeeWei - spentEth;
      if (op.kind == 'register') op.phase = 'register';
      progressMessage = shortfall > BigInt.zero
          ? 'Finding a swap route…'
          : 'Preparing transaction…';
      onChange();
      final swap = shortfall > BigInt.zero
          ? await gateway.swapQuote(shortfall, budget)
          : null;
      if (op.kind == 'register' && gateway.supportsAtomic) {
        await _send(
          op,
          {
            'kind': 'atomicRegister',
            'name': op.name,
            'unifiedAddress': op.unifiedAddress,
            'secret': op.secret,
            'amount': op.requiredTokenUnits.toString(),
            'maxDeposit': op.requiredTokenUnits.toString(),
            'extraDeposit': op.extraDeposit.toString(),
            'expectedPricingMode': op.registrationQuote!.pricingMode,
            'existingTokenUnits': state.token.toString(),
            'deadline': (state.timestamp + 600).toString(),
            'swap': swap,
          },
          refreshSwap: swap == null
              ? null
              : () => gateway.swapQuote(shortfall, budget),
        );
        return;
      }
      if (swap != null) {
        await _send(op, {'kind': 'swap', ...swap});
        return;
      }
      if (state.allowance < op.requiredTokenUnits) {
        await _send(op, {
          'kind': 'approve',
          'amount': op.requiredTokenUnits.toString(),
        });
        return;
      }
      final command = <String, dynamic>{'kind': op.kind};
      if (op.kind == 'register') command['name'] = op.name;
      if (!['register', 'withdrawClaims'].contains(op.kind)) {
        command['positionId'] = op.positionId.toString();
      }
      if (['register', 'update'].contains(op.kind)) {
        command['unifiedAddress'] = op.unifiedAddress;
      }
      if (op.kind == 'register') {
        command.addAll({
          'secret': op.secret,
          'maxDeposit': op.requiredTokenUnits.toString(),
          'extraDeposit': op.extraDeposit.toString(),
          'expectedPricingMode': op.registrationQuote!.pricingMode,
          'deadline': (state.timestamp + 600).toString(),
        });
      }
      if (op.kind == 'transfer') command['recipient'] = op.recipient;
      await _send(op, command);
    } catch (e) {
      error = e.toString();
      authorized = false;
      operation?.message = error;
      try {
        if (operation != null) await _save();
      } catch (_) {
        /* Retain error and in-memory recovery. */
      }
    } finally {
      progressMessage = null;
      busy = false;
      onChange();
      if (authorized && !_disposed) {
        _timer?.cancel();
        _timer = Timer(const Duration(seconds: 5), () => unawaited(advance()));
      }
    }
  }
}
