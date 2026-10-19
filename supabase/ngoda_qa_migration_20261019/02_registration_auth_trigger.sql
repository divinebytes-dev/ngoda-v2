BEGIN;

CREATE TRIGGER ngoda_record_registration_auth_creation
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION ngoda_private.record_registration_auth_creation();

COMMIT;