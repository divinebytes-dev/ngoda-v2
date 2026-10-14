
CREATE OR REPLACE FUNCTION public.update_wallet_balance_snapshot(
    p_transaction_type public."TransactionType",
    p_sender_id text,
    p_receiver_id text,
    p_treasury_id text,
    p_currency_code text,
    p_sender_wallet_owner public."WalletOwnerType",
    p_receiver_wallet_owner public."WalletOwnerType",
    p_sender_amount numeric,
    p_receiver_amount numeric,
    p_fiscal_year integer,
    p_period integer,
    p_country_code text,
    p_fee_amount numeric DEFAULT 0,
    p_blockchain_code text DEFAULT NULL::text
)
RETURNS void
LANGUAGE plpgsql
AS $function$
begin
    /*
     * ==========================================================
     * VALIDATE BLOCKCHAIN FOR GOLD
     * ==========================================================
     */
    if lower(p_currency_code) = 'gold'
       and nullif(
           btrim(p_blockchain_code),
           ''
       ) is null
    then
        raise exception
            'BLOCKCHAIN_CODE_REQUIRED_FOR_GOLD';
    end if;

    /*
     * ==========================================================
     * SKIP ZERO-VALUE TRANSACTIONS
     * ==========================================================
     */
    if p_sender_amount = 0
       and p_receiver_amount = 0
       and coalesce(p_fee_amount, 0) = 0
    then
        return;
    end if;

    /*
     * ==========================================================
     * GOLD TOKEN MINTING
     * ==========================================================
     *
     * Minting increases the treasury GOLD balance.
     */
    if p_transaction_type =
       'gold_token_mint'::public."TransactionType"
    then
        if p_receiver_id is null then
            raise exception
                'TREASURY_RECEIVER_REQUIRED_FOR_MINT';
        end if;

        if p_receiver_amount <= 0 then
            raise exception
                'INVALID_GOLD_MINT_AMOUNT';
        end if;

        perform public.apply_wallet_snapshot_update(
            p_receiver_id,
            p_country_code,
            p_currency_code,
            'treasury'::public."WalletOwnerType",
            0,
            p_receiver_amount,
            p_fiscal_year,
            p_period,
            p_blockchain_code
        );

        return;
    end if;

    /*
     * ==========================================================
     * GOLD TOKEN BURNING
     * ==========================================================
     *
     * Burning decreases the treasury GOLD balance.
     */
    if p_transaction_type =
       'gold_token_burn'::public."TransactionType"
    then
        if p_sender_id is null then
            raise exception
                'TREASURY_SENDER_REQUIRED_FOR_BURN';
        end if;

        if p_sender_amount <= 0 then
            raise exception
                'INVALID_GOLD_BURN_AMOUNT';
        end if;

        perform public.apply_wallet_snapshot_update(
            p_sender_id,
            p_country_code,
            p_currency_code,
            'treasury'::public."WalletOwnerType",
            p_sender_amount,
            0,
            p_fiscal_year,
            p_period,
            p_blockchain_code
        );

        return;
    end if;

    /*
     * ==========================================================
     * TREASURY FUNDING
     * ==========================================================
     */
    if p_transaction_type =
       'treasury_funding'::public."TransactionType"
    then
        perform public.apply_wallet_snapshot_update(
            p_receiver_id,
            p_country_code,
            p_currency_code,
            p_receiver_wallet_owner,
            0,
            p_receiver_amount,
            p_fiscal_year,
            p_period,
            p_blockchain_code
        );

        return;
    end if;

    /*
     * ==========================================================
     * TREASURY FUNDING REVERSAL
     * ==========================================================
     */
    if p_transaction_type =
       'treasury_funding_reversal'::public."TransactionType"
    then
        perform public.apply_wallet_snapshot_update(
            p_receiver_id,
            p_country_code,
            p_currency_code,
            p_receiver_wallet_owner,
            p_receiver_amount,
            0,
            p_fiscal_year,
            p_period,
            p_blockchain_code
        );

        return;
    end if;

    /*
     * ==========================================================
     * VALIDATE SENDER
     * ==========================================================
     */
    if p_sender_id is null then
        raise exception
            'SENDER_REQUIRED_FOR_WALLET_SNAPSHOT';
    end if;

    /*
     * ==========================================================
     * SENDER DEBIT
     * ==========================================================
     */
    if p_sender_amount > 0 then
        perform public.apply_wallet_snapshot_update(
            p_sender_id,
            p_country_code,
            p_currency_code,
            p_sender_wallet_owner,
            p_sender_amount,
            0,
            p_fiscal_year,
            p_period,
            p_blockchain_code
        );
    end if;

    /*
     * ==========================================================
     * RECEIVER CREDIT
     * ==========================================================
     */
    if p_receiver_amount > 0 then
        if p_transaction_type <>
           'government_tax_clearing'::public."TransactionType"
        then
            perform public.apply_wallet_snapshot_update(
                p_receiver_id,
                p_country_code,
                p_currency_code,
                p_receiver_wallet_owner,
                0,
                p_receiver_amount,
                p_fiscal_year,
                p_period,
                p_blockchain_code
            );
        end if;
    end if;

    /*
     * ==========================================================
     * TREASURY FEE CREDIT
     * ==========================================================
     */
    if coalesce(p_fee_amount, 0) > 0
       and p_treasury_id is not null
    then
        perform public.apply_wallet_snapshot_update(
            p_treasury_id,
            p_country_code,
            p_currency_code,
            'treasury'::public."WalletOwnerType",
            0,
            p_fee_amount,
            p_fiscal_year,
            p_period,
            p_blockchain_code
        );
    end if;
