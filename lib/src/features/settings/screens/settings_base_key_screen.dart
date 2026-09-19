import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/clipboard/sensitive_clipboard.dart';
import '../../../core/layout/app_desktop_backdrop_shell.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../core/privacy/sensitive_privacy_overlay.dart';
import '../../../core/security/password_policy.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../base_key_export.dart';
import '../widgets/confirm_access_card.dart';
import '../widgets/settings_pane_backdrop.dart';

/// Identity of one export session: active account, Zcash network, and the
/// derived Base owner. Any change (account switch, network failover, access
/// becoming unavailable, or the wallet locking) invalidates a revealed key.
final _baseKeySessionProvider = Provider.autoDispose<String>((ref) {
  final uuid = ref.watch(
    accountProvider.select((state) => state.value?.activeAccountUuid),
  );
  final network = ref.watch(
    rpcEndpointFailoverProvider.select((state) => state.current.networkName),
  );
  final owner = ref.watch(baseKeyExportAccessProvider).asData?.value?.owner;
  return '$uuid:$network:$owner';
});

/// Base account private key export, gated like the secret passphrase
/// screen: password confirmation first, the key revealed on a dedicated
/// screen afterwards. Secrets live only in this state, never in provider
/// view data, and are zeroed when the screen goes away.
class SettingsBaseKeyScreen extends ConsumerStatefulWidget {
  const SettingsBaseKeyScreen({super.key});
  @override
  ConsumerState<SettingsBaseKeyScreen> createState() =>
      _SettingsBaseKeyScreenState();
}

enum _Stage { password, reveal }

