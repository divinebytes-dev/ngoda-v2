export type SaveSignedPayloadResult = {
  success: boolean;

  queue_id: string;

  already_signed: boolean;

  signed_payload:
    Record<string, unknown>;
};