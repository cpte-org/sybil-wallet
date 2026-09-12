import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/app_form_factor.dart';
import '../../core/widgets/familiar_widgets.dart';
import '../contacts/application/contact_ui_preferences.dart';
import '../contacts/presentation/familiar_add_person_screen.dart';

class ContactSettingsScreen extends ConsumerStatefulWidget {
  const ContactSettingsScreen({super.key});

  @override
  ConsumerState<ContactSettingsScreen> createState() =>
      _ContactSettingsScreenState();
}

class _ContactSettingsScreenState extends ConsumerState<ContactSettingsScreen> {
  String? _error;

  Future<void> _setAdvanced(bool enabled) async {
    setState(() => _error = null);
    try {
      await ref.read(contactAdvancedToolsProvider.notifier).setEnabled(enabled);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save this setting. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preference = ref.watch(contactAdvancedToolsProvider);
    final advanced = preference.asData?.value == true;
    return FamiliarFlowPage(
      title: 'Contact options',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FamiliarPageHeader(
            title: 'Stay connected.',
            subtitle: 'Connect by scanning or sharing a code.',
          ),
          const SizedBox(height: 24),
          FamiliarCard(
            child: Column(
              children: [
                _ContactOption(
                  icon: Icons.qr_code_2,
                  title: 'Connect privately',
                  subtitle: 'Exchange details with someone you know.',
                  onTap: () => context.push('/contacts/exchange'),
                ),
                const Divider(),
                _ContactOption(
                  icon: Icons.people_outline,
                  title: 'Introductions',
                  subtitle: 'Connect through someone you both know.',
                  onTap: () => context.push('/contacts/introductions'),
                ),
                const Divider(),
                _ContactOption(
                  icon: Icons.lock_outline,
                  title: 'Connection backup',
                  subtitle: 'Save or restore your private connections.',
                  onTap: () => context.push('/contacts/backup'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FamiliarCard(
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
                  value: advanced,
                  onChanged: preference.isLoading ? null : _setAdvanced,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (advanced) ...[
                  const Divider(),
                  _ContactOption(
                    icon: Icons.link,
                    title: 'Private delivery',
                    subtitle: 'Set up or inspect the delivery connection.',
                    onTap: () => context.push('/contacts/delivery'),
                  ),
                  _ContactOption(
                    icon: Icons.people_outline,
                    title: 'Manual key pairing',
                    subtitle:
                        'Prepare reciprocal contact keys for introductions.',
                    onTap: () => context.push('/contacts/introductions'),
                  ),
                  _ContactOption(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Other networks',
                    subtitle: 'Addresses saved for other blockchains.',
                    onTap: () => context.push(
                      kAppFormFactor == AppFormFactor.mobile
                          ? '/settings/address-book'
                          : '/address-book',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactOption extends StatelessWidget {
  const _ContactOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
