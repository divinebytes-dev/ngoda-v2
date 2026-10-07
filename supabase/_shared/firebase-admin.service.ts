import {
  cert,
  getApps,
  initializeApp,
} from "firebase-admin/app";

import {
  getMessaging,
} from "firebase-admin/messaging";

import {
  AppError,
} from "./app-error.ts";

const projectId =
  Deno.env.get("FIREBASE_PROJECT_ID");

const clientEmail =
  Deno.env.get("FIREBASE_CLIENT_EMAIL");

const privateKey =
  Deno.env
    .get("FIREBASE_PRIVATE_KEY")
    ?.replace(/\\n/g, "\n");

if (!projectId) {
  throw new AppError(
    "ENV_FIREBASE_PROJECT_ID_MISSING",
  );
}

if (!clientEmail) {
  throw new AppError(
    "ENV_FIREBASE_CLIENT_EMAIL_MISSING",
  );
}

if (!privateKey) {
  throw new AppError(
    "ENV_FIREBASE_PRIVATE_KEY_MISSING",
  );
}

const firebaseApp =
  getApps()[0] ??
  initializeApp({
    credential: cert({
      projectId,
      clientEmail,
      privateKey,
    }),
  });

export const firebaseMessaging =
  getMessaging(firebaseApp);