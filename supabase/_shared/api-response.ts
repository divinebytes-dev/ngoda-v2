// supabase/functions/_shared/api-response.ts

import { AppError } from "./app-error.ts";


const headers = {
    "Content-Type": "application/json",
};

export function successResponse(
    data: unknown,
    message = "SUCCESS",
    statusCode = 200,
): Response {
    return new Response(
        JSON.stringify({
            success: true,
            message,
            data,
        }),
        {
            status: statusCode,
            headers,
        },
    );
}

export function errorResponse(
    error: unknown,
    fallbackMessage = "INTERNAL_SERVER_ERROR",
): Response {
    if (error instanceof AppError) {
        return new Response(
            JSON.stringify({
                success: false,
                message: error.message,
            }),
            {
                status: error.statusCode,
                headers,
            },
        );
    }

    const message = error instanceof Error
        ? error.message
        : fallbackMessage;

    return new Response(
        JSON.stringify({
            success: false,
            message,
        }),
        {
            status: 500,
            headers,
        },
    );
}