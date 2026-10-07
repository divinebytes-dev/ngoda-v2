import 'package:ngoda/data_models/gamification/notifications/gamification_notification.dart';

enum DialogType { info, success, error, destructive, loading, question }

enum ConfirmType { info, success, destructive }

enum TransactionStatus {
  waiting,
  detected,
  processing,
  success,
  failed;

  static TransactionStatus? fromJson(String? value) {
    return enumFromApiValue(values, value);
  }

  bool get isTerminal =>
      this == TransactionStatus.success || this == TransactionStatus.failed;

  bool get isSuccess => this == TransactionStatus.success;

  bool get isFailed => this == TransactionStatus.failed;
}

enum TapPaymentState {
  waiting,
  detected,
  processing,
  success,
  failed;

  bool get isTerminal =>
      this == TapPaymentState.success || this == TapPaymentState.failed;
}

enum PaymentRowType { text, amount }

enum AppIconButtonLayout { vertical, horizontal }

enum InputMode { fiat, gold }

enum NetworkStatus { connected, disconnected }

enum BorrowStep { input, preview, processing }

enum IdentifierType { email, phone, userId }

enum UserRole {
  customer,
  agent,
  admin,
  finance,
  accounts,
  treasury,
  merchant,
  compliance,
  vendor;

  static UserRole? fromJson(String? value) {
    return enumFromApiValue(values, value);
  }
}

enum GoldTransactionType { buy, sell, transfer }

enum FinanceTransactionType {
  externalFunding,
  customerDirectDeposit,
  goldPurchase,
}

enum FeePaymentMethod {
  cash,
  points;

  bool get isCash => this == FeePaymentMethod.cash;

  bool get isPoints => this == FeePaymentMethod.points;
}

enum FinancialBehaviourType {
  saver,
  investor,
  shopper,
  borrower,
  balanced,
  neutral;

  static FinancialBehaviourType fromJson(String? value) {
    return enumFromApiValue(values, value) ?? FinancialBehaviourType.neutral;
  }
}

enum GenderType {
  male,
  female,
  preferNotToSay,
  unknown;

  static GenderType fromJson(String? value) {
    return enumFromApiValue(values, value) ?? GenderType.unknown;
  }

  String get displayName {
    switch (this) {
      case GenderType.male:
        return 'Male';

      case GenderType.female:
        return 'Female';

      case GenderType.preferNotToSay:
        return 'Prefer not to say';

      case GenderType.unknown:
        return 'Unknown';
    }
  }
}

enum IdentificationType {
  nationalId,
  passport,
  driversLicense,
  unknown;

  static IdentificationType fromJson(String? value) {
    return enumFromApiValue(values, value) ?? IdentificationType.unknown;
  }

  String get displayName {
    switch (this) {
      case IdentificationType.nationalId:
        return 'National ID';

      case IdentificationType.passport:
        return 'Passport';

      case IdentificationType.driversLicense:
        return "Driver's Licence";

      case IdentificationType.unknown:
        return 'Unknown';
    }
  }
}

enum SourceOfFundsType {
  salary,
  businessIncome,
  investments,
  savings,
  pension,
  familySupport,
  other;

  static SourceOfFundsType fromJson(String? value) {
    return enumFromApiValue(values, value) ?? SourceOfFundsType.other;
  }

  String get displayName {
    switch (this) {
      case SourceOfFundsType.salary:
        return 'Salary';

      case SourceOfFundsType.businessIncome:
        return 'Business Income';

      case SourceOfFundsType.investments:
        return 'Investments';

      case SourceOfFundsType.savings:
        return 'Savings';

      case SourceOfFundsType.pension:
        return 'Pension';

      case SourceOfFundsType.familySupport:
        return 'Family Support';

      case SourceOfFundsType.other:
        return 'Other';
    }
  }
}

enum KycStatus {
  notStarted,
  pending,
  underReview,
  verified,
  rejected,
  expired,
  unknown;

  static KycStatus fromJson(String? value) {
    return enumFromApiValue(values, value) ?? KycStatus.unknown;
  }

  String get displayName {
    switch (this) {
      case KycStatus.notStarted:
        return 'Not Started';

      case KycStatus.pending:
        return 'Pending';

      case KycStatus.underReview:
        return 'Under Review';

      case KycStatus.verified:
        return 'Verified';

      case KycStatus.rejected:
        return 'Rejected';

      case KycStatus.expired:
        return 'Expired';

      case KycStatus.unknown:
        return 'Unknown';
    }
  }
}

enum VerificationDocumentType {
  nationalIdFront,
  nationalIdBack,
  passport,
  driversLicenseFront,
  driversLicenseBack,
  proofOfAddress,
  selfie,
  unknown;

  static VerificationDocumentType fromJson(String? value) {
    return enumFromApiValue(values, value) ?? VerificationDocumentType.unknown;
  }

