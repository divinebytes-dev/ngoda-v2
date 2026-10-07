import {
  firebaseMessaging,
} from "./firebase-admin.service.ts";

export async function sendPushNotification({
  tokens,
  title,
  body,
  data = {},
}: {
  tokens: string[];
  title: string;
  body: string;
  data?: Record<string, string>;
}) {
  /*
   * Remove empty and duplicate device tokens.
   */
  const validTokens = [
    ...new Set(
      tokens
        .map((token) => token.trim())
        .filter((token) => token.length > 0),
    ),
  ];

  if (validTokens.length === 0) {
    return;
  }

  const messages = validTokens.map(
    (token) => ({
      token,

      notification: {
        title,
        body,
      },

      data,

      android: {
        priority: "high" as const,
      },
    }),
  );

  return await firebaseMessaging.sendEach(
    messages,
  );
}