class _SettingsBaseKeyScreenState extends ConsumerState<SettingsBaseKeyScreen>
    with WidgetsBindingObserver {
  final _passwordController = TextEditingController();
  _Stage _stage = _Stage.password;
  bool _isSubmitting = false;
  bool _copied = false;
  String? _passwordError;
  String _owner = '';
  Uint8List? _key;
  Timer? _copyResetTimer;
  Timer? _expiry;
  int _generation = 0;

  bool get _canSubmit =>
      !_isSubmitting &&
      ref.read(baseKeyExportAccessProvider).asData?.value != null &&
      isWalletPasswordValid(_passwordController.text);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(_clearSensitiveState);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clearSensitiveState();
    _passwordController.dispose();
    super.dispose();
  }

  void _clearSensitiveState({String? passwordError}) {
    _generation++;
    _expiry?.cancel();
    _copyResetTimer?.cancel();
    _copied = false;
    _key?.fillRange(0, _key!.length, 0);
    _key = null;
    _owner = '';
    _passwordController.clear();
    _isSubmitting = false;
    _stage = _Stage.password;
    _passwordError = passwordError;
  }

  void _handleSessionChanged(String previous, String next) {
    final accountChanged = previous.split(':').first != next.split(':').first;
    final idleAtGate =
        _stage == _Stage.password && !_isSubmitting && _key == null;
    if (idleAtGate && !accountChanged) return;
    setState(() {
      _clearSensitiveState(
        passwordError: accountChanged
            ? 'Selected account changed. Enter your password again.'
            : null,
      );
    });
  }

  void _handlePasswordChanged() {
    if (_passwordError == null) {
      setState(() {});
      return;
    }
    setState(() => _passwordError = null);
  }

  Future<void> _submitPassword() async {
    if (_isSubmitting) return;
    final exporter = ref.read(baseKeyExportAccessProvider).asData?.value;
    if (exporter == null) {
      setState(
        () => _passwordError =
            'Unlock the selected software account to continue.',
      );
      return;
    }
    if (!isWalletPasswordValid(_passwordController.text)) {
      setState(
        () => _passwordError = validateWalletPassword(_passwordController.text),
      );
      return;
    }
    final generation = _generation;
    setState(() {
      _isSubmitting = true;
      _passwordError = null;
    });
    try {
      final key = await exporter.exportKey(_passwordController.text);
      if (!mounted || generation != _generation) {
        key.fillRange(0, key.length, 0);
        return;
      }
      setState(() {
        _key = key;
        _owner = exporter.owner;
        _stage = _Stage.reveal;
        _isSubmitting = false;
      });
      _passwordController.clear();
      _expiry = Timer(const Duration(minutes: 1), () {
        if (mounted) setState(_clearSensitiveState);
      });
    } catch (_) {
      // Never interpolate native errors or secret values into the UI.
      if (!mounted || generation != _generation) return;
      setState(() {
        _isSubmitting = false;
        _passwordError =
            'Could not export. Check your password and unlock the selected software account.';
      });
    }
  }

  Future<void> _copyKey() async {
    final key = _key;
    if (key == null) return;
    final hex = _keyHex(key);
    await SensitiveClipboard.copyText(hex);
    if (!mounted) return;
    _copyResetTimer?.cancel();
    setState(() => _copied = true);
    _copyResetTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(_baseKeySessionProvider, (previous, next) {
      if (previous == null || previous == next) return;
      _handleSessionChanged(previous, next);
    });
    final access = ref.watch(baseKeyExportAccessProvider);
    final exporter = access.asData?.value;
    final gate = ConfirmAccessCard(
      subtitle: 'To view your Base / Ethereum private key.',
      controller: _passwordController,
      errorText:
          _passwordError ??
          (access.isLoading || exporter != null
              ? null
              : 'Unlock the selected software account to continue.'),
      isSubmitting: _isSubmitting,
      canSubmit: _canSubmit,
      onChanged: _handlePasswordChanged,
      onSubmit: _submitPassword,
    );
    final content = switch (_stage) {
      _Stage.password => Center(
        child: kAppFormFactor == AppFormFactor.mobile
            ? SingleChildScrollView(
                child: FittedBox(fit: BoxFit.scaleDown, child: gate),
              )
            : gate,
      ),
      _Stage.reveal => _buildReveal(),
    };
    if (kAppFormFactor == AppFormFactor.mobile) {
      return Scaffold(
        backgroundColor: context.colors.background.window,
        body: SensitivePrivacyOverlay(
          sensitiveContentVisible: _stage == _Stage.reveal && _key != null,
          child: SafeArea(
            child: Column(
              children: [
                MobileTopNav.back(
                  title: _stage == _Stage.reveal ? 'Private key' : '',
                  onBack: () {
                    _clearSensitiveState();
                    context.pop();
                  },
                ),
                Expanded(child: content),
              ],
            ),
          ),
        ),
      );
    }
    return AppDesktopBackdropShell(
      background: _stage == _Stage.reveal
          ? ColoredBox(color: context.colors.background.window)
          : const SettingsPaneBackdrop(art: SettingsBackdropArt.castle),
      sidebar: const AppMainSidebar(),
      pane: SensitivePrivacyOverlay(
        sensitiveContentVisible: _stage == _Stage.reveal && _key != null,
        child: SizedBox.expand(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppPaneToolbar(
                backLinkMinWidth: 60,
                onBeforeNavigate: () => _clearSensitiveState(),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    0,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: content,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReveal() {
    final key = _key;
    if (key == null) return const SizedBox.shrink();
    final colors = context.colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Base / Ethereum private key',
              textAlign: TextAlign.center,
              style: AppTypography.headlineLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              'Anyone with this key controls the names and funds in this '
              'Base account.\nDon’t share it with anyone.',
              textAlign: TextAlign.center,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.accent,
                height: 18 / 14,
                letterSpacing: -0.14,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _BaseKeyCard(
              hex: _keyHex(key),
              owner: _owner,
              copied: _copied,
              onCopyPressed: _copyKey,
            ),
            const SizedBox(height: AppSpacing.s),
            SizedBox(
              width: ConfirmAccessCard.width,
              child: Text(
                'Import this key as a separate account in MetaMask. '
                'Importing your Sigil seed may produce a different address. '
                'Both wallets will control this account. The key is cleared '
                'from this screen after one minute or when you leave it. '
                'Your system clipboard may retain copied keys.',
                textAlign: TextAlign.center,
                style: AppTypography.labelMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BaseKeyCard extends StatelessWidget {
  const _BaseKeyCard({
    required this.hex,
    required this.owner,
    required this.copied,
    required this.onCopyPressed,
  });

  final String hex;
  final String owner;
  final bool copied;
  final Future<void> Function() onCopyPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cardTextColor = colors.text.homeCard;
    final mutedTextColor = cardTextColor.withValues(alpha: 0.6);
    return Container(
      width: ConfirmAccessCard.width,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.background.homeCard,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: [
          BoxShadow(color: colors.shadows.subtle, blurRadius: 0.5),
          BoxShadow(
            color: colors.shadows.subtle,
            offset: const Offset(0, 2),
            blurRadius: 2,
          ),
          BoxShadow(
            color: colors.shadows.subtle,
            offset: const Offset(0, 1),
            blurRadius: 1,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                AppIcon(
                  AppIcons.key,
                  size: AppIconSize.medium,
                  color: cardTextColor,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    'Private key',
                    style: AppTypography.bodyLarge.copyWith(
                      color: cardTextColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                AppButton(
                  key: const ValueKey('settings_base_key_copy_button'),
                  onPressed: onCopyPressed,
                  variant: AppButtonVariant.secondary,
                  size: AppButtonSize.mediumLarge,
                  height: 24,
                  minWidth: 52,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxs,
                  ),
                  child: Text(copied ? 'Copied' : 'Copy'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            'Base account',
            style: AppTypography.labelSmall.copyWith(color: mutedTextColor),
          ),
          const SizedBox(height: AppSpacing.xxs),
          SelectableText(
            owner,
            style: AppTypography.codeSmall.copyWith(color: cardTextColor),
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(
            _groupHexPairs(hex),
            key: const ValueKey('settings_base_key_value'),
            style: AppTypography.codeSmall.copyWith(
              color: cardTextColor,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

String _keyHex(Uint8List key) =>
    key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();

String _groupHexPairs(String hex) {
  final buffer = StringBuffer();
  for (var i = 0; i < hex.length; i += 2) {
    if (i > 0) buffer.write(' ');
    buffer.write(hex.substring(i, i + 2));
  }
  return buffer.toString();
}
