// Apache-2.0 section 4(b): modified from upstream by the Sybil fork.
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart'
    show ExpansionTile, Material, MaterialType;

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sybil_widgets.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/review_list_row.dart';
import '../../../core/widgets/review_wrap_card.dart';
import 'send_review_layout.dart';

/// Display phase of a submitted send on the redesigned status screens.
enum SendStatusPhase { inProgress, completed, failed }

/// Presentational content view for the three send status screens
/// (in progress / sent successfully / send failed).
///
/// Shares the review layout shell and swaps the phase-dependent pieces:
/// * title and Status row (loader / check-circle / cancel icon + color),
/// * connector glyph — arrow-down normally, uturn-up on failed,
/// * failed extras — strikethrough on the recipient headline and explicit
///   failure styling. Transaction identifiers expand under Payment details.
///
/// No in-content CTA exists on any phase per the specs — navigation is the
/// page-toolbar back button only.
class SendStatusContentView extends StatelessWidget {
  const SendStatusContentView({
    required this.phase,
    required this.amountText,
    required this.recipient,
    required this.timestampText,
    required this.txIdText,
    required this.feeText,
    this.isShieldedRecipient = true,
    this.recipientAddressType,
    this.fiatText,
    this.memoText,
    this.memoExpanded = false,
    this.noticeText,
    this.titleOverride,
    this.recipientRow,
    this.onShowFullAddress,
    this.onExpandMemo,
    this.onOpenExplorer,
    this.onFeeHelp,
    super.key,
  });

  final SendStatusPhase phase;

  /// Formatted send amount ("123.12 ZEC").
  final String amountText;

  final SendReviewRecipient recipient;

  /// Pool badge for raw-address recipients.
  final bool isShieldedRecipient;

  /// Full protocol address type from validation when available.
  final String? recipientAddressType;

  /// Formatted timestamp ("25 May, 13:30").
  final String timestampText;

  /// Transaction id (display-truncated by the row when long). The Tx ID row
  /// is omitted when null — no txid exists until the broadcast returns.
  final String? txIdText;

  /// Formatted fee ("0.012 ZEC").
  final String feeText;

  /// Optional fiat sub-label under the amount; hidden when null.
  final String? fiatText;

  /// Optional memo; the Message row is omitted when null.
  final String? memoText;

  /// Whether the Message row shows the full memo (see [ReviewMemoRows]).
  final bool memoExpanded;

  /// Optional status detail under the wrap card — the partial/offline
  /// broadcast guidance or the failure reason. Hidden when null.
  final String? noticeText;

  /// Flow-specific title. Null keeps the standard Send status copy.
  final String? titleOverride;

  /// Flow-specific recipient presentation. Null keeps the standard Send row.
  final Widget? recipientRow;

  final VoidCallback? onShowFullAddress;
  final VoidCallback? onExpandMemo;
  final VoidCallback? onOpenExplorer;
  final VoidCallback? onFeeHelp;

  bool get _failed => phase == SendStatusPhase.failed;

  @override
  Widget build(BuildContext context) {
    return SendReviewContentColumn(
      title:
          titleOverride ??
          switch (phase) {
            SendStatusPhase.inProgress => 'Send in progress...',
            SendStatusPhase.completed => 'Sent successfully',
            SendStatusPhase.failed => 'Send failed',
          },
      children: [
        SendReviewInfoSection(
          amountText: amountText,
          fiatText: fiatText,
          recipient: recipient,
          isShieldedRecipient: isShieldedRecipient,
          recipientAddressType: recipientAddressType,
          connectorIconName: _failed ? AppIcons.uturnUp : AppIcons.arrowDown,
          recipientStruckThrough: _failed,
          recipientRow: recipientRow,
          onShowFullAddress: onShowFullAddress,
        ),
        _statusCard(),
        if (noticeText != null)
          Builder(
            builder: (context) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text(
                noticeText!,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _statusCard() {
    return Builder(
      builder: (context) {
        final colors = context.colors;
        final (statusValue, statusIconName, statusColor) = switch (phase) {
          SendStatusPhase.inProgress => (
            'In progress',
            AppIcons.loader,
            colors.text.secondary,
          ),
          SendStatusPhase.completed => (
            'Completed',
            AppIcons.checkCircle,
            colors.text.positiveStrong,
          ),
          SendStatusPhase.failed => (
            'Failed',
            AppIcons.cancel,
            colors.text.destructive,
          ),
        };

        return SybilCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ReviewListRow(
                label: 'Status',
                value: statusValue,
                labelColor: _failed ? colors.text.destructive : null,
                valueColor: statusColor,
                leadingIconName: statusIconName,
              ),
              if (memoText != null)
                ReviewMemoRows(
                  memoText: memoText!,
                  expanded: memoExpanded,
                  onToggle: onExpandMemo,
                ),
              const SizedBox(height: AppSpacing.s),
              const ReviewWrapDivider(),
              const SizedBox(height: AppSpacing.s),
              ReviewListRow(
                label: 'Network fee',
                value: feeText,
                trailingIconName: AppIcons.help,
                trailingIconColor: colors.text.secondary,
                trailingIconTooltip: kTxFeeHelpTooltip,
                onPressed: onFeeHelp,
              ),
              Material(
                type: MaterialType.transparency,
                child: ExpansionTile(
                  title: Text(
                    'Payment details',
                    style: AppTypography.bodyMedium.copyWith(
                      color: SybilPalette.of(context).muted,
                    ),
                  ),
                  tilePadding: EdgeInsets.zero,
                  children: [
                    ReviewListRow(label: 'Timestamp', value: timestampText),
                    if (txIdText != null)
                      ReviewListRow(
                        label: 'Tx ID',
                        value: txIdText!,
                        trailingIconName: AppIcons.arrowTopRight,
                        onPressed: onOpenExplorer,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
