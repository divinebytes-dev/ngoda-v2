begin;

alter table public.tokenised_asset_adjustment_request
    drop constraint if exists ngoda_gold_blockchain_required_check;

alter table public.tokenised_asset_adjustment_request
    drop constraint if exists ngoda_token_adjustment_blockchain_format_check;

alter table public.tokenised_asset_adjustment_request
    add constraint ngoda_token_adjustment_blockchain_format_check
    check (
        blockchain_code is null
        or (
            blockchain_code = lower(btrim(blockchain_code))
            and btrim(blockchain_code) <> ''
        )
    );

alter table public.tokenised_asset_adjustment_request
    add constraint ngoda_token_adjustment_execution_blockchain_check
    check (
        (
            executed_by is null
            and tx_hash is null
            and executed_at is null
        )
        or blockchain_code is not null
    );

commit;