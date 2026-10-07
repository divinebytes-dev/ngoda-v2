import 'dart:math';

import 'package:ngoda/data_models/finance/finance_bucket.dart';
import 'package:ngoda/data_models/finance/finance_summary.dart';
import 'package:ngoda/data_models/finance/finance_summary_result.dart';
import 'package:ngoda/data_models/gold/gold_calculation_result.dart';
import 'package:ngoda/data_models/transaction/transfer_calculation_result.dart';

import 'package:ngoda/ui/enums/enums.dart';

abstract final class CalculationService {
  static const int goldDecimals = 6;

  static TransferCalculationResult calculateUserTransfer({
    required double amount,
    required double feePercent,
  }) {
    return _calculateTransfer(amount: amount, feePercent: feePercent);
  }

  static TransferCalculationResult calculateUserDeposit({
    required double amount,
    required double feePercent,
  }) {
    return _calculateTransfer(amount: amount, feePercent: feePercent);
  }

  static TransferCalculationResult _calculateTransfer({
    required double amount,
    required double feePercent,
  }) {
    final feeRate = _percentageRate(feePercent);

    final fee = amount * feeRate;

    return TransferCalculationResult(
      amount: amount,
      fee: fee,
      totalDebit: amount + fee,
      tax: 0.0,
    );
  }

  static TransferCalculationResult calculateCashWithdrawal({
    required double amount,
    required double feePercent,
    required double taxPercent,
    required double totalFee,
    required double totalTax,
  }) {
    /*
     * feePercent and taxPercent are intentionally retained
     * in the public API for compatibility with existing
     * callers.
     *
     * The backend-calculated totalFee and totalTax remain
     * the source of truth for the final withdrawal result.
     */
    final totalDebit = amount + totalFee + totalTax;

    return TransferCalculationResult(
      amount: amount,
      fee: totalFee,
      tax: totalTax,
      totalDebit: totalDebit,
    );
  }

  static GoldCalculationResult calculateGoldTransaction({
    required double principal,
    required String currency,
    required GoldTransactionType transactionType,
    required double goldMarketPrice,
    required double spreadRate,
    required double feeRate,
  }) {
    if (transactionType == GoldTransactionType.transfer) {
      return _calculateGoldTransfer(
        principal: principal,
        goldMarketPrice: goldMarketPrice,
        feeRate: feeRate,
      );
    }

    if (transactionType == GoldTransactionType.buy) {
      return _calculateGoldBuy(
        principal: principal,
        currency: currency,
        goldMarketPrice: goldMarketPrice,
        spreadRate: spreadRate,
        feeRate: feeRate,
      );
    }

    return _calculateGoldSell(
      principal: principal,
      currency: currency,
      goldMarketPrice: goldMarketPrice,
      spreadRate: spreadRate,
      feeRate: feeRate,
    );
  }

  static GoldCalculationResult _calculateGoldTransfer({
    required double principal,
    required double goldMarketPrice,
    required double feeRate,
  }) {
    final fee = principal * _percentageRate(feeRate);

    final total = principal + fee;

    final principalUsd = principal * goldMarketPrice;

    return GoldCalculationResult(
      principal: principal,
      quantity: total,
      fiatPaid: total * goldMarketPrice,
      fiatFee: fee * goldMarketPrice,
      feeGold: fee,
      spreadProfit: principalUsd,
    );
  }

  static GoldCalculationResult _calculateGoldBuy({
    required double principal,
    required String currency,
    required double goldMarketPrice,
    required double spreadRate,
    required double feeRate,
  }) {
    final spread = _percentageRate(spreadRate);

    final fee = _percentageRate(feeRate);

    final buyPrice = goldMarketPrice * (1 + spread);

    double quantity;
    double fiatPaid;
    double feeGold;
    double spreadProfit;
    double feeFiat;

    if (_isGoldCurrency(currency)) {
      /*
       * User enters the exact gold quantity
       * they want to receive.
       *
       * The fee is charged on top of the
       * gold purchase value.
       */
      quantity = principal;

      final fiatBase = quantity * buyPrice;

      feeFiat = fiatBase * fee;

      fiatPaid = fiatBase + feeFiat;

      feeGold = buyPrice > 0 ? feeFiat / buyPrice : 0;

      final treasuryCost = quantity * goldMarketPrice;

      spreadProfit = fiatBase - treasuryCost;
    } else {
      /*
       * User enters the total fiat amount
       * they want to pay.
       *
       * The fee is deducted first.
       * The remaining fiat purchases gold.
       */
      fiatPaid = principal;

      feeFiat = fiatPaid * fee;

      final fiatBase = fiatPaid - feeFiat;

      quantity = buyPrice > 0 ? fiatBase / buyPrice : 0;

      feeGold = buyPrice > 0 ? feeFiat / buyPrice : 0;

      final treasuryCost = quantity * goldMarketPrice;

      spreadProfit = fiatBase - treasuryCost;
    }

    return GoldCalculationResult(
      principal: roundDown(quantity),
      quantity: roundDown(quantity + feeGold),
      fiatPaid: roundDown(fiatPaid),
      fiatFee: roundDown(feeFiat),
      feeGold: roundDown(feeGold),
      spreadProfit: roundDown(spreadProfit),
    );
  }