end;
$function$;



CREATE OR REPLACE FUNCTION public.apply_wallet_snapshot_update(
    p_user_id text,
    p_country_code text,
    p_currency_code text,
    p_wallet_owner public."WalletOwnerType",
    p_debit numeric,
    p_credit numeric,
    p_fiscal_year integer,
    p_period integer,
    p_blockchain_code text DEFAULT NULL::text
)
RETURNS void
LANGUAGE plpgsql
AS $function$
declare
    v_opening numeric := 0;
    v_delta numeric;

    v_currency_code text;
    v_blockchain_code text;

    v_debit numeric;
    v_credit numeric;

begin
    /*
     * ==========================================================
     * NORMALIZE CURRENCY AND BLOCKCHAIN
     * ==========================================================
     */
    v_currency_code :=
        nullif(
            lower(btrim(p_currency_code)),
            ''
        );

    v_blockchain_code :=
        nullif(
            lower(btrim(p_blockchain_code)),
            ''
        );

    /*
     * ==========================================================
     * VALIDATE REQUIRED PARAMETERS
     * ==========================================================
     */
    if nullif(btrim(p_user_id), '') is null then
        raise exception
            'WALLET_SNAPSHOT_USER_REQUIRED';
    end if;

    if nullif(btrim(p_country_code), '') is null then
        raise exception
            'WALLET_SNAPSHOT_COUNTRY_REQUIRED';
    end if;

    if v_currency_code is null then
        raise exception
            'WALLET_SNAPSHOT_CURRENCY_REQUIRED';
    end if;

    if p_wallet_owner is null then
        raise exception
            'WALLET_SNAPSHOT_OWNER_REQUIRED';
    end if;

    if p_fiscal_year is null
       or p_period is null
       or p_period < 1
       or p_period > 12
    then
        raise exception
            'INVALID_WALLET_SNAPSHOT_PERIOD';
    end if;

    /*
     * ==========================================================
     * VALIDATE BLOCKCHAIN REQUIREMENTS
     * ==========================================================
     *
     * GOLD:
     *   blockchain_code is mandatory.
     *
     * FIAT:
     *   blockchain_code must be NULL.
     */
    if v_currency_code = 'gold' then

        if v_blockchain_code is null then
            raise exception
                'BLOCKCHAIN_CODE_REQUIRED_FOR_GOLD';
        end if;

    elsif v_blockchain_code is not null then

        raise exception
            'BLOCKCHAIN_CODE_NOT_ALLOWED_FOR_FIAT';

    end if;

    /*
     * ==========================================================
     * NORMALIZE DEBIT AND CREDIT
     * ==========================================================
     */
    v_debit :=
        coalesce(p_debit, 0);

    v_credit :=
        coalesce(p_credit, 0);

    if v_debit < 0 or v_credit < 0 then
        raise exception
            'NEGATIVE_WALLET_SNAPSHOT_AMOUNT_NOT_ALLOWED';
    end if;

    /*
     * ==========================================================
     * SKIP ZERO-VALUE UPDATES
     * ==========================================================
     */
    if v_debit = 0 and v_credit = 0 then
        return;
    end if;

    v_delta :=
        v_credit - v_debit;

    /*
     * ==========================================================
     * FIRST: EXACT CURRENT SNAPSHOT
     * ==========================================================
     */
    select
        s.closing_balance
    into
        v_opening
    from public.wallet_balance_snapshot s
    where s.user_id = p_user_id
      and s.country_code = p_country_code
      and s.currency_code = v_currency_code
      and s.wallet_owner = p_wallet_owner
      and s.blockchain_code is not distinct from
          v_blockchain_code
      and s.fiscal_year = p_fiscal_year
      and s.period = p_period;

    /*
     * ==========================================================
     * SECOND: PREVIOUS PERIOD IN SAME FISCAL YEAR
     * ==========================================================
     */
    if not found then

        select
            s.closing_balance
        into
            v_opening
        from public.wallet_balance_snapshot s
        where s.user_id = p_user_id
          and s.country_code = p_country_code
          and s.currency_code = v_currency_code
          and s.wallet_owner = p_wallet_owner
          and s.blockchain_code is not distinct from
              v_blockchain_code
          and s.fiscal_year = p_fiscal_year
          and s.period < p_period
        order by
            s.period desc
        limit 1;

    end if;

    /*
     * ==========================================================
     * THIRD: LATEST PREVIOUS FISCAL YEAR
     * ==========================================================
     */
    if not found then

        select
            s.closing_balance
        into
            v_opening
        from public.wallet_balance_snapshot s
        where s.user_id = p_user_id
          and s.country_code = p_country_code
          and s.currency_code = v_currency_code
          and s.wallet_owner = p_wallet_owner
          and s.blockchain_code is not distinct from
              v_blockchain_code
          and s.fiscal_year < p_fiscal_year
        order by
            s.fiscal_year desc,
            s.period desc
        limit 1;

    end if;

    v_opening :=
        coalesce(v_opening, 0);

    /*
     * ==========================================================
     * FIAT SNAPSHOT
     * ==========================================================
     *
     * Fiat balances have no blockchain_code.
     */
    if v_blockchain_code is null then

        insert into public.wallet_balance_snapshot
            as current_snapshot (
                user_id,
                country_code,
                currency_code,
                wallet_owner,
                blockchain_code,
                fiscal_year,
                period,
                opening_balance,
                debit,
                credit,
                closing_balance,
                created_at,
                updated_at
            )
        values (
            p_user_id,
            p_country_code,
            v_currency_code,
            p_wallet_owner,
            null,
            p_fiscal_year,
            p_period,
            v_opening,
            v_debit,
            v_credit,
            v_opening + v_delta,
            now(),
            now()
        )
        on conflict (
            user_id,
            currency_code,
            wallet_owner,
            fiscal_year,
            period
        )
        where blockchain_code is null

        do update
        set
            debit =
                current_snapshot.debit +
                excluded.debit,

            credit =
                current_snapshot.credit +
                excluded.credit,

            closing_balance =
                current_snapshot.closing_balance +
                excluded.credit -
                excluded.debit,

            updated_at =
                now();

    /*
     * ==========================================================
     * BLOCKCHAIN-SPECIFIC GOLD SNAPSHOT
     * ==========================================================
     */
    else

        insert into public.wallet_balance_snapshot
            as current_snapshot (
                user_id,
                country_code,
                currency_code,
                wallet_owner,
                blockchain_code,
                fiscal_year,
                period,
                opening_balance,
                debit,
                credit,
                closing_balance,
                created_at,
                updated_at
            )
        values (
            p_user_id,
            p_country_code,
            v_currency_code,
            p_wallet_owner,
            v_blockchain_code,
            p_fiscal_year,
            p_period,
            v_opening,
            v_debit,
            v_credit,
            v_opening + v_delta,
            now(),
            now()
        )
        on conflict (
            user_id,
            currency_code,
            wallet_owner,
            blockchain_code,
            fiscal_year,
            period
        )
        where blockchain_code is not null

        do update
        set
            debit =
                current_snapshot.debit +
                excluded.debit,

            credit =
                current_snapshot.credit +
                excluded.credit,

            closing_balance =
                current_snapshot.closing_balance +
                excluded.credit -
                excluded.debit,

            updated_at =
                now();

    end if;

end;
$function$;
