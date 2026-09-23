import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/sybil_widgets.dart';
import '../../zns/application/zns_controller.dart';
import '../../zns/data/zns_build_defaults.dart';
import '../../zns/presentation/zns_view_data.dart';

/// Compact labels must not expose a provider's API key in its path or query.
String baseRpcEndpointLabel(String value) {
  final uri = Uri.tryParse(value);
  return uri == null || uri.host.isEmpty ? 'Not configured' : uri.host;
}

class SettingsBaseEndpointScreen extends ConsumerWidget {
  const SettingsBaseEndpointScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(znsControllerProvider);
    final content = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650),
        child: BaseRpcEndpointEditor(
          data: data,
          onSave: ref.read(znsControllerProvider.notifier).updateRpcEndpoint,
        ),
      ),
    );
    if (kAppFormFactor == AppFormFactor.mobile) {
      return Scaffold(
        backgroundColor: context.colors.background.window,
        body: SafeArea(
          child: Column(
            children: [
              MobileTopNav.back(
                title: 'Base RPC endpoint',
                onBack: () => context.pop(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: content,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: AppPaneScrollScaffold(
          toolbar: const AppPaneToolbar(backLinkMinWidth: 60),
          padding: const EdgeInsets.all(AppSpacing.md),
          child: content,
        ),
      ),
    );
  }
}

class BaseRpcEndpointEditor extends StatefulWidget {
  const BaseRpcEndpointEditor({
    super.key,
    required this.data,
    required this.onSave,
  });

  final ZnsViewData data;
  final Future<bool> Function(String) onSave;

  @override
  State<BaseRpcEndpointEditor> createState() => _BaseRpcEndpointEditorState();
}

class _BaseRpcEndpointEditorState extends State<BaseRpcEndpointEditor> {
  final _custom = TextEditingController();
  bool _useCustom = false;
  bool _submitting = false;
  bool _failed = false;
  bool _saved = false;
  String? _unexpectedError;
  int _submission = 0;

  String? get _recommended => switch (widget.data.configuration.chainId) {
    8453 => znsMainnetRpc,
    84532 => znsSepoliaRpc,
    _ => null,
  };
  String get _selected => _useCustom ? _custom.text.trim() : _recommended!;
  String get _scope => [
    widget.data.accountId,
    widget.data.configuration.chainId,
    widget.data.configuration.registryAddress,
    widget.data.configuration.tokenAddress,
    widget.data.configuration.delegateAddress,
  ].join(':');
  bool get _disabled =>
      _submitting || widget.data.isBusy || widget.data.isLocked;

  String? get _validation {
    if (!_useCustom || _custom.text.trim().isEmpty) return null;
    final uri = Uri.tryParse(_custom.text.trim());
    final localTest =
        [31337, 84532].contains(widget.data.configuration.chainId) &&
        ['localhost', '127.0.0.1', '::1'].contains(uri?.host);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.scheme != 'https' && !(localTest && uri.scheme == 'http'))) {
      return 'Enter an HTTPS RPC URL without a username or fragment.';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _resetSelection();
  }

  void _resetSelection() {
    _custom.text = widget.data.configuration.rpcUrl;
    _useCustom = _recommended == null || _custom.text != _recommended;
    _failed = false;
    _saved = false;
    _unexpectedError = null;
  }

  @override
  void didUpdateWidget(BaseRpcEndpointEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.data;
    final current = widget.data;
    if (old.accountId != current.accountId ||
        old.configuration.chainId != current.configuration.chainId ||
        old.configuration.registryAddress !=
            current.configuration.registryAddress ||
        old.configuration.tokenAddress != current.configuration.tokenAddress ||
        old.configuration.delegateAddress !=
            current.configuration.delegateAddress ||
        (!old.isLocked && current.isLocked)) {
      _submission++;
      _submitting = false;
      _resetSelection();
    } else if (!_submitting &&
        old.configuration.rpcUrl != current.configuration.rpcUrl) {
      _resetSelection();
    }
  }

  void _select(bool custom) {
    if (_disabled) return;
    setState(() {
      _useCustom = custom;
      _failed = false;
      _saved = false;
      _unexpectedError = null;
    });
  }

  Future<void> _save() async {
    if (_disabled || _selected.isEmpty || _validation != null) return;
    final submission = ++_submission;
    final scope = _scope;
    setState(() {
      _submitting = true;
      _failed = false;
      _saved = false;
      _unexpectedError = null;
    });
    try {
      final saved = await widget.onSave(_selected);
      if (!mounted || submission != _submission || scope != _scope) return;
      setState(() {
        _saved = saved;
        _failed = !saved;
      });
    } catch (_) {
      if (!mounted || submission != _submission || scope != _scope) return;
      setState(() {
        _failed = true;
        _unexpectedError =
            'Could not verify this endpoint. Check the URL and try again.';
      });
    } finally {
      if (mounted && submission == _submission && scope == _scope) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  void dispose() {
    _submission++;
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSave =
        !_disabled &&
        _selected.isNotEmpty &&
        _validation == null &&
        _selected != widget.data.configuration.rpcUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SybilPageHeader(
          title: 'Base RPC endpoint',
          subtitle:
              'The connection used for Public Zcash names and your Base funds.',
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Current: ${baseRpcEndpointLabel(widget.data.configuration.rpcUrl)}',
          key: const Key('base-rpc-current'),
          style: AppTypography.bodyMediumStrong,
        ),
        const SizedBox(height: AppSpacing.md),
        SybilCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: AppSpacing.s,
                runSpacing: AppSpacing.s,
                children: [
                  if (_recommended != null)
                    AppButton(
                      key: const Key('base-rpc-recommended'),
                      variant: _useCustom
                          ? AppButtonVariant.secondary
                          : AppButtonVariant.primary,
                      onPressed: _disabled ? null : () => _select(false),
                      child: const Text('Recommended'),
                    ),
                  AppButton(
                    key: const Key('base-rpc-custom'),
                    variant: _useCustom
                        ? AppButtonVariant.primary
                        : AppButtonVariant.secondary,
                    onPressed: _disabled ? null : () => _select(true),
                    child: const Text('Custom endpoint'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (_useCustom)
                AppTextField(
                  key: const Key('base-rpc-url'),
                  controller: _custom,
                  label: 'RPC URL',
                  hintText: 'https://…',
                  enabled: !_disabled,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  tone: _validation == null
                      ? AppTextFieldTone.neutral
                      : AppTextFieldTone.destructive,
                  messageText: _validation,
                  onChanged: (_) => setState(() {
                    _failed = false;
                    _saved = false;
                    _unexpectedError = null;
                  }),
                  onSubmitted: (_) {
                    if (canSave) _save();
                  },
                )
              else ...[
                Text(
                  baseRpcEndpointLabel(_recommended!),
                  style: AppTypography.bodyMediumStrong,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  widget.data.configuration.chainId == 84532
                      ? 'Base Sepolia test network'
                      : 'Base mainnet · dRPC',
                  style: AppTypography.bodySmall,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              const Text(
                'The endpoint is checked against your current name service before it is saved.',
              ),
              const SizedBox(height: AppSpacing.md),
              if (widget.data.isLocked)
                const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.s),
                  child: Text('Unlock your wallet to change this connection.'),
                ),
              if (widget.data.isBusy && !_submitting)
                const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.s),
                  child: Text('Checking the current connection…'),
                ),
              if (_failed)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.s),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _unexpectedError ??
                          widget.data.error ??
                          'The endpoint could not be updated. Try again.',
                      key: const Key('base-rpc-error'),
                      style: AppTypography.bodySmall.copyWith(
                        color: context.colors.text.destructive,
                      ),
                    ),
                  ),
                ),
              if (_saved)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.s),
                  child: Semantics(
                    liveRegion: true,
                    child: const Text(
                      'Base RPC endpoint updated.',
                      key: Key('base-rpc-success'),
                    ),
                  ),
                ),
              AppButton(
                key: const Key('base-rpc-save'),
                onPressed: canSave ? _save : null,
                leading: _submitting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                child: Text(
                  _submitting ? 'Verifying endpoint…' : 'Verify and update',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
