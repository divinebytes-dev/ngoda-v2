import 'package:ngoda/data_models/transaction/sender_approval.dart';
import 'package:ngoda/data_models/transaction/signed_transaction.dart';
import 'package:ngoda/data_models/transaction/transaction_data.dart';
import 'package:ngoda/services/transaction_v_service.dart';
import 'package:ngoda/services/wallet_key_service.dart';
import 'package:ngoda/ui/functions/get_current_user.dart';

Future<SignedTransaction> getSignedTransaction({
  required String v,
  required String reference,
  required String identifier,
  required double amount,
  double feeAmount = 0,
  double taxAmount = 0,
  required String currency,
}) async {
  final version = v.trim();
  final transactionReference = reference.trim();
  final transactionIdentifier = identifier.trim();
  final currencyCode = currency.trim().toLowerCase();

  if (version.isEmpty) {
    throw ArgumentError.value(v, 'v', 'Transaction version is required');
  }

  if (transactionReference.isEmpty) {
    throw ArgumentError.value(
      reference,
      'reference',
      'Transaction reference is required',
    );
  }

  if (transactionIdentifier.isEmpty) {
    throw ArgumentError.value(
      identifier,
      'identifier',
      'Transaction identifier is required',
    );
  }

  if (currencyCode.isEmpty) {
    throw ArgumentError.value(currency, 'currency', 'Currency is required');
  }

  if (!amount.isFinite || amount <= 0) {
    throw ArgumentError.value(
      amount,
      'amount',
      'Amount must be greater than zero',
    );
  }

  if (!feeAmount.isFinite || feeAmount < 0) {
    throw ArgumentError.value(
      feeAmount,
      'feeAmount',
      'Fee amount cannot be negative',
    );
  }

  if (!taxAmount.isFinite || taxAmount < 0) {
    throw ArgumentError.value(
      taxAmount,
      'taxAmount',
      'Tax amount cannot be negative',
    );
  }

  final sender = getCurrentUser();
  final senderUserId = sender.userId;

  if (!sender.isAuthenticated ||
      senderUserId == null ||
      senderUserId.trim().isEmpty) {
    throw StateError('UNAUTHENTICATED');
  }

  final validitySeconds = TransactionVService.timeInSeconds(version);

  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /*
   * IMPORTANT:
   *
   * The signed transaction protocol currently
   * represents monetary fields in 1/100 units.
   *
   * This must remain aligned with the backend
   * signature verification protocol.
   */
  final amountMinorUnits = (amount * 100).round();

  final feeMinorUnits = (feeAmount * 100).round();

  final taxMinorUnits = (taxAmount * 100).round();

  final transaction = TransactionData(
    v: version,
    r: transactionReference,
    s: transactionIdentifier,
    a: amountMinorUnits,
    f: feeMinorUnits,
    g: taxMinorUnits,
    c: currencyCode,
    t: now,
    e: now + validitySeconds,
  );

  final transactionSignature = await WalletKeyService.signCanonicalString(
    transaction.canonicalString(),
  );

  final transactionData = TransactionData(
    v: transaction.v,
    r: transaction.r,
    s: transaction.s,
    a: transaction.a,
    f: transaction.f,
    g: transaction.g,
    c: transaction.c,
    t: transaction.t,
    e: transaction.e,
    ms: transactionSignature,
  );

  final approval = SenderApproval(
    v: 'approval_$version',
    r: transactionReference,
    b: senderUserId,
    a: amountMinorUnits,
    c: currencyCode,
    bs: '',
  );

  final senderSignature = await WalletKeyService.signCanonicalString(
    approval.canonicalString(version),
  );

  final senderApproval = SenderApproval(
    v: approval.v,
    r: approval.r,
    b: approval.b,
    a: approval.a,
    c: approval.c,
    bs: senderSignature,
  );

  return SignedTransaction(
    transactionData: transactionData,
    senderApproval: senderApproval,
  );
}
