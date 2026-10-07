import { AppError } from "./app-error.ts";

export function normalizePhoneNumber(
  phone: string,
  callingCode: string,
): string {
  let value = phone.trim();

  /*
   * Remove spaces, brackets and hyphens.
   */
  value = value.replace(
    /[\s()-]/g,
    "",
  );

  /*
   * Already E.164.
   *
   * +263772801122
   */
  if (value.startsWith("+")) {
    const digits = value.substring(1);

    if (!/^\d+$/.test(digits)) {
      throw new AppError(
        "INVALID_PHONE_NUMBER",
      );
    }

    if (!digits.startsWith(callingCode)) {
      throw new AppError(
        "PHONE_COUNTRY_CODE_MISMATCH",
      );
    }

    return `+${digits}`;
  }

  /*
   * International 00 notation.
   *
   * 00263772801122
   * ->
   * +263772801122
   */
  if (value.startsWith("00")) {
    const digits = value.substring(2);

    if (
      !/^\d+$/.test(digits) ||
      !digits.startsWith(callingCode)
    ) {
      throw new AppError(
        "INVALID_PHONE_NUMBER",
      );
    }

    return `+${digits}`;
  }

  /*
   * Calling code supplied without +.
   *
   * 263772801122
   * ->
   * +263772801122
   */
  if (value.startsWith(callingCode)) {
    if (!/^\d+$/.test(value)) {
      throw new AppError(
        "INVALID_PHONE_NUMBER",
      );
    }

    return `+${value}`;
  }

  /*
   * Local number.
   *
   * 0772801122
   * ->
   * remove leading trunk 0
   * ->
   * +263772801122
   */
  if (value.startsWith("0")) {
    value = value.substring(1);
  }

  if (
    !value ||
    !/^\d+$/.test(value)
  ) {
    throw new AppError(
      "INVALID_PHONE_NUMBER",
    );
  }

  return `+${callingCode}${value}`;
}