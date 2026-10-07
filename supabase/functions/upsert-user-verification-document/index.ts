import {
  errorResponse,
  successResponse,
} from "../../_shared/api-response.ts";

import {
  AppError,
} from "../../_shared/app-error.ts";

import {
  createSupabaseClient,
} from "../../_shared/supabase-client.ts";


const VERIFICATION_BUCKET =
  "user-verification";


const ALLOWED_CONTENT_TYPES =
  new Set([
    "image/jpeg",
    "image/png",
    "image/webp",
    "application/pdf",
  ]);


/*
 * 10 MB maximum verification document.
 */
const MAX_FILE_SIZE =
  10 * 1024 * 1024;


/*
 * ============================================================
 * REQUIRED STRING
 * ============================================================
 */
function parseRequiredString(
  value: FormDataEntryValue | null,
  errorMessage: string,
): string {
  if (
    typeof value !== "string" ||
    value.trim() === ""
  ) {
    throw new AppError(
      errorMessage,
      400,
    );
  }

  return value.trim();
}


/*
 * ============================================================
 * FILE EXTENSION
 *
 * We derive the stored extension from the validated MIME type
 * instead of trusting the original filename.
 * ============================================================
 */
function getFileExtension(
  contentType: string,
): string {
  switch (contentType) {
    case "image/jpeg":
      return "jpg";

    case "image/png":
      return "png";

    case "image/webp":
      return "webp";

    case "application/pdf":
      return "pdf";

    default:
      throw new AppError(
        "INVALID_DOCUMENT_FILE_TYPE",
        400,
      );
  }
}


