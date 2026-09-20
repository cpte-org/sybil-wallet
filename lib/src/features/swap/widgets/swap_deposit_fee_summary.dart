import 'package:flutter/widgets.dart';

import '../../../core/formatting/zec_amount.dart';
import '../../../core/widgets/review_list_row.dart';
import '../../../core/widgets/review_wrap_card.dart';
import '../domain/swap_contract.dart';
import '../providers/swap_deposit_sender.dart';

/// Exact wallet debit, separate from fees already included in the swap quote.
class SwapDepositFeeSummary extends StatelessWidget {
  const SwapDepositFeeSummary({
    required this.quote,
    required this.feeZatoshi,
    super.key,
  });

  final SwapQuote quote;
  final BigInt feeZatoshi;

  @override
  Widget build(BuildContext context) => ReviewWrapCard(
    children: [
      ReviewListRow(
        label: 'Zcash network fee',
        value: '${formatZecAmount(feeZatoshi)} ZEC',
      ),
      ReviewListRow(
        label: 'Total ZEC debit',
        value:
            '${formatZecAmount(zecDepositAmountZatoshiForQuote(quote) + feeZatoshi)} ZEC',
      ),
    ],
  );
}