  String get displayName {
    switch (this) {
      case VerificationDocumentType.nationalIdFront:
        return 'National ID Front';

      case VerificationDocumentType.nationalIdBack:
        return 'National ID Back';

      case VerificationDocumentType.passport:
        return 'Passport';

      case VerificationDocumentType.driversLicenseFront:
        return "Driver's Licence Front";

      case VerificationDocumentType.driversLicenseBack:
        return "Driver's Licence Back";

      case VerificationDocumentType.proofOfAddress:
        return 'Proof of Address';

      case VerificationDocumentType.selfie:
        return 'Selfie';

      case VerificationDocumentType.unknown:
        return 'Unknown';
    }
  }
}

enum VerificationDocumentStatus {
  notSubmitted,
  uploaded,
  pending,
  verified,
  rejected,
  expired,
  unknown;

  static VerificationDocumentStatus fromJson(String? value) {
    return enumFromApiValue(values, value) ??
        VerificationDocumentStatus.unknown;
  }

  String get displayName {
    switch (this) {
      case VerificationDocumentStatus.notSubmitted:
        return 'Not Submitted';

      case VerificationDocumentStatus.uploaded:
        return 'Uploaded';

      case VerificationDocumentStatus.pending:
        return 'Pending Review';

      case VerificationDocumentStatus.verified:
        return 'Verified';

      case VerificationDocumentStatus.rejected:
        return 'Rejected';

      case VerificationDocumentStatus.expired:
        return 'Expired';

      case VerificationDocumentStatus.unknown:
        return 'Unknown';
    }
  }
}

enum PasswordResetMethod { email, phone }

enum KycReviewDecision { approve, requestChanges, reject }

enum KycReviewStatus {
  pending,
  underReview,
  verified,
  rejected,
  requiresUpdate,
  unknown;

  factory KycReviewStatus.fromJson(String? value) {
    return enumFromApiValue(values, value) ?? KycReviewStatus.unknown;
  }

  String get value => apiValue;

  String get displayName {
    switch (this) {
      case KycReviewStatus.pending:
        return 'Pending';

      case KycReviewStatus.underReview:
        return 'Under Review';

      case KycReviewStatus.verified:
        return 'Verified';

      case KycReviewStatus.rejected:
        return 'Rejected';

      case KycReviewStatus.requiresUpdate:
        return 'Requires Update';

      case KycReviewStatus.unknown:
        return 'Unknown';
    }
  }
}

extension EnumApiValue on Enum {
  String get apiValue {
    return name.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => '_${match.group(1)!.toLowerCase()}',
    );
  }
}

T? enumFromApiValue<T extends Enum>(Iterable<T> values, String? value) {
  final normalized = value?.trim().toLowerCase();

  if (normalized == null || normalized.isEmpty) {
    return null;
  }

  for (final item in values) {
    if (item.apiValue == normalized) {
      return item;
    }
  }

  return null;
}

enum LoyaltyBadgeCategory {
  wallet,
  gold,
  lending,
  community,
  merchant,
  agent,
  unknown;

  static LoyaltyBadgeCategory fromValue(Object? value) {
    return LoyaltyBadgeCategory.values.firstWhere(
      (category) => category.name == value,
      orElse: () => LoyaltyBadgeCategory.unknown,
    );
  }
}

enum GamificationNotificationType {
  pointsEarned,
  levelUp,
  levelDown,
  badgeAwarded,
  challengeCompleted,
  rewardAvailable,
  unknown;

  static GamificationNotificationType fromValue(Object? value) {
    return switch (value) {
      'points_earned' => GamificationNotificationType.pointsEarned,
      'level_up' => GamificationNotificationType.levelUp,
      'level_down' => GamificationNotificationType.levelDown,
      'badge_awarded' => GamificationNotificationType.badgeAwarded,
      'challenge_completed' => GamificationNotificationType.challengeCompleted,
      'reward_available' => GamificationNotificationType.rewardAvailable,
      _ => GamificationNotificationType.unknown,
    };
  }
}

enum GamificationIntensity { tiny, small, medium, large, epic }

GamificationIntensity gamificationIntensityFor(
  GamificationNotification notification,
) {
  final notificationType = GamificationNotificationType.fromValue(
    notification.notificationType,
  );

  switch (notificationType) {
    case GamificationNotificationType.levelUp:
      return GamificationIntensity.epic;

    case GamificationNotificationType.badgeAwarded:
      return GamificationIntensity.large;

    case GamificationNotificationType.challengeCompleted:
      return GamificationIntensity.large;

    case GamificationNotificationType.rewardAvailable:
      return GamificationIntensity.medium;

    case GamificationNotificationType.pointsEarned:
      if (notification.points >= 1000) {
        return GamificationIntensity.epic;
      }

      if (notification.points >= 500) {
        return GamificationIntensity.large;
      }

      if (notification.points >= 100) {
        return GamificationIntensity.medium;
      }

      if (notification.points >= 10) {
        return GamificationIntensity.small;
      }

      return GamificationIntensity.tiny;

    case GamificationNotificationType.levelDown:
      return GamificationIntensity.medium;

    case GamificationNotificationType.unknown:
      return GamificationIntensity.small;
  }
}
