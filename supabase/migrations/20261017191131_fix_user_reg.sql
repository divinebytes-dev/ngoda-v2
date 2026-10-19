BEGIN;
CREATE SCHEMA IF NOT EXISTS ngoda_private;
REVOKE ALL ON SCHEMA ngoda_private FROM PUBLIC,anon,authenticated;
CREATE TABLE ngoda_private.registration_auth_creation (
    user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    attempt_id uuid NOT NULL UNIQUE,
    recorded_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE ngoda_private.registration_auth_creation ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ngoda_private.registration_auth_creation FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION ngoda_private.record_registration_auth_creation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_attempt text;
BEGIN
    v_attempt := NEW.raw_user_meta_data ->> 'ngoda_registration_attempt';
    IF v_attempt IS NULL OR v_attempt !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
        RETURN NEW;
    END IF;
    INSERT INTO ngoda_private.registration_auth_creation(user_id,attempt_id)
    VALUES(NEW.id,v_attempt::uuid);
    RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION ngoda_private.record_registration_auth_creation() FROM PUBLIC,anon,authenticated,service_role;
CREATE TRIGGER ngoda_record_registration_auth_creation
AFTER INSERT ON auth.users FOR EACH ROW
EXECUTE FUNCTION ngoda_private.record_registration_auth_creation();

CREATE OR REPLACE FUNCTION public.verify_registration_auth_creation(p_user_id uuid,p_attempt_id uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
BEGIN
    IF coalesce(auth.role(),'') <> 'service_role' THEN
        RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='SERVICE_ROLE_REQUIRED';
    END IF;
    RETURN EXISTS (
        SELECT 1 FROM ngoda_private.registration_auth_creation r
        WHERE r.user_id=p_user_id AND r.attempt_id=p_attempt_id
    );
END;
$function$;
REVOKE ALL ON FUNCTION public.verify_registration_auth_creation(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.verify_registration_auth_creation(uuid,uuid) TO service_role;
COMMIT;