  static GoldCalculationResult _calculateGoldSell({
    required double principal,
    required String currency,
    required double goldMarketPrice,
    required double spreadRate,
    required double feeRate,
  }) {
    final spread = _percentageRate(spreadRate);

    final fee = _percentageRate(feeRate);

    final sellPrice = goldMarketPrice * (1 - spread);

    double quantity;
    double fiatReceived;
    double feeGold;
    double spreadProfit;
    double feeFiat;

    if (_isGoldCurrency(currency)) {
      /*
     * User enters the exact gold quantity
     * they want to sell.
     *
     * quantity = entered quantity
     * fiatBase = quantity * sellPrice
     * feeFiat = configured fee on fiatBase
     * fiatReceived = fiatBase - feeFiat
     */
      quantity = principal;

      final fiatBase = quantity * sellPrice;

      feeFiat = fiatBase * fee;

      fiatReceived = fiatBase - feeFiat;

      feeGold = sellPrice > 0 ? feeFiat / sellPrice : 0;

      final marketFiat = quantity * goldMarketPrice;

      spreadProfit = marketFiat - fiatBase;
    } else {
      /*
     * User enters the exact fiat amount
     * they want to receive.
     *
     * This mirrors calculate_gold_sell_pricing()
     * and calculate_configured_amount().
     *
     * feeFiat =
     *     fiatReceived * fee
     *
     * fiatBase =
     *     fiatReceived + feeFiat
     *
     * quantity =
     *     fiatBase / sellPrice
     */
      fiatReceived = principal;

      feeFiat = fiatReceived * fee;

      final fiatBase = fiatReceived + feeFiat;

      quantity = sellPrice > 0 ? fiatBase / sellPrice : 0;

      feeGold = sellPrice > 0 ? feeFiat / sellPrice : 0;

      final marketFiat = quantity * goldMarketPrice;

      spreadProfit = marketFiat - fiatBase;
    }

    return GoldCalculationResult(
      principal: roundDown(principal),
      quantity: roundDown(quantity),
      fiatPaid: roundDown(fiatReceived),
      fiatFee: roundDown(feeFiat),
      feeGold: roundDown(feeGold),
      spreadProfit: roundDown(spreadProfit),
    );
  }

  static FinanceSummaryResult calculateFinanceSummary(FinanceSummary? summary) {
    if (summary == null) {
      return FinanceSummaryResult(
        financeCash: 0,
        agentNet: 0,
        creditAgentNet: 0,
        customerDeposit: 0,
        netPosition: 0,
      );
    }

    final financeCash = summary.bank.totalUsd + summary.treasury.totalUsd;

    final agentNet = summary.agentAsset.totalUsd - summary.agentFloat.totalUsd;

    final creditAgentNet =
        summary.creditAgentCash.totalUsd + summary.creditAgentFloat.totalUsd;

    final customerDeposit = summary.customer.totalUsd;

    final netPosition =
        financeCash + creditAgentNet - agentNet - customerDeposit;

    return FinanceSummaryResult(
      financeCash: financeCash,
      agentNet: agentNet,
      creditAgentNet: creditAgentNet,
      customerDeposit: customerDeposit,
      netPosition: netPosition,
    );
  }

  static double _percentageRate(double percent) {
    return percent / 100;
  }

  static bool _isGoldCurrency(String currency) {
    return currency.trim().toLowerCase() == 'gold';
  }

  static double roundDown(double value, {int decimals = goldDecimals}) {
    final factor = pow(10, decimals).toDouble();

    return (value * factor).floorToDouble() / factor;
  }
}
