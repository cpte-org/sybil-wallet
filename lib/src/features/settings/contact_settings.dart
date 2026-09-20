import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/sybil_widgets.dart';
import '../contacts/application/contact_delivery_preferences.dart';
import '../contacts/application/contact_delivery_providers.dart';
import '../contacts/application/contact_ui_preferences.dart';
import '../contacts/presentation/sybil_add_person_screen.dart';

class ContactSettingsScreen extends ConsumerStatefulWidget {
  const ContactSettingsScreen({super.key});

  @override
  ConsumerState<ContactSettingsScreen> createState() =>
      _ContactSettingsScreenState();
}

class _ContactSettingsScreenState extends ConsumerState<ContactSettingsScreen> {
  String? _advancedError;
  String? _deliveryError;

  Future<void> _setAdvanced(bool enabled) async {
    setState(() => _advancedError = null);
    try {
      await ref.read(contactAdvancedToolsProvider.notifier).setEnabled(enabled);
    } catch (_) {
      if (mounted) {
        setState(
          () => _advancedError = 'Could not save this setting. Try again.',
        );
      }
    }
  }

  Future<void> _setDelivery(bool enabled) async {
    setState(() => _deliveryError = null);
    try {
      await ref
          .read(simplexDeliveryEnabledProvider.notifier)
          .setEnabled(enabled);
    } catch (_) {
      if (mounted) {
        setState(
          () => _deliveryError = 'Could not save this setting. Try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final advanced = ref.watch(contactAdvancedToolsProvider);
    final delivery = ref.watch(simplexDeliveryEnabledProvider);
    final status = ref.watch(simplexDeliveryStatusProvider);
    final deliverySupported = Platform.isLinux || Platform.isAndroid;
    return SybilFlowPage(
      title: 'Contact options',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SybilPageHeader(
            title: 'Choose how People connects.',
            subtitle: 'Delivery, backup and advanced tools.',
          ),
          const SizedBox(height: 24),
          SybilCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile.adaptive(
                  key: const Key('contact-advanced-tools-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Advanced contact tools'),
                  subtitle: const Text(
                    'Manual tools for testing and troubleshooting.',
                  ),
                  value: advanced.asData?.value == true,
                  onChanged: advanced.isLoading ? null : _setAdvanced,
                ),
                if (_advancedError != null) _errorText(_advancedError!),
                const Divider(),
                if (delivery.hasError)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('SimpleX private delivery'),
                    subtitle: const Text(
                      'Could not read your setting. Private delivery stays paused.',
                    ),
                    trailing: TextButton(
                      key: const Key('contact-simplex-delivery-retry'),
                      onPressed: () {
                        setState(() => _deliveryError = null);
                        ref.invalidate(simplexDeliveryEnabledProvider);
                      },
                      child: const Text('Retry'),
                    ),
                  )
                else
                  SwitchListTile.adaptive(
                    key: const Key('contact-simplex-delivery-switch'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('SimpleX private delivery'),
                    subtitle: Text(
                      _deliverySubtitle(status, deliverySupported),
                    ),
                    value: delivery.asData?.value == true,
                    onChanged:
                        deliverySupported &&
                            delivery.asData != null &&
                            !delivery.isLoading
                        ? _setDelivery
                        : null,
                  ),
                if (_deliveryError != null) _errorText(_deliveryError!),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SybilCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline),
              title: const Text('Connection backup'),
              subtitle: const Text('Save or restore your private connections.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/contacts/backup'),
            ),
          ),
        ],
      ),
    );
  }

  String _deliverySubtitle(SimplexDeliveryStatus status, bool supported) {
    if (!supported) {
      return 'Private delivery runs on supported Linux and Android builds.';
    }
    return switch (status) {
      SimplexDeliveryReady() || SimplexDeliveryTurnedOff() =>
        'Exchange contact packets over a private connection when one is set up.',
      _ => status.message,
    };
  }

  Widget _errorText(String message) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}
