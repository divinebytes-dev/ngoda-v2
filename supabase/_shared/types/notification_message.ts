import { NotificationType } from "@prisma/client";

export type NotificationMessage = {
    notificationType: NotificationType;
    title: string;
    body: string;
    payload?: Record<string, string | number>;
};

