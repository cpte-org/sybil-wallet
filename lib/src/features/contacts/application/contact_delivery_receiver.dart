import 'dart:async';

/// Foreground-only reconciliation of already received packets. This runner has
/// no send, sign, accept, or payment capability. Its owner must also close the
/// transport synchronously when the lifecycle/privacy gate closes.
class ContactDeliveryReceiver {
  ContactDeliveryReceiver({
    required this.allowed,
    required this.reconcile,
    required this.onRefresh,
    required this.onFailure,
    this.interval = const Duration(seconds: 5),
  });

  final bool Function() allowed;
  final Future<void> Function() reconcile;
  final void Function() onRefresh;
  final void Function() onFailure;
  final Duration interval;
  Timer? _timer;
  bool _started = false, _stopped = false;

  void start() {
    if (_started || _stopped) return;
    _started = true;
    // Avoid work during provider construction; the open transaction must first
    // release the contact mutation gate used by receive().
    _timer = Timer(Duration.zero, _run);
  }

  Future<void> _run() async {
    if (_stopped || !allowed()) {
      stop();
      return;
    }
    try {
      await reconcile();
      if (_stopped || !allowed()) {
        stop();
        return;
      }
      onRefresh();
      // Schedule after completion, never overlap or queue periodic scans.
      if (!_stopped) _timer = Timer(interval, _run);
    } catch (_) {
      final report = !_stopped && allowed();
      stop();
      // No raw native diagnostics or packet contents cross this boundary.
      if (report) onFailure();
    }
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }
}