Deno.serve(async (request: Request) => {
  let uploadedPath:
    string | null = null;

  try {

    // ========================================================
    // METHOD
    // ========================================================

    if (request.method !== "POST") {
      throw new AppError(
        "METHOD_NOT_ALLOWED",
        405,
      );
    }


    // ========================================================
    // CONTENT TYPE
    // ========================================================

    const contentType =
      request.headers.get(
        "content-type",
      );


    if (
      !contentType ||
      !contentType
        .toLowerCase()
        .includes(
          "multipart/form-data",
        )
    ) {
      throw new AppError(
        "MULTIPART_FORM_DATA_REQUIRED",
        400,
      );
    }


    // ========================================================
    // FORM DATA
    // ========================================================

    let formData:
      FormData;


    try {
      formData =
        await request.formData();
    } catch {
      throw new AppError(
        "INVALID_FORM_DATA",
        400,
      );
    }


    // ========================================================
    // DOCUMENT TYPE
    //
    // JSON/API field naming remains camelCase:
    //
    // documentType = id_front
    //
    // id_front remains snake_case because it is the actual
    // VerificationDocumentType enum value.
    // ========================================================

    const documentType =
      parseRequiredString(
        formData.get(
          "documentType",
        ),
        "DOCUMENT_TYPE_MISSING",
      )
        .toLowerCase();


    // ========================================================
    // FILE
    // ========================================================

    const fileEntry =
      formData.get(
        "file",
      );


    if (
      !(fileEntry instanceof File)
    ) {
      throw new AppError(
        "DOCUMENT_FILE_MISSING",
        400,
      );
    }


    const file =
      fileEntry;


    if (file.size <= 0) {
      throw new AppError(
        "DOCUMENT_FILE_EMPTY",
        400,
      );
    }


    if (
      file.size >
        MAX_FILE_SIZE
    ) {
      throw new AppError(
        "DOCUMENT_FILE_TOO_LARGE",
        400,
      );
    }


    if (
      !ALLOWED_CONTENT_TYPES.has(
        file.type,
      )
    ) {
      throw new AppError(
        "INVALID_DOCUMENT_FILE_TYPE",
        400,
      );
    }


    const extension =
      getFileExtension(
        file.type,
      );


    // ========================================================
    // AUTHENTICATED CLIENT
    // ========================================================

    const supabase =
      createSupabaseClient(
        request,
      );


    // ========================================================
    // AUTHENTICATED USER
    // ========================================================

    const {
      data: userData,
      error: userError,
    } =
      await supabase.auth.getUser();


    if (
      userError ||
      !userData.user
    ) {
      throw new AppError(
        "UNAUTHORIZED",
        401,
      );
    }


    const userId =
      userData.user.id;


    // ========================================================
    // STORAGE PATH
    //
    // Bucket:
    //
    // user-verification
    //
    // Object:
    //
    // <user-id>/<document-type>/<uuid>.<extension>
    //
    // Example:
    //
    // abc123/id_front/
    // 76f7089d-44e4-4551-ae39-9fece920329b.jpg
    // ========================================================

    const objectId =
      crypto.randomUUID();


    uploadedPath =
      `${userId}/${documentType}/${objectId}.${extension}`;


    // ========================================================
    // UPLOAD FILE
    //
    // This uses the authenticated Supabase client.
    //
    // Storage RLS should allow authenticated users to upload
    // only underneath their own auth.uid() folder.
    // ========================================================

    const {
      error: uploadError,
    } =
      await supabase.storage
        .from(
          VERIFICATION_BUCKET,
        )
        .upload(
          uploadedPath,
          file,
          {
            contentType:
              file.type,

            upsert:
              false,
          },
        );


    if (uploadError) {
      console.error(
        "VERIFICATION_DOCUMENT_UPLOAD_FAILED",
        {
          userId,
          documentType,
          path:
            uploadedPath,

          message:
            uploadError.message,
        },
      );


      throw new AppError(
        uploadError.message ||
          "VERIFICATION_DOCUMENT_UPLOAD_FAILED",
        400,
      );
    }


    // ========================================================
    // CREATE DATABASE RECORD
    //
    // The database stores the private Storage object path,
    // not the image bytes.
    // ========================================================

    const {
      data,
      error,
    } = await supabase.rpc(
      "submit_my_verification_document",
      {
        p_document_type:
          documentType,

        p_storage_path:
          uploadedPath,

        p_file_name:
          file.name,
      },
    );


    // ========================================================
    // RPC ERROR
    //
    // If Storage succeeded but DB insertion failed, remove the
    // newly uploaded object so we don't leave an orphan file.
    // ========================================================

    if (error) {
      console.error(
        "SUBMIT_MY_VERIFICATION_DOCUMENT_RPC_FAILED",
        {
          code:
            error.code,

          message:
            error.message,

          details:
            error.details,

          hint:
            error.hint,
        },
      );


      const {
        error: removeError,
      } =
        await supabase.storage
          .from(
            VERIFICATION_BUCKET,
          )
          .remove([
            uploadedPath,
          ]);


      if (removeError) {
        console.error(
          "VERIFICATION_DOCUMENT_ROLLBACK_FAILED",
          {
            path:
              uploadedPath,

            message:
              removeError.message,
          },
        );
      }


      uploadedPath =
        null;


      throw new AppError(
        error.message ||
          "SUBMIT_VERIFICATION_DOCUMENT_FAILED",
      );
    }


    // ========================================================
    // RESULT
    // ========================================================

    if (
      data === null ||
      typeof data !== "object" ||
      Array.isArray(data)
    ) {
      throw new AppError(
        "INVALID_VERIFICATION_DOCUMENT_RESULT",
      );
    }


    // ========================================================
    // SUCCESS
    // ========================================================

    uploadedPath =
      null;


    return successResponse(
      data,
    );

  } catch (error) {

    console.error(
      "SUBMIT_MY_VERIFICATION_DOCUMENT_ERROR",
      {
        error:
          error instanceof Error
            ? error.message
            : String(error),
      },
    );


    return errorResponse(
      error,
      "SUBMIT_VERIFICATION_DOCUMENT_FAILED",
    );
  }
});