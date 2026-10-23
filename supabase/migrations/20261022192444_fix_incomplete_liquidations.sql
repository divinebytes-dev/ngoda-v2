BEGIN;

CREATE OR REPLACE FUNCTION public.fetch_liquidation_reconciliation_context(p_job_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_job_id text;
    v_result jsonb;
begin
    if coalesce(
        auth.role(),
        ''
    ) <> 'service_role'
    then
        raise exception using
            errcode = '42501',
            message = 'SERVICE_ROLE_REQUIRED';
    end if;

    v_job_id :=
        nullif(
            btrim(
                p_job_id
            ),
            ''
        );

    if v_job_id is null then
        raise exception
            'LIQUIDATION_JOB_ID_REQUIRED';
    end if;

    select jsonb_build_object(
        'blockchain_code',
        queue_record.blockchain_code,

        'queue_id',
        queue_record.id::text,

        'liquidation_job_id',
        job_record.id::text,

        'job_status',
        job_record.status::text,

        'queue_status',
        queue_record.status::text,

        'manual_review_required',
        queue_record.manual_review_required,

        'country_code',
        lower(
            btrim(
                job_record.country_code
            )
        ),

        'document_number',
        job_record.document_number,

        'sender_wallet_address',
        queue_record.sender_wallet_address,

        'receiver_wallet_address',
        coalesce(
            nullif(
                btrim(
                    queue_record.signed_payload ->> 'to'
                ),
                ''
            ),
            queue_record.receiver_wallet_address
        ),

        'collateral',
        trim_scale(
            queue_record.collateral
        )::text,

        'tx_hash',
        queue_record.tx_hash,

        'signed_payload',
        queue_record.signed_payload
    )
    into v_result
    from public.liquidation_job
        job_record

    join public.liquidation_blockchain_queue
        queue_record
      on queue_record.liquidation_job_id =
         job_record.id::text

    where job_record.id::text =
          v_job_id

      and queue_record.id::text = job_record.blockchain_queue_id
      and queue_record.user_id = job_record.user_id
      and queue_record.blockchain_code = job_record.blockchain_code
      and lower(btrim(queue_record.country_code)) = lower(btrim(job_record.country_code))
      and queue_record.manual_review_required = true;

    if v_result is null then
        raise exception
            'LIQUIDATION_RECONCILIATION_CONTEXT_NOT_FOUND';
    end if;

    return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.confirm_liquidation_blockchain_transfer(p_queue_id text, p_tx_hash text, p_explorer_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_queue public.liquidation_blockchain_queue%rowtype;
    v_existing_tx public.blockchain_transaction%rowtype;

    v_queue_id text;
    v_tx_hash text;
    v_receiver text;
    v_explorer_url text;
BEGIN
    IF coalesce(auth.role(), '') <> 'service_role' THEN
        RAISE EXCEPTION USING
            ERRCODE = '42501',
            MESSAGE = 'SERVICE_ROLE_REQUIRED';
    END IF;

    v_queue_id := nullif(btrim(p_queue_id), '');
    v_tx_hash := nullif(btrim(p_tx_hash), '');
    v_explorer_url := nullif(btrim(p_explorer_url), '');

    IF v_queue_id IS NULL THEN
        RAISE EXCEPTION 'LIQUIDATION_QUEUE_ID_REQUIRED';
    END IF;

    IF v_tx_hash IS NULL
       OR v_tx_hash !~ '^0x[0-9A-Fa-f]{64}$'
    THEN
        RAISE EXCEPTION 'INVALID_BLOCKCHAIN_TRANSACTION_HASH';
    END IF;

    SELECT q.*
    INTO v_queue
    FROM public.liquidation_blockchain_queue AS q
    WHERE q.id = v_queue_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'LIQUIDATION_BLOCKCHAIN_QUEUE_NOT_FOUND';
    END IF;

    IF nullif(btrim(v_queue.blockchain_code), '') IS NULL THEN
        RAISE EXCEPTION 'LIQUIDATION_BLOCKCHAIN_CODE_REQUIRED';
    END IF;

    IF (v_queue.signed_payload ->> 'blockchain_code')
       IS DISTINCT FROM v_queue.blockchain_code
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_SIGNED_BLOCKCHAIN_MISMATCH';
    END IF;

    PERFORM 1
    FROM public.liquidation_job AS j
    WHERE j.id::text = v_queue.liquidation_job_id
      AND j.user_id = v_queue.user_id
      AND lower(btrim(j.country_code)) =
          lower(btrim(v_queue.country_code))
      AND j.blockchain_code = v_queue.blockchain_code;

    IF NOT FOUND THEN
        RAISE EXCEPTION
            'LIQUIDATION_JOB_BLOCKCHAIN_MISMATCH_OR_NOT_FOUND';
    END IF;

    IF v_queue.tx_hash IS NOT NULL
       AND lower(btrim(v_queue.tx_hash)) <> lower(v_tx_hash)
    THEN
        RAISE EXCEPTION 'LIQUIDATION_BLOCKCHAIN_TX_HASH_MISMATCH';
    END IF;

    /*
     * Preserve idempotency without moving an already
     * completed accounting job back to blockchain_confirmed.
     */
    IF v_queue.status::text = 'confirmed' THEN
        IF v_queue.tx_hash IS NULL THEN
            RAISE EXCEPTION
                'CONFIRMED_LIQUIDATION_TX_HASH_REQUIRED';
        END IF;

        RETURN jsonb_build_object(
            'success', true,
            'queue_id', v_queue.id,
            'liquidation_job_id', v_queue.liquidation_job_id,
            'status', v_queue.status,
            'tx_hash', v_queue.tx_hash,
            'confirmed_at', v_queue.confirmed_at
        );
    END IF;

    /*
     * PostgreSQL records the receipt result supplied by
     * the service worker; it does not fetch the receipt itself.
     */
    PERFORM 1
    FROM public.liquidation_blockchain_queue AS other_queue
    WHERE lower(btrim(other_queue.tx_hash)) = lower(v_tx_hash)
      AND other_queue.id <> v_queue.id;

    IF FOUND THEN
        RAISE EXCEPTION
            'LIQUIDATION_BLOCKCHAIN_TX_HASH_ALREADY_ASSIGNED';
    END IF;

    v_receiver :=
        nullif(btrim(v_queue.signed_payload ->> 'to'), '');

    IF v_receiver IS NULL
       OR v_receiver !~ '^0x[0-9A-Fa-f]{40}$'
    THEN
        RAISE EXCEPTION
            'INVALID_LIQUIDATION_BLOCKCHAIN_RECEIVER';
    END IF;

    IF lower(v_receiver)
       IS DISTINCT FROM lower(v_queue.receiver_wallet_address)
    THEN
        RAISE EXCEPTION
            'LIQUIDATION_RECEIVER_ADDRESS_MISMATCH';
    END IF;

    /*
     * Check an existing audit row instead of silently
     * accepting a hash belonging to a different operation.
     */
    SELECT bt.*
    INTO v_existing_tx
    FROM public.blockchain_transaction AS bt
    WHERE lower(btrim(bt.tx_hash)) = lower(v_tx_hash);

    IF FOUND THEN
        IF v_existing_tx.transaction_type IS DISTINCT FROM
           'loan_liquidation'::public."TransactionType"
           OR v_existing_tx.chain IS DISTINCT FROM
              v_queue.blockchain_code
           OR (v_existing_tx.blockchain_code IS NOT NULL
               AND v_existing_tx.blockchain_code IS DISTINCT FROM v_queue.blockchain_code)
           OR lower(btrim(v_existing_tx.country_code)) IS DISTINCT FROM lower(btrim(v_queue.country_code))
           OR v_existing_tx.fiscal_year IS DISTINCT FROM v_queue.fiscal_year
           OR v_existing_tx.period IS DISTINCT FROM v_queue.period
           OR v_existing_tx.currency_code IS DISTINCT FROM 'gold'
           OR v_existing_tx.gross_amount IS DISTINCT FROM v_queue.total_debt
           OR v_existing_tx.net_amount IS DISTINCT FROM v_queue.debt_repayment_amount
           OR v_existing_tx.fee_amount IS DISTINCT FROM v_queue.penalty_amount
           OR v_existing_tx.reference IS DISTINCT FROM
              v_queue.document_number
           OR v_existing_tx.document_number IS DISTINCT FROM
              v_queue.document_number
           OR lower(v_existing_tx.sender) IS DISTINCT FROM
              lower(v_queue.sender_wallet_address)
           OR lower(v_existing_tx.receiver) IS DISTINCT FROM
              lower(v_receiver)
           OR v_existing_tx.quantity IS DISTINCT FROM
              v_queue.collateral
        THEN
            RAISE EXCEPTION
                'LIQUIDATION_BLOCKCHAIN_AUDIT_MISMATCH';
        END IF;
        -- Fill only a validated matching legacy audit record, never a ledger entry.
        UPDATE public.blockchain_transaction
        SET blockchain_code=v_queue.blockchain_code
        WHERE id=v_existing_tx.id AND blockchain_code IS NULL;
    ELSE
        INSERT INTO public.blockchain_transaction (
            document_number,
            fiscal_year,
            country_code,
            period,
            tx_hash,
            reference,
            transaction_type,
            chain,
            blockchain_code,
            sender,
            receiver,
            quantity,
            gross_amount,
            net_amount,
            fee_amount,
            currency_code,
            chain_status,
            status,
            description,
            explorer_url,
            created_by
        )
        VALUES (
            v_queue.document_number,
            v_queue.fiscal_year,
            lower(btrim(v_queue.country_code)),
            v_queue.period,
            v_tx_hash,
            v_queue.document_number,
            'loan_liquidation'::public."TransactionType",

            -- Selected blockchain code, replacing 'chiado'.
            v_queue.blockchain_code,
            v_queue.blockchain_code,

            v_queue.sender_wallet_address,
            v_receiver,
            v_queue.collateral,
            v_queue.total_debt,
            v_queue.debt_repayment_amount,
            v_queue.penalty_amount,
            'gold',
            'completed',
            'completed'::public."BlockchainTxStatus",
            format(
                'Loan liquidation blockchain transfer for user %s',
                v_queue.user_id
            ),
            v_explorer_url,
            'system'
        );
    END IF;

    UPDATE public.liquidation_blockchain_queue
    SET
        status =
            'confirmed'::public."BlockchainLiquidationStatus",
        tx_hash = v_tx_hash,
        receiver_wallet_address = v_receiver,
        explorer_url = v_explorer_url,
        submitted_at = coalesce(submitted_at, now()),
        confirmed_at = coalesce(confirmed_at, now()),
        manual_review_required = false,
        error_message = NULL,
        lease_expires_at = NULL,
        updated_at = now()
    WHERE id = v_queue.id
    RETURNING * INTO v_queue;

    UPDATE public.liquidation_job
    SET
        status =
            'blockchain_confirmed'::public."LiquidationJobStatus",
        error_message = NULL
    WHERE id::text = v_queue.liquidation_job_id
      AND blockchain_code = v_queue.blockchain_code
      AND status::text IN (
          'pending',
          'blockchain_processing',
          'failed',
          'blockchain_confirmed'
      );

    IF NOT FOUND THEN
        RAISE EXCEPTION 'INVALID_LIQUIDATION_JOB_STATE';
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'queue_id', v_queue.id,
        'liquidation_job_id', v_queue.liquidation_job_id,
        'status', v_queue.status,
        'tx_hash', v_queue.tx_hash,
        'confirmed_at', v_queue.confirmed_at
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fetch_my_manual_review_liquidation_job(p_job_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_user public.users%rowtype;
    v_job_id text;
    v_result jsonb;
begin
    if auth.uid() is null then
        raise exception using
            errcode = '42501',
            message = 'UNAUTHORIZED';
    end if;

    if not public.has_role(
        array[
            'accounts',
            'finance'
        ]::text[]
    ) then
        raise exception using
            errcode = '42501',
            message = 'FORBIDDEN';
    end if;

    v_user :=
        public.fetch_user_by_id(
            auth.uid()::text
        );

    if v_user.id is null then
        raise exception
            'REPORTING_USER_NOT_FOUND';
    end if;

    if v_user.status <>
       'active'::public."UserStatus"
    then
        raise exception
            'REPORTING_USER_NOT_ACTIVE';
    end if;

    if nullif(
        btrim(
            v_user.country_code
        ),
        ''
    ) is null
    then
        raise exception
            'USER_COUNTRY_NOT_CONFIGURED';
    end if;

    v_job_id :=
        nullif(
            btrim(
                p_job_id
            ),
            ''
        );

    if v_job_id is null then
        raise exception
            'LIQUIDATION_JOB_ID_REQUIRED';
    end if;

    select jsonb_build_object(
        'queue_id',
        queue_record.id::text,

        'liquidation_job_id',
        job_record.id::text,

        'manual_review_required',
        queue_record.manual_review_required,

        'document',
        jsonb_build_object(
            'document_number',
            job_record.document_number,

            'fiscal_year',
            job_record.fiscal_year,

            'period',
            job_record.period,

            'country_code',
            lower(
                btrim(
                    job_record.country_code
                )
            )
        ),

        'customer',
        jsonb_build_object(
            'user_id',
            job_record.user_id,

            'email',
            customer_record.email,

            'phone',
            customer_record.phone,

            'first_name',
            customer_record.first_name,

            'surname',
            customer_record.surname
        ),

        'status',
        jsonb_build_object(
            'job_status',
            job_record.status::text,

            'queue_status',
            queue_record.status::text,

            'job_error',
            job_record.error_message,

            'queue_error',
            queue_record.error_message,

            'attempt_count',
            queue_record.attempt_count,

            'retry_count',
            queue_record.retry_count
        ),

        'expected_transfer',
        jsonb_build_object(
            'chain',
            'chiado',

            'transaction_type',
            'loan_liquidation',

            'from',
            queue_record.sender_wallet_address,

            'to',
            coalesce(
                nullif(
                    btrim(
                        queue_record.signed_payload ->> 'to'
                    ),
                    ''
                ),
                queue_record.receiver_wallet_address
            ),

            'currency_code',
            'gold',

            'amount',
            trim_scale(
                queue_record.collateral
            )::text,

            'raw_amount',
            nullif(
                btrim(
                    queue_record.signed_payload ->> 'parsedAmount'
                ),
                ''
            ),

            'permit_owner',
            nullif(
                btrim(
                    queue_record.signed_payload ->> 'owner'
                ),
                ''
            ),

            'permit_nonce',
            nullif(
                btrim(
                    queue_record.signed_payload ->> 'nonce'
                ),
                ''
            ),

            'permit_deadline',
            case
                when queue_record.signed_payload ->> 'deadline'
                     ~ '^[0-9]+$'
                then to_timestamp(
                    (
                        queue_record.signed_payload ->>
                        'deadline'
                    )::double precision
                )
                else null
            end,

            'permit_expired',
            case
                when queue_record.signed_payload ->> 'deadline'
                     ~ '^[0-9]+$'
                then to_timestamp(
                    (
                        queue_record.signed_payload ->>
                        'deadline'
                    )::double precision
                ) < now()
                else null
            end
        ),

        'liquidation_values',
        jsonb_build_object(
            'principal',
            trim_scale(
                job_record.total_principal
            )::text,

            'interest',
            trim_scale(
                job_record.total_interest
            )::text,

            'total_debt',
            trim_scale(
                job_record.total_debt
            )::text,

            'repayment_required',
            trim_scale(
                job_record.repayment_required
            )::text,

            'penalty_amount',
            trim_scale(
                job_record.penalty_amount
            )::text,

            'total_proceeds',
            trim_scale(
                job_record.total_required
            )::text,

            'collateral_required',
            trim_scale(
                job_record.collateral_required
            )::text,

            'gold_price',
            trim_scale(
                job_record.gold_price
            )::text
        ),

        'blockchain_evidence',
        jsonb_build_object(
            'queue_tx_hash',
            queue_record.tx_hash,

            'recorded_tx_hash',
            blockchain_record.tx_hash,

            'blockchain_transaction_id',
            blockchain_record.id,

            'transaction_status',
            blockchain_record.status,

            'chain_status',
            blockchain_record.chain_status,

            'explorer_url',
            coalesce(
                queue_record.explorer_url,
                blockchain_record.explorer_url
            ),

            'submitted_at',
            queue_record.submitted_at,

            'confirmed_at',
            queue_record.confirmed_at,

            'recorded_at',
            blockchain_record.created_at
        ),

        'timeline',
        jsonb_build_object(
            'created_at',
            queue_record.created_at,

            'processing_started_at',
            queue_record.processing_started_at,

            'last_attempt_at',
            queue_record.last_attempt_at,

            'signed_at',
            queue_record.signed_at,

            'claimed_at',
            queue_record.claimed_at
        ),

        'recommended_action',
        case
            when nullif(
                btrim(
                    queue_record.tx_hash
                ),
                ''
            ) is null
            then jsonb_build_object(
                'code',
                'VERIFY_ON_CHAIN',

                'message',
                'Search the saved blockchain for the expected Gold transfer before changing this job.',

                'success_result',
                'A trusted service must verify and record the transaction hash, then confirm the transfer.',

                'not_found_result',
                'If the permit nonce is unchanged and no transfer exists, clear the expired signature and retry.',

                'uncertain_result',
                'If the nonce advanced but the matching transfer is not identified, keep manual review enabled.'
            )

            when queue_record.status::text = 'confirmed'
                 and blockchain_record.id is not null
            then jsonb_build_object(
                'code',
                'RESUME_ACCOUNTING',

                'message',
                'Blockchain confirmation is recorded. Resume liquidation accounting.'
            )

            else jsonb_build_object(
                'code',
                'VERIFY_STORED_TRANSACTION',

                'message',
                'Verify the stored hash, successful receipt and exact Gold transfer event before continuing.'
            )
        end,

        'verification_requirements',
        jsonb_build_array(
            'The transaction receipt succeeded on the saved blockchain.',
            'The token contract is the configured Gold token contract.',
            'The transfer sender equals expected_transfer.from.',
            'The transfer receiver equals expected_transfer.to.',
            'The raw token amount equals expected_transfer.raw_amount.',
            'The permit nonce belongs to expected_transfer.permit_owner.'
        )
    )
    into v_result
    from public.liquidation_job
        job_record

    join public.liquidation_blockchain_queue
        queue_record
      on queue_record.liquidation_job_id =
         job_record.id::text

    left join public.users
        customer_record
      on customer_record.id =
         job_record.user_id

    left join lateral (
        select transaction_record.*
        from public.blockchain_transaction
            transaction_record
        where (
            nullif(
                btrim(
                    queue_record.tx_hash
                ),
                ''
            ) is not null

            and lower(
                transaction_record.tx_hash
            ) = lower(
                btrim(
                    queue_record.tx_hash
                )
            )
        )

        or (
            nullif(
                btrim(
                    queue_record.tx_hash
                ),
                ''
            ) is null

            and transaction_record.document_number =
                job_record.document_number

            and transaction_record.transaction_type =
                'loan_liquidation'::public."TransactionType"
        )
        order by
            transaction_record.created_at desc
        limit 1
    ) as blockchain_record
      on true

    where job_record.id::text =
          v_job_id

      and queue_record.manual_review_required = true

      and lower(
          btrim(
              job_record.country_code
          )
      ) = lower(
          btrim(
              v_user.country_code
          )
      );

    if v_result is null then
        raise exception
            'MANUAL_REVIEW_LIQUIDATION_JOB_NOT_FOUND';
    end if;

    return v_result;
end;
$function$;

ALTER FUNCTION public.fetch_liquidation_reconciliation_context(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fetch_liquidation_reconciliation_context(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fetch_liquidation_reconciliation_context(text) TO service_role;

ALTER FUNCTION public.confirm_liquidation_blockchain_transfer(text,text,text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.confirm_liquidation_blockchain_transfer(text,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.confirm_liquidation_blockchain_transfer(text,text,text) TO service_role;

ALTER FUNCTION public.fetch_my_manual_review_liquidation_job(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION public.fetch_my_manual_review_liquidation_job(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.fetch_my_manual_review_liquidation_job(text) TO authenticated;

COMMIT;
