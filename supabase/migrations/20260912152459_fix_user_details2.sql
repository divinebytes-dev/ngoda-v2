create type public."VerificationDocumentType" as enum (
  'id_front',
  'id_back',
  'proof_of_address',
  'selfie'
);

create table public.user_verification_document (
  id text not null default gen_random_uuid()::text,
  user_id text not null,

  document_type public."VerificationDocumentType" not null,

  url text not null,
  file_name text null,

  status public."KycStatus" not null default 'pending'::public."KycStatus",

  uploaded_at timestamptz not null default now(),

  verified_by text null,
  verified_at timestamptz null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by text null,

  constraint user_verification_document_pkey
    primary key (id),

  constraint user_verification_document_user_id_fkey
    foreign key (user_id)
    references public.users (id)
    on update cascade
    on delete cascade
);

create index if not exists user_verification_document_user_id_idx
on public.user_verification_document (user_id);

create index if not exists user_verification_document_user_status_idx
on public.user_verification_document (
  user_id,
  status
);

create index if not exists user_verification_document_type_idx
on public.user_verification_document (
  user_id,
  document_type
);

create trigger user_verification_document_no_delete
before delete on public.user_verification_document
for each row
execute function public.ngoda_prevent_delete();