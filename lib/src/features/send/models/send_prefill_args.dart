import '../../contacts/domain/contact_models.dart';

class SendPrefillArgs {
  const SendPrefillArgs({
    required this.id,
    required this.source,
    required this.address,
    this.amountText,
    this.memoText,
    this.label,
    this.message,
    this.contactRecipient,
  });

  final String id;
  final String source;
  final String address;
  final String? amountText;
  final String? memoText;
  final String? label;
  final String? message;
  final ContactRecipientSnapshot? contactRecipient;

  String get fingerprint =>
      '$id|$address|${amountText ?? ''}|${memoText ?? ''}|${contactRecipient?.fingerprint ?? ''}';
}
