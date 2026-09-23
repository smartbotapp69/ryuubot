--
-- PostgreSQL database dump
--

\restrict uBPMUAW8Mb52sF6IKPBBKG1n2S24dThEdeNMwSGCGabVdCNZHOzX9TdCcfwVUkB

-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: cleanup_ryubot_transient_history(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.cleanup_ryubot_transient_history() RETURNS TABLE(trading_events_deleted bigint, provider_bets_deleted bigint, trading_commands_deleted bigint, trading_sessions_deleted bigint, bonus_events_deleted bigint)
    LANGUAGE plpgsql
    AS $$
DECLARE
    cutoff timestamptz := now() - interval '1 day';
BEGIN
    DELETE FROM trading_events WHERE created_at < cutoff;
    GET DIAGNOSTICS trading_events_deleted = ROW_COUNT;

    DELETE FROM provider_bets
    WHERE prepared_at < cutoff
      AND status IN ('COMPLETED','FAILED_CONFIRMED');
    GET DIAGNOSTICS provider_bets_deleted = ROW_COUNT;

    DELETE FROM trading_commands
    WHERE created_at < cutoff AND status IN ('COMPLETED','FAILED');
    GET DIAGNOSTICS trading_commands_deleted = ROW_COUNT;

    DELETE FROM trading_sessions
    WHERE completed_at < cutoff AND status='COMPLETED';
    GET DIAGNOSTICS trading_sessions_deleted = ROW_COUNT;

    DELETE FROM referral_bonus_events WHERE occurred_at < cutoff;
    GET DIAGNOSTICS bonus_events_deleted = ROW_COUNT;

    RETURN NEXT;
END;
$$;


ALTER FUNCTION public.cleanup_ryubot_transient_history() OWNER TO postgres;

--
-- Name: notify_ryubot_trading_command(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.notify_ryubot_trading_command() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM pg_notify('ryubot_trading_commands', NEW.id::text);
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.notify_ryubot_trading_command() OWNER TO postgres;

--
-- Name: notify_ryubot_trading_event(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.notify_ryubot_trading_event() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM pg_notify('ryubot_trading_events', NEW.id::text);
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.notify_ryubot_trading_event() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: admin_business_rule_audit; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.admin_business_rule_audit (
    id bigint NOT NULL,
    admin_user_id bigint NOT NULL,
    business_rule_version_id bigint NOT NULL,
    action character varying(20) NOT NULL,
    before_data jsonb,
    after_data jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT admin_business_rule_audit_action_check CHECK (((action)::text = 'SAVE'::text))
);


ALTER TABLE public.admin_business_rule_audit OWNER TO postgres;

--
-- Name: admin_business_rule_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.admin_business_rule_audit ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.admin_business_rule_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: admin_sessions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.admin_sessions (
    token_hash bytea NOT NULL,
    admin_user_id bigint NOT NULL,
    csrf_token character varying(64) NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.admin_sessions OWNER TO postgres;

--
-- Name: admin_user_actions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.admin_user_actions (
    id bigint NOT NULL,
    admin_username character varying(100) NOT NULL,
    user_id bigint NOT NULL,
    action character varying(24) NOT NULL,
    detail jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT admin_user_actions_action_check CHECK (((action)::text = ANY ((ARRAY['EXTEND_SUBSCRIPTION'::character varying, 'RESET_PASSWORD'::character varying, 'SUSPEND'::character varying, 'ACTIVATE'::character varying])::text[])))
);


ALTER TABLE public.admin_user_actions OWNER TO postgres;

--
-- Name: admin_user_actions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.admin_user_actions ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.admin_user_actions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: admin_users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.admin_users (
    id bigint NOT NULL,
    username character varying(50) NOT NULL,
    password_hash text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    failed_login_count integer DEFAULT 0 NOT NULL,
    locked_until timestamp with time zone,
    last_login_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT admin_users_failed_login_count_check CHECK ((failed_login_count >= 0))
);


ALTER TABLE public.admin_users OWNER TO postgres;

--
-- Name: admin_users_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.admin_users ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.admin_users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: app_setting_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.app_setting_categories (
    key character varying(30) NOT NULL,
    label text NOT NULL,
    description text NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.app_setting_categories OWNER TO postgres;

--
-- Name: app_settings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.app_settings (
    key text NOT NULL,
    category character varying(30) NOT NULL,
    label text NOT NULL,
    value text NOT NULL,
    value_type character varying(12) NOT NULL,
    minimum numeric,
    maximum numeric,
    sort_order integer DEFAULT 0 NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT app_settings_value_type_check CHECK (((value_type)::text = ANY ((ARRAY['decimal'::character varying, 'integer'::character varying, 'text'::character varying, 'time'::character varying, 'boolean'::character varying])::text[])))
);


ALTER TABLE public.app_settings OWNER TO postgres;

--
-- Name: app_settings_audit; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.app_settings_audit (
    id bigint NOT NULL,
    setting_key text NOT NULL,
    old_value text NOT NULL,
    new_value text NOT NULL,
    admin_user_id bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.app_settings_audit OWNER TO postgres;

--
-- Name: app_settings_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.app_settings_audit ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.app_settings_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: business_rule_versions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.business_rule_versions (
    id bigint NOT NULL,
    version integer NOT NULL,
    status character varying(12) NOT NULL,
    user_win_percent numeric(7,4) NOT NULL,
    holding_win_percent numeric(7,4) NOT NULL,
    kangden_win_percent numeric(7,4) NOT NULL,
    fee_exempt_username character varying(50) NOT NULL,
    referral_level_1_percent numeric(7,4) NOT NULL,
    referral_level_2_percent numeric(7,4) NOT NULL,
    referral_level_3_percent numeric(7,4) NOT NULL,
    subscription_coin character varying(12) NOT NULL,
    subscription_price numeric(38,8) NOT NULL,
    subscription_upline_reward numeric(38,8) NOT NULL,
    subscription_management_amount numeric(38,8) NOT NULL,
    subscription_trial_days integer NOT NULL,
    owner_nana_percent numeric(7,4) NOT NULL,
    owner_deni_percent numeric(7,4) NOT NULL,
    owner_arya_percent numeric(7,4) NOT NULL,
    operational_percent numeric(7,4) NOT NULL,
    owner_cutoff_timezone character varying(64) NOT NULL,
    owner_cutoff_times time without time zone[] NOT NULL,
    created_by bigint NOT NULL,
    activated_by bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    activated_at timestamp with time zone,
    CONSTRAINT active_version_has_activation CHECK ((((status)::text <> 'ACTIVE'::text) OR ((activated_by IS NOT NULL) AND (activated_at IS NOT NULL)))),
    CONSTRAINT business_rule_versions_holding_win_percent_check CHECK (((holding_win_percent >= (0)::numeric) AND (holding_win_percent <= (100)::numeric))),
    CONSTRAINT business_rule_versions_kangden_win_percent_check CHECK (((kangden_win_percent >= (0)::numeric) AND (kangden_win_percent <= (100)::numeric))),
    CONSTRAINT business_rule_versions_operational_percent_check CHECK ((operational_percent >= (0)::numeric)),
    CONSTRAINT business_rule_versions_owner_arya_percent_check CHECK ((owner_arya_percent >= (0)::numeric)),
    CONSTRAINT business_rule_versions_owner_deni_percent_check CHECK ((owner_deni_percent >= (0)::numeric)),
    CONSTRAINT business_rule_versions_owner_nana_percent_check CHECK ((owner_nana_percent >= (0)::numeric)),
    CONSTRAINT business_rule_versions_referral_level_1_percent_check CHECK ((referral_level_1_percent >= (0)::numeric)),
    CONSTRAINT business_rule_versions_referral_level_2_percent_check CHECK ((referral_level_2_percent >= (0)::numeric)),
    CONSTRAINT business_rule_versions_referral_level_3_percent_check CHECK ((referral_level_3_percent >= (0)::numeric)),
    CONSTRAINT business_rule_versions_status_check CHECK (((status)::text = ANY ((ARRAY['DRAFT'::character varying, 'ACTIVE'::character varying, 'ARCHIVED'::character varying])::text[]))),
    CONSTRAINT business_rule_versions_subscription_management_amount_check CHECK ((subscription_management_amount >= (0)::numeric)),
    CONSTRAINT business_rule_versions_subscription_price_check CHECK ((subscription_price > (0)::numeric)),
    CONSTRAINT business_rule_versions_subscription_trial_days_check CHECK ((subscription_trial_days >= 0)),
    CONSTRAINT business_rule_versions_subscription_upline_reward_check CHECK ((subscription_upline_reward >= (0)::numeric)),
    CONSTRAINT business_rule_versions_user_win_percent_check CHECK (((user_win_percent >= (0)::numeric) AND (user_win_percent <= (100)::numeric))),
    CONSTRAINT business_rule_versions_version_check CHECK ((version > 0)),
    CONSTRAINT owner_allocation_exactly_100 CHECK (((((owner_nana_percent + owner_deni_percent) + owner_arya_percent) + operational_percent) = (100)::numeric)),
    CONSTRAINT referral_within_holding_allocation CHECK ((((referral_level_1_percent + referral_level_2_percent) + referral_level_3_percent) <= holding_win_percent)),
    CONSTRAINT subscription_allocation_matches_price CHECK (((subscription_upline_reward + subscription_management_amount) = subscription_price)),
    CONSTRAINT win_allocation_exactly_100 CHECK ((((user_win_percent + holding_win_percent) + kangden_win_percent) = (100)::numeric))
);


ALTER TABLE public.business_rule_versions OWNER TO postgres;

--
-- Name: business_rule_versions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.business_rule_versions ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.business_rule_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: coin_rule_versions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.coin_rule_versions (
    business_rule_version_id bigint NOT NULL,
    coin character varying(12) NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    decimals smallint NOT NULL,
    minimum_bet numeric(38,18) NOT NULL,
    minimum_withdrawal numeric(38,18) NOT NULL,
    minimum_bonus_claim numeric(38,18) NOT NULL,
    CONSTRAINT coin_rule_versions_decimals_check CHECK (((decimals >= 0) AND (decimals <= 18))),
    CONSTRAINT coin_rule_versions_minimum_bet_check CHECK ((minimum_bet > (0)::numeric)),
    CONSTRAINT coin_rule_versions_minimum_bonus_claim_check CHECK ((minimum_bonus_claim > (0)::numeric)),
    CONSTRAINT coin_rule_versions_minimum_withdrawal_check CHECK ((minimum_withdrawal > (0)::numeric))
);


ALTER TABLE public.coin_rule_versions OWNER TO postgres;

--
-- Name: import_runs; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.import_runs (
    id uuid NOT NULL,
    source_name character varying(50) NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    status character varying(20) NOT NULL,
    users_imported integer DEFAULT 0 NOT NULL,
    bonus_rows_imported integer DEFAULT 0 NOT NULL,
    error_message text,
    CONSTRAINT import_runs_status_check CHECK (((status)::text = ANY ((ARRAY['RUNNING'::character varying, 'COMPLETED'::character varying, 'FAILED'::character varying])::text[])))
);


ALTER TABLE public.import_runs OWNER TO postgres;

--
-- Name: management_fee_payouts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.management_fee_payouts (
    id uuid NOT NULL,
    source_user_id bigint NOT NULL,
    coin character varying(12) NOT NULL,
    allocation character varying(12) NOT NULL,
    recipient_username character varying(50) NOT NULL,
    amount numeric(38,8) NOT NULL,
    status character varying(20) NOT NULL,
    provider_response jsonb,
    failure_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    sent_at timestamp with time zone,
    completed_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT management_fee_payouts_allocation_check CHECK (((allocation)::text = ANY ((ARRAY['HOLDING'::character varying, 'KANGDEN'::character varying])::text[]))),
    CONSTRAINT management_fee_payouts_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT management_fee_payouts_status_check CHECK (((status)::text = ANY ((ARRAY['PREPARED'::character varying, 'SENT'::character varying, 'COMPLETED'::character varying, 'FAILED'::character varying, 'REVIEW_REQUIRED'::character varying])::text[])))
);


ALTER TABLE public.management_fee_payouts OWNER TO postgres;

--
-- Name: owner_cutoff_batches; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.owner_cutoff_batches (
    id uuid NOT NULL,
    business_date date NOT NULL,
    cutoff_slot time without time zone NOT NULL,
    coin character varying(12) NOT NULL,
    collector_balance numeric(38,8) NOT NULL,
    reserved_liability numeric(38,8) NOT NULL,
    distributable_amount numeric(38,8) NOT NULL,
    status character varying(20) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT owner_cutoff_batches_status_check CHECK (((status)::text = ANY ((ARRAY['PROCESSING'::character varying, 'COMPLETED'::character varying, 'REVIEW_REQUIRED'::character varying])::text[])))
);


ALTER TABLE public.owner_cutoff_batches OWNER TO postgres;

--
-- Name: owner_cutoff_payouts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.owner_cutoff_payouts (
    id uuid NOT NULL,
    batch_id uuid NOT NULL,
    allocation character varying(16) NOT NULL,
    recipient_username character varying(50) NOT NULL,
    percentage numeric(7,4) NOT NULL,
    amount numeric(38,8) NOT NULL,
    status character varying(20) NOT NULL,
    provider_response jsonb,
    failure_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    sent_at timestamp with time zone,
    completed_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT owner_cutoff_payouts_allocation_check CHECK (((allocation)::text = ANY ((ARRAY['NANA'::character varying, 'DENI'::character varying, 'ARYA'::character varying, 'OPERATIONAL'::character varying])::text[]))),
    CONSTRAINT owner_cutoff_payouts_amount_check CHECK ((amount >= (0)::numeric)),
    CONSTRAINT owner_cutoff_payouts_status_check CHECK (((status)::text = ANY ((ARRAY['PREPARED'::character varying, 'SENT'::character varying, 'COMPLETED'::character varying, 'REVIEW_REQUIRED'::character varying])::text[])))
);


ALTER TABLE public.owner_cutoff_payouts OWNER TO postgres;

--
-- Name: provider_bets; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.provider_bets (
    id uuid NOT NULL,
    session_id uuid NOT NULL,
    user_id bigint NOT NULL,
    coin character varying(12) NOT NULL,
    amount numeric(38,8) NOT NULL,
    chance numeric(8,4) NOT NULL,
    status character varying(30) NOT NULL,
    provider_reference text,
    provider_balance_before numeric(38,8),
    provider_balance_after numeric(38,8),
    gross_profit numeric(38,8),
    user_profit numeric(38,8),
    result character varying(8),
    prepared_at timestamp with time zone DEFAULT now() NOT NULL,
    sent_at timestamp with time zone,
    completed_at timestamp with time zone,
    request_payload jsonb,
    response_payload jsonb,
    holding_amount numeric(38,8),
    kangden_amount numeric(38,8),
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT provider_bets_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT provider_bets_chance_check CHECK (((chance > (0)::numeric) AND (chance < (100)::numeric))),
    CONSTRAINT provider_bets_result_check CHECK (((result)::text = ANY ((ARRAY['WIN'::character varying, 'LOSS'::character varying])::text[]))),
    CONSTRAINT provider_bets_status_check CHECK (((status)::text = ANY ((ARRAY['PREPARED'::character varying, 'SENT'::character varying, 'COMPLETED'::character varying, 'FAILED_CONFIRMED'::character varying, 'RECONCILIATION_REQUIRED'::character varying])::text[])))
);


ALTER TABLE public.provider_bets OWNER TO postgres;

--
-- Name: referral_bonus_balances; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.referral_bonus_balances (
    user_id bigint NOT NULL,
    coin character varying(12) NOT NULL,
    available_amount numeric(38,8) DEFAULT 0 NOT NULL,
    claimed_amount numeric(38,8) DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT referral_bonus_balances_available_amount_check CHECK ((available_amount >= (0)::numeric)),
    CONSTRAINT referral_bonus_balances_claimed_amount_check CHECK ((claimed_amount >= (0)::numeric))
);


ALTER TABLE public.referral_bonus_balances OWNER TO postgres;

--
-- Name: referral_bonus_events; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.referral_bonus_events (
    id uuid NOT NULL,
    user_id bigint NOT NULL,
    coin character varying(12) NOT NULL,
    amount numeric(38,8) NOT NULL,
    event_type character varying(30) NOT NULL,
    source_external_id text,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT referral_bonus_events_amount_check CHECK ((amount <> (0)::numeric)),
    CONSTRAINT referral_bonus_events_event_type_check CHECK (((event_type)::text = ANY ((ARRAY['IMPORT_OPENING'::character varying, 'TRADING_ACCRUAL'::character varying, 'CLAIM_COMPLETED'::character varying, 'CLAIM_REVERSAL'::character varying])::text[])))
);


ALTER TABLE public.referral_bonus_events OWNER TO postgres;

--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.schema_migrations (
    name text NOT NULL,
    applied_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.schema_migrations OWNER TO postgres;

--
-- Name: trading_commands; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.trading_commands (
    id uuid NOT NULL,
    request_id uuid NOT NULL,
    user_id bigint NOT NULL,
    session_id uuid,
    command character varying(24) NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    status character varying(16) DEFAULT 'PENDING'::character varying NOT NULL,
    failure_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    processed_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    worker_id text,
    CONSTRAINT trading_commands_command_check CHECK (((command)::text = ANY ((ARRAY['START'::character varying, 'STOP'::character varying, 'UPDATE_CONFIG'::character varying, 'OVERRIDE'::character varying, 'RESET'::character varying, 'STOP_ON_WIN'::character varying])::text[]))),
    CONSTRAINT trading_commands_status_check CHECK (((status)::text = ANY ((ARRAY['PENDING'::character varying, 'PROCESSING'::character varying, 'COMPLETED'::character varying, 'FAILED'::character varying])::text[])))
);


ALTER TABLE public.trading_commands OWNER TO postgres;

--
-- Name: trading_events; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.trading_events (
    id bigint NOT NULL,
    user_id bigint NOT NULL,
    session_id uuid,
    event_type character varying(32) NOT NULL,
    payload jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.trading_events OWNER TO postgres;

--
-- Name: trading_events_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.trading_events ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.trading_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: trading_fee_balances; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.trading_fee_balances (
    user_id bigint NOT NULL,
    coin character varying(12) NOT NULL,
    holding_pending numeric(38,8) DEFAULT 0 NOT NULL,
    kangden_pending numeric(38,8) DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT trading_fee_balances_holding_pending_check CHECK ((holding_pending >= (0)::numeric)),
    CONSTRAINT trading_fee_balances_kangden_pending_check CHECK ((kangden_pending >= (0)::numeric))
);


ALTER TABLE public.trading_fee_balances OWNER TO postgres;

--
-- Name: trading_sessions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.trading_sessions (
    id uuid NOT NULL,
    user_id bigint NOT NULL,
    coin character varying(12) NOT NULL,
    status character varying(30) NOT NULL,
    settings_snapshot jsonb NOT NULL,
    rule_snapshot jsonb NOT NULL,
    opening_provider_balance numeric(38,8) NOT NULL,
    visible_user_balance numeric(38,8) NOT NULL,
    current_bet numeric(38,8) NOT NULL,
    profit numeric(38,8) DEFAULT 0 NOT NULL,
    wins integer DEFAULT 0 NOT NULL,
    losses integer DEFAULT 0 NOT NULL,
    last_result character varying(8),
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    stop_reason text,
    streak integer DEFAULT 0 NOT NULL,
    profit_cycle numeric(38,8) DEFAULT 0 NOT NULL,
    next_override numeric(38,8),
    reset_after_pending boolean DEFAULT false NOT NULL,
    worker_id text,
    lease_expires_at timestamp with time zone,
    max_win_streak integer DEFAULT 0 NOT NULL,
    max_loss_streak integer DEFAULT 0 NOT NULL,
    CONSTRAINT trading_sessions_current_bet_check CHECK ((current_bet > (0)::numeric)),
    CONSTRAINT trading_sessions_last_result_check CHECK (((last_result)::text = ANY ((ARRAY['WIN'::character varying, 'LOSS'::character varying])::text[]))),
    CONSTRAINT trading_sessions_losses_check CHECK ((losses >= 0)),
    CONSTRAINT trading_sessions_max_loss_streak_check CHECK ((max_loss_streak >= 0)),
    CONSTRAINT trading_sessions_max_win_streak_check CHECK ((max_win_streak >= 0)),
    CONSTRAINT trading_sessions_next_override_check CHECK (((next_override IS NULL) OR (next_override > (0)::numeric))),
    CONSTRAINT trading_sessions_opening_provider_balance_check CHECK ((opening_provider_balance >= (0)::numeric)),
    CONSTRAINT trading_sessions_status_check CHECK (((status)::text = ANY ((ARRAY['RUNNING'::character varying, 'STOP_REQUESTED'::character varying, 'RECONCILIATION_REQUIRED'::character varying, 'COMPLETED'::character varying])::text[]))),
    CONSTRAINT trading_sessions_streak_check CHECK ((streak >= 0)),
    CONSTRAINT trading_sessions_visible_user_balance_check CHECK ((visible_user_balance >= (0)::numeric)),
    CONSTRAINT trading_sessions_wins_check CHECK ((wins >= 0))
);


ALTER TABLE public.trading_sessions OWNER TO postgres;

--
-- Name: user_pasino_accounts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_pasino_accounts (
    user_id bigint NOT NULL,
    provider_username character varying(100) NOT NULL,
    provider_email character varying(254),
    password_ciphertext text,
    access_token_ciphertext text,
    access_token_expires_at timestamp with time zone,
    socket_token_ciphertext text,
    socket_token_expires_at timestamp with time zone,
    encryption_version smallint DEFAULT 0 NOT NULL,
    imported_from_legacy boolean DEFAULT false NOT NULL,
    last_authenticated_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.user_pasino_accounts OWNER TO postgres;

--
-- Name: user_referrals; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_referrals (
    user_id bigint NOT NULL,
    referrer_user_id bigint,
    provider_referrer character varying(30) DEFAULT '277064'::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT user_referrals_not_self CHECK (((referrer_user_id IS NULL) OR (user_id <> referrer_user_id)))
);


ALTER TABLE public.user_referrals OWNER TO postgres;

--
-- Name: user_sessions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_sessions (
    token_hash bytea NOT NULL,
    user_id bigint NOT NULL,
    csrf_token character varying(64) NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.user_sessions OWNER TO postgres;

--
-- Name: user_trading_settings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_trading_settings (
    user_id bigint NOT NULL,
    coin character varying(12) DEFAULT 'TRX'::character varying NOT NULL,
    base_bet numeric(38,8) DEFAULT 0.00000100 NOT NULL,
    chance_min integer DEFAULT 45 NOT NULL,
    chance_max integer DEFAULT 45 NOT NULL,
    delay_ms integer DEFAULT 500 NOT NULL,
    martingale_on_win integer DEFAULT 0 NOT NULL,
    martingale_on_loss integer DEFAULT 100 NOT NULL,
    reset_after_wins integer DEFAULT 1 NOT NULL,
    reset_after_losses integer DEFAULT 0 NOT NULL,
    boom_after_wins integer DEFAULT 0 NOT NULL,
    boom_win_amount numeric(38,8) DEFAULT 0 NOT NULL,
    boom_after_losses integer DEFAULT 0 NOT NULL,
    boom_loss_amount numeric(38,8) DEFAULT 0 NOT NULL,
    take_profit numeric(38,8) DEFAULT 0 NOT NULL,
    stop_loss numeric(38,8) DEFAULT 0 NOT NULL,
    balance_below numeric(38,8) DEFAULT 0 NOT NULL,
    stop_on_win boolean DEFAULT false NOT NULL,
    maximum_bet numeric(38,8) DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    profit_session numeric(38,8) DEFAULT 0 NOT NULL,
    CONSTRAINT user_trading_settings_balance_below_check CHECK ((balance_below >= (0)::numeric)),
    CONSTRAINT user_trading_settings_base_bet_check CHECK ((base_bet > (0)::numeric)),
    CONSTRAINT user_trading_settings_boom_after_losses_check CHECK ((boom_after_losses >= 0)),
    CONSTRAINT user_trading_settings_boom_after_wins_check CHECK ((boom_after_wins >= 0)),
    CONSTRAINT user_trading_settings_boom_loss_amount_check CHECK ((boom_loss_amount >= (0)::numeric)),
    CONSTRAINT user_trading_settings_boom_win_amount_check CHECK ((boom_win_amount >= (0)::numeric)),
    CONSTRAINT user_trading_settings_chance_max_check CHECK ((((chance_max)::numeric > (0)::numeric) AND ((chance_max)::numeric < (100)::numeric))),
    CONSTRAINT user_trading_settings_chance_min_check CHECK ((((chance_min)::numeric > (0)::numeric) AND ((chance_min)::numeric < (100)::numeric))),
    CONSTRAINT user_trading_settings_delay_ms_check CHECK (((delay_ms >= 100) AND (delay_ms <= 600000))),
    CONSTRAINT user_trading_settings_martingale_on_loss_check CHECK (((martingale_on_loss)::numeric >= (0)::numeric)),
    CONSTRAINT user_trading_settings_martingale_on_win_check CHECK (((martingale_on_win)::numeric >= (0)::numeric)),
    CONSTRAINT user_trading_settings_maximum_bet_check CHECK ((maximum_bet >= (0)::numeric)),
    CONSTRAINT user_trading_settings_profit_session_check CHECK ((profit_session >= (0)::numeric)),
    CONSTRAINT user_trading_settings_reset_after_losses_check CHECK ((reset_after_losses >= 0)),
    CONSTRAINT user_trading_settings_reset_after_wins_check CHECK ((reset_after_wins >= 0)),
    CONSTRAINT user_trading_settings_stop_loss_check CHECK ((stop_loss >= (0)::numeric)),
    CONSTRAINT user_trading_settings_take_profit_check CHECK ((take_profit >= (0)::numeric))
);


ALTER TABLE public.user_trading_settings OWNER TO postgres;

--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    username character varying(50) NOT NULL,
    email character varying(254) NOT NULL,
    password_hash text NOT NULL,
    status character varying(20) DEFAULT 'ACTIVE'::character varying NOT NULL,
    subscription_expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    legacy_user_id bigint,
    subscription_trial_ends_at timestamp with time zone,
    last_login_at timestamp with time zone,
    last_active_at timestamp with time zone,
    CONSTRAINT users_status_check CHECK (((status)::text = ANY ((ARRAY['ACTIVE'::character varying, 'SUSPENDED'::character varying, 'DELETED'::character varying])::text[])))
);


ALTER TABLE public.users OWNER TO postgres;

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.users ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: wallet_operations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.wallet_operations (
    request_id uuid NOT NULL,
    user_id bigint NOT NULL,
    operation character varying(12) NOT NULL,
    coin character varying(12) NOT NULL,
    amount numeric(38,8) NOT NULL,
    destination text NOT NULL,
    status character varying(24) NOT NULL,
    provider_response jsonb,
    failure_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    CONSTRAINT wallet_operations_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT wallet_operations_destination_check CHECK ((length(destination) > 0)),
    CONSTRAINT wallet_operations_operation_check CHECK (((operation)::text = ANY ((ARRAY['WITHDRAW'::character varying, 'TRANSFER'::character varying])::text[]))),
    CONSTRAINT wallet_operations_status_check CHECK (((status)::text = ANY ((ARRAY['PROCESSING'::character varying, 'COMPLETED'::character varying, 'FAILED'::character varying])::text[])))
);


ALTER TABLE public.wallet_operations OWNER TO postgres;

--
-- Data for Name: admin_business_rule_audit; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.admin_business_rule_audit (id, admin_user_id, business_rule_version_id, action, before_data, after_data, created_at) FROM stdin;
1	1	1	SAVE	\N	\N	2026-09-19 23:07:52.864772+07
2	1	1	SAVE	\N	\N	2026-09-19 23:08:18.158586+07
\.


--
-- Data for Name: admin_sessions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.admin_sessions (token_hash, admin_user_id, csrf_token, expires_at, created_at) FROM stdin;
\\x89a8104b0c07c3ce23fe25ccff321515c396b0bfdad1168115a620e018d786b7	1	f808099e6e2cf07853d12c545edb27fe00022b93ef969df2	2026-09-20 07:06:30.591456+07	2026-09-19 23:06:30.591456+07
\.


--
-- Data for Name: admin_user_actions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.admin_user_actions (id, admin_username, user_id, action, detail, created_at) FROM stdin;
1	admin	781	EXTEND_SUBSCRIPTION	{"months": 100}	2026-09-21 04:30:22.970621+07
2	admin	781	RESET_PASSWORD	{"sessions_revoked": true}	2026-09-21 04:30:51.515526+07
3	admin	1113	RESET_PASSWORD	{"sessions_revoked": true}	2026-09-21 04:37:10.36859+07
4	admin	1111	RESET_PASSWORD	{"sessions_revoked": true}	2026-09-21 04:38:04.512213+07
5	admin	1109	RESET_PASSWORD	{"sessions_revoked": true}	2026-09-21 04:39:03.160736+07
6	admin	1107	RESET_PASSWORD	{"sessions_revoked": true}	2026-09-21 04:40:20.998335+07
7	admin	1103	RESET_PASSWORD	{"sessions_revoked": true}	2026-09-21 04:41:16.57471+07
8	admin	1101	RESET_PASSWORD	{"sessions_revoked": true}	2026-09-21 04:42:54.704596+07
9	admin	1099	RESET_PASSWORD	{"sessions_revoked": true}	2026-09-21 04:43:52.554497+07
10	admin	1099	RESET_PASSWORD	{"sessions_revoked": true}	2026-09-21 04:44:21.690064+07
11	admin	1099	ACTIVATE	{}	2026-09-21 04:44:31.943574+07
12	admin	1099	SUSPEND	{}	2026-09-21 04:44:57.156642+07
13	admin	1097	RESET_PASSWORD	{"sessions_revoked": true}	2026-09-21 04:45:11.573169+07
14	admin	1095	RESET_PASSWORD	{"sessions_revoked": true}	2026-09-21 04:46:00.351198+07
15	admin	1093	RESET_PASSWORD	{"sessions_revoked": true}	2026-09-21 04:46:54.575296+07
16	admin	1093	ACTIVATE	{}	2026-09-21 04:46:58.936038+07
17	admin	1093	SUSPEND	{}	2026-09-21 04:47:41.794622+07
18	admin	1091	ACTIVATE	{}	2026-09-21 04:47:51.042369+07
19	admin	1091	RESET_PASSWORD	{"sessions_revoked": true}	2026-09-21 04:48:00.652156+07
20	admin	1089	ACTIVATE	{}	2026-09-21 04:48:39.92393+07
21	admin	1089	RESET_PASSWORD	{"sessions_revoked": true}	2026-09-21 04:48:49.556868+07
22	admin	1085	ACTIVATE	{}	2026-09-21 04:49:38.428153+07
23	admin	1085	RESET_PASSWORD	{"sessions_revoked": true}	2026-09-21 04:49:48.758623+07
24	admin	781	RESET_PASSWORD	{"sessions_revoked": true}	2026-09-21 10:29:24.432499+07
\.


--
-- Data for Name: admin_users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.admin_users (id, username, password_hash, is_active, failed_login_count, locked_until, last_login_at, created_at, updated_at) FROM stdin;
1	admin	$2a$10$KB5ptnaREGRaCKcf2YzESu.psrfZExl.HLjI6fTk8uJQPbbNYPxJO	t	0	\N	\N	2026-09-19 23:05:56.215307+07	2026-09-19 23:05:56.215307+07
\.


--
-- Data for Name: app_setting_categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.app_setting_categories (key, label, description, sort_order) FROM stdin;
trading	Trading & Fee	Pembagian hasil trading dan akun bebas fee.	10
referral	Referral	Persentase bonus referral dari bagian akun penampung.	20
subscription	Subscription	Harga langganan, trial, bagian upline, dan management.	30
owner	Owner & Jadwal	Pembagian saldo penampung dan jadwal cutoff.	40
coins	Coin & Minimum	Batas minimum bet, withdrawal, dan klaim bonus per coin.	50
accounts	Akun Bisnis	Username akun Pasino untuk penampung, langganan, fee, owner, dan operasional.	45
\.


--
-- Data for Name: app_settings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.app_settings (key, category, label, value, value_type, minimum, maximum, sort_order, updated_by, updated_at) FROM stdin;
trading.user_percent	trading	Bagian user (%)	86	decimal	0	100	10	\N	2026-09-19 23:36:34.855289+07
trading.holding_percent	trading	Bagian akun penampung (%)	12	decimal	0	100	20	\N	2026-09-19 23:36:34.855289+07
trading.kangden_percent	trading	Bagian kangden69 (%)	2	decimal	0	100	30	\N	2026-09-19 23:36:34.855289+07
trading.fee_exempt_username	trading	Username bebas fee	kangden69	text	\N	\N	40	\N	2026-09-19 23:36:34.855289+07
subscription.price_trx	subscription	Harga per bulan (TRX)	22	decimal	0	\N	10	\N	2026-09-19 23:36:34.855289+07
subscription.upline_trx	subscription	Bagian upline (TRX)	3	decimal	0	\N	20	\N	2026-09-19 23:36:34.855289+07
subscription.management_trx	subscription	Bagian management (TRX)	19	decimal	0	\N	30	\N	2026-09-19 23:36:34.855289+07
owner.nana_percent	owner	Kang Nana (%)	30	decimal	0	100	10	\N	2026-09-19 23:36:34.855289+07
owner.deni_percent	owner	Kang Deni (%)	30	decimal	0	100	20	\N	2026-09-19 23:36:34.855289+07
owner.arya_percent	owner	Pak Arya (%)	30	decimal	0	100	30	\N	2026-09-19 23:36:34.855289+07
owner.operational_percent	owner	Operasional (%)	10	decimal	0	100	40	\N	2026-09-19 23:36:34.855289+07
owner.cutoff_1	owner	Cutoff pertama	13:00	time	\N	\N	50	\N	2026-09-19 23:36:34.855289+07
owner.cutoff_2	owner	Cutoff kedua	18:00	time	\N	\N	60	\N	2026-09-19 23:36:34.855289+07
coin.TRX.minimum_bet	coins	TRX minimum bet	0.00000100	decimal	0	\N	10	\N	2026-09-19 23:36:34.855289+07
coin.DOGE.minimum_bet	coins	DOGE minimum bet	0.00010000	decimal	0	\N	20	\N	2026-09-19 23:36:34.855289+07
coin.DOGE.minimum_withdrawal	coins	DOGE minimum withdrawal	5	decimal	0	\N	21	\N	2026-09-19 23:36:34.855289+07
coin.FLOKI.minimum_bet	coins	FLOKI minimum bet	0.06000000	decimal	0	\N	30	\N	2026-09-19 23:36:34.855289+07
coin.FLOKI.minimum_withdrawal	coins	FLOKI minimum withdrawal	25000	decimal	0	\N	31	\N	2026-09-19 23:36:34.855289+07
coin.BTT.minimum_bet	coins	BTT minimum bet	0.10000000	decimal	0	\N	40	\N	2026-09-19 23:36:34.855289+07
coin.BTT.minimum_withdrawal	coins	BTT minimum withdrawal	2000000	decimal	0	\N	41	\N	2026-09-19 23:36:34.855289+07
coin.DOGE.minimum_claim	coins	DOGE minimum claim bonus	5	decimal	0	\N	22	1	2026-09-19 23:39:01.738154+07
coin.FLOKI.minimum_claim	coins	FLOKI minimum claim bonus	25000	decimal	0	\N	32	1	2026-09-19 23:39:01.738154+07
coin.BTT.minimum_claim	coins	BTT minimum claim bonus	2000000	decimal	0	\N	42	1	2026-09-19 23:39:01.738154+07
subscription.trial_days	subscription	Trial user baru (hari)	30	integer	0	365	40	1	2026-09-19 23:55:21.099662+07
account.fee_collector_username	accounts	Akun penampung fee	smartbotapp	text	\N	\N	10	\N	2026-09-21 04:05:20.220716+07
account.subscription_collector_username	accounts	Akun penampung langganan	langgananbot	text	\N	\N	20	\N	2026-09-21 04:05:20.220716+07
account.kangden_username	accounts	Akun penerima fee kangden	kangden69	text	\N	\N	30	\N	2026-09-21 04:05:20.220716+07
referral.level_1_percent	referral	Referral level 1 (%)	1	decimal	0	100	10	\N	2026-09-21 04:07:54.002751+07
referral.level_2_percent	referral	Referral level 2 (%)	0.5	decimal	0	100	20	\N	2026-09-21 04:07:54.002751+07
referral.level_3_percent	referral	Referral level 3 (%)	0.5	decimal	0	100	30	\N	2026-09-21 04:07:54.002751+07
coin.TRX.minimum_claim	coins	TRX minimum claim bonus	15	decimal	0	\N	12	\N	2026-09-21 04:08:07.335884+07
coin.TRX.minimum_withdrawal	coins	TRX minimum withdrawal	15	decimal	0	\N	11	\N	2026-09-21 04:08:12.77379+07
account.owner_deni_username	accounts	Akun Kang Deni	kangden69	text	\N	\N	50	\N	2026-09-21 04:10:31.017173+07
account.owner_arya_username	accounts	Akun Pak Arya	smartrich88	text	\N	\N	60	\N	2026-09-21 04:10:31.017173+07
account.operational_username	accounts	Akun operasional	opryuubot	text	\N	\N	70	\N	2026-09-21 04:10:31.017173+07
account.owner_nana_username	accounts	Akun Kang Nana	gudangopit	text	\N	\N	40	\N	2026-09-21 04:10:31.017173+07
\.


--
-- Data for Name: app_settings_audit; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.app_settings_audit (id, setting_key, old_value, new_value, admin_user_id, created_at) FROM stdin;
1	coin.TRX.minimum_claim	30	3	1	2026-09-19 23:39:01.738154+07
2	coin.DOGE.minimum_claim	50	5	1	2026-09-19 23:39:01.738154+07
3	coin.FLOKI.minimum_claim	250000	25000	1	2026-09-19 23:39:01.738154+07
4	coin.BTT.minimum_claim	20000000	2000000	1	2026-09-19 23:39:01.738154+07
5	subscription.trial_days	2	30	1	2026-09-19 23:55:21.099662+07
6	referral.level_1_percent	1.5	1	\N	2026-09-21 04:07:54.002751+07
7	referral.level_2_percent	0.9	0.5	\N	2026-09-21 04:07:54.002751+07
8	referral.level_3_percent	0.6	0.5	\N	2026-09-21 04:07:54.002751+07
9	coin.TRX.minimum_claim	3	15	\N	2026-09-21 04:08:07.335884+07
10	coin.TRX.minimum_withdrawal	3	15	\N	2026-09-21 04:08:12.77379+07
11	account.owner_deni_username	deni	kangden69	\N	2026-09-21 04:10:31.017173+07
12	account.owner_arya_username	arya	smartrich88	\N	2026-09-21 04:10:31.017173+07
13	account.operational_username	operasional	opryuubot	\N	2026-09-21 04:10:31.017173+07
14	account.owner_nana_username	nana	gudangopit	\N	2026-09-21 04:10:31.017173+07
\.


--
-- Data for Name: business_rule_versions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.business_rule_versions (id, version, status, user_win_percent, holding_win_percent, kangden_win_percent, fee_exempt_username, referral_level_1_percent, referral_level_2_percent, referral_level_3_percent, subscription_coin, subscription_price, subscription_upline_reward, subscription_management_amount, subscription_trial_days, owner_nana_percent, owner_deni_percent, owner_arya_percent, operational_percent, owner_cutoff_timezone, owner_cutoff_times, created_by, activated_by, created_at, activated_at) FROM stdin;
1	1	ACTIVE	86.0000	12.0000	2.0000	kangden69	1.0000	0.5000	0.5000	TRX	22.00000000	3.00000000	19.00000000	30	30.0000	30.0000	30.0000	10.0000	Asia/Jakarta	{13:00:00,18:00:00}	1	1	2026-09-19 23:07:52.864772+07	2026-09-19 23:08:18.158586+07
\.


--
-- Data for Name: coin_rule_versions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.coin_rule_versions (business_rule_version_id, coin, is_active, decimals, minimum_bet, minimum_withdrawal, minimum_bonus_claim) FROM stdin;
\.


--
-- Data for Name: import_runs; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.import_runs (id, source_name, started_at, completed_at, status, users_imported, bonus_rows_imported, error_message) FROM stdin;
\.


--
-- Data for Name: management_fee_payouts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.management_fee_payouts (id, source_user_id, coin, allocation, recipient_username, amount, status, provider_response, failure_reason, created_at, sent_at, completed_at, updated_at) FROM stdin;
997fca56-e933-4ca2-9a22-079491faae8b	747	TRX	HOLDING	smartbotapp	0.00000628	COMPLETED	{"coin": "TRX", "amount": "0.00000628", "balance": "0.09558748", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 04:16:41.448684+07	2026-09-21 04:16:41.470106+07	2026-09-21 04:16:42.067755+07	2026-09-21 04:16:42.067755+07
9d4de461-0ad6-4113-8c89-79fdc64d7d48	747	TRX	KANGDEN	kangden69	0.00000097	COMPLETED	{"coin": "TRX", "amount": "0.00000097", "balance": "0.09558651", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 04:16:41.466698+07	2026-09-21 04:16:42.074621+07	2026-09-21 04:16:42.544596+07	2026-09-21 04:16:42.544596+07
65f8dae6-c6e8-487a-b1ff-986bd876341c	747	BTT	HOLDING	smartbotapp	0.02253048	COMPLETED	{"coin": "BTT", "amount": "0.02253048", "balance": "22971506.91603413", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 10:55:04.806292+07	2026-09-21 10:55:04.814702+07	2026-09-21 10:55:05.126344+07	2026-09-21 10:55:05.126344+07
aac79143-c6f6-4580-acaa-19244e05457c	747	BTT	KANGDEN	kangden69	0.00375508	COMPLETED	{"coin": "BTT", "amount": "0.00375508", "balance": "22971506.91227905", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 10:55:04.807719+07	2026-09-21 10:55:05.134453+07	2026-09-21 10:55:05.428735+07	2026-09-21 10:55:05.428735+07
70c409d4-4331-412a-b148-ae72bf897c63	747	BTT	HOLDING	smartbotapp	0.01126524	COMPLETED	{"coin": "BTT", "amount": "0.01126524", "balance": "22971506.99489081", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:03:10.908263+07	2026-09-21 11:03:10.92117+07	2026-09-21 11:03:11.226543+07	2026-09-21 11:03:11.226543+07
c2f5291d-df85-4c8e-b263-29958583e2bd	747	BTT	KANGDEN	kangden69	0.00187754	COMPLETED	{"coin": "BTT", "amount": "0.00187754", "balance": "22971506.99301327", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:03:10.914788+07	2026-09-21 11:03:11.232213+07	2026-09-21 11:03:11.53741+07	2026-09-21 11:03:11.53741+07
effec64b-33c7-497f-a488-9b4d106c6348	747	BTT	HOLDING	smartbotapp	0.02253048	COMPLETED	{"coin": "BTT", "amount": "0.02253048", "balance": "22971507.05823679", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:08:28.39607+07	2026-09-21 11:08:28.406458+07	2026-09-21 11:08:28.703664+07	2026-09-21 11:08:28.703664+07
5250d398-8ba5-449e-b16d-fae88a535c5f	747	BTT	KANGDEN	kangden69	0.00375508	COMPLETED	{"coin": "BTT", "amount": "0.00375508", "balance": "22971507.05448171", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:08:28.404671+07	2026-09-21 11:08:28.712544+07	2026-09-21 11:08:29.006458+07	2026-09-21 11:08:29.006458+07
5542ce4e-0f70-47e3-95fa-801cceddaf14	747	BTT	HOLDING	smartbotapp	0.11265240	COMPLETED	{"coin": "BTT", "amount": "0.11265240", "balance": "22971507.48059931", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:14:21.193905+07	2026-09-21 11:14:21.203004+07	2026-09-21 11:14:21.505861+07	2026-09-21 11:14:21.505861+07
8d684e29-da07-4f7c-b260-da8df73fa39b	747	BTT	KANGDEN	kangden69	0.01877540	COMPLETED	{"coin": "BTT", "amount": "0.01877540", "balance": "22971507.26182391", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:14:21.196668+07	2026-09-21 11:14:21.511132+07	2026-09-21 11:14:21.811295+07	2026-09-21 11:14:21.811295+07
700a7209-a0b4-4594-8aa3-b4393b34c531	747	BTT	HOLDING	smartbotapp	0.18024384	COMPLETED	{"coin": "BTT", "amount": "0.18024384", "balance": "22971507.68361207", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:14:26.191045+07	2026-09-21 11:14:26.19421+07	2026-09-21 11:14:26.498658+07	2026-09-21 11:14:26.498658+07
7e859b37-6227-4b32-8c46-1662bb0a19da	747	BTT	KANGDEN	kangden69	0.03004064	COMPLETED	{"coin": "BTT", "amount": "0.03004064", "balance": "22971507.74744843", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:14:26.192232+07	2026-09-21 11:14:26.50285+07	2026-09-21 11:14:26.804158+07	2026-09-21 11:14:26.804158+07
df806072-ac84-4c06-80d3-8ffe13725a9d	747	BTT	HOLDING	smartbotapp	0.09012192	COMPLETED	{"coin": "BTT", "amount": "0.09012192", "balance": "22971507.91446551", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:14:31.185546+07	2026-09-21 11:14:31.188891+07	2026-09-21 11:14:31.49663+07	2026-09-21 11:14:31.49663+07
c78819e4-caa0-40d6-9ad1-17316b43946f	747	BTT	KANGDEN	kangden69	0.01502032	COMPLETED	{"coin": "BTT", "amount": "0.01502032", "balance": "22971507.49944519", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:14:31.187067+07	2026-09-21 11:14:31.498758+07	2026-09-21 11:14:31.808431+07	2026-09-21 11:14:31.808431+07
3cf75577-9086-4e72-9b1f-73a029675a24	747	BTT	HOLDING	smartbotapp	0.77730156	COMPLETED	{"coin": "BTT", "amount": "0.77730156", "balance": "22971507.49965663", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:14:36.185176+07	2026-09-21 11:14:36.188282+07	2026-09-21 11:14:36.495157+07	2026-09-21 11:14:36.495157+07
98eca5d1-ad9b-4322-8c82-49d42983bbe1	747	BTT	KANGDEN	kangden69	0.12955026	COMPLETED	{"coin": "BTT", "amount": "0.12955026", "balance": "22971507.27010637", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:14:36.186346+07	2026-09-21 11:14:36.498668+07	2026-09-21 11:14:36.797274+07	2026-09-21 11:14:36.797274+07
883f0ec2-93a1-49f4-83a2-f7326368e02b	747	BTT	HOLDING	smartbotapp	0.09012192	COMPLETED	{"coin": "BTT", "amount": "0.09012192", "balance": "22971507.13100045", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:14:41.186983+07	2026-09-21 11:14:41.19072+07	2026-09-21 11:14:41.493947+07	2026-09-21 11:14:41.493947+07
d8d4d900-d388-4621-b57a-61456b59a354	747	BTT	KANGDEN	kangden69	0.01502032	COMPLETED	{"coin": "BTT", "amount": "0.01502032", "balance": "22971507.11598013", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:14:41.189467+07	2026-09-21 11:14:41.501477+07	2026-09-21 11:14:41.798681+07	2026-09-21 11:14:41.798681+07
d6d28745-4a86-4923-ba16-1e41a571f759	747	BTT	HOLDING	smartbotapp	1.44195072	COMPLETED	{"coin": "BTT", "amount": "1.44195072", "balance": "22971504.99028541", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:16:53.100924+07	2026-09-21 11:16:53.112236+07	2026-09-21 11:16:53.419675+07	2026-09-21 11:16:53.419675+07
7cfd8802-56e6-47cf-9389-3b1e3b2aa21f	747	BTT	KANGDEN	kangden69	0.24032512	COMPLETED	{"coin": "BTT", "amount": "0.24032512", "balance": "22971504.74996029", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:16:53.103991+07	2026-09-21 11:16:53.422263+07	2026-09-21 11:16:53.719998+07	2026-09-21 11:16:53.719998+07
527552bc-a7bb-4411-ac9c-c86a23f0ecf3	747	FLOKI	HOLDING	smartbotapp	0.03379570	COMPLETED	{"coin": "FLOKI", "amount": "0.03379570", "balance": "69395.72857117", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:17:33.092469+07	2026-09-21 11:17:33.095797+07	2026-09-21 11:17:33.40035+07	2026-09-21 11:17:33.40035+07
e7aa58a7-52b4-40b6-874c-883ee82f6ec2	747	FLOKI	KANGDEN	kangden69	0.00563260	COMPLETED	{"coin": "FLOKI", "amount": "0.00563260", "balance": "69395.72293857", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:17:33.094357+07	2026-09-21 11:17:33.405134+07	2026-09-21 11:17:33.7313+07	2026-09-21 11:17:33.7313+07
98b9e789-68d3-4ed6-8098-53e0f8245d98	747	FLOKI	HOLDING	smartbotapp	0.01351828	COMPLETED	{"coin": "FLOKI", "amount": "0.01351828", "balance": "69395.82207269", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:17:38.097875+07	2026-09-21 11:17:38.110179+07	2026-09-21 11:17:38.413538+07	2026-09-21 11:17:38.413538+07
813b90c8-891a-47ec-aca0-65d3e66be955	747	FLOKI	KANGDEN	kangden69	0.00225304	COMPLETED	{"coin": "FLOKI", "amount": "0.00225304", "balance": "69395.81981965", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:17:38.103234+07	2026-09-21 11:17:38.4198+07	2026-09-21 11:17:38.728328+07	2026-09-21 11:17:38.728328+07
64dc4d28-9f58-4f65-b3c0-0b25dfa0e95f	747	BTT	HOLDING	smartbotapp	0.07885668	COMPLETED	{"coin": "BTT", "amount": "0.07885668", "balance": "22971505.02824261", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:20:56.493396+07	2026-09-21 11:20:56.502287+07	2026-09-21 11:20:56.805713+07	2026-09-21 11:20:56.805713+07
79abdd78-b4bb-4800-9cc8-9f563f41973d	747	BTT	KANGDEN	kangden69	0.01314278	COMPLETED	{"coin": "BTT", "amount": "0.01314278", "balance": "22971505.10897683", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:20:56.49608+07	2026-09-21 11:20:56.809661+07	2026-09-21 11:20:57.102163+07	2026-09-21 11:20:57.102163+07
18746095-723e-4fa6-afa6-4a63255e88ef	747	BTT	HOLDING	smartbotapp	0.13518288	COMPLETED	{"coin": "BTT", "amount": "0.13518288", "balance": "22971505.20644095", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:21:01.495562+07	2026-09-21 11:21:01.503731+07	2026-09-21 11:21:01.798904+07	2026-09-21 11:21:01.798904+07
7f01af56-86d5-42c4-9bdc-89839a8809e3	747	BTT	KANGDEN	kangden69	0.02253048	COMPLETED	{"coin": "BTT", "amount": "0.02253048", "balance": "22971505.18391047", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:21:01.500948+07	2026-09-21 11:21:01.803243+07	2026-09-21 11:21:02.096135+07	2026-09-21 11:21:02.096135+07
8f861b54-0da0-481a-8d1d-7c02bc86168c	747	BTT	KANGDEN	kangden69	0.00563262	COMPLETED	{"coin": "BTT", "amount": "0.00563262", "balance": "22971505.22814513", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:21:11.49035+07	2026-09-21 11:21:11.81341+07	2026-09-21 11:21:12.115989+07	2026-09-21 11:21:12.115989+07
0959999e-a4c7-4b3d-8e88-df9d06ae52b6	747	BTT	KANGDEN	kangden69	0.15020320	COMPLETED	{"coin": "BTT", "amount": "0.15020320", "balance": "22971503.98485073", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:21:16.492496+07	2026-09-21 11:21:16.796967+07	2026-09-21 11:21:17.109088+07	2026-09-21 11:21:17.109088+07
814547ba-3db3-4ac4-88ff-bb406059b6ec	751	BTT	KANGDEN	kangden69	0.01777776	COMPLETED	{"coin": "BTT", "amount": "0.01777776", "balance": "13584085.09174796", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:50:49.012337+07	2026-09-21 15:50:49.49589+07	2026-09-21 15:50:49.894809+07	2026-09-21 15:50:49.894809+07
04362e88-605d-4bd2-810c-855d1d44dbbc	747	BTT	HOLDING	smartbotapp	0.09197568	COMPLETED	{"coin": "BTT", "amount": "0.09197568", "balance": "22971504.45933905", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:24:41.687642+07	2026-09-21 11:24:41.72003+07	2026-09-21 11:24:42.033672+07	2026-09-21 11:24:42.033672+07
c9625e4c-2230-43f2-b183-4f4c8d1cf3a2	747	BTT	KANGDEN	kangden69	0.01532928	COMPLETED	{"coin": "BTT", "amount": "0.01532928", "balance": "22971504.24400977", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:24:41.711916+07	2026-09-21 11:24:42.039549+07	2026-09-21 11:24:42.352167+07	2026-09-21 11:24:42.352167+07
36c9e1aa-3275-40bc-a06a-d07bed3f1a17	751	BTT	HOLDING	smartbotapp	1088.66691072	COMPLETED	{"coin": "BTT", "amount": "1088.66691072", "balance": "13585532.71247488", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:57:03.946865+07	2026-09-21 15:57:03.984473+07	2026-09-21 15:57:04.34423+07	2026-09-21 15:57:04.34423+07
7c28c817-09ba-4d04-8a50-e6820b37fcd3	751	BTT	KANGDEN	kangden69	181.44448512	COMPLETED	{"coin": "BTT", "amount": "181.44448512", "balance": "13585351.26798976", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:57:03.981571+07	2026-09-21 15:57:04.348505+07	2026-09-21 15:57:04.678302+07	2026-09-21 15:57:04.678302+07
65614580-1493-4cd0-b4e7-2e7838c91ba9	747	BTT	HOLDING	smartbotapp	0.44199360	COMPLETED	{"coin": "BTT", "amount": "0.44199360", "balance": "22971509.44322897", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:34:17.658838+07	2026-09-21 15:34:17.684816+07	2026-09-21 15:34:18.014727+07	2026-09-21 15:34:18.014727+07
77ad0a09-03d3-4a22-8b8b-b13fad1a2076	747	BTT	KANGDEN	kangden69	0.07366560	COMPLETED	{"coin": "BTT", "amount": "0.07366560", "balance": "22971509.36956337", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:34:17.682443+07	2026-09-21 15:34:18.025735+07	2026-09-21 15:34:18.420942+07	2026-09-21 15:34:18.420942+07
21a9bf03-d3a4-44e8-8091-e2047b7ccb2c	751	BTT	HOLDING	smartbotapp	975302.51575296	COMPLETED	{"coin": "BTT", "amount": "975302.51575296", "balance": "17388680.11684480", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:57:13.946662+07	2026-09-21 15:57:13.965674+07	2026-09-21 15:57:14.27351+07	2026-09-21 15:57:14.27351+07
3c830737-aa3c-449c-a3f6-1ea871d8ee48	747	BTT	HOLDING	smartbotapp	0.45904104	COMPLETED	{"coin": "BTT", "amount": "0.45904104", "balance": "22971514.44896721", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:34:42.671648+07	2026-09-21 15:34:42.684463+07	2026-09-21 15:34:42.992458+07	2026-09-21 15:34:42.992458+07
ccad4d4a-9737-41a1-bf73-d34d99c0ac39	747	BTT	KANGDEN	kangden69	0.07650684	COMPLETED	{"coin": "BTT", "amount": "0.07650684", "balance": "22971516.57522037", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:34:42.674017+07	2026-09-21 15:34:42.999675+07	2026-09-21 15:34:43.299534+07	2026-09-21 15:34:43.299534+07
55d9972e-3031-41e7-bbe7-9ecf01710bbe	751	BTT	KANGDEN	kangden69	162550.41929216	COMPLETED	{"coin": "BTT", "amount": "162550.41929216", "balance": "17226129.69755264", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:57:13.962095+07	2026-09-21 15:57:14.281232+07	2026-09-21 15:57:14.598516+07	2026-09-21 15:57:14.598516+07
50302dbb-8f73-4a26-a301-64a301c7ee4a	747	BTT	HOLDING	smartbotapp	0.63343116	COMPLETED	{"coin": "BTT", "amount": "0.63343116", "balance": "22971517.91762221", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:34:47.659546+07	2026-09-21 15:34:47.667955+07	2026-09-21 15:34:48.009705+07	2026-09-21 15:34:48.009705+07
e89d3635-e32e-4fb8-95d1-4736062553e6	747	BTT	KANGDEN	kangden69	0.10557186	COMPLETED	{"coin": "BTT", "amount": "0.10557186", "balance": "22971517.61205035", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:34:47.662616+07	2026-09-21 15:34:48.018818+07	2026-09-21 15:34:48.320206+07	2026-09-21 15:34:48.320206+07
6a34d15c-37c2-4aba-b449-5c200fd7ed8f	751	FLOKI	HOLDING	smartbotapp	0.10053344	COMPLETED	{"coin": "FLOKI", "amount": "0.10053344", "balance": "16273.13793355", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:11:44.058423+07	2026-09-21 16:11:44.070882+07	2026-09-21 16:11:44.491803+07	2026-09-21 16:11:44.491803+07
f3fcf39c-c7b0-4735-8477-720e5b0631bf	751	FLOKI	KANGDEN	kangden69	0.01675556	COMPLETED	{"coin": "FLOKI", "amount": "0.01675556", "balance": "16272.64117799", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:11:44.066877+07	2026-09-21 16:11:44.499704+07	2026-09-21 16:11:44.849507+07	2026-09-21 16:11:44.849507+07
4447a929-83c1-432c-89c9-135726905bc7	747	BTT	HOLDING	smartbotapp	0.48820656	COMPLETED	{"coin": "BTT", "amount": "0.48820656", "balance": "22971518.99223179", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:34:52.659125+07	2026-09-21 15:34:52.664935+07	2026-09-21 15:34:53.027038+07	2026-09-21 15:34:53.027038+07
a543e9e2-917e-4c6e-bd06-6a9f5c875e91	747	BTT	KANGDEN	kangden69	0.08136776	COMPLETED	{"coin": "BTT", "amount": "0.08136776", "balance": "22971517.31086403", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:34:52.66201+07	2026-09-21 15:34:53.031967+07	2026-09-21 15:34:53.333852+07	2026-09-21 15:34:53.333852+07
5e318b25-b561-431b-ae26-0f696e92ad11	751	FLOKI	HOLDING	smartbotapp	0.37772883	COMPLETED	{"coin": "FLOKI", "amount": "0.37772883", "balance": "16291.52157238", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:04.042309+07	2026-09-21 16:12:04.046862+07	2026-09-21 16:12:04.348773+07	2026-09-21 16:12:04.348773+07
745de738-4d40-4a7a-ab5f-421d17553f47	747	BTT	HOLDING	smartbotapp	31.14635808	COMPLETED	{"coin": "BTT", "amount": "31.14635808", "balance": "22971646.21748995", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:34:57.660404+07	2026-09-21 15:34:57.664601+07	2026-09-21 15:34:58.046326+07	2026-09-21 15:34:58.046326+07
935cfb16-55ab-41cc-b531-2909b9a971a2	747	BTT	KANGDEN	kangden69	5.19105968	COMPLETED	{"coin": "BTT", "amount": "5.19105968", "balance": "22971640.92643027", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:34:57.662202+07	2026-09-21 15:34:58.051318+07	2026-09-21 15:34:58.35152+07	2026-09-21 15:34:58.35152+07
5fed0f39-6e01-4240-99ad-0c52d07686d5	751	FLOKI	KANGDEN	kangden69	0.06295479	COMPLETED	{"coin": "FLOKI", "amount": "0.06295479", "balance": "16291.21861759", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:04.044351+07	2026-09-21 16:12:04.352735+07	2026-09-21 16:12:04.6618+07	2026-09-21 16:12:04.6618+07
833eee98-0a9c-4fcd-b185-3fbe267847eb	747	BTT	HOLDING	smartbotapp	0.54177360	COMPLETED	{"coin": "BTT", "amount": "0.54177360", "balance": "22971642.49943667", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:35:02.657628+07	2026-09-21 15:35:03.002218+07	2026-09-21 15:35:03.317362+07	2026-09-21 15:35:03.317362+07
6fee5d82-8dca-454c-9932-b04f69a595af	747	BTT	HOLDING	smartbotapp	0.76684428	COMPLETED	{"coin": "BTT", "amount": "0.76684428", "balance": "22971648.33585261", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:42:08.958536+07	2026-09-21 15:42:08.994916+07	2026-09-21 15:42:09.309436+07	2026-09-21 15:42:09.309436+07
538c6318-00f4-4540-b5bf-7ef98dc34396	747	BTT	KANGDEN	kangden69	0.12780738	COMPLETED	{"coin": "BTT", "amount": "0.12780738", "balance": "22971648.00804523", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:42:08.961388+07	2026-09-21 15:42:09.314917+07	2026-09-21 15:42:09.677887+07	2026-09-21 15:42:09.677887+07
71d188e5-87f3-4e3d-8cdd-1c4feafc4977	747	BTT	HOLDING	smartbotapp	1.46951364	COMPLETED	{"coin": "BTT", "amount": "1.46951364", "balance": "22971656.17160159", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:42:13.94701+07	2026-09-21 15:42:13.952017+07	2026-09-21 15:42:14.291303+07	2026-09-21 15:42:14.291303+07
39b48cd6-0713-4814-bd77-1e24ee51015a	747	BTT	KANGDEN	kangden69	0.24491894	COMPLETED	{"coin": "BTT", "amount": "0.24491894", "balance": "22971655.92668265", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:42:13.949244+07	2026-09-21 15:42:14.295313+07	2026-09-21 15:42:14.598866+07	2026-09-21 15:42:14.598866+07
7055847c-17da-49f8-a39d-cc342e37322c	747	BTT	HOLDING	smartbotapp	0.03379572	COMPLETED	{"coin": "BTT", "amount": "0.03379572", "balance": "22971505.33377775", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:21:11.488273+07	2026-09-21 11:21:11.495746+07	2026-09-21 11:21:11.811365+07	2026-09-21 11:21:11.811365+07
51c5fe74-20ed-4abc-a51b-f0f6285c2bb3	747	BTT	HOLDING	smartbotapp	0.90121920	COMPLETED	{"coin": "BTT", "amount": "0.90121920", "balance": "22971504.13505393", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:21:16.489232+07	2026-09-21 11:21:16.500905+07	2026-09-21 11:21:16.79458+07	2026-09-21 11:21:16.79458+07
cb5c5114-c195-4a00-87d2-158b4399d6c7	751	BTT	HOLDING	smartbotapp	0.10666656	COMPLETED	{"coin": "BTT", "amount": "0.10666656", "balance": "13584085.90952572", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:50:48.948077+07	2026-09-21 15:50:49.032588+07	2026-09-21 15:50:49.482976+07	2026-09-21 15:50:49.482976+07
6315e59c-305a-4c8f-9b82-d9b692e12176	747	BTT	HOLDING	smartbotapp	0.63514560	COMPLETED	{"coin": "BTT", "amount": "0.63514560", "balance": "22971507.40174417", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:24:46.673647+07	2026-09-21 11:24:46.693092+07	2026-09-21 11:24:47.001523+07	2026-09-21 11:24:47.001523+07
29c2033e-b98c-4b93-9ae7-9dd2227c652e	747	BTT	KANGDEN	kangden69	0.10585760	COMPLETED	{"coin": "BTT", "amount": "0.10585760", "balance": "22971507.29588657", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 11:24:46.680597+07	2026-09-21 11:24:47.008078+07	2026-09-21 11:24:47.351177+07	2026-09-21 11:24:47.351177+07
efc9345a-85c1-4980-8957-161d26f2a18b	751	BTT	HOLDING	smartbotapp	0.45333288	COMPLETED	{"coin": "BTT", "amount": "0.45333288", "balance": "13584088.11618908", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:50:53.966943+07	2026-09-21 15:50:53.979214+07	2026-09-21 15:50:54.310258+07	2026-09-21 15:50:54.310258+07
bba1b9ee-e31f-4670-8a87-6b0a9cbeef2c	751	BTT	KANGDEN	kangden69	0.07555548	COMPLETED	{"coin": "BTT", "amount": "0.07555548", "balance": "13584088.04063360", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:50:53.970438+07	2026-09-21 15:50:54.332566+07	2026-09-21 15:50:54.713512+07	2026-09-21 15:50:54.713512+07
0924e7c3-751f-4437-b629-e5a2b01498ef	747	BTT	HOLDING	smartbotapp	1.04918496	COMPLETED	{"coin": "BTT", "amount": "1.04918496", "balance": "22971513.45753041", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:34:22.659418+07	2026-09-21 15:34:22.665369+07	2026-09-21 15:34:22.966582+07	2026-09-21 15:34:22.966582+07
0a3c5edb-767d-4eb5-a105-244d2893d958	747	BTT	KANGDEN	kangden69	0.17486416	COMPLETED	{"coin": "BTT", "amount": "0.17486416", "balance": "22971513.28266625", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:34:22.662503+07	2026-09-21 15:34:22.975337+07	2026-09-21 15:34:23.330319+07	2026-09-21 15:34:23.330319+07
f8b72ec5-5f1f-446b-8cf3-1b22142794ce	747	BTT	KANGDEN	kangden69	0.09029560	COMPLETED	{"coin": "BTT", "amount": "0.09029560", "balance": "22971644.48683707", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:35:02.974439+07	2026-09-21 15:35:03.328623+07	2026-09-21 15:35:03.632763+07	2026-09-21 15:35:03.632763+07
51ec225e-0ccd-4cf6-b84d-e40988b7f306	751	BTT	HOLDING	smartbotapp	2.03923200	COMPLETED	{"coin": "BTT", "amount": "2.03923200", "balance": "13584138.59708160", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:56:58.946908+07	2026-09-21 15:56:58.954325+07	2026-09-21 15:56:59.584055+07	2026-09-21 15:56:59.584055+07
f405a2ba-a039-436f-aef4-76e8bf27c61f	751	BTT	KANGDEN	kangden69	0.33987200	COMPLETED	{"coin": "BTT", "amount": "0.33987200", "balance": "13584112.65720960", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:56:58.951735+07	2026-09-21 15:56:59.591849+07	2026-09-21 15:56:59.942974+07	2026-09-21 15:56:59.942974+07
d0d7fe22-046b-4a57-b87d-8b83dad0222c	747	BTT	HOLDING	smartbotapp	0.27951444	COMPLETED	{"coin": "BTT", "amount": "0.27951444", "balance": "22971644.45891363", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:35:07.659006+07	2026-09-21 15:35:07.692331+07	2026-09-21 15:35:08.081156+07	2026-09-21 15:35:08.081156+07
63aebd2c-7318-4402-8987-7c1bc2c10017	747	BTT	KANGDEN	kangden69	0.04658574	COMPLETED	{"coin": "BTT", "amount": "0.04658574", "balance": "22971644.41232789", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:35:07.662783+07	2026-09-21 15:35:08.091363+07	2026-09-21 15:35:08.524977+07	2026-09-21 15:35:08.524977+07
8a9438e4-1659-4bf5-8f30-3ab41eec8a31	751	FLOKI	HOLDING	smartbotapp	7.45592831	COMPLETED	{"coin": "FLOKI", "amount": "7.45592831", "balance": "47147.79903504", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:11:14.043539+07	2026-09-21 16:11:14.052459+07	2026-09-21 16:11:14.70785+07	2026-09-21 16:11:14.70785+07
5d66f584-47a8-42b0-9871-9b9e3f1c7345	747	BTT	HOLDING	smartbotapp	1.79626980	COMPLETED	{"coin": "BTT", "amount": "1.79626980", "balance": "22971663.12086085", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:42:18.947444+07	2026-09-21 15:42:18.967377+07	2026-09-21 15:42:19.282514+07	2026-09-21 15:42:19.282514+07
1e9c3fa3-8b5b-44c0-b3a5-2b3fa202f550	747	BTT	KANGDEN	kangden69	0.29937830	COMPLETED	{"coin": "BTT", "amount": "0.29937830", "balance": "22971663.04221155", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:42:18.96395+07	2026-09-21 15:42:19.289208+07	2026-09-21 15:42:19.723164+07	2026-09-21 15:42:19.723164+07
992f5a8e-b37c-4bfd-ac3c-d222e2827508	751	FLOKI	KANGDEN	kangden69	1.24265471	COMPLETED	{"coin": "FLOKI", "amount": "1.24265471", "balance": "47146.55638033", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:11:14.049413+07	2026-09-21 16:11:14.718934+07	2026-09-21 16:11:15.024655+07	2026-09-21 16:11:15.024655+07
2e81a720-12cc-462a-a2a9-92d50e8e6d62	747	BTT	HOLDING	smartbotapp	0.11152620	COMPLETED	{"coin": "BTT", "amount": "0.11152620", "balance": "22971662.93068535", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:42:23.946743+07	2026-09-21 15:42:23.955277+07	2026-09-21 15:42:24.287536+07	2026-09-21 15:42:24.287536+07
25c97327-7404-4fb2-95e1-44d8da31a7cb	747	BTT	KANGDEN	kangden69	0.01858770	COMPLETED	{"coin": "BTT", "amount": "0.01858770", "balance": "22971662.91209765", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:42:23.952007+07	2026-09-21 15:42:24.294601+07	2026-09-21 15:42:24.647239+07	2026-09-21 15:42:24.647239+07
a4af30ae-e38f-47ac-b2e5-9257625d0363	751	FLOKI	HOLDING	smartbotapp	83.98245887	COMPLETED	{"coin": "FLOKI", "amount": "83.98245887", "balance": "16286.37843986", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:11:19.042679+07	2026-09-21 16:11:19.051106+07	2026-09-21 16:11:19.355518+07	2026-09-21 16:11:19.355518+07
21e4b6f1-e1b0-41fd-9ca2-674d06d64106	751	FLOKI	KANGDEN	kangden69	13.99707647	COMPLETED	{"coin": "FLOKI", "amount": "13.99707647", "balance": "16272.38136339", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:11:19.048116+07	2026-09-21 16:11:19.363187+07	2026-09-21 16:11:19.755974+07	2026-09-21 16:11:19.755974+07
f69d401d-52d8-43ac-9507-bb4418b1aaef	751	FLOKI	HOLDING	smartbotapp	1.24093273	COMPLETED	{"coin": "FLOKI", "amount": "1.24093273", "balance": "16277.82202666", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:11:49.043288+07	2026-09-21 16:11:49.052498+07	2026-09-21 16:11:49.362129+07	2026-09-21 16:11:49.362129+07
3932d43a-a458-4092-a358-c3a928e44349	751	FLOKI	KANGDEN	kangden69	0.20682211	COMPLETED	{"coin": "FLOKI", "amount": "0.20682211", "balance": "16277.13520455", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:11:49.049171+07	2026-09-21 16:11:49.366275+07	2026-09-21 16:11:49.66982+07	2026-09-21 16:11:49.66982+07
1ee777c7-5934-4110-b8bd-5e14e575530b	751	FLOKI	HOLDING	smartbotapp	2.37113494	COMPLETED	{"coin": "FLOKI", "amount": "2.37113494", "balance": "16287.38352761", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:11:54.043749+07	2026-09-21 16:11:54.070828+07	2026-09-21 16:11:54.471405+07	2026-09-21 16:11:54.471405+07
b37d1e59-f37e-4ca7-986b-b28ee955151f	751	FLOKI	KANGDEN	kangden69	0.39518914	COMPLETED	{"coin": "FLOKI", "amount": "0.39518914", "balance": "16287.61566967", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:11:54.046062+07	2026-09-21 16:11:54.478719+07	2026-09-21 16:11:54.794757+07	2026-09-21 16:11:54.794757+07
50f47cea-3766-44d4-8eb0-ba75c8c7628c	751	FLOKI	HOLDING	smartbotapp	0.54742635	COMPLETED	{"coin": "FLOKI", "amount": "0.54742635", "balance": "16289.14279852", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:11:59.042544+07	2026-09-21 16:11:59.048033+07	2026-09-21 16:11:59.355391+07	2026-09-21 16:11:59.355391+07
c13215e3-1d60-4e19-8887-32010638690b	751	FLOKI	KANGDEN	kangden69	0.09123771	COMPLETED	{"coin": "FLOKI", "amount": "0.09123771", "balance": "16291.45382641", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:11:59.044505+07	2026-09-21 16:11:59.361221+07	2026-09-21 16:11:59.666442+07	2026-09-21 16:11:59.666442+07
0d71329a-a648-4a71-93c7-45ec79b1de7a	751	FLOKI	HOLDING	smartbotapp	3020.85203557	COMPLETED	{"coin": "FLOKI", "amount": "3020.85203557", "balance": "32754.04981360", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:44.050727+07	2026-09-21 16:12:44.078385+07	2026-09-21 16:12:44.393995+07	2026-09-21 16:12:44.393995+07
44129580-7ffb-460a-8a3d-a5a258608184	751	FLOKI	HOLDING	smartbotapp	1.34167549	COMPLETED	{"coin": "FLOKI", "amount": "1.34167549", "balance": "16297.51757130", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:09.043025+07	2026-09-21 16:12:09.049628+07	2026-09-21 16:12:09.360237+07	2026-09-21 16:12:09.360237+07
53c4a85f-13bc-44a5-b354-8223a9acfd85	751	FLOKI	KANGDEN	kangden69	0.22361257	COMPLETED	{"coin": "FLOKI", "amount": "0.22361257", "balance": "16297.05395873", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:09.045118+07	2026-09-21 16:12:09.368491+07	2026-09-21 16:12:09.694431+07	2026-09-21 16:12:09.694431+07
985d5635-ceed-4de9-bdc4-3eb1d37c5575	751	FLOKI	KANGDEN	kangden69	503.47533925	COMPLETED	{"coin": "FLOKI", "amount": "503.47533925", "balance": "32250.57447435", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:44.068246+07	2026-09-21 16:12:44.402635+07	2026-09-21 16:12:44.755579+07	2026-09-21 16:12:44.755579+07
21851e8d-4b19-4209-9cb6-fd5c92a904ef	751	FLOKI	HOLDING	smartbotapp	0.38374212	COMPLETED	{"coin": "FLOKI", "amount": "0.38374212", "balance": "16299.28199621", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:14.042146+07	2026-09-21 16:12:14.049224+07	2026-09-21 16:12:14.417655+07	2026-09-21 16:12:14.417655+07
dd2e0bf2-a631-415d-9518-30c9c5bf125f	751	FLOKI	KANGDEN	kangden69	0.06395700	COMPLETED	{"coin": "FLOKI", "amount": "0.06395700", "balance": "16299.15803921", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:14.047127+07	2026-09-21 16:12:14.425874+07	2026-09-21 16:12:14.731956+07	2026-09-21 16:12:14.731956+07
957dc5e9-8fc6-4421-bb86-20cff23185ea	751	FLOKI	HOLDING	smartbotapp	0.03708993	COMPLETED	{"coin": "FLOKI", "amount": "0.03708993", "balance": "32250.72646722", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:49.043667+07	2026-09-21 16:12:49.051909+07	2026-09-21 16:12:49.361273+07	2026-09-21 16:12:49.361273+07
29852333-fe07-44f8-92e6-c588a087f88b	751	FLOKI	HOLDING	smartbotapp	0.15346525	COMPLETED	{"coin": "FLOKI", "amount": "0.15346525", "balance": "16300.13640916", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:19.042588+07	2026-09-21 16:12:19.050897+07	2026-09-21 16:12:19.385051+07	2026-09-21 16:12:19.385051+07
ec874e27-de99-4bf4-8613-c279bf0b5e2d	751	FLOKI	KANGDEN	kangden69	0.00618165	COMPLETED	{"coin": "FLOKI", "amount": "0.00618165", "balance": "32250.86908917", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:49.048411+07	2026-09-21 16:12:49.365818+07	2026-09-21 16:12:49.671407+07	2026-09-21 16:12:49.671407+07
2ea408fd-9e66-4709-a9d8-fc0fcadfbcbe	751	FLOKI	HOLDING	smartbotapp	0.70275916	COMPLETED	{"coin": "FLOKI", "amount": "0.70275916", "balance": "16362.34628687", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:24.042861+07	2026-09-21 16:12:24.050192+07	2026-09-21 16:12:24.354356+07	2026-09-21 16:12:24.354356+07
2197727d-02e4-4d8e-b1b2-0cb53149c944	751	FLOKI	KANGDEN	kangden69	0.11712652	COMPLETED	{"coin": "FLOKI", "amount": "0.11712652", "balance": "16674.88011715", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:24.047513+07	2026-09-21 16:12:24.359745+07	2026-09-21 16:12:24.695669+07	2026-09-21 16:12:24.695669+07
5d712c9b-6d59-4417-b772-366d34ba8f26	751	FLOKI	HOLDING	smartbotapp	0.35161803	COMPLETED	{"coin": "FLOKI", "amount": "0.35161803", "balance": "32252.27881794", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:54.04242+07	2026-09-21 16:12:54.049344+07	2026-09-21 16:12:54.361035+07	2026-09-21 16:12:54.361035+07
4cb8a09e-6edb-400a-a4b7-936a0822cb02	751	FLOKI	HOLDING	smartbotapp	74.28626205	COMPLETED	{"coin": "FLOKI", "amount": "74.28626205", "balance": "16604.53619590", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:29.044469+07	2026-09-21 16:12:29.052719+07	2026-09-21 16:12:29.390628+07	2026-09-21 16:12:29.390628+07
4a83f4af-e525-4b3e-a56d-bf476ee10d59	751	FLOKI	KANGDEN	kangden69	0.05860299	COMPLETED	{"coin": "FLOKI", "amount": "0.05860299", "balance": "32251.98021495", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:54.047103+07	2026-09-21 16:12:54.364149+07	2026-09-21 16:12:54.667378+07	2026-09-21 16:12:54.667378+07
1c7196c4-7739-443f-9148-f3b32de4e241	751	FLOKI	KANGDEN	kangden69	12.38104365	COMPLETED	{"coin": "FLOKI", "amount": "12.38104365", "balance": "16592.09515225", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:29.049776+07	2026-09-21 16:12:29.397837+07	2026-09-21 16:12:29.704993+07	2026-09-21 16:12:29.704993+07
8e109cf8-0207-4847-b9c2-f889a3e9880d	751	FLOKI	KANGDEN	kangden69	0.06925469	COMPLETED	{"coin": "FLOKI", "amount": "0.06925469", "balance": "32257.33780429", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:13:04.048287+07	2026-09-21 16:13:04.358132+07	2026-09-21 16:13:04.669287+07	2026-09-21 16:13:04.669287+07
10dcfc4f-cd4e-4fef-947a-e39f61d3d4a0	751	FLOKI	HOLDING	smartbotapp	0.31390430	COMPLETED	{"coin": "FLOKI", "amount": "0.31390430", "balance": "16561.32722915", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:34.042646+07	2026-09-21 16:12:34.050434+07	2026-09-21 16:12:34.38653+07	2026-09-21 16:12:34.38653+07
f4672f49-fbd8-42c8-a47f-9bb0ff190311	751	FLOKI	KANGDEN	kangden69	0.05231738	COMPLETED	{"coin": "FLOKI", "amount": "0.05231738", "balance": "16598.74163817", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:34.047982+07	2026-09-21 16:12:34.393094+07	2026-09-21 16:12:34.696977+07	2026-09-21 16:12:34.696977+07
c6ea0ce1-d8ca-4c07-8399-0cf307d04e74	751	FLOKI	HOLDING	smartbotapp	0.25823690	COMPLETED	{"coin": "FLOKI", "amount": "0.25823690", "balance": "32257.96992247", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:13:14.041895+07	2026-09-21 16:13:14.048776+07	2026-09-21 16:13:14.358663+07	2026-09-21 16:13:14.358663+07
37531b92-859d-4e6b-8f13-1e0c01b3af82	751	FLOKI	HOLDING	smartbotapp	261.41301962	COMPLETED	{"coin": "FLOKI", "amount": "261.41301962", "balance": "16542.94372255", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:39.043764+07	2026-09-21 16:12:39.051851+07	2026-09-21 16:12:39.360914+07	2026-09-21 16:12:39.360914+07
646a6e70-fa53-4b36-94f8-4f37c2de25f7	751	FLOKI	KANGDEN	kangden69	43.56883658	COMPLETED	{"coin": "FLOKI", "amount": "43.56883658", "balance": "14533.29488597", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:39.049305+07	2026-09-21 16:12:39.36658+07	2026-09-21 16:12:39.704266+07	2026-09-21 16:12:39.704266+07
93ddd4b9-3046-43e2-a50d-6b959b59b2f7	751	FLOKI	KANGDEN	kangden69	0.04303946	COMPLETED	{"coin": "FLOKI", "amount": "0.04303946", "balance": "32257.92688301", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:13:14.04661+07	2026-09-21 16:13:14.364049+07	2026-09-21 16:13:14.680961+07	2026-09-21 16:13:14.680961+07
1a9bf3c7-ebac-4669-92e4-f20f7fa863e9	751	FLOKI	HOLDING	smartbotapp	0.67196784	COMPLETED	{"coin": "FLOKI", "amount": "0.67196784", "balance": "32262.76313417", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:13:19.042582+07	2026-09-21 16:13:19.047199+07	2026-09-21 16:13:19.358375+07	2026-09-21 16:13:19.358375+07
e8305c0c-f77a-4266-9d2d-2bcf70c03750	751	FLOKI	KANGDEN	kangden69	0.11199462	COMPLETED	{"coin": "FLOKI", "amount": "0.11199462", "balance": "32262.65113955", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:13:19.045031+07	2026-09-21 16:13:19.36241+07	2026-09-21 16:13:19.666326+07	2026-09-21 16:13:19.666326+07
2ec5368d-6833-4678-92da-38851d766741	751	FLOKI	HOLDING	smartbotapp	0.08197846	COMPLETED	{"coin": "FLOKI", "amount": "0.08197846", "balance": "32261.18382829", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:13:24.042371+07	2026-09-21 16:13:24.068016+07	2026-09-21 16:13:24.375843+07	2026-09-21 16:13:24.375843+07
ccf316eb-52dd-4bb0-aa8c-7ffd0f7e2a4c	751	FLOKI	KANGDEN	kangden69	0.01366306	COMPLETED	{"coin": "FLOKI", "amount": "0.01366306", "balance": "32261.17016523", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:13:24.04477+07	2026-09-21 16:13:24.379303+07	2026-09-21 16:13:24.796123+07	2026-09-21 16:13:24.796123+07
81f7249b-e8e5-4cbb-b1ab-b6679e7f77e8	751	FLOKI	HOLDING	smartbotapp	76.08611635	COMPLETED	{"coin": "FLOKI", "amount": "76.08611635", "balance": "32575.23501848", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:13:29.042727+07	2026-09-21 16:13:29.047313+07	2026-09-21 16:13:29.356221+07	2026-09-21 16:13:29.356221+07
95ad957f-c786-44c6-b856-f8125f607eb5	751	FLOKI	KANGDEN	kangden69	12.68101939	COMPLETED	{"coin": "FLOKI", "amount": "12.68101939", "balance": "32562.55399909", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:13:29.044734+07	2026-09-21 16:13:29.360194+07	2026-09-21 16:13:29.710442+07	2026-09-21 16:13:29.710442+07
b3ba2d76-8097-4950-aa5d-c017bed694f5	751	FLOKI	KANGDEN	kangden69	0.02557753	COMPLETED	{"coin": "FLOKI", "amount": "0.02557753", "balance": "16299.15083163", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:19.047476+07	2026-09-21 16:12:19.389582+07	2026-09-21 16:12:19.697847+07	2026-09-21 16:12:19.697847+07
fc4806d1-a9ec-4c8b-87aa-6e636fb7ce2d	751	FLOKI	HOLDING	smartbotapp	0.64316771	COMPLETED	{"coin": "FLOKI", "amount": "0.64316771", "balance": "32254.83677824", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:59.042595+07	2026-09-21 16:12:59.051598+07	2026-09-21 16:12:59.360532+07	2026-09-21 16:12:59.360532+07
a445acbd-8a5a-40db-bb57-17c23c8cefa9	751	FLOKI	KANGDEN	kangden69	0.10719461	COMPLETED	{"coin": "FLOKI", "amount": "0.10719461", "balance": "32255.32785083", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:59.04824+07	2026-09-21 16:12:59.364403+07	2026-09-21 16:12:59.707668+07	2026-09-21 16:12:59.707668+07
7bf8dfce-6660-49ec-bd70-1e28da37f6f3	751	FLOKI	HOLDING	smartbotapp	0.41552825	COMPLETED	{"coin": "FLOKI", "amount": "0.41552825", "balance": "32257.33017138", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:13:04.043563+07	2026-09-21 16:13:04.05167+07	2026-09-21 16:13:04.353395+07	2026-09-21 16:13:04.353395+07
f0c33429-e3fb-41cf-bbc1-c0f5345a8a6f	751	FLOKI	HOLDING	smartbotapp	0.20771840	COMPLETED	{"coin": "FLOKI", "amount": "0.20771840", "balance": "32258.09080469", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:13:09.042545+07	2026-09-21 16:13:09.049382+07	2026-09-21 16:13:09.357056+07	2026-09-21 16:13:09.357056+07
a4fb0637-0467-4db3-a436-dda48cc598e8	751	FLOKI	KANGDEN	kangden69	0.03461972	COMPLETED	{"coin": "FLOKI", "amount": "0.03461972", "balance": "32258.05618497", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:13:09.047243+07	2026-09-21 16:13:09.361292+07	2026-09-21 16:13:09.671607+07	2026-09-21 16:13:09.671607+07
6c26d52f-0e34-41df-a3df-8c289331109c	751	FLOKI	HOLDING	smartbotapp	0.39799784	COMPLETED	{"coin": "FLOKI", "amount": "0.39799784", "balance": "32564.76698765", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:13:34.042964+07	2026-09-21 16:13:34.04693+07	2026-09-21 16:13:34.350765+07	2026-09-21 16:13:34.350765+07
6d3d9343-1346-45b5-9bbd-71e6f495f413	751	FLOKI	KANGDEN	kangden69	0.06633296	COMPLETED	{"coin": "FLOKI", "amount": "0.06633296", "balance": "32564.70065469", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:13:34.044758+07	2026-09-21 16:13:34.354553+07	2026-09-21 16:13:34.66302+07	2026-09-21 16:13:34.66302+07
4e2de8b2-d404-4a0d-aaf8-cdf2332d7f5f	751	FLOKI	HOLDING	smartbotapp	1.07314155	COMPLETED	{"coin": "FLOKI", "amount": "1.07314155", "balance": "32576.29685394", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:13:39.043684+07	2026-09-21 16:13:39.048007+07	2026-09-21 16:13:39.356115+07	2026-09-21 16:13:39.356115+07
6b6ef823-b0d8-46ae-ad21-5c22ca7f622c	751	FLOKI	KANGDEN	kangden69	0.17885691	COMPLETED	{"coin": "FLOKI", "amount": "0.17885691", "balance": "32576.11799703", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:13:39.045616+07	2026-09-21 16:13:39.360683+07	2026-09-21 16:13:39.669027+07	2026-09-21 16:13:39.669027+07
d0617c56-30c3-4873-ba91-d0ef4f23ce06	751	FLOKI	HOLDING	smartbotapp	11.62294272	COMPLETED	{"coin": "FLOKI", "amount": "11.62294272", "balance": "33822.84769431", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:13:44.042985+07	2026-09-21 16:13:44.056895+07	2026-09-21 16:13:44.365081+07	2026-09-21 16:13:44.365081+07
59239720-3815-484b-9d70-e32c479e73d0	751	FLOKI	KANGDEN	kangden69	1.93715712	COMPLETED	{"coin": "FLOKI", "amount": "1.93715712", "balance": "33820.91053719", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:13:44.048145+07	2026-09-21 16:13:44.372716+07	2026-09-21 16:13:44.766687+07	2026-09-21 16:13:44.766687+07
26a04d34-9469-4dea-a56d-3f3629c85bcc	751	FLOKI	HOLDING	smartbotapp	611.69467392	COMPLETED	{"coin": "FLOKI", "amount": "611.69467392", "balance": "5684.09586327", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:13:49.043522+07	2026-09-21 16:13:49.060169+07	2026-09-21 16:13:49.477551+07	2026-09-21 16:13:49.477551+07
e7ae8ea7-b389-4a19-8f62-4ecc5489fdb0	751	FLOKI	KANGDEN	kangden69	101.94911232	COMPLETED	{"coin": "FLOKI", "amount": "101.94911232", "balance": "5582.14675095", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:13:49.057739+07	2026-09-21 16:13:49.484878+07	2026-09-21 16:13:49.789388+07	2026-09-21 16:13:49.789388+07
d91b7b27-41a0-4746-a616-07be992c23f7	747	BTT	HOLDING	smartbotapp	114.03460776	COMPLETED	{"coin": "BTT", "amount": "114.03460776", "balance": "24788876.62867781", "message": "Successfully transferred to user", "success": true}	\N	2026-09-23 04:53:17.638371+07	2026-09-23 04:53:17.656548+07	2026-09-23 04:53:17.956605+07	2026-09-23 04:53:17.956605+07
06c5e42e-3209-417b-b440-37ef765c8034	747	BTT	KANGDEN	kangden69	19.00576796	COMPLETED	{"coin": "BTT", "amount": "19.00576796", "balance": "24788857.52290985", "message": "Successfully transferred to user", "success": true}	\N	2026-09-23 04:53:17.654442+07	2026-09-23 04:53:17.962629+07	2026-09-23 04:53:18.463261+07	2026-09-23 04:53:18.463261+07
48d867fd-65cf-4885-bc7e-dd8513bd2446	747	BTT	HOLDING	smartbotapp	2.74814208	COMPLETED	{"coin": "BTT", "amount": "2.74814208", "balance": "24788871.47595177", "message": "Successfully transferred to user", "success": true}	\N	2026-09-23 04:53:47.638134+07	2026-09-23 04:53:47.658648+07	2026-09-23 04:53:47.961771+07	2026-09-23 04:53:47.961771+07
5b30fdae-8331-43b1-9ca5-41a69789e8a6	747	BTT	KANGDEN	kangden69	0.45802368	COMPLETED	{"coin": "BTT", "amount": "0.45802368", "balance": "24788871.01792809", "message": "Successfully transferred to user", "success": true}	\N	2026-09-23 04:53:47.640852+07	2026-09-23 04:53:47.967622+07	2026-09-23 04:53:48.267121+07	2026-09-23 04:53:48.267121+07
\.


--
-- Data for Name: owner_cutoff_batches; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.owner_cutoff_batches (id, business_date, cutoff_slot, coin, collector_balance, reserved_liability, distributable_amount, status, created_at, completed_at, updated_at) FROM stdin;
\.


--
-- Data for Name: owner_cutoff_payouts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.owner_cutoff_payouts (id, batch_id, allocation, recipient_username, percentage, amount, status, provider_response, failure_reason, created_at, sent_at, completed_at, updated_at) FROM stdin;
\.


--
-- Data for Name: provider_bets; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.provider_bets (id, session_id, user_id, coin, amount, chance, status, provider_reference, provider_balance_before, provider_balance_after, gross_profit, user_profit, result, prepared_at, sent_at, completed_at, request_payload, response_payload, holding_amount, kangden_amount, updated_at) FROM stdin;
6e58f47b-3438-4474-ac5e-f9f9daf307f5	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	0.10000000	23.0700	COMPLETED	34019604221	24788451.37488757	24788451.68667757	0.31179000	0.26813940	WIN	2026-09-23 04:52:54.485062+07	2026-09-23 04:52:54.507408+07	2026-09-23 04:52:54.716633+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "4.11790", "profit": "0.31179000", "bet_amt": "0.10000000", "client_seed": "45ccaa016c2d797306b5a8f1ad69204b", "winning_chance": "23.07"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019604221", "payout": "4.11790", "profit": "0.31179000", "balance": "24788451.68667757", "time_taken": 0.0254058837890625, "roll_number": 7827}	0.03741480	0.00623580	2026-09-23 04:52:54.716633+07
1af8cefe-a9dc-417c-a9c4-b9be608f4882	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	0.10000000	22.6900	COMPLETED	34019604276	24788451.68667757	24788451.58667757	-0.10000000	-0.10000000	LOSS	2026-09-23 04:52:55.736142+07	2026-09-23 04:52:55.74881+07	2026-09-23 04:52:55.955122+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "4.18686", "profit": "0.31868600", "bet_amt": "0.10000000", "client_seed": "a273a561404fa75740003276cb50200b", "winning_chance": "22.69"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019604276", "payout": "4.18686", "profit": "-0.10000000", "balance": "24788451.58667757", "time_taken": 0.023231029510498047, "roll_number": 2139}	0.00000000	0.00000000	2026-09-23 04:52:55.955122+07
0b221394-e336-4446-a715-35bea44fe845	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	0.20000000	24.0100	COMPLETED	34019604319	24788451.58667757	24788451.38667757	-0.20000000	-0.20000000	LOSS	2026-09-23 04:52:56.96595+07	2026-09-23 04:52:56.968457+07	2026-09-23 04:52:57.174735+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "3.95668", "profit": "0.59133600", "bet_amt": "0.20000000", "client_seed": "730d2a0ecde4b0d025e67bdb23b8d7f2", "winning_chance": "24.01"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019604319", "payout": "3.95668", "profit": "-0.20000000", "balance": "24788451.38667757", "time_taken": 0.023538827896118164, "roll_number": 4862}	0.00000000	0.00000000	2026-09-23 04:52:57.174735+07
de7bdaeb-7f0a-42db-b6a8-d228310f25e8	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	0.40000000	26.4700	COMPLETED	34019604385	24788451.38667757	24788450.98667757	-0.40000000	-0.40000000	LOSS	2026-09-23 04:52:58.183235+07	2026-09-23 04:52:58.185686+07	2026-09-23 04:52:58.392448+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.58896", "profit": "1.03558400", "bet_amt": "0.40000000", "client_seed": "da79573cb03226196d483cc8b58eeddf", "winning_chance": "26.47"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019604385", "payout": "3.58896", "profit": "-0.40000000", "balance": "24788450.98667757", "time_taken": 0.0234677791595459, "roll_number": 2069}	0.00000000	0.00000000	2026-09-23 04:52:58.392448+07
483a57f6-7451-4551-b119-3515eb0fd80f	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	0.80000000	23.3500	COMPLETED	34019604437	24788450.98667757	24788450.18667757	-0.80000000	-0.80000000	LOSS	2026-09-23 04:52:59.40168+07	2026-09-23 04:52:59.403666+07	2026-09-23 04:52:59.610111+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "4.06852", "profit": "2.45481600", "bet_amt": "0.80000000", "client_seed": "ab101144f63a1a25cc07e3507c2584e4", "winning_chance": "23.35"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019604437", "payout": "4.06852", "profit": "-0.80000000", "balance": "24788450.18667757", "time_taken": 0.023910045623779297, "roll_number": 3512}	0.00000000	0.00000000	2026-09-23 04:52:59.610111+07
a04c3985-0c9a-4e0b-99e1-572b8a5ff312	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	1.60000000	27.7600	COMPLETED	34019604509	24788450.18667757	24788448.58667757	-1.60000000	-1.60000000	LOSS	2026-09-23 04:53:00.61716+07	2026-09-23 04:53:00.619427+07	2026-09-23 04:53:00.824553+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "3.42219", "profit": "3.87550400", "bet_amt": "1.60000000", "client_seed": "c599c682cc15fcec4ac6c7a963b727db", "winning_chance": "27.76"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019604509", "payout": "3.42219", "profit": "-1.60000000", "balance": "24788448.58667757", "time_taken": 0.022227048873901367, "roll_number": 5271}	0.00000000	0.00000000	2026-09-23 04:53:00.824553+07
0ba8c576-bd5e-40d3-a4c0-edd6e2f97374	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	3.20000000	23.6300	COMPLETED	34019604565	24788448.58667757	24788445.38667757	-3.20000000	-3.20000000	LOSS	2026-09-23 04:53:01.856537+07	2026-09-23 04:53:01.859886+07	2026-09-23 04:53:02.067582+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "4.02031", "profit": "9.66499200", "bet_amt": "3.20000000", "client_seed": "5fd055a6be92f395a608ea8f56fe4f2c", "winning_chance": "23.63"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019604565", "payout": "4.02031", "profit": "-3.20000000", "balance": "24788445.38667757", "time_taken": 0.024765968322753906, "roll_number": 4700}	0.00000000	0.00000000	2026-09-23 04:53:02.067582+07
ed7b2b9b-54c4-4b7e-bdce-cbf963c750dc	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	6.40000000	26.7700	COMPLETED	34019604632	24788445.38667757	24788438.98667757	-6.40000000	-6.40000000	LOSS	2026-09-23 04:53:03.088386+07	2026-09-23 04:53:03.092287+07	2026-09-23 04:53:03.299483+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.54874", "profit": "16.31193600", "bet_amt": "6.40000000", "client_seed": "039af601254a11ab9738b3a7bbeedcbd", "winning_chance": "26.77"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019604632", "payout": "3.54874", "profit": "-6.40000000", "balance": "24788438.98667757", "time_taken": 0.023586034774780273, "roll_number": 6345}	0.00000000	0.00000000	2026-09-23 04:53:03.299483+07
9d49e159-4fce-4a96-86d4-17cbe03cfaa8	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	12.80000000	26.1700	COMPLETED	34019604688	24788438.98667757	24788426.18667757	-12.80000000	-12.80000000	LOSS	2026-09-23 04:53:04.319905+07	2026-09-23 04:53:04.321847+07	2026-09-23 04:53:04.528533+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.63011", "profit": "33.66540800", "bet_amt": "12.80000000", "client_seed": "80e9c74522bc627faccbb363963bc0f1", "winning_chance": "26.17"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019604688", "payout": "3.63011", "profit": "-12.80000000", "balance": "24788426.18667757", "time_taken": 0.023370981216430664, "roll_number": 3100}	0.00000000	0.00000000	2026-09-23 04:53:04.528533+07
dd45d165-7695-45a8-9cb2-f2e590bcffdb	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	25.60000000	24.3800	COMPLETED	34019604741	24788426.18667757	24788400.58667757	-25.60000000	-25.60000000	LOSS	2026-09-23 04:53:05.541733+07	2026-09-23 04:53:05.54511+07	2026-09-23 04:53:05.753703+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "3.89663", "profit": "74.15372800", "bet_amt": "25.60000000", "client_seed": "b4bf6dbbd41364c7eb119a706f439c16", "winning_chance": "24.38"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019604741", "payout": "3.89663", "profit": "-25.60000000", "balance": "24788400.58667757", "time_taken": 0.02586197853088379, "roll_number": 9983}	0.00000000	0.00000000	2026-09-23 04:53:05.753703+07
0f159474-9502-4ccb-87d6-14198acba050	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	51.20000000	26.4300	COMPLETED	34019604787	24788400.58667757	24788349.38667757	-51.20000000	-51.20000000	LOSS	2026-09-23 04:53:06.766167+07	2026-09-23 04:53:06.76823+07	2026-09-23 04:53:06.975321+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.59440", "profit": "132.83328000", "bet_amt": "51.20000000", "client_seed": "3029653860349f83c76a6977bd862ff0", "winning_chance": "26.43"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019604787", "payout": "3.59440", "profit": "-51.20000000", "balance": "24788349.38667757", "time_taken": 0.024003028869628906, "roll_number": 6822}	0.00000000	0.00000000	2026-09-23 04:53:06.975321+07
5466927b-16c6-46ca-946c-b9a389778571	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	102.40000000	25.9500	COMPLETED	34019604856	24788349.38667757	24788246.98667757	-102.40000000	-102.40000000	LOSS	2026-09-23 04:53:07.986484+07	2026-09-23 04:53:07.989544+07	2026-09-23 04:53:08.199375+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.66088", "profit": "272.47411200", "bet_amt": "102.40000000", "client_seed": "0ac444884e7d5523594e34d39d7f29d9", "winning_chance": "25.95"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019604856", "payout": "3.66088", "profit": "-102.40000000", "balance": "24788246.98667757", "time_taken": 0.024253129959106445, "roll_number": 1252}	0.00000000	0.00000000	2026-09-23 04:53:08.199375+07
ddb3d778-4cac-41bd-9cc6-095b7958c644	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.10000000	38.2000	COMPLETED	34019643941	459868.00385268	459868.15254368	0.14869100	0.14869100	WIN	2026-09-23 05:05:35.991421+07	2026-09-23 05:05:36.022154+07	2026-09-23 05:05:36.23629+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.48691", "profit": "0.14869100", "bet_amt": "0.10000000", "client_seed": "5be9d4a7340c8f4d64094471fe949f61", "winning_chance": "38.20"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019643941", "payout": "2.48691", "profit": "0.14869100", "balance": "459868.15254368", "time_taken": 0.030183076858520508, "roll_number": 191}	0.00000000	0.00000000	2026-09-23 05:05:36.23629+07
e099afe4-f238-4354-9395-ca0ea4efef8c	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.80000000	39.6900	COMPLETED	34019693509	459935.31882868	459934.51882868	-0.80000000	-0.80000000	LOSS	2026-09-23 05:21:44.953773+07	2026-09-23 05:21:44.964025+07	2026-09-23 05:21:45.173995+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.39355", "profit": "1.11484000", "bet_amt": "0.80000000", "client_seed": "39015b6d2660a9a05a66a6b64a4bfca8", "winning_chance": "39.69"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693509", "payout": "2.39355", "profit": "-0.80000000", "balance": "459934.51882868", "time_taken": 0.026136159896850586, "roll_number": 3195}	0.00000000	0.00000000	2026-09-23 05:21:45.173995+07
cfbd6ae8-f00b-4bbd-8fbe-6c9ebb131d9a	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	409.60000000	28.7000	COMPLETED	34019604983	24788042.18667757	24788988.40363757	946.21696000	813.74658560	WIN	2026-09-23 04:53:10.447994+07	2026-09-23 04:53:10.449402+07	2026-09-23 04:53:10.660852+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.31010", "profit": "946.21696000", "bet_amt": "409.60000000", "client_seed": "300923ff9ced28d015111053e255a03b", "winning_chance": "28.70"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019604983", "payout": "3.31010", "profit": "946.21696000", "balance": "24788988.40363757", "time_taken": 0.030139923095703125, "roll_number": 8436}	113.54603520	18.92433920	2026-09-23 04:53:10.660852+07
d017f5ed-3ef8-4203-b91f-6767e765f829	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.10000000	37.1000	COMPLETED	34019643961	459868.15254368	459868.05254368	-0.10000000	-0.10000000	LOSS	2026-09-23 05:05:36.346905+07	2026-09-23 05:05:36.34898+07	2026-09-23 05:05:36.558314+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.56064", "profit": "0.15606400", "bet_amt": "0.10000000", "client_seed": "5042a90d68632ee9ec4e65c31bc1f27e", "winning_chance": "37.10"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019643961", "payout": "2.56064", "profit": "-0.10000000", "balance": "459868.05254368", "time_taken": 0.026312828063964844, "roll_number": 8143}	0.00000000	0.00000000	2026-09-23 05:05:36.558314+07
cf59d9e6-2821-4046-96b9-829cca5af0d2	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	0.20000000	23.0900	COMPLETED	34019605124	24788988.30363757	24788988.10363757	-0.20000000	-0.20000000	LOSS	2026-09-23 04:53:13.088081+07	2026-09-23 04:53:13.090838+07	2026-09-23 04:53:13.300139+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "4.11433", "profit": "0.62286600", "bet_amt": "0.20000000", "client_seed": "2e1a7d2f29429bd8411be30fa0eb5316", "winning_chance": "23.09"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019605124", "payout": "4.11433", "profit": "-0.20000000", "balance": "24788988.10363757", "time_taken": 0.026556015014648438, "roll_number": 1018}	0.00000000	0.00000000	2026-09-23 04:53:13.300139+07
3244370a-5855-4487-a9e3-6abe0e7f5961	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	0.80000000	22.0700	COMPLETED	34019605223	24788987.70363757	24788986.90363757	-0.80000000	-0.80000000	LOSS	2026-09-23 04:53:15.534239+07	2026-09-23 04:53:15.536174+07	2026-09-23 04:53:15.7434+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "4.30448", "profit": "2.64358400", "bet_amt": "0.80000000", "client_seed": "8794da28cf2214ddfe49f9e2dcfb1198", "winning_chance": "22.07"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019605223", "payout": "4.30448", "profit": "-0.80000000", "balance": "24788986.90363757", "time_taken": 0.02495408058166504, "roll_number": 6312}	0.00000000	0.00000000	2026-09-23 04:53:15.7434+07
0416cc83-5151-45f8-841d-ae1c48a3f26c	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	1.60000000	39.5100	COMPLETED	34019644029	459866.65254368	459868.89966368	2.24712000	2.24712000	WIN	2026-09-23 05:05:37.663089+07	2026-09-23 05:05:37.665543+07	2026-09-23 05:05:37.875133+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.40445", "profit": "2.24712000", "bet_amt": "1.60000000", "client_seed": "688266200bd18ccbcf2d4499890af406", "winning_chance": "39.51"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019644029", "payout": "2.40445", "profit": "2.24712000", "balance": "459868.89966368", "time_taken": 0.026983022689819336, "roll_number": 1363}	0.00000000	0.00000000	2026-09-23 05:05:37.875133+07
cd9c1fe0-8b86-4145-a488-9774b0b5d6b5	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	0.10000000	22.6100	COMPLETED	34019605377	24788876.62867781	24788876.52867781	-0.10000000	-0.10000000	LOSS	2026-09-23 04:53:17.975543+07	2026-09-23 04:53:17.977389+07	2026-09-23 04:53:18.180917+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "4.20168", "profit": "0.32016800", "bet_amt": "0.10000000", "client_seed": "b98d878e79db10abf0ddb9b0fa7d7624", "winning_chance": "22.61"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019605377", "payout": "4.20168", "profit": "-0.10000000", "balance": "24788876.52867781", "time_taken": 0.021798133850097656, "roll_number": 1364}	0.00000000	0.00000000	2026-09-23 04:53:18.180917+07
cabc9107-4504-4ad8-9094-92d9eb4b666d	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	0.40000000	26.0600	COMPLETED	34019605505	24788857.32290985	24788856.92290985	-0.40000000	-0.40000000	LOSS	2026-09-23 04:53:20.437115+07	2026-09-23 04:53:20.438816+07	2026-09-23 04:53:20.644859+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.64543", "profit": "1.05817200", "bet_amt": "0.40000000", "client_seed": "4a82c03de38588742c5997d354e066c2", "winning_chance": "26.06"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019605505", "payout": "3.64543", "profit": "-0.40000000", "balance": "24788856.92290985", "time_taken": 0.0245969295501709, "roll_number": 4179}	0.00000000	0.00000000	2026-09-23 04:53:20.644859+07
4e53e675-6d15-4cf4-8037-eb4fd83b25df	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	1.60000000	20.6900	COMPLETED	34019605670	24788856.12290985	24788854.52290985	-1.60000000	-1.60000000	LOSS	2026-09-23 04:53:22.887471+07	2026-09-23 04:53:22.889375+07	2026-09-23 04:53:23.093999+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "4.59159", "profit": "5.74654400", "bet_amt": "1.60000000", "client_seed": "0415d4ed0ec7dd018f0809d5b935c125", "winning_chance": "20.69"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019605670", "payout": "4.59159", "profit": "-1.60000000", "balance": "24788854.52290985", "time_taken": 0.023055076599121094, "roll_number": 5104}	0.00000000	0.00000000	2026-09-23 04:53:23.093999+07
b8b36047-e4dd-49a2-9843-9d7d302e3a94	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	6.40000000	20.7500	COMPLETED	34019605786	24788851.32290985	24788874.22409385	22.90118400	19.69501824	WIN	2026-09-23 04:53:25.318779+07	2026-09-23 04:53:25.349411+07	2026-09-23 04:53:25.556641+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "4.57831", "profit": "22.90118400", "bet_amt": "6.40000000", "client_seed": "5e5b0cc7226b381afb8c16397d1b3ff6", "winning_chance": "20.75"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019605786", "payout": "4.57831", "profit": "22.90118400", "balance": "24788874.22409385", "time_taken": 0.025300025939941406, "roll_number": 9142}	2.74814208	0.45802368	2026-09-23 04:53:25.556641+07
8100559c-3eaa-4c99-b5b7-3c0370f17462	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	204.80000000	25.7200	COMPLETED	34019604929	24788246.98667757	24788042.18667757	-204.80000000	-204.80000000	LOSS	2026-09-23 04:53:09.213961+07	2026-09-23 04:53:09.216796+07	2026-09-23 04:53:09.423271+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "3.69362", "profit": "551.65337600", "bet_amt": "204.80000000", "client_seed": "f7fd28549fbbd3c70757a48390747606", "winning_chance": "25.72"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019604929", "payout": "3.69362", "profit": "-204.80000000", "balance": "24788042.18667757", "time_taken": 0.023890972137451172, "roll_number": 9644}	0.00000000	0.00000000	2026-09-23 04:53:09.423271+07
8ef2bcca-5417-439e-9f92-e7d2d6e720ed	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	0.10000000	24.8400	COMPLETED	34019605058	24788988.40363757	24788988.30363757	-0.10000000	-0.10000000	LOSS	2026-09-23 04:53:11.667147+07	2026-09-23 04:53:11.668449+07	2026-09-23 04:53:12.077844+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "3.82447", "profit": "0.28244700", "bet_amt": "0.10000000", "client_seed": "6c37c5853cfeba0e9470ea89962fed3a", "winning_chance": "24.84"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019605058", "payout": "3.82447", "profit": "-0.10000000", "balance": "24788988.30363757", "time_taken": 0.22803306579589844, "roll_number": 7872}	0.00000000	0.00000000	2026-09-23 04:53:12.077844+07
955de60e-fd09-43e9-8346-1827efe9c559	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.20000000	33.5300	COMPLETED	34019643973	459868.05254368	459867.85254368	-0.20000000	-0.20000000	LOSS	2026-09-23 05:05:36.681054+07	2026-09-23 05:05:36.691647+07	2026-09-23 05:05:36.903303+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.83328", "profit": "0.36665600", "bet_amt": "0.20000000", "client_seed": "40a03dca3b59278a0fddebe1e26fe21a", "winning_chance": "33.53"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019643973", "payout": "2.83328", "profit": "-0.20000000", "balance": "459867.85254368", "time_taken": 0.02712082862854004, "roll_number": 632}	0.00000000	0.00000000	2026-09-23 05:05:36.903303+07
66af8ffa-42dc-4cb1-b902-3caa57fcc93f	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	0.40000000	29.2100	COMPLETED	34019605167	24788988.10363757	24788987.70363757	-0.40000000	-0.40000000	LOSS	2026-09-23 04:53:14.306812+07	2026-09-23 04:53:14.308363+07	2026-09-23 04:53:14.515469+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "3.25231", "profit": "0.90092400", "bet_amt": "0.40000000", "client_seed": "c4b2c99ddb74635499c7b160a1a4c0ce", "winning_chance": "29.21"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019605167", "payout": "3.25231", "profit": "-0.40000000", "balance": "24788987.70363757", "time_taken": 0.024399995803833008, "roll_number": 3435}	0.00000000	0.00000000	2026-09-23 04:53:14.515469+07
6970ed23-701b-4edd-a018-3dd99c962f5d	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.40000000	33.5700	COMPLETED	34019643985	459867.85254368	459867.45254368	-0.40000000	-0.40000000	LOSS	2026-09-23 05:05:37.019719+07	2026-09-23 05:05:37.024103+07	2026-09-23 05:05:37.232643+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.82990", "profit": "0.73196000", "bet_amt": "0.40000000", "client_seed": "cc44e6ae41a79e7f76df59ce8dd48899", "winning_chance": "33.57"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019643985", "payout": "2.82990", "profit": "-0.40000000", "balance": "459867.45254368", "time_taken": 0.025092124938964844, "roll_number": 4735}	0.00000000	0.00000000	2026-09-23 05:05:37.232643+07
46817c3b-cecd-4e5d-8e80-3112ae1137d8	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	1.60000000	28.3600	COMPLETED	34019605306	24788986.90363757	24788990.66328557	3.75964800	3.23329728	WIN	2026-09-23 04:53:16.760865+07	2026-09-23 04:53:16.762265+07	2026-09-23 04:53:16.969437+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "3.34978", "profit": "3.75964800", "bet_amt": "1.60000000", "client_seed": "839d2c4f33618aa6604213548d4d329e", "winning_chance": "28.36"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019605306", "payout": "3.34978", "profit": "3.75964800", "balance": "24788990.66328557", "time_taken": 0.024960994720458984, "roll_number": 1361}	0.45115776	0.07519296	2026-09-23 04:53:16.969437+07
ba0f0672-9f5e-45ba-b76f-20d0a78f7f44	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	0.20000000	22.1400	COMPLETED	34019605426	24788857.52290985	24788857.32290985	-0.20000000	-0.20000000	LOSS	2026-09-23 04:53:19.194038+07	2026-09-23 04:53:19.196773+07	2026-09-23 04:53:19.403829+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "4.29087", "profit": "0.65817400", "bet_amt": "0.20000000", "client_seed": "9163ca6cc0f80e69d396e0a651ddc531", "winning_chance": "22.14"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019605426", "payout": "4.29087", "profit": "-0.20000000", "balance": "24788857.32290985", "time_taken": 0.024815797805786133, "roll_number": 3375}	0.00000000	0.00000000	2026-09-23 04:53:19.403829+07
4597c2a9-2753-4d49-910b-1d48f98773d2	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.80000000	32.2400	COMPLETED	34019644007	459867.45254368	459866.65254368	-0.80000000	-0.80000000	LOSS	2026-09-23 05:05:37.342515+07	2026-09-23 05:05:37.344694+07	2026-09-23 05:05:37.55486+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.94665", "profit": "1.55732000", "bet_amt": "0.80000000", "client_seed": "76213da4366bf2aa6360d7382151cb8d", "winning_chance": "32.24"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019644007", "payout": "2.94665", "profit": "-0.80000000", "balance": "459866.65254368", "time_taken": 0.027385950088500977, "roll_number": 4936}	0.00000000	0.00000000	2026-09-23 05:05:37.55486+07
759282ef-e5f3-4daa-a4ab-c6ebf0e6c089	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.10000000	33.8500	COMPLETED	34019644041	459868.89966368	459868.79966368	-0.10000000	-0.10000000	LOSS	2026-09-23 05:05:37.986691+07	2026-09-23 05:05:37.990533+07	2026-09-23 05:05:38.19763+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.80649", "profit": "0.18064900", "bet_amt": "0.10000000", "client_seed": "97ac6404842156f81d1a02e2ccea57af", "winning_chance": "33.85"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019644041", "payout": "2.80649", "profit": "-0.10000000", "balance": "459868.79966368", "time_taken": 0.025659799575805664, "roll_number": 4923}	0.00000000	0.00000000	2026-09-23 05:05:38.19763+07
c46ab6da-f505-4953-975f-e36d4137d560	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	0.80000000	25.2700	COMPLETED	34019605587	24788856.92290985	24788856.12290985	-0.80000000	-0.80000000	LOSS	2026-09-23 04:53:21.662849+07	2026-09-23 04:53:21.664236+07	2026-09-23 04:53:21.868066+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.75939", "profit": "2.20751200", "bet_amt": "0.80000000", "client_seed": "1d21e787950ce0213e44cf693adb86d1", "winning_chance": "25.27"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019605587", "payout": "3.75939", "profit": "-0.80000000", "balance": "24788856.12290985", "time_taken": 0.020899057388305664, "roll_number": 3813}	0.00000000	0.00000000	2026-09-23 04:53:21.868066+07
bf72e954-a9ad-43ca-8e31-d314d1f93c26	387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	3.20000000	24.8000	COMPLETED	34019605741	24788854.52290985	24788851.32290985	-3.20000000	-3.20000000	LOSS	2026-09-23 04:53:24.103592+07	2026-09-23 04:53:24.105609+07	2026-09-23 04:53:24.311045+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.83064", "profit": "9.05804800", "bet_amt": "3.20000000", "client_seed": "9a2da786d8a2167fe91a8aebd735961e", "winning_chance": "24.80"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019605741", "payout": "3.83064", "profit": "-3.20000000", "balance": "24788851.32290985", "time_taken": 0.023478984832763672, "roll_number": 5613}	0.00000000	0.00000000	2026-09-23 04:53:24.311045+07
b48f5529-1ddc-4246-a729-9a836cd149af	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.20000000	32.5100	COMPLETED	34019644056	459868.79966368	459869.18409768	0.38443400	0.38443400	WIN	2026-09-23 05:05:38.304334+07	2026-09-23 05:05:38.306246+07	2026-09-23 05:05:38.516998+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.92217", "profit": "0.38443400", "bet_amt": "0.20000000", "client_seed": "f9a76b018803374d4e6b211f80dd396a", "winning_chance": "32.51"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019644056", "payout": "2.92217", "profit": "0.38443400", "balance": "459869.18409768", "time_taken": 0.0286099910736084, "roll_number": 7294}	0.00000000	0.00000000	2026-09-23 05:05:38.516998+07
a4380329-cafb-4b24-9adf-2bcc093598a3	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	1.60000000	33.7700	COMPLETED	34019693533	459934.51882868	459932.91882868	-1.60000000	-1.60000000	LOSS	2026-09-23 05:21:45.280588+07	2026-09-23 05:21:45.289141+07	2026-09-23 05:21:45.498382+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.81314", "profit": "2.90102400", "bet_amt": "1.60000000", "client_seed": "1dd8f0f882bb856fb081d1bb8864e4e6", "winning_chance": "33.77"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693533", "payout": "2.81314", "profit": "-1.60000000", "balance": "459932.91882868", "time_taken": 0.025075197219848633, "roll_number": 8310}	0.00000000	0.00000000	2026-09-23 05:21:45.498382+07
ea1c454e-9e39-4611-9ceb-022cd32b8a4e	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.10000000	38.6100	COMPLETED	34019644082	459869.32552068	459869.47157068	0.14605000	0.14605000	WIN	2026-09-23 05:05:38.943177+07	2026-09-23 05:05:38.945185+07	2026-09-23 05:05:39.155029+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.46050", "profit": "0.14605000", "bet_amt": "0.10000000", "client_seed": "66f3a1e7b180e5722f9ea9117df480b3", "winning_chance": "38.61"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019644082", "payout": "2.46050", "profit": "0.14605000", "balance": "459869.47157068", "time_taken": 0.02802300453186035, "roll_number": 2124}	0.00000000	0.00000000	2026-09-23 05:05:39.155029+07
056b5335-69b1-4f3e-a1b7-dddad5b3e35c	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	25.60000000	36.4500	COMPLETED	34019693619	459910.51882868	459884.91882868	-25.60000000	-25.60000000	LOSS	2026-09-23 05:21:46.562126+07	2026-09-23 05:21:46.565778+07	2026-09-23 05:21:46.774849+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.60631", "profit": "41.12153600", "bet_amt": "25.60000000", "client_seed": "b1abc6e9c4af901089b328a3dad50f76", "winning_chance": "36.45"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693619", "payout": "2.60631", "profit": "-25.60000000", "balance": "459884.91882868", "time_taken": 0.025296926498413086, "roll_number": 4217}	0.00000000	0.00000000	2026-09-23 05:21:46.774849+07
9e2c7f1a-f98c-466b-94a8-708aca63745c	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.10000000	33.6200	COMPLETED	34019644139	459869.76848568	459869.95105468	0.18256900	0.18256900	WIN	2026-09-23 05:05:39.905225+07	2026-09-23 05:05:39.908398+07	2026-09-23 05:05:40.11727+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.82569", "profit": "0.18256900", "bet_amt": "0.10000000", "client_seed": "c02678daf94ed5aa55029baffb568801", "winning_chance": "33.62"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019644139", "payout": "2.82569", "profit": "0.18256900", "balance": "459869.95105468", "time_taken": 0.027503013610839844, "roll_number": 9443}	0.00000000	0.00000000	2026-09-23 05:05:40.11727+07
cecc8f60-a344-4283-92c5-0773efce09f3	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.20000000	35.0700	COMPLETED	34019644177	459869.85105468	459869.65105468	-0.20000000	-0.20000000	LOSS	2026-09-23 05:05:40.53351+07	2026-09-23 05:05:40.534912+07	2026-09-23 05:05:40.742863+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.70886", "profit": "0.34177200", "bet_amt": "0.20000000", "client_seed": "cf8b487aed4b390d60da5ca039ce2074", "winning_chance": "35.07"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019644177", "payout": "2.70886", "profit": "-0.20000000", "balance": "459869.65105468", "time_taken": 0.026833057403564453, "roll_number": 3406}	0.00000000	0.00000000	2026-09-23 05:05:40.742863+07
779121e4-7ecc-4155-aaad-6a5e6b17b900	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	34.7000	COMPLETED	34019693657	459959.63089268	459959.53089268	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:47.19726+07	2026-09-23 05:21:47.2+07	2026-09-23 05:21:47.410282+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.73775", "profit": "0.17377500", "bet_amt": "0.10000000", "client_seed": "e065a9700a4882a2146c5c08e924ee09", "winning_chance": "34.70"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693657", "payout": "2.73775", "profit": "-0.10000000", "balance": "459959.53089268", "time_taken": 0.02641892433166504, "roll_number": 8819}	0.00000000	0.00000000	2026-09-23 05:21:47.410282+07
7187e6fc-2e4d-4fa7-ba42-191bf22051a9	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.10000000	36.4700	COMPLETED	34019644215	459870.44377068	459870.60425868	0.16048800	0.16048800	WIN	2026-09-23 05:05:41.166916+07	2026-09-23 05:05:41.169712+07	2026-09-23 05:05:41.377924+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.60488", "profit": "0.16048800", "bet_amt": "0.10000000", "client_seed": "fed8265ba8d89db9fcb580c8da1bd585", "winning_chance": "36.47"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019644215", "payout": "2.60488", "profit": "0.16048800", "balance": "459870.60425868", "time_taken": 0.026826858520507812, "roll_number": 9631}	0.00000000	0.00000000	2026-09-23 05:05:41.377924+07
f433557d-b3e7-4843-b073-02f7ef07b5f3	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	34.1600	COMPLETED	34019693681	459959.86340268	459959.76340268	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:47.836842+07	2026-09-23 05:21:47.839391+07	2026-09-23 05:21:48.04877+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.78103", "profit": "0.17810300", "bet_amt": "0.10000000", "client_seed": "616415580d8a15819da8e9509ce7787b", "winning_chance": "34.16"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693681", "payout": "2.78103", "profit": "-0.10000000", "balance": "459959.76340268", "time_taken": 0.02628922462463379, "roll_number": 3669}	0.00000000	0.00000000	2026-09-23 05:21:48.04877+07
d31cf86f-b252-46d4-898b-10dda87db47e	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.20000000	36.8000	COMPLETED	34019644253	459870.50425868	459870.82056268	0.31630400	0.31630400	WIN	2026-09-23 05:05:41.802942+07	2026-09-23 05:05:41.806082+07	2026-09-23 05:05:42.015661+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.58152", "profit": "0.31630400", "bet_amt": "0.20000000", "client_seed": "e1dcca7d3dd34398078b144851c4b84b", "winning_chance": "36.80"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019644253", "payout": "2.58152", "profit": "0.31630400", "balance": "459870.82056268", "time_taken": 0.027493000030517578, "roll_number": 7955}	0.00000000	0.00000000	2026-09-23 05:05:42.015661+07
d241e92b-dae0-4970-9775-cfa9e46ee33a	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	34.0600	COMPLETED	34019693713	459959.56340268	459960.27907868	0.71567600	0.71567600	WIN	2026-09-23 05:21:48.473657+07	2026-09-23 05:21:48.475444+07	2026-09-23 05:21:48.687056+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.78919", "profit": "0.71567600", "bet_amt": "0.40000000", "client_seed": "120ce7f4f8bd5fb1ffd69edfea9e75c7", "winning_chance": "34.06"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693713", "payout": "2.78919", "profit": "0.71567600", "balance": "459960.27907868", "time_taken": 0.027994871139526367, "roll_number": 1173}	0.00000000	0.00000000	2026-09-23 05:21:48.687056+07
b122fd91-d93c-45d3-96f1-2fbdab34c94c	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.10000000	39.3500	COMPLETED	34019644068	459869.18409768	459869.32552068	0.14142300	0.14142300	WIN	2026-09-23 05:05:38.626138+07	2026-09-23 05:05:38.62824+07	2026-09-23 05:05:38.836066+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.41423", "profit": "0.14142300", "bet_amt": "0.10000000", "client_seed": "da472cd7719b8d9a6a44f3b69bbd986d", "winning_chance": "39.35"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019644068", "payout": "2.41423", "profit": "0.14142300", "balance": "459869.32552068", "time_taken": 0.026283979415893555, "roll_number": 9720}	0.00000000	0.00000000	2026-09-23 05:05:38.836066+07
e42f6d04-5c24-4610-a342-11ec4bc2cb55	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.10000000	36.9800	COMPLETED	34019644095	459869.47157068	459869.62846568	0.15689500	0.15689500	WIN	2026-09-23 05:05:39.26437+07	2026-09-23 05:05:39.268042+07	2026-09-23 05:05:39.476953+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.56895", "profit": "0.15689500", "bet_amt": "0.10000000", "client_seed": "51fe7becdc41bfc0bf358f733cbc9d1e", "winning_chance": "36.98"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019644095", "payout": "2.56895", "profit": "0.15689500", "balance": "459869.62846568", "time_taken": 0.027693986892700195, "roll_number": 7565}	0.00000000	0.00000000	2026-09-23 05:05:39.476953+07
74c5c9cc-5246-48a7-bb28-6f688574070a	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	3.20000000	34.1100	COMPLETED	34019693553	459932.91882868	459929.71882868	-3.20000000	-3.20000000	LOSS	2026-09-23 05:21:45.606689+07	2026-09-23 05:21:45.608567+07	2026-09-23 05:21:45.818172+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.78510", "profit": "5.71232000", "bet_amt": "3.20000000", "client_seed": "d0bd64283024d53e40b531836b04d045", "winning_chance": "34.11"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693553", "payout": "2.78510", "profit": "-3.20000000", "balance": "459929.71882868", "time_taken": 0.026654958724975586, "roll_number": 4808}	0.00000000	0.00000000	2026-09-23 05:21:45.818172+07
e83ec5b3-9897-46c3-834c-e3fc5098093b	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.10000000	39.5800	COMPLETED	34019644116	459869.62846568	459869.76848568	0.14002000	0.14002000	WIN	2026-09-23 05:05:39.583204+07	2026-09-23 05:05:39.584791+07	2026-09-23 05:05:39.796032+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.40020", "profit": "0.14002000", "bet_amt": "0.10000000", "client_seed": "87acf311d7292bca0382ed0fad9fd630", "winning_chance": "39.58"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019644116", "payout": "2.40020", "profit": "0.14002000", "balance": "459869.76848568", "time_taken": 0.028920888900756836, "roll_number": 9986}	0.00000000	0.00000000	2026-09-23 05:05:39.796032+07
1f916b1e-855f-4686-a725-fd1b607c51a7	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	6.40000000	31.2300	COMPLETED	34019693578	459929.71882868	459923.31882868	-6.40000000	-6.40000000	LOSS	2026-09-23 05:21:45.924454+07	2026-09-23 05:21:45.926149+07	2026-09-23 05:21:46.136005+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "3.04194", "profit": "13.06841600", "bet_amt": "6.40000000", "client_seed": "48c5136922d87e5903bf6b4144dcdd6f", "winning_chance": "31.23"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693578", "payout": "3.04194", "profit": "-6.40000000", "balance": "459923.31882868", "time_taken": 0.026695966720581055, "roll_number": 3357}	0.00000000	0.00000000	2026-09-23 05:21:46.136005+07
6ae77da6-8e4c-4375-8f13-d8a095b7ba6c	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.10000000	33.6700	COMPLETED	34019644159	459869.95105468	459869.85105468	-0.10000000	-0.10000000	LOSS	2026-09-23 05:05:40.222771+07	2026-09-23 05:05:40.224265+07	2026-09-23 05:05:40.42859+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.82150", "profit": "0.18215000", "bet_amt": "0.10000000", "client_seed": "53e687cbc638843c43135cfd7306e671", "winning_chance": "33.67"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019644159", "payout": "2.82150", "profit": "-0.10000000", "balance": "459869.85105468", "time_taken": 0.023611068725585938, "roll_number": 4483}	0.00000000	0.00000000	2026-09-23 05:05:40.42859+07
8f506c5c-a991-4e94-83e0-d61645d949ee	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.40000000	31.8600	COMPLETED	34019644194	459869.65105468	459870.44377068	0.79271600	0.79271600	WIN	2026-09-23 05:05:40.847644+07	2026-09-23 05:05:40.848909+07	2026-09-23 05:05:41.058602+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.98179", "profit": "0.79271600", "bet_amt": "0.40000000", "client_seed": "6a59a12ecbf959e6b1ad90587c04ed3c", "winning_chance": "31.86"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019644194", "payout": "2.98179", "profit": "0.79271600", "balance": "459870.44377068", "time_taken": 0.02884507179260254, "roll_number": 9960}	0.00000000	0.00000000	2026-09-23 05:05:41.058602+07
bc62c642-7f23-461e-9f38-b813a5fa4217	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	12.80000000	39.0800	COMPLETED	34019693595	459923.31882868	459910.51882868	-12.80000000	-12.80000000	LOSS	2026-09-23 05:21:46.242084+07	2026-09-23 05:21:46.243778+07	2026-09-23 05:21:46.452921+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.43091", "profit": "18.31564800", "bet_amt": "12.80000000", "client_seed": "0462b5904a72ae87e144bd4ee3fa309a", "winning_chance": "39.08"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693595", "payout": "2.43091", "profit": "-12.80000000", "balance": "459910.51882868", "time_taken": 0.025802135467529297, "roll_number": 767}	0.00000000	0.00000000	2026-09-23 05:21:46.452921+07
ee86d9e7-9d6e-4625-bdc8-a23834891569	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.10000000	31.7200	COMPLETED	34019644233	459870.60425868	459870.50425868	-0.10000000	-0.10000000	LOSS	2026-09-23 05:05:41.486356+07	2026-09-23 05:05:41.488483+07	2026-09-23 05:05:41.696679+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.99495", "profit": "0.19949500", "bet_amt": "0.10000000", "client_seed": "4bcdbd1e41b8c4790cf14aba8224cd6c", "winning_chance": "31.72"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019644233", "payout": "2.99495", "profit": "-0.10000000", "balance": "459870.50425868", "time_taken": 0.027081966400146484, "roll_number": 2269}	0.00000000	0.00000000	2026-09-23 05:05:41.696679+07
777a14a7-fc44-4616-b727-0c84593ff7b6	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	51.20000000	38.6300	COMPLETED	34019693642	459884.91882868	459959.63089268	74.71206400	74.71206400	WIN	2026-09-23 05:21:46.880272+07	2026-09-23 05:21:46.882156+07	2026-09-23 05:21:47.091681+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.45922", "profit": "74.71206400", "bet_amt": "51.20000000", "client_seed": "7ad791603ce6854a3f0f91ecb9a98597", "winning_chance": "38.63"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693642", "payout": "2.45922", "profit": "74.71206400", "balance": "459959.63089268", "time_taken": 0.02644491195678711, "roll_number": 2}	0.00000000	0.00000000	2026-09-23 05:21:47.091681+07
837a4542-aea1-4a5e-a5b1-6017d08212a0	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	35.6800	COMPLETED	34019693671	459959.53089268	459959.86340268	0.33251000	0.33251000	WIN	2026-09-23 05:21:47.519208+07	2026-09-23 05:21:47.521105+07	2026-09-23 05:21:47.731222+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.66255", "profit": "0.33251000", "bet_amt": "0.20000000", "client_seed": "169a20cfa1c6d6d48d6691b3dc658125", "winning_chance": "35.68"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693671", "payout": "2.66255", "profit": "0.33251000", "balance": "459959.86340268", "time_taken": 0.026839017868041992, "roll_number": 8175}	0.00000000	0.00000000	2026-09-23 05:21:47.731222+07
447b4c7c-de11-4cc4-8d41-e0d75c5b3857	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	30.2600	COMPLETED	34019691812	459870.82056268	459871.03450768	0.21394500	0.21394500	WIN	2026-09-23 05:21:13.852881+07	2026-09-23 05:21:13.877921+07	2026-09-23 05:21:14.093881+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "3.13945", "profit": "0.21394500", "bet_amt": "0.10000000", "client_seed": "8e256f3e3021b8a53ce2b76d70269d1a", "winning_chance": "30.26"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019691812", "payout": "3.13945", "profit": "0.21394500", "balance": "459871.03450768", "time_taken": 0.02908802032470703, "roll_number": 533}	0.00000000	0.00000000	2026-09-23 05:21:14.093881+07
961504c7-40fc-45b8-b536-c9cbd8d5afb3	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	33.9100	COMPLETED	34019693692	459959.76340268	459959.56340268	-0.20000000	-0.20000000	LOSS	2026-09-23 05:21:48.155376+07	2026-09-23 05:21:48.157101+07	2026-09-23 05:21:48.368876+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.80153", "profit": "0.36030600", "bet_amt": "0.20000000", "client_seed": "65802614b6ea446e8be656ade78fdedc", "winning_chance": "33.91"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693692", "payout": "2.80153", "profit": "-0.20000000", "balance": "459959.56340268", "time_taken": 0.02863001823425293, "roll_number": 2018}	0.00000000	0.00000000	2026-09-23 05:21:48.368876+07
2123df6b-e0e0-423f-b6b8-eb6060b72235	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	39.8800	COMPLETED	34019691854	459870.93450768	459871.21093568	0.27642800	0.27642800	WIN	2026-09-23 05:21:14.559444+07	2026-09-23 05:21:14.563199+07	2026-09-23 05:21:14.778395+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.38214", "profit": "0.27642800", "bet_amt": "0.20000000", "client_seed": "53c23a37bb9cfdef0cbee3183dd9fa19", "winning_chance": "39.88"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019691854", "payout": "2.38214", "profit": "0.27642800", "balance": "459871.21093568", "time_taken": 0.029421091079711914, "roll_number": 407}	0.00000000	0.00000000	2026-09-23 05:21:14.778395+07
f37fbb55-247e-46a0-b18d-85c02e0d29be	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.80000000	38.8000	COMPLETED	34019691913	459870.51093568	459869.71093568	-0.80000000	-0.80000000	LOSS	2026-09-23 05:21:15.848951+07	2026-09-23 05:21:15.851464+07	2026-09-23 05:21:16.063086+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.44845", "profit": "1.15876000", "bet_amt": "0.80000000", "client_seed": "401680df1a767be6152f6be88b66f7fd", "winning_chance": "38.80"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019691913", "payout": "2.44845", "profit": "-0.80000000", "balance": "459869.71093568", "time_taken": 0.02762317657470703, "roll_number": 2741}	0.00000000	0.00000000	2026-09-23 05:21:16.063086+07
21a8237a-fab9-4024-8e42-ec3a0f28d8da	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	1.60000000	35.4100	COMPLETED	34019691922	459869.71093568	459872.40349568	2.69256000	2.69256000	WIN	2026-09-23 05:21:16.171408+07	2026-09-23 05:21:16.174704+07	2026-09-23 05:21:16.388104+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.68285", "profit": "2.69256000", "bet_amt": "1.60000000", "client_seed": "11db0100b00462b8bfb108ffa039754f", "winning_chance": "35.41"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019691922", "payout": "2.68285", "profit": "2.69256000", "balance": "459872.40349568", "time_taken": 0.028513193130493164, "roll_number": 2729}	0.00000000	0.00000000	2026-09-23 05:21:16.388104+07
bd3398d5-5d2b-4afd-be80-15bca924423c	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	32.5400	COMPLETED	34019691958	459872.59137368	459872.49137368	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:16.819508+07	2026-09-23 05:21:16.822221+07	2026-09-23 05:21:17.032748+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.91948", "profit": "0.19194800", "bet_amt": "0.10000000", "client_seed": "59230b50c8cfe4e26860ce0a35c8f2aa", "winning_chance": "32.54"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019691958", "payout": "2.91948", "profit": "-0.10000000", "balance": "459872.49137368", "time_taken": 0.025712966918945312, "roll_number": 4313}	0.00000000	0.00000000	2026-09-23 05:21:17.032748+07
bfde4684-c705-40ae-b044-cb3112131e0d	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	32.4900	COMPLETED	34019691984	459872.29137368	459871.89137368	-0.40000000	-0.40000000	LOSS	2026-09-23 05:21:17.461207+07	2026-09-23 05:21:17.463342+07	2026-09-23 05:21:17.673716+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.92397", "profit": "0.76958800", "bet_amt": "0.40000000", "client_seed": "387173149eb49035205dc33a4554266e", "winning_chance": "32.49"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019691984", "payout": "2.92397", "profit": "-0.40000000", "balance": "459871.89137368", "time_taken": 0.026925086975097656, "roll_number": 4986}	0.00000000	0.00000000	2026-09-23 05:21:17.673716+07
a09fa708-2e85-4bad-83f2-3873fe4c4ec1	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	1.60000000	31.1300	COMPLETED	34019692010	459871.09137368	459869.49137368	-1.60000000	-1.60000000	LOSS	2026-09-23 05:21:18.097771+07	2026-09-23 05:21:18.09955+07	2026-09-23 05:21:18.30977+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.05171", "profit": "3.28273600", "bet_amt": "1.60000000", "client_seed": "d48d1feade05033a63f897009ea584e3", "winning_chance": "31.13"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692010", "payout": "3.05171", "profit": "-1.60000000", "balance": "459869.49137368", "time_taken": 0.026655912399291992, "roll_number": 4133}	0.00000000	0.00000000	2026-09-23 05:21:18.30977+07
74417647-8c36-4b66-852b-fe0caaa30cb8	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	32.0900	COMPLETED	34019692095	459875.61770968	459875.21770968	-0.40000000	-0.40000000	LOSS	2026-09-23 05:21:19.382506+07	2026-09-23 05:21:19.383801+07	2026-09-23 05:21:19.594705+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.96042", "profit": "0.78416800", "bet_amt": "0.40000000", "client_seed": "22128eeadd34b28df7c0ef35bf2d1c60", "winning_chance": "32.09"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692095", "payout": "2.96042", "profit": "-0.40000000", "balance": "459875.21770968", "time_taken": 0.02742290496826172, "roll_number": 1991}	0.00000000	0.00000000	2026-09-23 05:21:19.594705+07
f9526922-75fc-4270-ad67-b7a3ee6bd4b8	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	32.8500	COMPLETED	34019692175	459876.58577168	459876.96415768	0.37838600	0.37838600	WIN	2026-09-23 05:21:20.655359+07	2026-09-23 05:21:20.658127+07	2026-09-23 05:21:20.869757+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.89193", "profit": "0.37838600", "bet_amt": "0.20000000", "client_seed": "2d565393d421750903b894ad8fe9c019", "winning_chance": "32.85"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692175", "payout": "2.89193", "profit": "0.37838600", "balance": "459876.96415768", "time_taken": 0.027899980545043945, "roll_number": 584}	0.00000000	0.00000000	2026-09-23 05:21:20.869757+07
2219ae6a-a89c-45e6-83b5-43a9adeee6bd	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	34.1300	COMPLETED	34019692204	459876.86415768	459877.22085168	0.35669400	0.35669400	WIN	2026-09-23 05:21:21.300407+07	2026-09-23 05:21:21.301776+07	2026-09-23 05:21:21.512796+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.78347", "profit": "0.35669400", "bet_amt": "0.20000000", "client_seed": "9a6cb474125881a995ca3dfe9623f8e8", "winning_chance": "34.13"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692204", "payout": "2.78347", "profit": "0.35669400", "balance": "459877.22085168", "time_taken": 0.027710914611816406, "roll_number": 2757}	0.00000000	0.00000000	2026-09-23 05:21:21.512796+07
ec008051-76a4-453a-adf7-5bc55bd5a15c	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	37.7000	COMPLETED	34019692243	459877.43458968	459877.58657868	0.15198900	0.15198900	WIN	2026-09-23 05:21:21.937266+07	2026-09-23 05:21:21.938537+07	2026-09-23 05:21:22.150864+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.51989", "profit": "0.15198900", "bet_amt": "0.10000000", "client_seed": "bb5fd1ed24878a70f58b8a258597322e", "winning_chance": "37.70"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692243", "payout": "2.51989", "profit": "0.15198900", "balance": "459877.58657868", "time_taken": 0.029491901397705078, "roll_number": 7172}	0.00000000	0.00000000	2026-09-23 05:21:22.150864+07
04e4b7a0-1163-42a2-8886-c775a0e49ec7	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	30.5800	COMPLETED	34019691837	459871.03450768	459870.93450768	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:14.211956+07	2026-09-23 05:21:14.231958+07	2026-09-23 05:21:14.445078+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.10660", "profit": "0.21066000", "bet_amt": "0.10000000", "client_seed": "d073e6d70fc880847483c6a615b6e8a4", "winning_chance": "30.58"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019691837", "payout": "3.10660", "profit": "-0.10000000", "balance": "459870.93450768", "time_taken": 0.026807069778442383, "roll_number": 6424}	0.00000000	0.00000000	2026-09-23 05:21:14.445078+07
6ae9713f-1e08-4ee4-a4f1-74afba4b0fd1	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	33.2100	COMPLETED	34019691869	459871.21093568	459871.11093568	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:14.886655+07	2026-09-23 05:21:14.88993+07	2026-09-23 05:21:15.100676+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.86058", "profit": "0.18605800", "bet_amt": "0.10000000", "client_seed": "354b1c60c4794ce495da769f443f337e", "winning_chance": "33.21"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019691869", "payout": "2.86058", "profit": "-0.10000000", "balance": "459871.11093568", "time_taken": 0.026314973831176758, "roll_number": 8623}	0.00000000	0.00000000	2026-09-23 05:21:15.100676+07
466db795-5b57-45b1-bdfa-38054f2db13a	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	35.8800	COMPLETED	34019691884	459871.11093568	459870.91093568	-0.20000000	-0.20000000	LOSS	2026-09-23 05:21:15.208777+07	2026-09-23 05:21:15.210834+07	2026-09-23 05:21:15.421922+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.64771", "profit": "0.32954200", "bet_amt": "0.20000000", "client_seed": "c0c656afbe55ef5cb530b71072807eca", "winning_chance": "35.88"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019691884", "payout": "2.64771", "profit": "-0.20000000", "balance": "459870.91093568", "time_taken": 0.025846004486083984, "roll_number": 446}	0.00000000	0.00000000	2026-09-23 05:21:15.421922+07
71f25eae-ab24-42c5-bb91-0986bf6be5e0	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	35.6800	COMPLETED	34019691897	459870.91093568	459870.51093568	-0.40000000	-0.40000000	LOSS	2026-09-23 05:21:15.530589+07	2026-09-23 05:21:15.532828+07	2026-09-23 05:21:15.741831+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.66255", "profit": "0.66502000", "bet_amt": "0.40000000", "client_seed": "3c5de8e365453a7ae4f4fc71cd200acc", "winning_chance": "35.68"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019691897", "payout": "2.66255", "profit": "-0.40000000", "balance": "459870.51093568", "time_taken": 0.025758981704711914, "roll_number": 3401}	0.00000000	0.00000000	2026-09-23 05:21:15.741831+07
4c7b2a32-b827-404a-9724-aa2c0178ff2f	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	33.0000	COMPLETED	34019691941	459872.40349568	459872.59137368	0.18787800	0.18787800	WIN	2026-09-23 05:21:16.496906+07	2026-09-23 05:21:16.500187+07	2026-09-23 05:21:16.712285+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.87878", "profit": "0.18787800", "bet_amt": "0.10000000", "client_seed": "e0be7b6d13c801eafcf6a4334687c85b", "winning_chance": "33.00"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019691941", "payout": "2.87878", "profit": "0.18787800", "balance": "459872.59137368", "time_taken": 0.027671098709106445, "roll_number": 9626}	0.00000000	0.00000000	2026-09-23 05:21:16.712285+07
b3cceab1-87c2-4b56-b792-b7cd04d7dae5	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	31.9700	COMPLETED	34019691971	459872.49137368	459872.29137368	-0.20000000	-0.20000000	LOSS	2026-09-23 05:21:17.140099+07	2026-09-23 05:21:17.142087+07	2026-09-23 05:21:17.352857+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.97153", "profit": "0.39430600", "bet_amt": "0.20000000", "client_seed": "bce9c045c66c41961f5c238a516ce452", "winning_chance": "31.97"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019691971", "payout": "2.97153", "profit": "-0.20000000", "balance": "459872.29137368", "time_taken": 0.026318073272705078, "roll_number": 641}	0.00000000	0.00000000	2026-09-23 05:21:17.352857+07
6d00bd5b-63dc-422d-b7e6-54c6f67060e2	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.80000000	32.6100	COMPLETED	34019691997	459871.89137368	459871.09137368	-0.80000000	-0.80000000	LOSS	2026-09-23 05:21:17.779663+07	2026-09-23 05:21:17.781206+07	2026-09-23 05:21:17.992444+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.91321", "profit": "1.53056800", "bet_amt": "0.80000000", "client_seed": "7aa3f81927fc20358dcf87a839adbdc8", "winning_chance": "32.61"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019691997", "payout": "2.91321", "profit": "-0.80000000", "balance": "459871.09137368", "time_taken": 0.02782893180847168, "roll_number": 3780}	0.00000000	0.00000000	2026-09-23 05:21:17.992444+07
f3868f90-3a66-4b93-874c-23eea841943b	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	3.20000000	31.5800	COMPLETED	34019692029	459869.49137368	459875.91770968	6.42633600	6.42633600	WIN	2026-09-23 05:21:18.416239+07	2026-09-23 05:21:18.419026+07	2026-09-23 05:21:18.634899+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.00823", "profit": "6.42633600", "bet_amt": "3.20000000", "client_seed": "dcfdc3c3e78284999638114a6885cb17", "winning_chance": "31.58"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692029", "payout": "3.00823", "profit": "6.42633600", "balance": "459875.91770968", "time_taken": 0.02621006965637207, "roll_number": 7477}	0.00000000	0.00000000	2026-09-23 05:21:18.634899+07
9476aa73-8825-4b23-82ce-df0da85169d7	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	35.9900	COMPLETED	34019692051	459875.91770968	459875.81770968	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:18.743189+07	2026-09-23 05:21:18.745496+07	2026-09-23 05:21:18.956901+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.63962", "profit": "0.16396200", "bet_amt": "0.10000000", "client_seed": "7b73e19294aa4c7f5e664de84b76d48f", "winning_chance": "35.99"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692051", "payout": "2.63962", "profit": "-0.10000000", "balance": "459875.81770968", "time_taken": 0.027014970779418945, "roll_number": 5112}	0.00000000	0.00000000	2026-09-23 05:21:18.956901+07
49be2446-8871-447f-9995-e9dd24530201	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	31.4100	COMPLETED	34019692074	459875.81770968	459875.61770968	-0.20000000	-0.20000000	LOSS	2026-09-23 05:21:19.065513+07	2026-09-23 05:21:19.067367+07	2026-09-23 05:21:19.277229+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.02451", "profit": "0.40490200", "bet_amt": "0.20000000", "client_seed": "95b1a5b04e6fb63329ae5a46979a049d", "winning_chance": "31.41"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692074", "payout": "3.02451", "profit": "-0.20000000", "balance": "459875.61770968", "time_taken": 0.0269930362701416, "roll_number": 3969}	0.00000000	0.00000000	2026-09-23 05:21:19.277229+07
932f1055-e9ad-44ce-ab01-495d93211536	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.80000000	36.1800	COMPLETED	34019692118	459875.21770968	459876.51831768	1.30060800	1.30060800	WIN	2026-09-23 05:21:19.700136+07	2026-09-23 05:21:19.701642+07	2026-09-23 05:21:19.912472+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.62576", "profit": "1.30060800", "bet_amt": "0.80000000", "client_seed": "8ba1b442c341ed50753a4e94e8040a7f", "winning_chance": "36.18"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692118", "payout": "2.62576", "profit": "1.30060800", "balance": "459876.51831768", "time_taken": 0.027673959732055664, "roll_number": 8470}	0.00000000	0.00000000	2026-09-23 05:21:19.912472+07
cbd74007-5636-4bb1-8b51-003a679f56da	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	35.5200	COMPLETED	34019692139	459876.51831768	459876.68577168	0.16745400	0.16745400	WIN	2026-09-23 05:21:20.018011+07	2026-09-23 05:21:20.019397+07	2026-09-23 05:21:20.229174+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.67454", "profit": "0.16745400", "bet_amt": "0.10000000", "client_seed": "d9d4b0831cd405a7351014cd5494e7dd", "winning_chance": "35.52"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692139", "payout": "2.67454", "profit": "0.16745400", "balance": "459876.68577168", "time_taken": 0.02623605728149414, "roll_number": 8110}	0.00000000	0.00000000	2026-09-23 05:21:20.229174+07
350431e7-83b3-4a3a-bee1-06a2dc295583	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	35.8500	COMPLETED	34019693734	459960.27907868	459960.17907868	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:48.793334+07	2026-09-23 05:21:48.795763+07	2026-09-23 05:21:49.003781+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.64993", "profit": "0.16499300", "bet_amt": "0.10000000", "client_seed": "545325447546b1d6db0e4367864bd5d5", "winning_chance": "35.85"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693734", "payout": "2.64993", "profit": "-0.10000000", "balance": "459960.17907868", "time_taken": 0.024734020233154297, "roll_number": 8319}	0.00000000	0.00000000	2026-09-23 05:21:49.003781+07
4de7ac1c-81f9-4178-9c24-e0615f373d96	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	31.6500	COMPLETED	34019692157	459876.68577168	459876.58577168	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:20.334863+07	2026-09-23 05:21:20.336555+07	2026-09-23 05:21:20.548109+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "3.00157", "profit": "0.20015700", "bet_amt": "0.10000000", "client_seed": "dc0f3808d792159a1bf90bf3d5785900", "winning_chance": "31.65"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692157", "payout": "3.00157", "profit": "-0.10000000", "balance": "459876.58577168", "time_taken": 0.027875900268554688, "roll_number": 8084}	0.00000000	0.00000000	2026-09-23 05:21:20.548109+07
177d6d47-d0bc-4fc5-8b45-e156be71d003	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	31.0900	COMPLETED	34019692188	459876.96415768	459876.86415768	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:20.978655+07	2026-09-23 05:21:20.981602+07	2026-09-23 05:21:21.19266+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.05564", "profit": "0.20556400", "bet_amt": "0.10000000", "client_seed": "894d321278b3c044a2dd1d596e09de30", "winning_chance": "31.09"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692188", "payout": "3.05564", "profit": "-0.10000000", "balance": "459876.86415768", "time_taken": 0.026035070419311523, "roll_number": 4873}	0.00000000	0.00000000	2026-09-23 05:21:21.19266+07
036f45c6-e106-4cf1-977f-68f8bbc3da5f	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	30.2800	COMPLETED	34019692218	459877.22085168	459877.43458968	0.21373800	0.21373800	WIN	2026-09-23 05:21:21.619586+07	2026-09-23 05:21:21.620817+07	2026-09-23 05:21:21.832246+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.13738", "profit": "0.21373800", "bet_amt": "0.10000000", "client_seed": "0fc7d97bb519a630be6d5bd245ee6924", "winning_chance": "30.28"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692218", "payout": "3.13738", "profit": "0.21373800", "balance": "459877.43458968", "time_taken": 0.02803492546081543, "roll_number": 9236}	0.00000000	0.00000000	2026-09-23 05:21:21.832246+07
271083ca-7f6f-42bb-9e5e-54b505cf97ce	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	32.1200	COMPLETED	34019692266	459877.58657868	459877.48657868	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:22.256292+07	2026-09-23 05:21:22.258587+07	2026-09-23 05:21:22.468818+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.95765", "profit": "0.19576500", "bet_amt": "0.10000000", "client_seed": "bed5816dd502790263233616ba760f8b", "winning_chance": "32.12"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692266", "payout": "2.95765", "profit": "-0.10000000", "balance": "459877.48657868", "time_taken": 0.0265500545501709, "roll_number": 6753}	0.00000000	0.00000000	2026-09-23 05:21:22.468818+07
a63fe8e0-4f1e-4ff2-906e-a7b36ebf663c	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	30.6400	COMPLETED	34019692309	459877.28657868	459876.88657868	-0.40000000	-0.40000000	LOSS	2026-09-23 05:21:22.891313+07	2026-09-23 05:21:22.893511+07	2026-09-23 05:21:23.101357+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.10052", "profit": "0.84020800", "bet_amt": "0.40000000", "client_seed": "5f0a18e09954db413dd6abb7e4a77d45", "winning_chance": "30.64"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692309", "payout": "3.10052", "profit": "-0.40000000", "balance": "459876.88657868", "time_taken": 0.024727821350097656, "roll_number": 4822}	0.00000000	0.00000000	2026-09-23 05:21:23.101357+07
e80c7c2b-bb4b-4891-90fb-22f86410ebb0	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	1.60000000	37.0000	COMPLETED	34019692341	459876.08657868	459874.48657868	-1.60000000	-1.60000000	LOSS	2026-09-23 05:21:23.530787+07	2026-09-23 05:21:23.532257+07	2026-09-23 05:21:23.744561+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.56756", "profit": "2.50809600", "bet_amt": "1.60000000", "client_seed": "035880b554bec1cec91e4e2b193c32c0", "winning_chance": "37.00"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692341", "payout": "2.56756", "profit": "-1.60000000", "balance": "459874.48657868", "time_taken": 0.02862095832824707, "roll_number": 3098}	0.00000000	0.00000000	2026-09-23 05:21:23.744561+07
3fdb4b66-afd2-4f73-985e-67040a206157	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	6.40000000	34.9200	COMPLETED	34019692370	459871.28657868	459864.88657868	-6.40000000	-6.40000000	LOSS	2026-09-23 05:21:24.170795+07	2026-09-23 05:21:24.172124+07	2026-09-23 05:21:24.382858+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.72050", "profit": "11.01120000", "bet_amt": "6.40000000", "client_seed": "000bd4acdc3d550b78c72c781e45a8d3", "winning_chance": "34.92"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692370", "payout": "2.72050", "profit": "-6.40000000", "balance": "459864.88657868", "time_taken": 0.027313947677612305, "roll_number": 4906}	0.00000000	0.00000000	2026-09-23 05:21:24.382858+07
75bfbd7e-72bf-4a79-bc3d-a692ea1d2a23	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	25.60000000	31.4900	COMPLETED	34019692400	459852.08657868	459903.71742668	51.63084800	51.63084800	WIN	2026-09-23 05:21:24.810153+07	2026-09-23 05:21:24.811723+07	2026-09-23 05:21:25.020839+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "3.01683", "profit": "51.63084800", "bet_amt": "25.60000000", "client_seed": "d2a211e6f46a554397dbd584f94028a5", "winning_chance": "31.49"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692400", "payout": "3.01683", "profit": "51.63084800", "balance": "459903.71742668", "time_taken": 0.025883197784423828, "roll_number": 218}	0.00000000	0.00000000	2026-09-23 05:21:25.020839+07
96e44c09-49eb-4af0-af93-4bc895a35961	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	37.0600	COMPLETED	34019692413	459903.71742668	459903.61742668	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:25.125605+07	2026-09-23 05:21:25.126885+07	2026-09-23 05:21:25.340103+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.56341", "profit": "0.15634100", "bet_amt": "0.10000000", "client_seed": "4b9fb23629738459cceee22dfde3c6ab", "winning_chance": "37.06"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692413", "payout": "2.56341", "profit": "-0.10000000", "balance": "459903.61742668", "time_taken": 0.028510093688964844, "roll_number": 6202}	0.00000000	0.00000000	2026-09-23 05:21:25.340103+07
8b4500a2-be69-415a-8a54-515b2cfb2819	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	36.1100	COMPLETED	34019692432	459903.61742668	459903.41742668	-0.20000000	-0.20000000	LOSS	2026-09-23 05:21:25.449733+07	2026-09-23 05:21:25.453036+07	2026-09-23 05:21:25.664297+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.63085", "profit": "0.32617000", "bet_amt": "0.20000000", "client_seed": "6e1c98fe5d4c0e2877e142e174fb8f17", "winning_chance": "36.11"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692432", "payout": "2.63085", "profit": "-0.20000000", "balance": "459903.41742668", "time_taken": 0.027058839797973633, "roll_number": 9684}	0.00000000	0.00000000	2026-09-23 05:21:25.664297+07
3d692f95-8678-478c-9731-36656158bfed	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	34.6500	COMPLETED	34019692288	459877.48657868	459877.28657868	-0.20000000	-0.20000000	LOSS	2026-09-23 05:21:22.57515+07	2026-09-23 05:21:22.576513+07	2026-09-23 05:21:22.784543+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.74170", "profit": "0.34834000", "bet_amt": "0.20000000", "client_seed": "c4f7e6cab00e732a590390f7f4268730", "winning_chance": "34.65"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692288", "payout": "2.74170", "profit": "-0.20000000", "balance": "459877.28657868", "time_taken": 0.02436208724975586, "roll_number": 5305}	0.00000000	0.00000000	2026-09-23 05:21:22.784543+07
a92dd731-c40c-4ce1-8e5b-8583fe78a20e	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	32.9500	COMPLETED	34019693761	459960.17907868	459959.97907868	-0.20000000	-0.20000000	LOSS	2026-09-23 05:21:49.108898+07	2026-09-23 05:21:49.110616+07	2026-09-23 05:21:49.320748+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.88315", "profit": "0.37663000", "bet_amt": "0.20000000", "client_seed": "c6ab40064606eb15dae23b1f5f2b1e03", "winning_chance": "32.95"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693761", "payout": "2.88315", "profit": "-0.20000000", "balance": "459959.97907868", "time_taken": 0.02674412727355957, "roll_number": 9343}	0.00000000	0.00000000	2026-09-23 05:21:49.320748+07
b4eb87f4-9e7f-4027-aee7-b47e318d7167	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.80000000	30.9100	COMPLETED	34019692327	459876.88657868	459876.08657868	-0.80000000	-0.80000000	LOSS	2026-09-23 05:21:23.206647+07	2026-09-23 05:21:23.208827+07	2026-09-23 05:21:23.421106+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.07343", "profit": "1.65874400", "bet_amt": "0.80000000", "client_seed": "2c4cc2d1504653a7b17d9e8a61cfdd1f", "winning_chance": "30.91"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692327", "payout": "3.07343", "profit": "-0.80000000", "balance": "459876.08657868", "time_taken": 0.027395009994506836, "roll_number": 6448}	0.00000000	0.00000000	2026-09-23 05:21:23.421106+07
fbb47fc4-8548-4560-90e0-0d722b4b07e8	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	3.20000000	34.2800	COMPLETED	34019692355	459874.48657868	459871.28657868	-3.20000000	-3.20000000	LOSS	2026-09-23 05:21:23.851051+07	2026-09-23 05:21:23.85334+07	2026-09-23 05:21:24.064843+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.77129", "profit": "5.66812800", "bet_amt": "3.20000000", "client_seed": "8e142aef954292a4aca3f2a02c625c0b", "winning_chance": "34.28"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692355", "payout": "2.77129", "profit": "-3.20000000", "balance": "459871.28657868", "time_taken": 0.027132034301757812, "roll_number": 9780}	0.00000000	0.00000000	2026-09-23 05:21:24.064843+07
86d65b6f-f5dc-4028-a788-5b3c71d25fe2	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	12.80000000	37.2200	COMPLETED	34019692384	459864.88657868	459852.08657868	-12.80000000	-12.80000000	LOSS	2026-09-23 05:21:24.490191+07	2026-09-23 05:21:24.492786+07	2026-09-23 05:21:24.703137+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.55239", "profit": "19.87059200", "bet_amt": "12.80000000", "client_seed": "a48e7bd72efce52d41acfe1de18250d8", "winning_chance": "37.22"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692384", "payout": "2.55239", "profit": "-12.80000000", "balance": "459852.08657868", "time_taken": 0.02526402473449707, "roll_number": 7313}	0.00000000	0.00000000	2026-09-23 05:21:24.703137+07
d832909a-3bce-4fbb-9488-4408b584ac46	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	33.6000	COMPLETED	34019692454	459903.41742668	459903.01742668	-0.40000000	-0.40000000	LOSS	2026-09-23 05:21:25.769863+07	2026-09-23 05:21:25.772062+07	2026-09-23 05:21:26.182612+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.82738", "profit": "0.73095200", "bet_amt": "0.40000000", "client_seed": "a99b104ec7779bb5f209222405e435c2", "winning_chance": "33.60"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692454", "payout": "2.82738", "profit": "-0.40000000", "balance": "459903.01742668", "time_taken": 0.22729110717773438, "roll_number": 3538}	0.00000000	0.00000000	2026-09-23 05:21:26.182612+07
ceb9fa3a-e725-4b10-bbba-ab4eb478e1be	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	1.60000000	30.9900	COMPLETED	34019692507	459902.21742668	459900.61742668	-1.60000000	-1.60000000	LOSS	2026-09-23 05:21:26.607542+07	2026-09-23 05:21:26.60983+07	2026-09-23 05:21:26.820142+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.06550", "profit": "3.30480000", "bet_amt": "1.60000000", "client_seed": "8d1891511395362519fea123726bcae0", "winning_chance": "30.99"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692507", "payout": "3.06550", "profit": "-1.60000000", "balance": "459900.61742668", "time_taken": 0.0270230770111084, "roll_number": 4548}	0.00000000	0.00000000	2026-09-23 05:21:26.820142+07
abf1ea11-bb0d-49cc-be50-6de8ba1a2611	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	6.40000000	32.5400	COMPLETED	34019692542	459897.41742668	459891.01742668	-6.40000000	-6.40000000	LOSS	2026-09-23 05:21:27.243432+07	2026-09-23 05:21:27.246299+07	2026-09-23 05:21:27.455592+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.91948", "profit": "12.28467200", "bet_amt": "6.40000000", "client_seed": "3a15958b340a9d914791c675bbaeff28", "winning_chance": "32.54"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692542", "payout": "2.91948", "profit": "-6.40000000", "balance": "459891.01742668", "time_taken": 0.02521800994873047, "roll_number": 6305}	0.00000000	0.00000000	2026-09-23 05:21:27.455592+07
adf24130-d312-46f5-b1d1-7f764ef84b3b	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	25.60000000	33.2300	COMPLETED	34019692566	459878.21742668	459925.80424268	47.58681600	47.58681600	WIN	2026-09-23 05:21:27.881364+07	2026-09-23 05:21:27.88268+07	2026-09-23 05:21:28.095586+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.85886", "profit": "47.58681600", "bet_amt": "25.60000000", "client_seed": "d4199042f0f2422989ddf50cef947e51", "winning_chance": "33.23"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692566", "payout": "2.85886", "profit": "47.58681600", "balance": "459925.80424268", "time_taken": 0.02863907814025879, "roll_number": 9301}	0.00000000	0.00000000	2026-09-23 05:21:28.095586+07
32e694a3-bccc-414a-b792-7bd3425a7543	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	34.3400	COMPLETED	34019692597	459925.70424268	459926.05753268	0.35329000	0.35329000	WIN	2026-09-23 05:21:28.519042+07	2026-09-23 05:21:28.520787+07	2026-09-23 05:21:28.732279+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.76645", "profit": "0.35329000", "bet_amt": "0.20000000", "client_seed": "41f843f9c2e71eabba495696ea9a8a61", "winning_chance": "34.34"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692597", "payout": "2.76645", "profit": "0.35329000", "balance": "459926.05753268", "time_taken": 0.028542041778564453, "roll_number": 3135}	0.00000000	0.00000000	2026-09-23 05:21:28.732279+07
1b286f7b-b416-4b32-9cc1-8eff05eb143a	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	38.2800	COMPLETED	34019692635	459925.95753268	459925.75753268	-0.20000000	-0.20000000	LOSS	2026-09-23 05:21:29.154064+07	2026-09-23 05:21:29.155527+07	2026-09-23 05:21:29.366074+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.48171", "profit": "0.29634200", "bet_amt": "0.20000000", "client_seed": "c591f8c50c2dda99c266c35fb5b55b85", "winning_chance": "38.28"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692635", "payout": "2.48171", "profit": "-0.20000000", "balance": "459925.75753268", "time_taken": 0.02661299705505371, "roll_number": 3352}	0.00000000	0.00000000	2026-09-23 05:21:29.366074+07
bead6e82-c7cc-4242-9899-e59f42800f4d	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	1.60000000	30.8300	COMPLETED	34019692681	459924.55753268	459927.88778868	3.33025600	3.33025600	WIN	2026-09-23 05:21:30.108628+07	2026-09-23 05:21:30.110138+07	2026-09-23 05:21:30.319807+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.08141", "profit": "3.33025600", "bet_amt": "1.60000000", "client_seed": "0a62804c8b57a3503f7227945ef7ed39", "winning_chance": "30.83"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692681", "payout": "3.08141", "profit": "3.33025600", "balance": "459927.88778868", "time_taken": 0.02695488929748535, "roll_number": 9441}	0.00000000	0.00000000	2026-09-23 05:21:30.319807+07
353039ff-afda-43ac-a7c5-d8569fa9188d	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.80000000	32.9700	COMPLETED	34019692484	459903.01742668	459902.21742668	-0.80000000	-0.80000000	LOSS	2026-09-23 05:21:26.290159+07	2026-09-23 05:21:26.291451+07	2026-09-23 05:21:26.500343+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.88140", "profit": "1.50512000", "bet_amt": "0.80000000", "client_seed": "d8f565022ed1163808f3c7ea95d0ba7a", "winning_chance": "32.97"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692484", "payout": "2.88140", "profit": "-0.80000000", "balance": "459902.21742668", "time_taken": 0.02503514289855957, "roll_number": 5521}	0.00000000	0.00000000	2026-09-23 05:21:26.500343+07
a1a8cda7-85ab-477a-956b-cec0b3909482	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	3.20000000	34.6500	COMPLETED	34019692527	459900.61742668	459897.41742668	-3.20000000	-3.20000000	LOSS	2026-09-23 05:21:26.926155+07	2026-09-23 05:21:26.92742+07	2026-09-23 05:21:27.135599+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.74170", "profit": "5.57344000", "bet_amt": "3.20000000", "client_seed": "939035b2c8cb0723747a054effd6ae5c", "winning_chance": "34.65"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692527", "payout": "2.74170", "profit": "-3.20000000", "balance": "459897.41742668", "time_taken": 0.0252840518951416, "roll_number": 9120}	0.00000000	0.00000000	2026-09-23 05:21:27.135599+07
9f11fa13-2a28-40d1-8d15-43ccf88570e1	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	12.80000000	30.5600	COMPLETED	34019692558	459891.01742668	459878.21742668	-12.80000000	-12.80000000	LOSS	2026-09-23 05:21:27.563689+07	2026-09-23 05:21:27.565714+07	2026-09-23 05:21:27.776746+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "3.10863", "profit": "26.99046400", "bet_amt": "12.80000000", "client_seed": "b6c53c3d201119437f8fcef76c5f3c31", "winning_chance": "30.56"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692558", "payout": "3.10863", "profit": "-12.80000000", "balance": "459878.21742668", "time_taken": 0.02811717987060547, "roll_number": 5504}	0.00000000	0.00000000	2026-09-23 05:21:27.776746+07
e5739ca9-2448-4fed-ae88-23b2d93e4b3e	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	33.3400	COMPLETED	34019692577	459925.80424268	459925.70424268	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:28.200514+07	2026-09-23 05:21:28.201933+07	2026-09-23 05:21:28.412842+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.84943", "profit": "0.18494300", "bet_amt": "0.10000000", "client_seed": "e954ccf2e18bc84aa1ead4f73712b31b", "winning_chance": "33.34"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692577", "payout": "2.84943", "profit": "-0.10000000", "balance": "459925.70424268", "time_taken": 0.0278470516204834, "roll_number": 5941}	0.00000000	0.00000000	2026-09-23 05:21:28.412842+07
559040d8-6f24-427c-bf99-9950f8d083e9	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	32.7500	COMPLETED	34019692618	459926.05753268	459925.95753268	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:28.838226+07	2026-09-23 05:21:28.839792+07	2026-09-23 05:21:29.048562+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.90076", "profit": "0.19007600", "bet_amt": "0.10000000", "client_seed": "cd9c423030e5714260c975e3e1b9095d", "winning_chance": "32.75"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692618", "payout": "2.90076", "profit": "-0.10000000", "balance": "459925.95753268", "time_taken": 0.025803089141845703, "roll_number": 5296}	0.00000000	0.00000000	2026-09-23 05:21:29.048562+07
bc619d6b-b9ff-4b72-86a5-faf03bcfca28	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	34.7800	COMPLETED	34019692654	459925.75753268	459925.35753268	-0.40000000	-0.40000000	LOSS	2026-09-23 05:21:29.473817+07	2026-09-23 05:21:29.476922+07	2026-09-23 05:21:29.687288+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.73145", "profit": "0.69258000", "bet_amt": "0.40000000", "client_seed": "85ec9a87660e5d4797dd35c1f9f8ac93", "winning_chance": "34.78"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692654", "payout": "2.73145", "profit": "-0.40000000", "balance": "459925.35753268", "time_taken": 0.026951074600219727, "roll_number": 1508}	0.00000000	0.00000000	2026-09-23 05:21:29.687288+07
0bd17330-3ff4-40f4-a525-a532b2a6a679	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.80000000	30.9900	COMPLETED	34019692667	459925.35753268	459924.55753268	-0.80000000	-0.80000000	LOSS	2026-09-23 05:21:29.793582+07	2026-09-23 05:21:29.795467+07	2026-09-23 05:21:30.003958+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.06550", "profit": "1.65240000", "bet_amt": "0.80000000", "client_seed": "32295077deb2aec9eb345cd2193a34a9", "winning_chance": "30.99"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692667", "payout": "3.06550", "profit": "-0.80000000", "balance": "459924.55753268", "time_taken": 0.025255918502807617, "roll_number": 1026}	0.00000000	0.00000000	2026-09-23 05:21:30.003958+07
dda910c5-988d-4f4a-beac-522b1da194aa	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	31.1900	COMPLETED	34019692698	459927.88778868	459927.78778868	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:30.424863+07	2026-09-23 05:21:30.426359+07	2026-09-23 05:21:30.636134+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.04584", "profit": "0.20458400", "bet_amt": "0.10000000", "client_seed": "77c583f20e0cbca4c2f2304c7db0441f", "winning_chance": "31.19"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692698", "payout": "3.04584", "profit": "-0.10000000", "balance": "459927.78778868", "time_taken": 0.027186155319213867, "roll_number": 3533}	0.00000000	0.00000000	2026-09-23 05:21:30.636134+07
b3e3880e-3793-410e-9767-f84e110d0c02	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	35.0500	COMPLETED	34019692737	459928.15716068	459928.05716068	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:31.057924+07	2026-09-23 05:21:31.059519+07	2026-09-23 05:21:31.266747+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.71041", "profit": "0.17104100", "bet_amt": "0.10000000", "client_seed": "9316862b82fccf38ff7670faef284816", "winning_chance": "35.05"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692737", "payout": "2.71041", "profit": "-0.10000000", "balance": "459928.05716068", "time_taken": 0.023433923721313477, "roll_number": 6162}	0.00000000	0.00000000	2026-09-23 05:21:31.266747+07
3ca6643c-1e7e-4f35-9f57-ed9388f4ad34	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	31.3400	COMPLETED	34019692785	459928.40110468	459928.30110468	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:31.694492+07	2026-09-23 05:21:31.696032+07	2026-09-23 05:21:31.903904+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "3.03126", "profit": "0.20312600", "bet_amt": "0.10000000", "client_seed": "2484d97112cc5bd7b58f8302f2dd49c8", "winning_chance": "31.34"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692785", "payout": "3.03126", "profit": "-0.10000000", "balance": "459928.30110468", "time_taken": 0.024618148803710938, "roll_number": 6882}	0.00000000	0.00000000	2026-09-23 05:21:31.903904+07
5e538cb3-5f61-45c5-8894-16e0062a8f04	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	38.8500	COMPLETED	34019692827	459928.10110468	459928.67922468	0.57812000	0.57812000	WIN	2026-09-23 05:21:32.323944+07	2026-09-23 05:21:32.325215+07	2026-09-23 05:21:32.535372+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.44530", "profit": "0.57812000", "bet_amt": "0.40000000", "client_seed": "19e8b33b38e8e1b56593f274e3a7a2fa", "winning_chance": "38.85"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692827", "payout": "2.44530", "profit": "0.57812000", "balance": "459928.67922468", "time_taken": 0.026134014129638672, "roll_number": 7473}	0.00000000	0.00000000	2026-09-23 05:21:32.535372+07
18f07a07-fdf8-4786-b9f5-458f084994c1	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	33.3700	COMPLETED	34019692717	459927.78778868	459928.15716068	0.36937200	0.36937200	WIN	2026-09-23 05:21:30.741636+07	2026-09-23 05:21:30.743899+07	2026-09-23 05:21:30.953459+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.84686", "profit": "0.36937200", "bet_amt": "0.20000000", "client_seed": "4a4974e464c76b7b518a0b66abc8e3bf", "winning_chance": "33.37"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692717", "payout": "2.84686", "profit": "0.36937200", "balance": "459928.15716068", "time_taken": 0.026027917861938477, "roll_number": 7950}	0.00000000	0.00000000	2026-09-23 05:21:30.953459+07
95b8527c-25dd-4849-898a-ab9f60026fda	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	30.3900	COMPLETED	34019693781	459959.97907868	459960.82948668	0.85040800	0.85040800	WIN	2026-09-23 05:21:49.427473+07	2026-09-23 05:21:49.429077+07	2026-09-23 05:21:49.640834+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.12602", "profit": "0.85040800", "bet_amt": "0.40000000", "client_seed": "be9b3e2529b9faa36015b71a8c2b6793", "winning_chance": "30.39"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693781", "payout": "3.12602", "profit": "0.85040800", "balance": "459960.82948668", "time_taken": 0.028062105178833008, "roll_number": 8817}	0.00000000	0.00000000	2026-09-23 05:21:49.640834+07
7e0393fb-d4ee-4114-a9ab-1d083f5d6376	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	34.9300	COMPLETED	34019692762	459928.05716068	459928.40110468	0.34394400	0.34394400	WIN	2026-09-23 05:21:31.373864+07	2026-09-23 05:21:31.376269+07	2026-09-23 05:21:31.587934+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.71972", "profit": "0.34394400", "bet_amt": "0.20000000", "client_seed": "37cd117977eba812692acb68026b0a1f", "winning_chance": "34.93"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692762", "payout": "2.71972", "profit": "0.34394400", "balance": "459928.40110468", "time_taken": 0.0279691219329834, "roll_number": 2573}	0.00000000	0.00000000	2026-09-23 05:21:31.587934+07
dfa17c8c-e64f-4dd1-b80a-87c4193bbabd	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	30.1200	COMPLETED	34019692805	459928.30110468	459928.10110468	-0.20000000	-0.20000000	LOSS	2026-09-23 05:21:32.009002+07	2026-09-23 05:21:32.01143+07	2026-09-23 05:21:32.219421+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.15405", "profit": "0.43081000", "bet_amt": "0.20000000", "client_seed": "4d60e28b18693b1903cf4aba1dfbd892", "winning_chance": "30.12"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692805", "payout": "3.15405", "profit": "-0.20000000", "balance": "459928.10110468", "time_taken": 0.023782014846801758, "roll_number": 2297}	0.00000000	0.00000000	2026-09-23 05:21:32.219421+07
f8c7d8a6-b0e2-4b87-a25d-b2119283528d	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	34.0400	COMPLETED	34019692841	459928.67922468	459928.57922468	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:32.644+07	2026-09-23 05:21:32.64588+07	2026-09-23 05:21:32.856822+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.79083", "profit": "0.17908300", "bet_amt": "0.10000000", "client_seed": "8c4a1529133cc1f4e62aa86902e19d59", "winning_chance": "34.04"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692841", "payout": "2.79083", "profit": "-0.10000000", "balance": "459928.57922468", "time_taken": 0.026404142379760742, "roll_number": 1072}	0.00000000	0.00000000	2026-09-23 05:21:32.856822+07
a5dc467e-56b5-4011-8e0c-1ac2171b0da8	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	32.4900	COMPLETED	34019692871	459928.37922468	459927.97922468	-0.40000000	-0.40000000	LOSS	2026-09-23 05:21:33.278486+07	2026-09-23 05:21:33.280519+07	2026-09-23 05:21:33.490764+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.92397", "profit": "0.76958800", "bet_amt": "0.40000000", "client_seed": "0c93376e546065c93e1b1db1d04c5ea6", "winning_chance": "32.49"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692871", "payout": "2.92397", "profit": "-0.40000000", "balance": "459927.97922468", "time_taken": 0.02600693702697754, "roll_number": 9882}	0.00000000	0.00000000	2026-09-23 05:21:33.490764+07
55119763-a33a-441a-8d80-13128c264220	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	3.20000000	30.7400	COMPLETED	34019692914	459925.57922468	459932.26860068	6.68937600	6.68937600	WIN	2026-09-23 05:21:34.227242+07	2026-09-23 05:21:34.228902+07	2026-09-23 05:21:34.438593+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.09043", "profit": "6.68937600", "bet_amt": "3.20000000", "client_seed": "030d176a7acd8fe717781c47d9233843", "winning_chance": "30.74"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692914", "payout": "3.09043", "profit": "6.68937600", "balance": "459932.26860068", "time_taken": 0.026504993438720703, "roll_number": 7048}	0.00000000	0.00000000	2026-09-23 05:21:34.438593+07
161ebd47-9fec-4773-9c13-43a811579d8b	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	39.6300	COMPLETED	34019692925	459932.26860068	459932.40831768	0.13971700	0.13971700	WIN	2026-09-23 05:21:34.54701+07	2026-09-23 05:21:34.549812+07	2026-09-23 05:21:34.761099+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.39717", "profit": "0.13971700", "bet_amt": "0.10000000", "client_seed": "925faf047265afa3ebb5222bb00717ae", "winning_chance": "39.63"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692925", "payout": "2.39717", "profit": "0.13971700", "balance": "459932.40831768", "time_taken": 0.027219057083129883, "roll_number": 2869}	0.00000000	0.00000000	2026-09-23 05:21:34.761099+07
8d23efd0-6425-44ea-915e-96b9be7640a8	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	35.5700	COMPLETED	34019692948	459932.30831768	459932.10831768	-0.20000000	-0.20000000	LOSS	2026-09-23 05:21:35.185005+07	2026-09-23 05:21:35.186468+07	2026-09-23 05:21:35.39698+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.67078", "profit": "0.33415600", "bet_amt": "0.20000000", "client_seed": "65d60292c8b685044fc5ef39ccf33648", "winning_chance": "35.57"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692948", "payout": "2.67078", "profit": "-0.20000000", "balance": "459932.10831768", "time_taken": 0.026399850845336914, "roll_number": 5843}	0.00000000	0.00000000	2026-09-23 05:21:35.39698+07
bf261614-af16-4b28-8f1c-65e2b4a3c14f	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	39.2100	COMPLETED	34019692991	459932.72872568	459932.87101068	0.14228500	0.14228500	WIN	2026-09-23 05:21:35.818381+07	2026-09-23 05:21:35.819808+07	2026-09-23 05:21:36.028645+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.42285", "profit": "0.14228500", "bet_amt": "0.10000000", "client_seed": "6d68a791647493bcc5a985df11202bfb", "winning_chance": "39.21"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692991", "payout": "2.42285", "profit": "0.14228500", "balance": "459932.87101068", "time_taken": 0.025713205337524414, "roll_number": 7288}	0.00000000	0.00000000	2026-09-23 05:21:36.028645+07
7e8122fa-5e99-41e1-ae1a-b4946570fd9f	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	32.5700	COMPLETED	34019693036	459932.77101068	459933.15436868	0.38335800	0.38335800	WIN	2026-09-23 05:21:36.450327+07	2026-09-23 05:21:36.452609+07	2026-09-23 05:21:36.664011+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.91679", "profit": "0.38335800", "bet_amt": "0.20000000", "client_seed": "d70cc142a216e1f059840b005528346e", "winning_chance": "32.57"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693036", "payout": "2.91679", "profit": "0.38335800", "balance": "459933.15436868", "time_taken": 0.027322053909301758, "roll_number": 2323}	0.00000000	0.00000000	2026-09-23 05:21:36.664011+07
42eb70bb-35b7-46e3-b358-4d2c7782749d	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	32.4600	COMPLETED	34019693062	459933.05436868	459932.85436868	-0.20000000	-0.20000000	LOSS	2026-09-23 05:21:37.085828+07	2026-09-23 05:21:37.087225+07	2026-09-23 05:21:37.295198+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.92667", "profit": "0.38533400", "bet_amt": "0.20000000", "client_seed": "227ee607bd1c4e158c1731f5a022d2ea", "winning_chance": "32.46"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693062", "payout": "2.92667", "profit": "-0.20000000", "balance": "459932.85436868", "time_taken": 0.025104045867919922, "roll_number": 2006}	0.00000000	0.00000000	2026-09-23 05:21:37.295198+07
d0e19ef7-6aa5-4714-9517-2cfe2cfd3736	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	38.7200	COMPLETED	34019692857	459928.57922468	459928.37922468	-0.20000000	-0.20000000	LOSS	2026-09-23 05:21:32.961938+07	2026-09-23 05:21:32.963425+07	2026-09-23 05:21:33.173407+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.45351", "profit": "0.29070200", "bet_amt": "0.20000000", "client_seed": "df11331bdce29a54771a35e9bcadf14e", "winning_chance": "38.72"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692857", "payout": "2.45351", "profit": "-0.20000000", "balance": "459928.37922468", "time_taken": 0.026840925216674805, "roll_number": 4804}	0.00000000	0.00000000	2026-09-23 05:21:33.173407+07
69aae520-0c4b-4ece-9967-3d0722f7dd21	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.80000000	38.4700	COMPLETED	34019692883	459927.97922468	459927.17922468	-0.80000000	-0.80000000	LOSS	2026-09-23 05:21:33.595885+07	2026-09-23 05:21:33.597437+07	2026-09-23 05:21:33.806229+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.46945", "profit": "1.17556000", "bet_amt": "0.80000000", "client_seed": "4b6065f822da8709e3450ed6d0729d2b", "winning_chance": "38.47"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692883", "payout": "2.46945", "profit": "-0.80000000", "balance": "459927.17922468", "time_taken": 0.025365114212036133, "roll_number": 6857}	0.00000000	0.00000000	2026-09-23 05:21:33.806229+07
db2e1739-40cd-432b-940f-92e68f53506a	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	1.60000000	35.0000	COMPLETED	34019692898	459927.17922468	459925.57922468	-1.60000000	-1.60000000	LOSS	2026-09-23 05:21:33.912079+07	2026-09-23 05:21:33.91354+07	2026-09-23 05:21:34.121735+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.71428", "profit": "2.74284800", "bet_amt": "1.60000000", "client_seed": "ade8c38f582defb87b5cb9315f69e5d5", "winning_chance": "35.00"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692898", "payout": "2.71428", "profit": "-1.60000000", "balance": "459925.57922468", "time_taken": 0.02526688575744629, "roll_number": 4354}	0.00000000	0.00000000	2026-09-23 05:21:34.121735+07
5d42832e-877f-427d-ba54-70f8b8457ce0	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	30.8000	COMPLETED	34019692937	459932.40831768	459932.30831768	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:34.867033+07	2026-09-23 05:21:34.869327+07	2026-09-23 05:21:35.079605+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.08441", "profit": "0.20844100", "bet_amt": "0.10000000", "client_seed": "bae3b2cdeaeb853a738f7a8f67f331e4", "winning_chance": "30.80"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692937", "payout": "3.08441", "profit": "-0.10000000", "balance": "459932.30831768", "time_taken": 0.027504920959472656, "roll_number": 661}	0.00000000	0.00000000	2026-09-23 05:21:35.079605+07
f13c28cd-7806-4fa7-8fa3-9d29e58d8f40	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	37.2400	COMPLETED	34019692969	459932.10831768	459932.72872568	0.62040800	0.62040800	WIN	2026-09-23 05:21:35.501489+07	2026-09-23 05:21:35.502762+07	2026-09-23 05:21:35.71368+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.55102", "profit": "0.62040800", "bet_amt": "0.40000000", "client_seed": "d97c71a120d0e7d664e5aedb67610112", "winning_chance": "37.24"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019692969", "payout": "2.55102", "profit": "0.62040800", "balance": "459932.72872568", "time_taken": 0.028294086456298828, "roll_number": 8309}	0.00000000	0.00000000	2026-09-23 05:21:35.71368+07
e2e47d7a-7fcc-4497-918b-3497cf790dfd	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	37.1500	COMPLETED	34019693012	459932.87101068	459932.77101068	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:36.133312+07	2026-09-23 05:21:36.134594+07	2026-09-23 05:21:36.343669+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.55720", "profit": "0.15572000", "bet_amt": "0.10000000", "client_seed": "2a6232a20f89763d15b9fdd955ff75e1", "winning_chance": "37.15"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693012", "payout": "2.55720", "profit": "-0.10000000", "balance": "459932.77101068", "time_taken": 0.025833845138549805, "roll_number": 7948}	0.00000000	0.00000000	2026-09-23 05:21:36.343669+07
db35ef83-6e8f-4e6f-8cb8-0176a7bf08bc	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	30.8400	COMPLETED	34019693049	459933.15436868	459933.05436868	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:36.770957+07	2026-09-23 05:21:36.772392+07	2026-09-23 05:21:36.980913+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.08041", "profit": "0.20804100", "bet_amt": "0.10000000", "client_seed": "fa86f929dc9e4578e46cec7c5515c0df", "winning_chance": "30.84"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693049", "payout": "3.08041", "profit": "-0.10000000", "balance": "459933.05436868", "time_taken": 0.024950027465820312, "roll_number": 1261}	0.00000000	0.00000000	2026-09-23 05:21:36.980913+07
d04bdbcf-e050-4659-a077-de4fcbf29c43	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	39.1900	COMPLETED	34019693082	459932.85436868	459933.42400068	0.56963200	0.56963200	WIN	2026-09-23 05:21:37.401599+07	2026-09-23 05:21:37.404086+07	2026-09-23 05:21:37.614031+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.42408", "profit": "0.56963200", "bet_amt": "0.40000000", "client_seed": "36f58b243ce762fbbf163ee5eee32dbb", "winning_chance": "39.19"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693082", "payout": "2.42408", "profit": "0.56963200", "balance": "459933.42400068", "time_taken": 0.02626204490661621, "roll_number": 2770}	0.00000000	0.00000000	2026-09-23 05:21:37.614031+07
dd2b4b54-5da9-4d06-8465-b2559fdae082	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	33.1300	COMPLETED	34019693110	459933.32400068	459933.69749868	0.37349800	0.37349800	WIN	2026-09-23 05:21:38.038997+07	2026-09-23 05:21:38.040416+07	2026-09-23 05:21:38.248867+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.86749", "profit": "0.37349800", "bet_amt": "0.20000000", "client_seed": "6c16ca15875b7689461a75aa375a9828", "winning_chance": "33.13"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693110", "payout": "2.86749", "profit": "0.37349800", "balance": "459933.69749868", "time_taken": 0.025054931640625, "roll_number": 3114}	0.00000000	0.00000000	2026-09-23 05:21:38.248867+07
3390a4ef-1c4b-4007-ba0c-b4978f2332e0	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	31.5100	COMPLETED	34019693150	459933.84450768	459933.74450768	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:38.672074+07	2026-09-23 05:21:38.673561+07	2026-09-23 05:21:38.882704+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "3.01491", "profit": "0.20149100", "bet_amt": "0.10000000", "client_seed": "aa06977989835057b05564bcb8749bc8", "winning_chance": "31.51"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693150", "payout": "3.01491", "profit": "-0.10000000", "balance": "459933.74450768", "time_taken": 0.02586197853088379, "roll_number": 5515}	0.00000000	0.00000000	2026-09-23 05:21:38.882704+07
129a6084-d3f7-465a-8558-bd5988be6ec6	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	37.0800	COMPLETED	34019693218	459934.36828368	459934.26828368	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:39.635146+07	2026-09-23 05:21:39.636508+07	2026-09-23 05:21:39.843604+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.56202", "profit": "0.15620200", "bet_amt": "0.10000000", "client_seed": "ce7396a3cde85a83fdcc83c6346925d6", "winning_chance": "37.08"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693218", "payout": "2.56202", "profit": "-0.10000000", "balance": "459934.26828368", "time_taken": 0.024066925048828125, "roll_number": 1311}	0.00000000	0.00000000	2026-09-23 05:21:39.843604+07
343e8fe4-da43-482b-9029-c98ffc00179e	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	37.8600	COMPLETED	34019693092	459933.42400068	459933.32400068	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:37.720554+07	2026-09-23 05:21:37.722615+07	2026-09-23 05:21:37.932472+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.50924", "profit": "0.15092400", "bet_amt": "0.10000000", "client_seed": "593dc411bb68baf3f17706232916dfc9", "winning_chance": "37.86"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693092", "payout": "2.50924", "profit": "-0.10000000", "balance": "459933.32400068", "time_taken": 0.026020050048828125, "roll_number": 7222}	0.00000000	0.00000000	2026-09-23 05:21:37.932472+07
26f3b0a8-92b0-411c-9a6f-dc48d5255d71	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	32.4900	COMPLETED	34019693804	459960.82948668	459960.72948668	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:49.746496+07	2026-09-23 05:21:49.748673+07	2026-09-23 05:21:49.956408+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.92397", "profit": "0.19239700", "bet_amt": "0.10000000", "client_seed": "b9e8235c9f93826eeffd566b20d1afb3", "winning_chance": "32.49"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693804", "payout": "2.92397", "profit": "-0.10000000", "balance": "459960.72948668", "time_taken": 0.02465510368347168, "roll_number": 5017}	0.00000000	0.00000000	2026-09-23 05:21:49.956408+07
bddd43fa-3f68-4de4-9f0b-bd88d4d733ee	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	38.4600	COMPLETED	34019693127	459933.69749868	459933.84450768	0.14700900	0.14700900	WIN	2026-09-23 05:21:38.353666+07	2026-09-23 05:21:38.355172+07	2026-09-23 05:21:38.566303+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.47009", "profit": "0.14700900", "bet_amt": "0.10000000", "client_seed": "acb9924efb28395e8d4d6c3834a07a58", "winning_chance": "38.46"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693127", "payout": "2.47009", "profit": "0.14700900", "balance": "459933.84450768", "time_taken": 0.02697300910949707, "roll_number": 565}	0.00000000	0.00000000	2026-09-23 05:21:38.566303+07
ba2c5219-f742-4c0e-a426-a2daaa8be4ee	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	30.1100	COMPLETED	34019693174	459933.74450768	459934.17552568	0.43101800	0.43101800	WIN	2026-09-23 05:21:38.991383+07	2026-09-23 05:21:38.993778+07	2026-09-23 05:21:39.205975+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "3.15509", "profit": "0.43101800", "bet_amt": "0.20000000", "client_seed": "9a02425601726c72932546700ff6019c", "winning_chance": "30.11"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693174", "payout": "3.15509", "profit": "0.43101800", "balance": "459934.17552568", "time_taken": 0.028107166290283203, "roll_number": 2309}	0.00000000	0.00000000	2026-09-23 05:21:39.205975+07
7b9128fb-fdbc-45d1-b1e8-87100addc4d9	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	32.4500	COMPLETED	34019693195	459934.17552568	459934.36828368	0.19275800	0.19275800	WIN	2026-09-23 05:21:39.31341+07	2026-09-23 05:21:39.315719+07	2026-09-23 05:21:39.527408+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.92758", "profit": "0.19275800", "bet_amt": "0.10000000", "client_seed": "44ad5397b6bf50f19ae14a463f0d0c39", "winning_chance": "32.45"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693195", "payout": "2.92758", "profit": "0.19275800", "balance": "459934.36828368", "time_taken": 0.027531862258911133, "roll_number": 8110}	0.00000000	0.00000000	2026-09-23 05:21:39.527408+07
c57c4e6c-50e4-4d97-af5e-f04fbfce05ab	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	30.6200	COMPLETED	34019693233	459934.26828368	459934.06828368	-0.20000000	-0.20000000	LOSS	2026-09-23 05:21:39.949025+07	2026-09-23 05:21:39.950829+07	2026-09-23 05:21:40.160142+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.10254", "profit": "0.42050800", "bet_amt": "0.20000000", "client_seed": "24ba478f014499ba4c7e3d1dfde31085", "winning_chance": "30.62"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693233", "payout": "3.10254", "profit": "-0.20000000", "balance": "459934.06828368", "time_taken": 0.026417970657348633, "roll_number": 6651}	0.00000000	0.00000000	2026-09-23 05:21:40.160142+07
8f7f269f-09ad-44db-ab30-d2ac4961f7e8	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	30.9200	COMPLETED	34019693262	459934.69893168	459934.90617568	0.20724400	0.20724400	WIN	2026-09-23 05:21:40.585982+07	2026-09-23 05:21:40.588162+07	2026-09-23 05:21:40.798108+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.07244", "profit": "0.20724400", "bet_amt": "0.10000000", "client_seed": "675518595b5bcab8dac765871ec3f1ec", "winning_chance": "30.92"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693262", "payout": "3.07244", "profit": "0.20724400", "balance": "459934.90617568", "time_taken": 0.025896072387695312, "roll_number": 8201}	0.00000000	0.00000000	2026-09-23 05:21:40.798108+07
aee19b98-a801-4969-9f65-62ff5963712f	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	36.1400	COMPLETED	34019693293	459934.80617568	459934.60617568	-0.20000000	-0.20000000	LOSS	2026-09-23 05:21:41.22248+07	2026-09-23 05:21:41.225183+07	2026-09-23 05:21:41.435359+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.62866", "profit": "0.32573200", "bet_amt": "0.20000000", "client_seed": "b49529869b1b0f81870c1c657c659d0a", "winning_chance": "36.14"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693293", "payout": "2.62866", "profit": "-0.20000000", "balance": "459934.60617568", "time_taken": 0.026163101196289062, "roll_number": 5216}	0.00000000	0.00000000	2026-09-23 05:21:41.435359+07
9affffb7-7942-497b-9a63-0ce45af4a148	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	38.1400	COMPLETED	34019693316	459934.60617568	459935.20250368	0.59632800	0.59632800	WIN	2026-09-23 05:21:41.541288+07	2026-09-23 05:21:41.543198+07	2026-09-23 05:21:41.75545+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.49082", "profit": "0.59632800", "bet_amt": "0.40000000", "client_seed": "83cb304810e237033f2efb738d2b07f3", "winning_chance": "38.14"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693316", "payout": "2.49082", "profit": "0.59632800", "balance": "459935.20250368", "time_taken": 0.029551982879638672, "roll_number": 8089}	0.00000000	0.00000000	2026-09-23 05:21:41.75545+07
3d81f0b9-4d5a-4682-8568-0d525cce51b6	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	36.3400	COMPLETED	34019693355	459935.10250368	459935.42534168	0.32283800	0.32283800	WIN	2026-09-23 05:21:42.177519+07	2026-09-23 05:21:42.1796+07	2026-09-23 05:21:42.393008+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.61419", "profit": "0.32283800", "bet_amt": "0.20000000", "client_seed": "e8e4df66827e1ec991edd44d5898e972", "winning_chance": "36.34"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693355", "payout": "2.61419", "profit": "0.32283800", "balance": "459935.42534168", "time_taken": 0.030462026596069336, "roll_number": 7995}	0.00000000	0.00000000	2026-09-23 05:21:42.393008+07
35138ddd-ab5e-409e-abab-bd3ba924c7b3	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	30.7800	COMPLETED	34019693365	459935.42534168	459935.63398268	0.20864100	0.20864100	WIN	2026-09-23 05:21:42.498534+07	2026-09-23 05:21:42.500901+07	2026-09-23 05:21:42.711396+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.08641", "profit": "0.20864100", "bet_amt": "0.10000000", "client_seed": "a30dfcf6733a07777ee305aaa5f4a63b", "winning_chance": "30.78"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693365", "payout": "3.08641", "profit": "0.20864100", "balance": "459935.63398268", "time_taken": 0.026887893676757812, "roll_number": 7030}	0.00000000	0.00000000	2026-09-23 05:21:42.711396+07
b1ba76c4-73f4-40fc-b317-43cf96004d39	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	35.5900	COMPLETED	34019693405	459935.53398268	459935.86783868	0.33385600	0.33385600	WIN	2026-09-23 05:21:43.340223+07	2026-09-23 05:21:43.342715+07	2026-09-23 05:21:43.554158+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.66928", "profit": "0.33385600", "bet_amt": "0.20000000", "client_seed": "802a1a23631fbacbb1629f3adbd0522f", "winning_chance": "35.59"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693405", "payout": "2.66928", "profit": "0.33385600", "balance": "459935.86783868", "time_taken": 0.028084993362426758, "roll_number": 9854}	0.00000000	0.00000000	2026-09-23 05:21:43.554158+07
cc2ed6f7-e47f-4942-8243-54d3ce0041e9	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	36.8700	COMPLETED	34019693245	459934.06828368	459934.69893168	0.63064800	0.63064800	WIN	2026-09-23 05:21:40.264918+07	2026-09-23 05:21:40.266193+07	2026-09-23 05:21:40.477732+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.57662", "profit": "0.63064800", "bet_amt": "0.40000000", "client_seed": "9dec11e29970f7dacbb6eff1f4b88878", "winning_chance": "36.87"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693245", "payout": "2.57662", "profit": "0.63064800", "balance": "459934.69893168", "time_taken": 0.028126955032348633, "roll_number": 7618}	0.00000000	0.00000000	2026-09-23 05:21:40.477732+07
dfb237ab-73a6-4ca8-9a5a-8d22afbc260f	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	32.3500	COMPLETED	34019693279	459934.90617568	459934.80617568	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:40.904465+07	2026-09-23 05:21:40.907274+07	2026-09-23 05:21:41.116541+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.93663", "profit": "0.19366300", "bet_amt": "0.10000000", "client_seed": "1cba8f0c1fe7049db93e2c0e5b1b86a2", "winning_chance": "32.35"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693279", "payout": "2.93663", "profit": "-0.10000000", "balance": "459934.80617568", "time_taken": 0.025521039962768555, "roll_number": 5472}	0.00000000	0.00000000	2026-09-23 05:21:41.116541+07
0f3b91d1-a2d8-4285-a8df-d4756b213d85	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	30.6200	COMPLETED	34019693822	459960.72948668	459960.52948668	-0.20000000	-0.20000000	LOSS	2026-09-23 05:21:50.060623+07	2026-09-23 05:21:50.062055+07	2026-09-23 05:21:50.271735+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.10254", "profit": "0.42050800", "bet_amt": "0.20000000", "client_seed": "c3e2dc225cbefea60a2958d0b6ab81dd", "winning_chance": "30.62"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693822", "payout": "3.10254", "profit": "-0.20000000", "balance": "459960.52948668", "time_taken": 0.02691197395324707, "roll_number": 3574}	0.00000000	0.00000000	2026-09-23 05:21:50.271735+07
923b2afd-c976-457f-a525-37216d2483cb	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	30.4300	COMPLETED	34019693337	459935.20250368	459935.10250368	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:41.860434+07	2026-09-23 05:21:41.861793+07	2026-09-23 05:21:42.071079+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.12191", "profit": "0.21219100", "bet_amt": "0.10000000", "client_seed": "1c3fa29f6314daf4b9358ab5f845addd", "winning_chance": "30.43"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693337", "payout": "3.12191", "profit": "-0.10000000", "balance": "459935.10250368", "time_taken": 0.026005983352661133, "roll_number": 3651}	0.00000000	0.00000000	2026-09-23 05:21:42.071079+07
c89a5b86-e411-4010-a67d-efffa0e8458d	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.80000000	30.5800	COMPLETED	34019693861	459960.12948668	459959.32948668	-0.80000000	-0.80000000	LOSS	2026-09-23 05:21:50.696815+07	2026-09-23 05:21:50.698825+07	2026-09-23 05:21:50.909872+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.10660", "profit": "1.68528000", "bet_amt": "0.80000000", "client_seed": "2d2d159bd0cf50e90c64dd860099c9dc", "winning_chance": "30.58"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693861", "payout": "3.10660", "profit": "-0.80000000", "balance": "459959.32948668", "time_taken": 0.027909040451049805, "roll_number": 185}	0.00000000	0.00000000	2026-09-23 05:21:50.909872+07
1df9bdd0-f758-4a76-8ad2-c7b77d44ce32	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	38.8700	COMPLETED	34019693377	459935.63398268	459935.53398268	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:42.817643+07	2026-09-23 05:21:42.819193+07	2026-09-23 05:21:43.232069+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.44404", "profit": "0.14440400", "bet_amt": "0.10000000", "client_seed": "675aecfc536e52f2a569771e68a76f11", "winning_chance": "38.87"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693377", "payout": "2.44404", "profit": "-0.10000000", "balance": "459935.53398268", "time_taken": 0.22907114028930664, "roll_number": 1445}	0.00000000	0.00000000	2026-09-23 05:21:43.232069+07
b7cdb3b2-eaee-425e-ac6e-6ab69d1ba1f7	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	35.9900	COMPLETED	34019693445	459936.01882868	459935.91882868	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:43.976002+07	2026-09-23 05:21:43.977286+07	2026-09-23 05:21:44.186858+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.63962", "profit": "0.16396200", "bet_amt": "0.10000000", "client_seed": "ad2bc6a854ebe6de3bf8be9110e36fab", "winning_chance": "35.99"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693445", "payout": "2.63962", "profit": "-0.10000000", "balance": "459935.91882868", "time_taken": 0.026237010955810547, "roll_number": 2974}	0.00000000	0.00000000	2026-09-23 05:21:44.186858+07
396e351a-761e-458e-bd84-70f6b09c2034	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	3.20000000	38.8700	COMPLETED	34019693891	459957.72948668	459954.52948668	-3.20000000	-3.20000000	LOSS	2026-09-23 05:21:51.346598+07	2026-09-23 05:21:51.349653+07	2026-09-23 05:21:51.559892+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.44404", "profit": "4.62092800", "bet_amt": "3.20000000", "client_seed": "1a612fcf86e887c039e749330e37931c", "winning_chance": "38.87"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693891", "payout": "2.44404", "profit": "-3.20000000", "balance": "459954.52948668", "time_taken": 0.026897192001342773, "roll_number": 3739}	0.00000000	0.00000000	2026-09-23 05:21:51.559892+07
d1e7b841-7b93-48f5-83b3-0cd877ac545c	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	31.2200	COMPLETED	34019693483	459935.71882868	459935.31882868	-0.40000000	-0.40000000	LOSS	2026-09-23 05:21:44.612972+07	2026-09-23 05:21:44.615899+07	2026-09-23 05:21:44.831899+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "3.04292", "profit": "0.81716800", "bet_amt": "0.40000000", "client_seed": "0d13bdda61a109d0395699a23e22d50a", "winning_chance": "31.22"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693483", "payout": "3.04292", "profit": "-0.40000000", "balance": "459935.31882868", "time_taken": 0.02485513687133789, "roll_number": 3328}	0.00000000	0.00000000	2026-09-23 05:21:44.831899+07
d7e2098d-7cda-497b-8013-3ec972c79e50	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	37.9900	COMPLETED	34019693922	459968.36238268	459968.26238268	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:51.986088+07	2026-09-23 05:21:51.987756+07	2026-09-23 05:21:52.197141+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.50065", "profit": "0.15006500", "bet_amt": "0.10000000", "client_seed": "c5a6bdd02fffe3f434dbd641243fb607", "winning_chance": "37.99"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693922", "payout": "2.50065", "profit": "-0.10000000", "balance": "459968.26238268", "time_taken": 0.026049137115478516, "roll_number": 4172}	0.00000000	0.00000000	2026-09-23 05:21:52.197141+07
2923e13e-4db6-449b-9246-7393c1580b4e	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	38.3100	COMPLETED	34019693962	459968.06238268	459968.65429068	0.59190800	0.59190800	WIN	2026-09-23 05:21:52.625859+07	2026-09-23 05:21:52.628875+07	2026-09-23 05:21:52.841066+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.47977", "profit": "0.59190800", "bet_amt": "0.40000000", "client_seed": "26a87ab2cb8dc119d56122f417e3ad3d", "winning_chance": "38.31"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693962", "payout": "2.47977", "profit": "0.59190800", "balance": "459968.65429068", "time_taken": 0.028017044067382812, "roll_number": 9003}	0.00000000	0.00000000	2026-09-23 05:21:52.841066+07
80472829-856d-418a-b42c-652809b4e115	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	37.8500	COMPLETED	34019693427	459935.86783868	459936.01882868	0.15099000	0.15099000	WIN	2026-09-23 05:21:43.659833+07	2026-09-23 05:21:43.661299+07	2026-09-23 05:21:43.869872+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.50990", "profit": "0.15099000", "bet_amt": "0.10000000", "client_seed": "c447dec69c6181b74ec4a05a63e6c8cd", "winning_chance": "37.85"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693427", "payout": "2.50990", "profit": "0.15099000", "balance": "459936.01882868", "time_taken": 0.02525496482849121, "roll_number": 6348}	0.00000000	0.00000000	2026-09-23 05:21:43.869872+07
e32274dc-ce9f-4c88-bb3c-07cce1158466	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	33.1400	COMPLETED	34019693465	459935.91882868	459935.71882868	-0.20000000	-0.20000000	LOSS	2026-09-23 05:21:44.2922+07	2026-09-23 05:21:44.293582+07	2026-09-23 05:21:44.504232+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.86662", "profit": "0.37332400", "bet_amt": "0.20000000", "client_seed": "183072b491e0df1e4d0b500b7ad999c8", "winning_chance": "33.14"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693465", "payout": "2.86662", "profit": "-0.20000000", "balance": "459935.71882868", "time_taken": 0.026935100555419922, "roll_number": 3195}	0.00000000	0.00000000	2026-09-23 05:21:44.504232+07
2f2d94c2-0d9d-4cec-9dd5-e1557b15839e	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	39.4200	COMPLETED	34019693840	459960.52948668	459960.12948668	-0.40000000	-0.40000000	LOSS	2026-09-23 05:21:50.377489+07	2026-09-23 05:21:50.378889+07	2026-09-23 05:21:50.589917+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.40994", "profit": "0.56397600", "bet_amt": "0.40000000", "client_seed": "d3491b20a10eba64c8e54cf154714b20", "winning_chance": "39.42"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693840", "payout": "2.40994", "profit": "-0.40000000", "balance": "459960.12948668", "time_taken": 0.027259111404418945, "roll_number": 6026}	0.00000000	0.00000000	2026-09-23 05:21:50.589917+07
ca1e59a1-3ebc-4261-8f99-b18c22491b67	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	1.60000000	39.8600	COMPLETED	34019693877	459959.32948668	459957.72948668	-1.60000000	-1.60000000	LOSS	2026-09-23 05:21:51.014985+07	2026-09-23 05:21:51.016426+07	2026-09-23 05:21:51.239127+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.38334", "profit": "2.21334400", "bet_amt": "1.60000000", "client_seed": "87662b9c41ed1b23b0d0bddad4f4acfd", "winning_chance": "39.86"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693877", "payout": "2.38334", "profit": "-1.60000000", "balance": "459957.72948668", "time_taken": 0.025719881057739258, "roll_number": 6434}	0.00000000	0.00000000	2026-09-23 05:21:51.239127+07
ee1ec677-be97-4ce7-9867-9609526d2c20	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	6.40000000	30.0500	COMPLETED	34019693905	459954.52948668	459968.36238268	13.83289600	13.83289600	WIN	2026-09-23 05:21:51.666044+07	2026-09-23 05:21:51.667731+07	2026-09-23 05:21:51.880471+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.16139", "profit": "13.83289600", "bet_amt": "6.40000000", "client_seed": "18fb13da4af2793c2fbbfbeb04b4d788", "winning_chance": "30.05"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693905", "payout": "3.16139", "profit": "13.83289600", "balance": "459968.36238268", "time_taken": 0.02962803840637207, "roll_number": 9014}	0.00000000	0.00000000	2026-09-23 05:21:51.880471+07
b6f3dcb5-07c7-4829-985a-4e91f8cc1195	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	32.0000	COMPLETED	34019693941	459968.26238268	459968.06238268	-0.20000000	-0.20000000	LOSS	2026-09-23 05:21:52.303182+07	2026-09-23 05:21:52.30489+07	2026-09-23 05:21:52.515924+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.96875", "profit": "0.39375000", "bet_amt": "0.20000000", "client_seed": "8e9870948b16b7effe3c53a8aa371d53", "winning_chance": "32.00"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693941", "payout": "2.96875", "profit": "-0.20000000", "balance": "459968.06238268", "time_taken": 0.026706933975219727, "roll_number": 6105}	0.00000000	0.00000000	2026-09-23 05:21:52.515924+07
39d34a64-50f1-44f6-8f2f-35648078c625	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	37.2900	COMPLETED	34019693986	459968.65429068	459968.80904968	0.15475900	0.15475900	WIN	2026-09-23 05:21:52.949452+07	2026-09-23 05:21:52.952186+07	2026-09-23 05:21:53.162996+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.54759", "profit": "0.15475900", "bet_amt": "0.10000000", "client_seed": "fddab514f760de8bfb477b1f59f24cac", "winning_chance": "37.29"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693986", "payout": "2.54759", "profit": "0.15475900", "balance": "459968.80904968", "time_taken": 0.02705216407775879, "roll_number": 3286}	0.00000000	0.00000000	2026-09-23 05:21:53.162996+07
af24e42d-bb19-4d1a-a6a4-c3a614abc7b3	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	33.1200	COMPLETED	34019694005	459968.80904968	459968.70904968	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:53.268163+07	2026-09-23 05:21:53.270423+07	2026-09-23 05:21:53.482252+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.86835", "profit": "0.18683500", "bet_amt": "0.10000000", "client_seed": "db47801c7d7ecc36191cb8b3dcda8765", "winning_chance": "33.12"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694005", "payout": "2.86835", "profit": "-0.10000000", "balance": "459968.70904968", "time_taken": 0.027196884155273438, "roll_number": 4452}	0.00000000	0.00000000	2026-09-23 05:21:53.482252+07
6651e7ad-c862-4083-83e0-fb87060e4517	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	39.1500	COMPLETED	34019694018	459968.70904968	459968.99436168	0.28531200	0.28531200	WIN	2026-09-23 05:21:53.588759+07	2026-09-23 05:21:53.590049+07	2026-09-23 05:21:53.801254+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.42656", "profit": "0.28531200", "bet_amt": "0.20000000", "client_seed": "8e92e45d3a8a305e1218959677f9d32f", "winning_chance": "39.15"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694018", "payout": "2.42656", "profit": "0.28531200", "balance": "459968.99436168", "time_taken": 0.02782917022705078, "roll_number": 2873}	0.00000000	0.00000000	2026-09-23 05:21:53.801254+07
5c504425-e96b-4635-9f6b-ae20418ac675	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	39.7600	COMPLETED	34019694033	459968.99436168	459969.13329468	0.13893300	0.13893300	WIN	2026-09-23 05:21:53.906099+07	2026-09-23 05:21:53.90756+07	2026-09-23 05:21:54.119276+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.38933", "profit": "0.13893300", "bet_amt": "0.10000000", "client_seed": "f15b3751ff5b174b3f314687cab48d79", "winning_chance": "39.76"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694033", "payout": "2.38933", "profit": "0.13893300", "balance": "459969.13329468", "time_taken": 0.028934001922607422, "roll_number": 6817}	0.00000000	0.00000000	2026-09-23 05:21:54.119276+07
9816ee21-e72c-4ce9-843e-e2e611e981e9	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	36.8100	COMPLETED	34019694048	459969.13329468	459969.03329468	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:54.224372+07	2026-09-23 05:21:54.225828+07	2026-09-23 05:21:54.436761+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.58082", "profit": "0.15808200", "bet_amt": "0.10000000", "client_seed": "b08678f38bf2075daae605aeb1d5b8ae", "winning_chance": "36.81"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694048", "payout": "2.58082", "profit": "-0.10000000", "balance": "459969.03329468", "time_taken": 0.027386903762817383, "roll_number": 3999}	0.00000000	0.00000000	2026-09-23 05:21:54.436761+07
cb546f58-c9db-4acf-a2f7-ed9458896251	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	30.4700	COMPLETED	34019694058	459969.03329468	459968.83329468	-0.20000000	-0.20000000	LOSS	2026-09-23 05:21:54.544948+07	2026-09-23 05:21:54.546311+07	2026-09-23 05:21:54.758609+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "3.11782", "profit": "0.42356400", "bet_amt": "0.20000000", "client_seed": "9bd1f39e1f0df037975a9049529f45e2", "winning_chance": "30.47"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694058", "payout": "3.11782", "profit": "-0.20000000", "balance": "459968.83329468", "time_taken": 0.028119802474975586, "roll_number": 8970}	0.00000000	0.00000000	2026-09-23 05:21:54.758609+07
0419dc65-5646-46f3-a47f-c7ad3a6d02ce	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.80000000	34.0000	COMPLETED	34019694086	459968.43329468	459969.86858268	1.43528800	1.43528800	WIN	2026-09-23 05:21:55.178714+07	2026-09-23 05:21:55.180223+07	2026-09-23 05:21:55.393324+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.79411", "profit": "1.43528800", "bet_amt": "0.80000000", "client_seed": "d5623a6c7c51955e13f97d563a20c7e5", "winning_chance": "34.00"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694086", "payout": "2.79411", "profit": "1.43528800", "balance": "459969.86858268", "time_taken": 0.028560876846313477, "roll_number": 9826}	0.00000000	0.00000000	2026-09-23 05:21:55.393324+07
8ac2dcd0-6878-469b-aa86-69d4a754091e	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	34.5600	COMPLETED	34019694128	459969.76858268	459969.56858268	-0.20000000	-0.20000000	LOSS	2026-09-23 05:21:55.818007+07	2026-09-23 05:21:55.819929+07	2026-09-23 05:21:56.029486+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.74884", "profit": "0.34976800", "bet_amt": "0.20000000", "client_seed": "d059702299260a600f61cd77716866d7", "winning_chance": "34.56"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694128", "payout": "2.74884", "profit": "-0.20000000", "balance": "459969.56858268", "time_taken": 0.02641916275024414, "roll_number": 8054}	0.00000000	0.00000000	2026-09-23 05:21:56.029486+07
1840437d-d149-4db6-b6bd-492adb581016	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.80000000	37.4700	COMPLETED	34019694171	459969.16858268	459970.39687068	1.22828800	1.22828800	WIN	2026-09-23 05:21:56.452044+07	2026-09-23 05:21:56.454811+07	2026-09-23 05:21:56.665861+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.53536", "profit": "1.22828800", "bet_amt": "0.80000000", "client_seed": "c7912c2cabe455cd74a814d6e0ab1668", "winning_chance": "37.47"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694171", "payout": "2.53536", "profit": "1.22828800", "balance": "459970.39687068", "time_taken": 0.027040958404541016, "roll_number": 1732}	0.00000000	0.00000000	2026-09-23 05:21:56.665861+07
5504a237-a875-4aa4-b924-7b136153f054	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	31.5700	COMPLETED	34019694193	459970.39687068	459970.29687068	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:56.771129+07	2026-09-23 05:21:56.772577+07	2026-09-23 05:21:56.983314+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "3.00918", "profit": "0.20091800", "bet_amt": "0.10000000", "client_seed": "0cc03cd8d3430de5ca94e83d01d55e93", "winning_chance": "31.57"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694193", "payout": "3.00918", "profit": "-0.10000000", "balance": "459970.29687068", "time_taken": 0.02686309814453125, "roll_number": 7648}	0.00000000	0.00000000	2026-09-23 05:21:56.983314+07
43cc3e36-727c-492b-ad77-682a9efd1286	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	34.0200	COMPLETED	34019694231	459970.09687068	459969.69687068	-0.40000000	-0.40000000	LOSS	2026-09-23 05:21:57.407378+07	2026-09-23 05:21:57.409658+07	2026-09-23 05:21:57.620507+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.79247", "profit": "0.71698800", "bet_amt": "0.40000000", "client_seed": "465517796a5acfa45f741a6f0c3dc2fd", "winning_chance": "34.02"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694231", "payout": "2.79247", "profit": "-0.40000000", "balance": "459969.69687068", "time_taken": 0.027666091918945312, "roll_number": 1589}	0.00000000	0.00000000	2026-09-23 05:21:57.620507+07
17a6cbed-5cff-4caa-87a5-d465c1ef8237	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	36.9100	COMPLETED	34019694265	459971.13019068	459971.03019068	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:58.042931+07	2026-09-23 05:21:58.044418+07	2026-09-23 05:21:58.253698+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.57382", "profit": "0.15738200", "bet_amt": "0.10000000", "client_seed": "b856123de3f61c627e5c186c163625bb", "winning_chance": "36.91"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694265", "payout": "2.57382", "profit": "-0.10000000", "balance": "459971.03019068", "time_taken": 0.02659010887145996, "roll_number": 5119}	0.00000000	0.00000000	2026-09-23 05:21:58.253698+07
46be9643-c84e-497d-b833-cde7c457c912	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	31.8900	COMPLETED	34019694307	459970.83019068	459970.43019068	-0.40000000	-0.40000000	LOSS	2026-09-23 05:21:58.679913+07	2026-09-23 05:21:58.681357+07	2026-09-23 05:21:58.891634+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.97899", "profit": "0.79159600", "bet_amt": "0.40000000", "client_seed": "33ab1a641181e73ba1ddb2af98b4cbc2", "winning_chance": "31.89"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694307", "payout": "2.97899", "profit": "-0.40000000", "balance": "459970.43019068", "time_taken": 0.026829004287719727, "roll_number": 917}	0.00000000	0.00000000	2026-09-23 05:21:58.891634+07
edebd2ba-b219-4795-a9fa-9478d0eb1f32	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	1.60000000	34.4700	COMPLETED	34019694334	459969.63019068	459968.03019068	-1.60000000	-1.60000000	LOSS	2026-09-23 05:21:59.31372+07	2026-09-23 05:21:59.315123+07	2026-09-23 05:21:59.527824+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.75601", "profit": "2.80961600", "bet_amt": "1.60000000", "client_seed": "66ce0b0ff0dae550bec8d76752165ba3", "winning_chance": "34.47"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694334", "payout": "2.75601", "profit": "-1.60000000", "balance": "459968.03019068", "time_taken": 0.029269933700561523, "roll_number": 4609}	0.00000000	0.00000000	2026-09-23 05:21:59.527824+07
e5884732-d39c-41c6-909a-6143cd645e22	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	36.5100	COMPLETED	34019694360	459973.10679868	459973.00679868	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:59.951383+07	2026-09-23 05:21:59.952825+07	2026-09-23 05:22:00.164626+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.60202", "profit": "0.16020200", "bet_amt": "0.10000000", "client_seed": "df751f1628917a544090e486a4c9db6c", "winning_chance": "36.51"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694360", "payout": "2.60202", "profit": "-0.10000000", "balance": "459973.00679868", "time_taken": 0.02799701690673828, "roll_number": 7269}	0.00000000	0.00000000	2026-09-23 05:22:00.164626+07
ad7736d0-6f70-491c-a6b4-b2abe8757177	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	34.7400	COMPLETED	34019694371	459973.00679868	459972.80679868	-0.20000000	-0.20000000	LOSS	2026-09-23 05:22:00.270038+07	2026-09-23 05:22:00.271578+07	2026-09-23 05:22:00.683819+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.73459", "profit": "0.34691800", "bet_amt": "0.20000000", "client_seed": "cb2d4b6b643ed95fe2572f6f480f8945", "winning_chance": "34.74"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694371", "payout": "2.73459", "profit": "-0.20000000", "balance": "459972.80679868", "time_taken": 0.22931408882141113, "roll_number": 9365}	0.00000000	0.00000000	2026-09-23 05:22:00.683819+07
e571f121-f9fd-45d8-aa6b-a80219992007	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	31.2000	COMPLETED	34019694072	459968.83329468	459968.43329468	-0.40000000	-0.40000000	LOSS	2026-09-23 05:21:54.864609+07	2026-09-23 05:21:54.866073+07	2026-09-23 05:21:55.073778+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "3.04487", "profit": "0.81794800", "bet_amt": "0.40000000", "client_seed": "1e1f82de9007bf2ddd5700c6b96d3a73", "winning_chance": "31.20"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694072", "payout": "3.04487", "profit": "-0.40000000", "balance": "459968.43329468", "time_taken": 0.02511119842529297, "roll_number": 9591}	0.00000000	0.00000000	2026-09-23 05:21:55.073778+07
fc3b8d87-ea26-4935-baa5-b0a2bf11e1a9	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	33.8700	COMPLETED	34019694103	459969.86858268	459969.76858268	-0.10000000	-0.10000000	LOSS	2026-09-23 05:21:55.50002+07	2026-09-23 05:21:55.502901+07	2026-09-23 05:21:55.712109+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.80484", "profit": "0.18048400", "bet_amt": "0.10000000", "client_seed": "246b858e55249356c0f123544c784284", "winning_chance": "33.87"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694103", "payout": "2.80484", "profit": "-0.10000000", "balance": "459969.76858268", "time_taken": 0.025358915328979492, "roll_number": 1007}	0.00000000	0.00000000	2026-09-23 05:21:55.712109+07
3b473a9e-cdb4-4e4c-b0db-67732b361710	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	30.9200	COMPLETED	34019694149	459969.56858268	459969.16858268	-0.40000000	-0.40000000	LOSS	2026-09-23 05:21:56.134676+07	2026-09-23 05:21:56.136326+07	2026-09-23 05:21:56.346256+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.07244", "profit": "0.82897600", "bet_amt": "0.40000000", "client_seed": "86afaae8b09ed3b8151dc7dad21c4927", "winning_chance": "30.92"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694149", "payout": "3.07244", "profit": "-0.40000000", "balance": "459969.16858268", "time_taken": 0.02639007568359375, "roll_number": 2555}	0.00000000	0.00000000	2026-09-23 05:21:56.346256+07
7753de30-9741-4bb2-baca-b5cd1d6f141b	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	32.7800	COMPLETED	34019694214	459970.29687068	459970.09687068	-0.20000000	-0.20000000	LOSS	2026-09-23 05:21:57.090305+07	2026-09-23 05:21:57.091715+07	2026-09-23 05:21:57.301014+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.89810", "profit": "0.37962000", "bet_amt": "0.20000000", "client_seed": "e07bb93cbcd2b9edb0afc3abe3d3d34f", "winning_chance": "32.78"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694214", "payout": "2.89810", "profit": "-0.20000000", "balance": "459970.09687068", "time_taken": 0.0258181095123291, "roll_number": 4009}	0.00000000	0.00000000	2026-09-23 05:21:57.301014+07
ea97bc61-9a4e-4b51-aeb4-cf0d757a4475	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.80000000	34.0300	COMPLETED	34019694247	459969.69687068	459971.13019068	1.43332000	1.43332000	WIN	2026-09-23 05:21:57.725857+07	2026-09-23 05:21:57.727237+07	2026-09-23 05:21:57.937954+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.79165", "profit": "1.43332000", "bet_amt": "0.80000000", "client_seed": "39481a20e0a81477458c6f5f72dc3a6a", "winning_chance": "34.03"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694247", "payout": "2.79165", "profit": "1.43332000", "balance": "459971.13019068", "time_taken": 0.028130054473876953, "roll_number": 8003}	0.00000000	0.00000000	2026-09-23 05:21:57.937954+07
f1cc944d-98fe-4f95-90b1-ac3a08564098	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	37.6400	COMPLETED	34019694287	459971.03019068	459970.83019068	-0.20000000	-0.20000000	LOSS	2026-09-23 05:21:58.360465+07	2026-09-23 05:21:58.363289+07	2026-09-23 05:21:58.574853+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.52391", "profit": "0.30478200", "bet_amt": "0.20000000", "client_seed": "35e34dc4e573e24d6a4b307cb80b9eee", "winning_chance": "37.64"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694287", "payout": "2.52391", "profit": "-0.20000000", "balance": "459970.83019068", "time_taken": 0.027441978454589844, "roll_number": 1006}	0.00000000	0.00000000	2026-09-23 05:21:58.574853+07
7aaf22a5-b1a7-4779-a7a3-44261ef27f28	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.80000000	34.0900	COMPLETED	34019694320	459970.43019068	459969.63019068	-0.80000000	-0.80000000	LOSS	2026-09-23 05:21:58.996429+07	2026-09-23 05:21:58.997832+07	2026-09-23 05:21:59.207949+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.78674", "profit": "1.42939200", "bet_amt": "0.80000000", "client_seed": "59631b2e805ba1bc1c80f237c1e9bf30", "winning_chance": "34.09"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694320", "payout": "2.78674", "profit": "-0.80000000", "balance": "459969.63019068", "time_taken": 0.026379108428955078, "roll_number": 3063}	0.00000000	0.00000000	2026-09-23 05:21:59.207949+07
8bc6f591-9eab-4c0a-a272-f3e00a98acd4	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	3.20000000	36.7300	COMPLETED	34019694346	459968.03019068	459973.10679868	5.07660800	5.07660800	WIN	2026-09-23 05:21:59.634884+07	2026-09-23 05:21:59.636235+07	2026-09-23 05:21:59.846506+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.58644", "profit": "5.07660800", "bet_amt": "3.20000000", "client_seed": "3872d93af667548cb5219a1e9d98046b", "winning_chance": "36.73"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694346", "payout": "2.58644", "profit": "5.07660800", "balance": "459973.10679868", "time_taken": 0.027240991592407227, "roll_number": 7427}	0.00000000	0.00000000	2026-09-23 05:21:59.846506+07
4804aa50-83cd-4c3c-8944-a9c4cc2bd4d5	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	1.60000000	30.3600	COMPLETED	34019694434	459971.60679868	459970.00679868	-1.60000000	-1.60000000	LOSS	2026-09-23 05:22:01.433167+07	2026-09-23 05:22:01.435615+07	2026-09-23 05:22:01.645283+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "3.12911", "profit": "3.40657600", "bet_amt": "1.60000000", "client_seed": "a8a0cbdc73e36728579a6a918333515b", "winning_chance": "30.36"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694434", "payout": "3.12911", "profit": "-1.60000000", "balance": "459970.00679868", "time_taken": 0.02621293067932129, "roll_number": 9310}	0.00000000	0.00000000	2026-09-23 05:22:01.645283+07
8c9ada98-d3e2-4c78-9dda-6bb261bc2e36	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	6.40000000	32.8200	COMPLETED	34019694457	459966.80679868	459960.40679868	-6.40000000	-6.40000000	LOSS	2026-09-23 05:22:02.0795+07	2026-09-23 05:22:02.081377+07	2026-09-23 05:22:02.293165+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.89457", "profit": "12.12524800", "bet_amt": "6.40000000", "client_seed": "e95ef8020ccfa8f67580d616ca34c5ca", "winning_chance": "32.82"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694457", "payout": "2.89457", "profit": "-6.40000000", "balance": "459960.40679868", "time_taken": 0.02818894386291504, "roll_number": 6551}	0.00000000	0.00000000	2026-09-23 05:22:02.293165+07
095a1d6a-451f-4f08-a4b5-44430a1fbcb8	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	25.60000000	31.9400	COMPLETED	34019694493	459947.60679868	459998.14939068	50.54259200	50.54259200	WIN	2026-09-23 05:22:02.7194+07	2026-09-23 05:22:02.721153+07	2026-09-23 05:22:02.931813+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.97432", "profit": "50.54259200", "bet_amt": "25.60000000", "client_seed": "54c4b97d2d9fa8bff4fb97a73004b4d8", "winning_chance": "31.94"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694493", "payout": "2.97432", "profit": "50.54259200", "balance": "459998.14939068", "time_taken": 0.02717304229736328, "roll_number": 7777}	0.00000000	0.00000000	2026-09-23 05:22:02.931813+07
78cb4dce-462b-438f-ab65-ba73bd8680f0	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	38.8100	COMPLETED	34019694403	459972.80679868	459972.40679868	-0.40000000	-0.40000000	LOSS	2026-09-23 05:22:00.791751+07	2026-09-23 05:22:00.793147+07	2026-09-23 05:22:01.003647+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.44782", "profit": "0.57912800", "bet_amt": "0.40000000", "client_seed": "37d863a9fa5c7196cbf6050abede7fbe", "winning_chance": "38.81"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694403", "payout": "2.44782", "profit": "-0.40000000", "balance": "459972.40679868", "time_taken": 0.02687215805053711, "roll_number": 4850}	0.00000000	0.00000000	2026-09-23 05:22:01.003647+07
71be9279-778a-4b58-a284-f7a80649e53f	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.80000000	37.3300	COMPLETED	34019694416	459972.40679868	459971.60679868	-0.80000000	-0.80000000	LOSS	2026-09-23 05:22:01.115775+07	2026-09-23 05:22:01.117819+07	2026-09-23 05:22:01.326759+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.54487", "profit": "1.23589600", "bet_amt": "0.80000000", "client_seed": "ee0178396c4a8d9a71464c1a397e349e", "winning_chance": "37.33"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694416", "payout": "2.54487", "profit": "-0.80000000", "balance": "459971.60679868", "time_taken": 0.02560591697692871, "roll_number": 4777}	0.00000000	0.00000000	2026-09-23 05:22:01.326759+07
1da74e98-6ed3-4118-8aa6-337dfc2af09c	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	3.20000000	32.4700	COMPLETED	34019694445	459970.00679868	459966.80679868	-3.20000000	-3.20000000	LOSS	2026-09-23 05:22:01.760828+07	2026-09-23 05:22:01.762264+07	2026-09-23 05:22:01.972591+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.92577", "profit": "6.16246400", "bet_amt": "3.20000000", "client_seed": "55cea0049c872e4339fb638f0539235a", "winning_chance": "32.47"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694445", "payout": "2.92577", "profit": "-3.20000000", "balance": "459966.80679868", "time_taken": 0.027066946029663086, "roll_number": 7919}	0.00000000	0.00000000	2026-09-23 05:22:01.972591+07
4035e060-ee0c-4cf0-8501-a4fa093cc8a5	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	12.80000000	31.8300	COMPLETED	34019694476	459960.40679868	459947.60679868	-12.80000000	-12.80000000	LOSS	2026-09-23 05:22:02.398982+07	2026-09-23 05:22:02.401363+07	2026-09-23 05:22:02.61287+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.98460", "profit": "25.40288000", "bet_amt": "12.80000000", "client_seed": "b11e94b298289e679c2135e115c9e01e", "winning_chance": "31.83"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694476", "payout": "2.98460", "profit": "-12.80000000", "balance": "459947.60679868", "time_taken": 0.026614904403686523, "roll_number": 7358}	0.00000000	0.00000000	2026-09-23 05:22:02.61287+07
5d4ced2e-40c3-48f1-9b95-05c6e7a34519	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	39.5000	COMPLETED	34019694518	459998.14939068	459998.04939068	-0.10000000	-0.10000000	LOSS	2026-09-23 05:22:03.036921+07	2026-09-23 05:22:03.038584+07	2026-09-23 05:22:03.248231+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.40506", "profit": "0.14050600", "bet_amt": "0.10000000", "client_seed": "85dcefe8b1fd1ada83761b34fcfee8d9", "winning_chance": "39.50"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694518", "payout": "2.40506", "profit": "-0.10000000", "balance": "459998.04939068", "time_taken": 0.025630950927734375, "roll_number": 705}	0.00000000	0.00000000	2026-09-23 05:22:03.248231+07
cb700ab7-2fbc-41bf-9170-7d68ec7aeb9c	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	36.6700	COMPLETED	34019694561	459997.84939068	459998.48565868	0.63626800	0.63626800	WIN	2026-09-23 05:22:03.672025+07	2026-09-23 05:22:03.673578+07	2026-09-23 05:22:03.883512+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.59067", "profit": "0.63626800", "bet_amt": "0.40000000", "client_seed": "d0a658e37a5770cb516dca45334d038f", "winning_chance": "36.67"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694561", "payout": "2.59067", "profit": "0.63626800", "balance": "459998.48565868", "time_taken": 0.026883840560913086, "roll_number": 2538}	0.00000000	0.00000000	2026-09-23 05:22:03.883512+07
4e470ca8-0e96-4413-87fa-48085d8f37c6	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	33.7400	COMPLETED	34019694586	459998.38565868	459998.74878668	0.36312800	0.36312800	WIN	2026-09-23 05:22:04.303665+07	2026-09-23 05:22:04.305355+07	2026-09-23 05:22:04.520675+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.81564", "profit": "0.36312800", "bet_amt": "0.20000000", "client_seed": "9876c2e8eb563915a42eeb0bf0e3e176", "winning_chance": "33.74"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694586", "payout": "2.81564", "profit": "0.36312800", "balance": "459998.74878668", "time_taken": 0.03113412857055664, "roll_number": 8712}	0.00000000	0.00000000	2026-09-23 05:22:04.520675+07
74d9697d-94b6-4836-97d0-fcf2092656b4	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	38.2200	COMPLETED	34019694613	459998.64878668	459998.94590668	0.29712000	0.29712000	WIN	2026-09-23 05:22:04.953053+07	2026-09-23 05:22:04.955253+07	2026-09-23 05:22:05.167491+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.48560", "profit": "0.29712000", "bet_amt": "0.20000000", "client_seed": "36d5a591a92a3193b325d07fd2a6c4cc", "winning_chance": "38.22"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694613", "payout": "2.48560", "profit": "0.29712000", "balance": "459998.94590668", "time_taken": 0.0286409854888916, "roll_number": 8640}	0.00000000	0.00000000	2026-09-23 05:22:05.167491+07
34bffce7-c085-4dea-a82e-74e445947f41	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	32.2700	COMPLETED	34019694649	459999.12368368	459999.02368368	-0.10000000	-0.10000000	LOSS	2026-09-23 05:22:05.594337+07	2026-09-23 05:22:05.596133+07	2026-09-23 05:22:05.80655+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.94391", "profit": "0.19439100", "bet_amt": "0.10000000", "client_seed": "c609bf61896ef1fcb2570ddff3c8cc80", "winning_chance": "32.27"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694649", "payout": "2.94391", "profit": "-0.10000000", "balance": "459999.02368368", "time_taken": 0.026736021041870117, "roll_number": 1885}	0.00000000	0.00000000	2026-09-23 05:22:05.80655+07
c312dc89-a9e8-40e1-9f21-4725ce00af24	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.40000000	34.1300	COMPLETED	34019694681	459998.82368368	459998.42368368	-0.40000000	-0.40000000	LOSS	2026-09-23 05:22:06.231417+07	2026-09-23 05:22:06.233056+07	2026-09-23 05:22:06.444626+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.78347", "profit": "0.71338800", "bet_amt": "0.40000000", "client_seed": "68f2fc48bad64ace3726d6b8c1810a27", "winning_chance": "34.13"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694681", "payout": "2.78347", "profit": "-0.40000000", "balance": "459998.42368368", "time_taken": 0.028079986572265625, "roll_number": 7011}	0.00000000	0.00000000	2026-09-23 05:22:06.444626+07
3438953f-54ad-48dc-a595-61ab300320b9	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	3.20000000	36.9700	COMPLETED	34019694737	459996.02368368	459992.82368368	-3.20000000	-3.20000000	LOSS	2026-09-23 05:22:07.188088+07	2026-09-23 05:22:07.189388+07	2026-09-23 05:22:07.399918+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.56965", "profit": "5.02288000", "bet_amt": "3.20000000", "client_seed": "d3c29c936db21951b432565a95942164", "winning_chance": "36.97"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694737", "payout": "2.56965", "profit": "-3.20000000", "balance": "459992.82368368", "time_taken": 0.026401042938232422, "roll_number": 3137}	0.00000000	0.00000000	2026-09-23 05:22:07.399918+07
48646632-52c6-4bcc-9979-83112ac9b993	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	30.4800	COMPLETED	34019694538	459998.04939068	459997.84939068	-0.20000000	-0.20000000	LOSS	2026-09-23 05:22:03.356033+07	2026-09-23 05:22:03.359533+07	2026-09-23 05:22:03.566042+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.11679", "profit": "0.42335800", "bet_amt": "0.20000000", "client_seed": "ef240be0a62ff087c5a675739e892caf", "winning_chance": "30.48"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694538", "payout": "3.11679", "profit": "-0.20000000", "balance": "459997.84939068", "time_taken": 0.023028135299682617, "roll_number": 4094}	0.00000000	0.00000000	2026-09-23 05:22:03.566042+07
10ec364b-df73-4d35-9f5b-1986da76a920	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	34.1500	COMPLETED	34019694574	459998.48565868	459998.38565868	-0.10000000	-0.10000000	LOSS	2026-09-23 05:22:03.989121+07	2026-09-23 05:22:03.990449+07	2026-09-23 05:22:04.199205+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.78184", "profit": "0.17818400", "bet_amt": "0.10000000", "client_seed": "0350ed9dadd30a951e26777a7c066f79", "winning_chance": "34.15"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694574", "payout": "2.78184", "profit": "-0.10000000", "balance": "459998.38565868", "time_taken": 0.025990009307861328, "roll_number": 6279}	0.00000000	0.00000000	2026-09-23 05:22:04.199205+07
4275d207-edb6-4c15-979e-c7101345a312	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	30.0900	COMPLETED	34019694602	459998.74878668	459998.64878668	-0.10000000	-0.10000000	LOSS	2026-09-23 05:22:04.629806+07	2026-09-23 05:22:04.631311+07	2026-09-23 05:22:04.843062+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.15719", "profit": "0.21571900", "bet_amt": "0.10000000", "client_seed": "85aa3a4b386bd90fd563cf322c3228d0", "winning_chance": "30.09"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694602", "payout": "3.15719", "profit": "-0.10000000", "balance": "459998.64878668", "time_taken": 0.027779102325439453, "roll_number": 6746}	0.00000000	0.00000000	2026-09-23 05:22:04.843062+07
9eff1a5c-e5b2-4418-841d-d76df2947bb9	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	34.2000	COMPLETED	34019694627	459998.94590668	459999.12368368	0.17777700	0.17777700	WIN	2026-09-23 05:22:05.273923+07	2026-09-23 05:22:05.276272+07	2026-09-23 05:22:05.488314+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.77777", "profit": "0.17777700", "bet_amt": "0.10000000", "client_seed": "13ec6382d6fd51ef05fdb1ac5643dee9", "winning_chance": "34.20"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694627", "payout": "2.77777", "profit": "0.17777700", "balance": "459999.12368368", "time_taken": 0.02757096290588379, "roll_number": 7440}	0.00000000	0.00000000	2026-09-23 05:22:05.488314+07
6bd0d300-cc2c-4fec-9937-f1058ba3f24c	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	39.2200	COMPLETED	34019694665	459999.02368368	459998.82368368	-0.20000000	-0.20000000	LOSS	2026-09-23 05:22:05.912473+07	2026-09-23 05:22:05.914547+07	2026-09-23 05:22:06.124259+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.42223", "profit": "0.28444600", "bet_amt": "0.20000000", "client_seed": "6af56f6a09ab31276e8e58026a0fb519", "winning_chance": "39.22"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694665", "payout": "2.42223", "profit": "-0.20000000", "balance": "459998.82368368", "time_taken": 0.026314973831176758, "roll_number": 4675}	0.00000000	0.00000000	2026-09-23 05:22:06.124259+07
9fe1b405-05ba-4782-b00e-37d4ac9f899e	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.80000000	36.7400	COMPLETED	34019694704	459998.42368368	459997.62368368	-0.80000000	-0.80000000	LOSS	2026-09-23 05:22:06.552448+07	2026-09-23 05:22:06.554454+07	2026-09-23 05:22:06.764129+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.58573", "profit": "1.26858400", "bet_amt": "0.80000000", "client_seed": "d713fb999e2f63665c2de1c4ad801f01", "winning_chance": "36.74"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694704", "payout": "2.58573", "profit": "-0.80000000", "balance": "459997.62368368", "time_taken": 0.02636098861694336, "roll_number": 4994}	0.00000000	0.00000000	2026-09-23 05:22:06.764129+07
d3b247c1-96ad-4837-a40b-0a8cf9d7e05e	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	1.60000000	35.0200	COMPLETED	34019694719	459997.62368368	459996.02368368	-1.60000000	-1.60000000	LOSS	2026-09-23 05:22:06.871192+07	2026-09-23 05:22:06.872962+07	2026-09-23 05:22:07.082919+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.71273", "profit": "2.74036800", "bet_amt": "1.60000000", "client_seed": "3a9fb7530d6160e836997fa88e4420d0", "winning_chance": "35.02"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694719", "payout": "2.71273", "profit": "-1.60000000", "balance": "459996.02368368", "time_taken": 0.02708292007446289, "roll_number": 911}	0.00000000	0.00000000	2026-09-23 05:22:07.082919+07
bbd00383-654b-47d8-ae05-06664b4e6b94	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	6.40000000	30.0200	COMPLETED	34019694747	459992.82368368	459986.42368368	-6.40000000	-6.40000000	LOSS	2026-09-23 05:22:07.507246+07	2026-09-23 05:22:07.508824+07	2026-09-23 05:22:07.719288+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "3.16455", "profit": "13.85312000", "bet_amt": "6.40000000", "client_seed": "0becd49ed911e356132d00cb05c4a902", "winning_chance": "30.02"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694747", "payout": "3.16455", "profit": "-6.40000000", "balance": "459986.42368368", "time_taken": 0.02735590934753418, "roll_number": 2198}	0.00000000	0.00000000	2026-09-23 05:22:07.719288+07
9cbeca02-d020-40c9-9075-215e6289e279	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	33.1600	COMPLETED	34019694771	460011.52883568	460011.71532468	0.18648900	0.18648900	WIN	2026-09-23 05:22:08.143559+07	2026-09-23 05:22:08.144947+07	2026-09-23 05:22:08.356903+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.86489", "profit": "0.18648900", "bet_amt": "0.10000000", "client_seed": "49a3d0779eca1a877f0124cea9c516b0", "winning_chance": "33.16"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694771", "payout": "2.86489", "profit": "0.18648900", "balance": "460011.71532468", "time_taken": 0.028090953826904297, "roll_number": 7463}	0.00000000	0.00000000	2026-09-23 05:22:08.356903+07
338b6d8d-9c44-4d9e-9b6e-688990f43620	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.20000000	38.9200	COMPLETED	34019694811	460011.61532468	460011.90350468	0.28818000	0.28818000	WIN	2026-09-23 05:22:08.781929+07	2026-09-23 05:22:08.783308+07	2026-09-23 05:22:08.994551+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.44090", "profit": "0.28818000", "bet_amt": "0.20000000", "client_seed": "89a5e45c6d6bc491b04030b4e03b23ef", "winning_chance": "38.92"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694811", "payout": "2.44090", "profit": "0.28818000", "balance": "460011.90350468", "time_taken": 0.028506994247436523, "roll_number": 6638}	0.00000000	0.00000000	2026-09-23 05:22:08.994551+07
c71f3fb1-d952-42b3-8fa3-2ecab8343404	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	12.80000000	32.0800	COMPLETED	34019694760	459986.42368368	460011.52883568	25.10515200	25.10515200	WIN	2026-09-23 05:22:07.824046+07	2026-09-23 05:22:07.825564+07	2026-09-23 05:22:08.03785+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.96134", "profit": "25.10515200", "bet_amt": "12.80000000", "client_seed": "a1b109377376733ea14defeb6c9366e2", "winning_chance": "32.08"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694760", "payout": "2.96134", "profit": "25.10515200", "balance": "460011.52883568", "time_taken": 0.028617143630981445, "roll_number": 1995}	0.00000000	0.00000000	2026-09-23 05:22:08.03785+07
4a9c9276-764c-443f-b616-de70051c31c5	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.10000000	38.5600	COMPLETED	34019694787	460011.71532468	460011.61532468	-0.10000000	-0.10000000	LOSS	2026-09-23 05:22:08.462381+07	2026-09-23 05:22:08.465132+07	2026-09-23 05:22:08.676124+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.46369", "profit": "0.14636900", "bet_amt": "0.10000000", "client_seed": "f0c5fc0a26ef698437f3d21bc40ea48e", "winning_chance": "38.56"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019694787", "payout": "2.46369", "profit": "-0.10000000", "balance": "460011.61532468", "time_taken": 0.026880979537963867, "roll_number": 4536}	0.00000000	0.00000000	2026-09-23 05:22:08.676124+07
\.


--
-- Data for Name: referral_bonus_balances; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.referral_bonus_balances (user_id, coin, available_amount, claimed_amount, updated_at) FROM stdin;
859	BTT	0.00000000	0.00000000	2026-09-23 10:17:21.778238+07
859	DOGE	0.00000000	0.00000000	2026-09-23 10:17:22.075827+07
859	FLOKI	0.00000000	0.00000000	2026-09-23 10:17:22.378635+07
859	TRX	0.00000000	0.00000000	2026-09-23 10:17:22.68471+07
1087	BTT	0.00000000	0.00000000	2026-09-23 10:17:23.001062+07
1087	FLOKI	0.00000000	0.00000000	2026-09-23 10:17:23.305454+07
973	BTT	0.00000000	0.00000000	2026-09-23 10:17:23.618606+07
973	FLOKI	0.00000000	0.00000000	2026-09-23 10:17:23.923077+07
971	BTT	0.00000000	0.00000000	2026-09-23 10:17:24.21814+07
971	DOGE	0.00000000	0.00000000	2026-09-23 10:17:24.517195+07
971	FLOKI	0.00000000	0.00000000	2026-09-23 10:17:24.816347+07
863	BTT	0.00000000	0.00000000	2026-09-23 10:17:25.119474+07
863	TRX	0.00000000	0.00000000	2026-09-23 10:17:25.414266+07
1013	FLOKI	0.00000000	0.00000000	2026-09-23 10:17:25.715189+07
981	BTT	0.00000000	0.00000000	2026-09-23 10:17:26.01866+07
981	FLOKI	0.00000000	0.00000000	2026-09-23 10:17:26.324601+07
947	BTT	0.00000000	0.00000000	2026-09-23 10:17:26.627215+07
751	BTT	0.00000000	0.00000000	2026-09-23 10:17:26.928615+07
751	DOGE	0.00000000	0.00000000	2026-09-23 10:17:27.429768+07
751	FLOKI	0.00000000	0.00000000	2026-09-23 10:17:27.73322+07
751	TRX	0.00000000	0.00000000	2026-09-23 10:17:28.037904+07
745	BTT	0.00000000	0.00000000	2026-09-23 10:17:28.337348+07
745	FLOKI	0.00000000	0.00000000	2026-09-23 10:17:28.642306+07
745	TRX	0.00000000	0.00000000	2026-09-23 10:17:28.945208+07
987	DOGE	0.00000000	0.00000000	2026-09-23 10:17:29.245226+07
797	BTT	0.00000000	0.00000000	2026-09-23 10:17:13.678493+07
797	FLOKI	0.00000000	0.00000000	2026-09-23 10:17:14.010731+07
797	TRX	0.00000000	0.00000000	2026-09-23 10:17:14.316022+07
925	BTT	0.00000000	0.00000000	2026-09-23 10:17:14.611232+07
925	DOGE	0.00000000	0.00000000	2026-09-23 10:17:14.917647+07
925	FLOKI	0.00000000	0.00000000	2026-09-23 10:17:15.437221+07
983	BTT	0.00000000	0.00000000	2026-09-23 10:17:15.737243+07
983	DOGE	0.00000000	0.00000000	2026-09-23 10:17:16.0371+07
983	FLOKI	0.00000000	0.00000000	2026-09-23 10:17:16.33652+07
929	DOGE	0.00000000	0.00000000	2026-09-23 10:17:16.634835+07
929	FLOKI	0.00000000	0.00000000	2026-09-23 10:17:16.934245+07
931	BTT	0.00000000	0.00000000	2026-09-23 10:17:17.236961+07
931	FLOKI	0.00000000	0.00000000	2026-09-23 10:17:17.542132+07
959	BTT	0.00000000	0.00000000	2026-09-23 10:17:17.845508+07
959	FLOKI	0.00000000	0.00000000	2026-09-23 10:17:18.146242+07
933	BTT	0.00000000	0.00000000	2026-09-23 10:17:18.450708+07
793	BTT	0.00000000	0.00000000	2026-09-23 10:17:18.753784+07
979	BTT	0.00000000	0.00000000	2026-09-23 10:17:19.055515+07
979	DOGE	0.00000000	0.00000000	2026-09-23 10:17:19.365922+07
979	FLOKI	0.00000000	0.00000000	2026-09-23 10:17:19.667237+07
993	BTT	0.00000000	0.00000000	2026-09-23 10:17:19.96989+07
993	DOGE	0.00000000	0.00000000	2026-09-23 10:17:20.274074+07
993	FLOKI	0.00000000	0.00000000	2026-09-23 10:17:20.573509+07
749	BTT	0.00000000	0.00000000	2026-09-23 10:17:20.873561+07
749	FLOKI	0.00000000	0.00000000	2026-09-23 10:17:21.175438+07
749	TRX	0.00000000	0.00000000	2026-09-23 10:17:21.473788+07
\.


--
-- Data for Name: referral_bonus_events; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.referral_bonus_events (id, user_id, coin, amount, event_type, source_external_id, occurred_at, created_at) FROM stdin;
81400aef-7792-454e-8083-14b45febd2e2	745	BTT	0.00311790	TRADING_ACCRUAL	provider-bet:6e58f47b-3438-4474-ac5e-f9f9daf307f5:referral:1	2026-09-23 04:52:55.259075+07	2026-09-23 04:52:55.259075+07
89d4d1ec-99a8-4563-9839-089d7de74e69	749	BTT	0.00155895	TRADING_ACCRUAL	provider-bet:6e58f47b-3438-4474-ac5e-f9f9daf307f5:referral:2	2026-09-23 04:52:55.259075+07	2026-09-23 04:52:55.259075+07
63392d59-c114-4229-925c-75c0a1689bf7	745	BTT	9.46216960	TRADING_ACCRUAL	provider-bet:cfbd6ae8-f00b-4bbd-8fbe-6c9ebb131d9a:referral:1	2026-09-23 04:53:11.258295+07	2026-09-23 04:53:11.258295+07
fb6813c3-8944-4100-89a1-847917fcc808	749	BTT	4.73108480	TRADING_ACCRUAL	provider-bet:cfbd6ae8-f00b-4bbd-8fbe-6c9ebb131d9a:referral:2	2026-09-23 04:53:11.258295+07	2026-09-23 04:53:11.258295+07
3f4be206-d76a-4081-9714-7ac5d9348650	745	BTT	0.03759648	TRADING_ACCRUAL	provider-bet:46817c3b-cecd-4e5d-8e80-3112ae1137d8:referral:1	2026-09-23 04:53:17.258179+07	2026-09-23 04:53:17.258179+07
c7f4ebb6-f6fe-47ef-82b2-87b0e3f818b0	749	BTT	0.01879824	TRADING_ACCRUAL	provider-bet:46817c3b-cecd-4e5d-8e80-3112ae1137d8:referral:2	2026-09-23 04:53:17.258179+07	2026-09-23 04:53:17.258179+07
80918c9d-4e0c-4058-8a2e-71d18063b616	745	BTT	0.22901184	TRADING_ACCRUAL	provider-bet:b8b36047-e4dd-49a2-9843-9d7d302e3a94:referral:1	2026-09-23 04:53:25.58513+07	2026-09-23 04:53:25.58513+07
0c0171ff-f0af-4d94-a898-ea67e6e10cc0	749	BTT	0.11450592	TRADING_ACCRUAL	provider-bet:b8b36047-e4dd-49a2-9843-9d7d302e3a94:referral:2	2026-09-23 04:53:25.58513+07	2026-09-23 04:53:25.58513+07
1a434b2f-0f1f-42e4-af36-ce6152bc0d52	797	BTT	-12993963.46252133	CLAIM_REVERSAL	admin:bonus-move:749:797:BTT	2026-09-23 10:17:13.678493+07	2026-09-23 10:17:13.678493+07
ec7e7259-e933-4064-b73c-bd51e30236dd	797	FLOKI	-25666.20052016	CLAIM_REVERSAL	admin:bonus-move:749:797:FLOKI	2026-09-23 10:17:14.010731+07	2026-09-23 10:17:14.010731+07
c99e5620-5563-4efd-9b37-6f112d2f65f8	797	TRX	-0.00336185	CLAIM_REVERSAL	admin:bonus-move:749:797:TRX	2026-09-23 10:17:14.316022+07	2026-09-23 10:17:14.316022+07
fe79e1c1-4d64-496d-b7ec-40d17017121e	925	BTT	-0.05333328	CLAIM_REVERSAL	admin:bonus-move:749:925:BTT	2026-09-23 10:17:14.611232+07	2026-09-23 10:17:14.611232+07
96ef8eb0-bdca-42bb-bff5-907c14eb9512	925	DOGE	-0.00006772	CLAIM_REVERSAL	admin:bonus-move:749:925:DOGE	2026-09-23 10:17:14.917647+07	2026-09-23 10:17:14.917647+07
cc6203c6-401b-45ed-9dce-79075a48841a	925	FLOKI	-184.45059589	CLAIM_REVERSAL	admin:bonus-move:749:925:FLOKI	2026-09-23 10:17:15.437221+07	2026-09-23 10:17:15.437221+07
02852570-84d5-4ce4-920f-e9a984815ccf	983	BTT	-23352.42137014	CLAIM_REVERSAL	admin:bonus-move:749:983:BTT	2026-09-23 10:17:15.737243+07	2026-09-23 10:17:15.737243+07
122d55fe-cf55-4e38-a054-04d5503770c8	983	DOGE	-0.00001196	CLAIM_REVERSAL	admin:bonus-move:749:983:DOGE	2026-09-23 10:17:16.0371+07	2026-09-23 10:17:16.0371+07
48c35294-4be4-4813-a96e-04db2d99953c	983	FLOKI	-0.18613803	CLAIM_REVERSAL	admin:bonus-move:749:983:FLOKI	2026-09-23 10:17:16.33652+07	2026-09-23 10:17:16.33652+07
e3cf0adb-e324-4ca5-b7bd-46ef2ab7bf67	929	DOGE	-0.15675017	CLAIM_REVERSAL	admin:bonus-move:749:929:DOGE	2026-09-23 10:17:16.634835+07	2026-09-23 10:17:16.634835+07
e00ded7a-ad66-4f65-8db9-f9a0d0d13d06	929	FLOKI	-1453.60536265	CLAIM_REVERSAL	admin:bonus-move:749:929:FLOKI	2026-09-23 10:17:16.934245+07	2026-09-23 10:17:16.934245+07
c6120d4f-4e97-477d-9c75-4ecd37a137b2	931	BTT	-6.38252191	CLAIM_REVERSAL	admin:bonus-move:749:931:BTT	2026-09-23 10:17:17.236961+07	2026-09-23 10:17:17.236961+07
d04be5d8-2254-40f2-b252-af6552719911	931	FLOKI	-36.23659814	CLAIM_REVERSAL	admin:bonus-move:749:931:FLOKI	2026-09-23 10:17:17.542132+07	2026-09-23 10:17:17.542132+07
555450a8-883e-46d7-95b5-1abc54c73faf	959	BTT	-521155.92578909	CLAIM_REVERSAL	admin:bonus-move:749:959:BTT	2026-09-23 10:17:17.845508+07	2026-09-23 10:17:17.845508+07
1912b8fc-31ec-4672-b0d8-d41e25e729c8	959	FLOKI	-461.12649650	CLAIM_REVERSAL	admin:bonus-move:749:959:FLOKI	2026-09-23 10:17:18.146242+07	2026-09-23 10:17:18.146242+07
cf698746-ec49-45e8-8190-ad729b5cfd37	933	BTT	-1055222.03174734	CLAIM_REVERSAL	admin:bonus-move:749:933:BTT	2026-09-23 10:17:18.450708+07	2026-09-23 10:17:18.450708+07
a62e97c1-5e5b-4881-af0c-5fc1484824d8	793	BTT	-437382.37277524	CLAIM_REVERSAL	admin:bonus-move:749:793:BTT	2026-09-23 10:17:18.753784+07	2026-09-23 10:17:18.753784+07
cd7b4738-d23a-4a6e-93d8-c4821c706b4c	979	BTT	-15585.18640737	CLAIM_REVERSAL	admin:bonus-move:749:979:BTT	2026-09-23 10:17:19.055515+07	2026-09-23 10:17:19.055515+07
26de8e8d-4d20-4ec3-bce9-7462bdd61d92	979	DOGE	-0.00000714	CLAIM_REVERSAL	admin:bonus-move:749:979:DOGE	2026-09-23 10:17:19.365922+07	2026-09-23 10:17:19.365922+07
32de8536-7007-4294-bcf9-b85d38044ef5	979	FLOKI	-0.18613803	CLAIM_REVERSAL	admin:bonus-move:749:979:FLOKI	2026-09-23 10:17:19.667237+07	2026-09-23 10:17:19.667237+07
e9b98406-de2a-44a0-a830-35791a91b33f	993	BTT	-38937.60778540	CLAIM_REVERSAL	admin:bonus-move:749:993:BTT	2026-09-23 10:17:19.96989+07	2026-09-23 10:17:19.96989+07
92820ff9-1f86-47df-8e9d-3ce66c50dbf4	993	DOGE	-3.00127633	CLAIM_REVERSAL	admin:bonus-move:749:993:DOGE	2026-09-23 10:17:20.274074+07	2026-09-23 10:17:20.274074+07
ed6f1a52-fdbd-45af-8f14-16f93ea7cceb	993	FLOKI	-6518.42044508	CLAIM_REVERSAL	admin:bonus-move:749:993:FLOKI	2026-09-23 10:17:20.573509+07	2026-09-23 10:17:20.573509+07
896bc5ca-80fa-4240-aa2d-7267415e0b06	749	BTT	-81960.11323597	CLAIM_REVERSAL	admin:bonus-move:749:749:BTT	2026-09-23 10:17:20.873561+07	2026-09-23 10:17:20.873561+07
01082e00-81e9-4f2a-9ee4-162c1c6c020a	749	FLOKI	-346.59073643	CLAIM_REVERSAL	admin:bonus-move:749:749:FLOKI	2026-09-23 10:17:21.175438+07	2026-09-23 10:17:21.175438+07
c8526d67-30cc-4c2f-b4e4-e1f16262f241	749	TRX	-0.00000261	CLAIM_REVERSAL	admin:bonus-move:749:749:TRX	2026-09-23 10:17:21.473788+07	2026-09-23 10:17:21.473788+07
edfd2e9c-055f-4c9b-a1e8-9b129dbe3011	859	BTT	-3852.07771635	CLAIM_REVERSAL	admin:bonus-move:749:859:BTT	2026-09-23 10:17:21.778238+07	2026-09-23 10:17:21.778238+07
6e1c6507-f947-4b12-9749-1d9661117703	859	DOGE	-18.05189629	CLAIM_REVERSAL	admin:bonus-move:749:859:DOGE	2026-09-23 10:17:22.075827+07	2026-09-23 10:17:22.075827+07
b54ab9a2-0e47-4524-b11c-e5f6d434184f	859	FLOKI	-7180.60537448	CLAIM_REVERSAL	admin:bonus-move:749:859:FLOKI	2026-09-23 10:17:22.378635+07	2026-09-23 10:17:22.378635+07
69f7836b-5bd3-4478-9daf-da38a92b9991	859	TRX	-0.78142510	CLAIM_REVERSAL	admin:bonus-move:749:859:TRX	2026-09-23 10:17:22.68471+07	2026-09-23 10:17:22.68471+07
e364e26a-39f6-4f07-a12d-a6183e1ac777	1087	BTT	-232797.64687616	CLAIM_REVERSAL	admin:bonus-move:749:1087:BTT	2026-09-23 10:17:23.001062+07	2026-09-23 10:17:23.001062+07
ae69423f-9b35-4b73-82ca-d127fb75e3a3	1087	FLOKI	-2503.21189389	CLAIM_REVERSAL	admin:bonus-move:749:1087:FLOKI	2026-09-23 10:17:23.305454+07	2026-09-23 10:17:23.305454+07
606acf42-7def-48d3-9134-8e3fafc47253	973	BTT	-3217.05840034	CLAIM_REVERSAL	admin:bonus-move:749:973:BTT	2026-09-23 10:17:23.618606+07	2026-09-23 10:17:23.618606+07
5281fac9-1faf-4163-a0e0-20b2b1c4b408	973	FLOKI	-2003.48759385	CLAIM_REVERSAL	admin:bonus-move:749:973:FLOKI	2026-09-23 10:17:23.923077+07	2026-09-23 10:17:23.923077+07
da9ae2db-a00a-421d-accd-87c0b6d5341d	971	BTT	-275437.67764884	CLAIM_REVERSAL	admin:bonus-move:749:971:BTT	2026-09-23 10:17:24.21814+07	2026-09-23 10:17:24.21814+07
e33fb956-4964-42a4-b92d-eec700810320	971	DOGE	-12.60314509	CLAIM_REVERSAL	admin:bonus-move:749:971:DOGE	2026-09-23 10:17:24.517195+07	2026-09-23 10:17:24.517195+07
59f7ddad-fb70-4ce5-8c6f-581024077afd	971	FLOKI	-4449.63450583	CLAIM_REVERSAL	admin:bonus-move:749:971:FLOKI	2026-09-23 10:17:24.816347+07	2026-09-23 10:17:24.816347+07
61ec2b2a-17fc-45c0-8ebd-a833755c4f43	863	BTT	-500925.66822683	CLAIM_REVERSAL	admin:bonus-move:749:863:BTT	2026-09-23 10:17:25.119474+07	2026-09-23 10:17:25.119474+07
74694e4d-e4cc-48f8-9dac-3d190dbb9d03	863	TRX	-0.02199383	CLAIM_REVERSAL	admin:bonus-move:749:863:TRX	2026-09-23 10:17:25.414266+07	2026-09-23 10:17:25.414266+07
ff367a4d-473c-4c3d-a619-bd99d91c06e2	1013	FLOKI	-2213.31405208	CLAIM_REVERSAL	admin:bonus-move:749:1013:FLOKI	2026-09-23 10:17:25.715189+07	2026-09-23 10:17:25.715189+07
740eabb7-4fea-4fb2-9fde-831da046954b	981	BTT	-24868.92147813	CLAIM_REVERSAL	admin:bonus-move:749:981:BTT	2026-09-23 10:17:26.01866+07	2026-09-23 10:17:26.01866+07
3bceef0e-dfb5-4388-92d9-be848f73a2ef	981	FLOKI	-142024.71310536	CLAIM_REVERSAL	admin:bonus-move:749:981:FLOKI	2026-09-23 10:17:26.324601+07	2026-09-23 10:17:26.324601+07
02f32691-e48b-4b68-b718-38060236e7ab	947	BTT	-110.02988979	CLAIM_REVERSAL	admin:bonus-move:749:947:BTT	2026-09-23 10:17:26.627215+07	2026-09-23 10:17:26.627215+07
5d660278-3221-4ebf-ba49-913cbd4aa012	751	BTT	-97945.04349517	CLAIM_REVERSAL	admin:bonus-move:749:751:BTT	2026-09-23 10:17:26.928615+07	2026-09-23 10:17:26.928615+07
97ff7beb-3c7a-4f1e-a352-299021fecd19	751	DOGE	-0.00713606	CLAIM_REVERSAL	admin:bonus-move:749:751:DOGE	2026-09-23 10:17:27.429768+07	2026-09-23 10:17:27.429768+07
23f7e546-b9cf-4b06-ae14-6b045f3e34b9	751	FLOKI	-1923.11231095	CLAIM_REVERSAL	admin:bonus-move:749:751:FLOKI	2026-09-23 10:17:27.73322+07	2026-09-23 10:17:27.73322+07
0ff15094-aaf6-4356-9bd9-563f6b34a003	751	TRX	-0.45546349	CLAIM_REVERSAL	admin:bonus-move:749:751:TRX	2026-09-23 10:17:28.037904+07	2026-09-23 10:17:28.037904+07
9e5f08a0-f996-476c-aa82-78caedd67b0d	745	BTT	-13.38260846	CLAIM_REVERSAL	admin:bonus-move:749:745:BTT	2026-09-23 10:17:28.337348+07	2026-09-23 10:17:28.337348+07
fbbfd91d-8d2d-4b9d-b632-f57927a1163c	745	FLOKI	-0.00394282	CLAIM_REVERSAL	admin:bonus-move:749:745:FLOKI	2026-09-23 10:17:28.642306+07	2026-09-23 10:17:28.642306+07
3a435d6e-d44b-4cd1-a4d4-38c26c4e7bb8	745	TRX	-0.06596064	CLAIM_REVERSAL	admin:bonus-move:749:745:TRX	2026-09-23 10:17:28.945208+07	2026-09-23 10:17:28.945208+07
de9554b9-4982-4969-8d67-a0c317a76831	987	DOGE	-0.00257599	CLAIM_REVERSAL	admin:bonus-move:749:987:DOGE	2026-09-23 10:17:29.245226+07	2026-09-23 10:17:29.245226+07
\.


--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.schema_migrations (name, applied_at) FROM stdin;
001_admin_business_rules.sql	2026-09-19 23:05:15.082777+07
002_direct_business_rule_save.sql	2026-09-19 23:36:34.833287+07
003_dynamic_settings.sql	2026-09-19 23:36:34.855289+07
004_user_bot_foundation.sql	2026-09-20 02:59:28.637535+07
005_import_users_and_bonus_only.sql	2026-09-20 02:59:28.85801+07
006_import_pasino_credentials.sql	2026-09-20 02:59:28.89185+07
007_import_legacy_trading_settings.sql	2026-09-20 03:13:05.917193+07
008_user_referrals_and_trial.sql	2026-09-20 09:35:04.625126+07
009_trading_settlement_ledger.sql	2026-09-20 09:35:04.813217+07
010_trading_session_state.sql	2026-09-20 09:35:04.816889+07
011_wallet_operations.sql	2026-09-20 14:45:56.912244+07
012_wallet_remove_processing_lock.sql	2026-09-20 15:16:16.083031+07
013_trading_fee_obligations.sql	2026-09-20 20:22:58.250044+07
014_realtime_trading_commands.sql	2026-09-20 20:22:58.426708+07
015_compact_financial_retention.sql	2026-09-20 20:22:58.549903+07
016_trading_setting_defaults.sql	2026-09-20 20:22:58.580272+07
017_trading_next_command.sql	2026-09-20 20:22:58.585431+07
018_trading_event_notification_id.sql	2026-09-20 22:58:19.1395+07
019_trading_worker_lease.sql	2026-09-20 22:58:19.15712+07
020_close_preproduction_reconciliation.sql	2026-09-21 01:37:16.900289+07
021_trading_streak_counters.sql	2026-09-21 01:42:47.839673+07
022_dynamic_business_accounts.sql	2026-09-21 04:05:20.220716+07
023_management_payouts.sql	2026-09-21 04:16:36.205024+07
024_admin_user_actions.sql	2026-09-21 04:29:25.226592+07
025_user_activity.sql	2026-09-21 10:27:06.191788+07
026_integer_trading_controls.sql	2026-09-21 11:07:24.360612+07
027_provider_bets_cascade.sql	2026-09-23 02:38:53.564796+07
028_delay_ms_min_100.sql	2026-09-23 04:58:56.295595+07
\.


--
-- Data for Name: trading_commands; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.trading_commands (id, request_id, user_id, session_id, command, payload, status, failure_reason, created_at, processed_at, updated_at, worker_id) FROM stdin;
c0d5cf54-1028-43ca-b518-1907c5ba9df6	237aa204-ae2a-4aa1-bdff-a5f2e1569c9f	747	\N	START	{"enabled": false}	COMPLETED	\N	2026-09-23 04:52:53.857908+07	2026-09-23 04:52:54.242312+07	2026-09-23 04:52:54.242312+07	KangDen-24236
c1d7017a-4321-471e-bf95-1f08c6c1a67a	f38276ca-332e-407c-bd6f-981e91a5a0de	747	\N	STOP_ON_WIN	{"amount": "", "enabled": true}	COMPLETED	\N	2026-09-23 04:53:24.766323+07	2026-09-23 04:53:25.030959+07	2026-09-23 04:53:25.030959+07	KangDen-24236
16350d03-c6c7-4608-9b89-7d3efebfc62a	152e87ab-e0b2-443b-a40d-c3af59f4b6c7	749	\N	START	{"enabled": false}	FAILED	minimum base trade 0.1 BTT	2026-09-23 05:05:08.703673+07	2026-09-23 05:05:08.835973+07	2026-09-23 05:05:08.835973+07	KangDen-9340
d1b43d8b-601b-4d6c-bce7-9d5697f1244e	e04acebb-00f0-4332-bd85-2ecbc98e7a89	749	\N	START	{"enabled": false}	FAILED	minimum base trade 0.1 BTT	2026-09-23 05:05:20.282334+07	2026-09-23 05:05:20.336051+07	2026-09-23 05:05:20.336051+07	KangDen-9340
0b527e62-90f9-4727-941b-3c900b364ea6	799ca142-9360-4db4-9be0-9aa216af6fdb	749	\N	START	{"enabled": false}	COMPLETED	\N	2026-09-23 05:05:35.443368+07	2026-09-23 05:05:35.866857+07	2026-09-23 05:05:35.866857+07	KangDen-9340
a36519c0-a26c-4f95-b608-6cef25fec667	d599d267-abcb-426a-8150-1ed4c1ba6147	749	\N	STOP_ON_WIN	{"amount": "", "enabled": true}	COMPLETED	\N	2026-09-23 05:05:41.513875+07	2026-09-23 05:05:41.833761+07	2026-09-23 05:05:41.833761+07	KangDen-9340
835a2877-0ba2-4c78-90d5-65a314a37a17	0a410471-84ed-4593-8c65-6b641eb67cbd	749	\N	START	{"enabled": false}	COMPLETED	\N	2026-09-23 05:21:12.84072+07	2026-09-23 05:21:13.483328+07	2026-09-23 05:21:13.483328+07	KangDen-18240
d3e401fb-1c37-4a2d-8b74-cff03f890d32	583bdf41-ae95-428d-a832-d08466e06e39	749	\N	STOP_ON_WIN	{"amount": "", "enabled": true}	COMPLETED	\N	2026-09-23 05:22:08.475913+07	2026-09-23 05:22:08.773716+07	2026-09-23 05:22:08.773716+07	KangDen-18240
\.


--
-- Data for Name: trading_events; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.trading_events (id, user_id, session_id, event_type, payload, created_at) FROM stdin;
637	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	RUNNER_STATE	{"status": "RUNNING", "message": "Trading dimulai"}	2026-09-23 04:52:54.229044+07
638	747	\N	COMMAND_RESULT	{"ok": true, "command": "START", "message": "", "request_id": "237aa204-ae2a-4aa1-bdff-a5f2e1569c9f"}	2026-09-23 04:52:54.243799+07
639	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.1", "bet_id": "6e58f47b-3438-4474-ac5e-f9f9daf307f5", "losses": 0, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.2681394", "gross_profit": "0.31179", "balance_after": "24788451.64302697", "session_profit": "0.26813940"}	2026-09-23 04:52:54.716633+07
640	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.1", "bet_id": "1af8cefe-a9dc-417c-a9c4-b9be608f4882", "losses": 1, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "24788451.54302697", "session_profit": "0.16813940"}	2026-09-23 04:52:55.955122+07
641	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.2", "bet_id": "0b221394-e336-4446-a715-35bea44fe845", "losses": 2, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "24788451.34302697", "session_profit": "-0.03186060"}	2026-09-23 04:52:57.174735+07
642	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.4", "bet_id": "de7bdaeb-7f0a-42db-b6a8-d228310f25e8", "losses": 3, "result": "LOSS", "streak": 3, "last_result": "LOSS", "user_profit": "-0.4", "gross_profit": "-0.4", "balance_after": "24788450.94302697", "session_profit": "-0.43186060"}	2026-09-23 04:52:58.392448+07
643	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.8", "bet_id": "483a57f6-7451-4551-b119-3515eb0fd80f", "losses": 4, "result": "LOSS", "streak": 4, "last_result": "LOSS", "user_profit": "-0.8", "gross_profit": "-0.8", "balance_after": "24788450.14302697", "session_profit": "-1.23186060"}	2026-09-23 04:52:59.610111+07
644	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "1.6", "bet_id": "a04c3985-0c9a-4e0b-99e1-572b8a5ff312", "losses": 5, "result": "LOSS", "streak": 5, "last_result": "LOSS", "user_profit": "-1.6", "gross_profit": "-1.6", "balance_after": "24788448.54302697", "session_profit": "-2.83186060"}	2026-09-23 04:53:00.824553+07
645	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "3.2", "bet_id": "0ba8c576-bd5e-40d3-a4c0-edd6e2f97374", "losses": 6, "result": "LOSS", "streak": 6, "last_result": "LOSS", "user_profit": "-3.2", "gross_profit": "-3.2", "balance_after": "24788445.34302697", "session_profit": "-6.03186060"}	2026-09-23 04:53:02.067582+07
646	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "6.4", "bet_id": "ed7b2b9b-54c4-4b7e-bdce-cbf963c750dc", "losses": 7, "result": "LOSS", "streak": 7, "last_result": "LOSS", "user_profit": "-6.4", "gross_profit": "-6.4", "balance_after": "24788438.94302697", "session_profit": "-12.43186060"}	2026-09-23 04:53:03.299483+07
647	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "12.8", "bet_id": "9d49e159-4fce-4a96-86d4-17cbe03cfaa8", "losses": 8, "result": "LOSS", "streak": 8, "last_result": "LOSS", "user_profit": "-12.8", "gross_profit": "-12.8", "balance_after": "24788426.14302697", "session_profit": "-25.23186060"}	2026-09-23 04:53:04.528533+07
648	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "25.6", "bet_id": "dd45d165-7695-45a8-9cb2-f2e590bcffdb", "losses": 9, "result": "LOSS", "streak": 9, "last_result": "LOSS", "user_profit": "-25.6", "gross_profit": "-25.6", "balance_after": "24788400.54302697", "session_profit": "-50.83186060"}	2026-09-23 04:53:05.753703+07
649	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "51.2", "bet_id": "0f159474-9502-4ccb-87d6-14198acba050", "losses": 10, "result": "LOSS", "streak": 10, "last_result": "LOSS", "user_profit": "-51.2", "gross_profit": "-51.2", "balance_after": "24788349.34302697", "session_profit": "-102.03186060"}	2026-09-23 04:53:06.975321+07
650	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "102.4", "bet_id": "5466927b-16c6-46ca-946c-b9a389778571", "losses": 11, "result": "LOSS", "streak": 11, "last_result": "LOSS", "user_profit": "-102.4", "gross_profit": "-102.4", "balance_after": "24788246.94302697", "session_profit": "-204.43186060"}	2026-09-23 04:53:08.199375+07
651	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "204.8", "bet_id": "8100559c-3eaa-4c99-b5b7-3c0370f17462", "losses": 12, "result": "LOSS", "streak": 12, "last_result": "LOSS", "user_profit": "-204.8", "gross_profit": "-204.8", "balance_after": "24788042.14302697", "session_profit": "-409.23186060"}	2026-09-23 04:53:09.423271+07
652	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "409.6", "bet_id": "cfbd6ae8-f00b-4bbd-8fbe-6c9ebb131d9a", "losses": 12, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "813.7465856", "gross_profit": "946.21696", "balance_after": "24788855.88961257", "session_profit": "404.51472500"}	2026-09-23 04:53:10.660852+07
653	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.1", "bet_id": "8ef2bcca-5417-439e-9f92-e7d2d6e720ed", "losses": 12, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "24788855.78961257", "session_profit": "404.41472500"}	2026-09-23 04:53:12.077844+07
654	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.2", "bet_id": "cf59d9e6-2821-4046-96b9-829cca5af0d2", "losses": 12, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "24788855.58961257", "session_profit": "404.21472500"}	2026-09-23 04:53:13.300139+07
655	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.4", "bet_id": "66af8ffa-42dc-4cb1-b902-3caa57fcc93f", "losses": 12, "result": "LOSS", "streak": 3, "last_result": "LOSS", "user_profit": "-0.4", "gross_profit": "-0.4", "balance_after": "24788855.18961257", "session_profit": "403.81472500"}	2026-09-23 04:53:14.515469+07
656	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.8", "bet_id": "3244370a-5855-4487-a9e3-6abe0e7f5961", "losses": 12, "result": "LOSS", "streak": 4, "last_result": "LOSS", "user_profit": "-0.8", "gross_profit": "-0.8", "balance_after": "24788854.38961257", "session_profit": "403.01472500"}	2026-09-23 04:53:15.7434+07
657	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "1.6", "bet_id": "46817c3b-cecd-4e5d-8e80-3112ae1137d8", "losses": 12, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "3.23329728", "gross_profit": "3.759648", "balance_after": "24788857.62290985", "session_profit": "406.24802228"}	2026-09-23 04:53:16.969437+07
658	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.1", "bet_id": "cd9c1fe0-8b86-4145-a488-9774b0b5d6b5", "losses": 12, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "24788857.52290985", "session_profit": "406.14802228"}	2026-09-23 04:53:18.180917+07
660	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.4", "bet_id": "cabc9107-4504-4ad8-9094-92d9eb4b666d", "losses": 12, "result": "LOSS", "streak": 3, "last_result": "LOSS", "user_profit": "-0.4", "gross_profit": "-0.4", "balance_after": "24788856.92290985", "session_profit": "405.54802228"}	2026-09-23 04:53:20.644859+07
662	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "1.6", "bet_id": "4e53e675-6d15-4cf4-8037-eb4fd83b25df", "losses": 12, "result": "LOSS", "streak": 5, "last_result": "LOSS", "user_profit": "-1.6", "gross_profit": "-1.6", "balance_after": "24788854.52290985", "session_profit": "403.14802228"}	2026-09-23 04:53:23.093999+07
664	747	\N	COMMAND_RESULT	{"ok": true, "command": "STOP_ON_WIN", "message": "", "request_id": "f38276ca-332e-407c-bd6f-981e91a5a0de"}	2026-09-23 04:53:25.032655+07
665	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "6.4", "bet_id": "b8b36047-e4dd-49a2-9843-9d7d302e3a94", "losses": 12, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "19.69501824", "gross_profit": "22.901184", "balance_after": "24788871.01792809", "session_profit": "419.64304052"}	2026-09-23 04:53:25.556641+07
666	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	RUNNER_STATE	{"status": "COMPLETED", "message": "Stop Win tercapai"}	2026-09-23 04:53:25.583803+07
659	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.2", "bet_id": "ba0f0672-9f5e-45ba-b76f-20d0a78f7f44", "losses": 12, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "24788857.32290985", "session_profit": "405.94802228"}	2026-09-23 04:53:19.403829+07
661	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.8", "bet_id": "c46ab6da-f505-4953-975f-e36d4137d560", "losses": 12, "result": "LOSS", "streak": 4, "last_result": "LOSS", "user_profit": "-0.8", "gross_profit": "-0.8", "balance_after": "24788856.12290985", "session_profit": "404.74802228"}	2026-09-23 04:53:21.868066+07
663	747	387c7d27-dc7c-4afc-8213-a0910fc9de59	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "3.2", "bet_id": "bf72e954-a9ad-43ca-8e31-d314d1f93c26", "losses": 12, "result": "LOSS", "streak": 6, "last_result": "LOSS", "user_profit": "-3.2", "gross_profit": "-3.2", "balance_after": "24788851.32290985", "session_profit": "399.94802228"}	2026-09-23 04:53:24.311045+07
667	749	\N	COMMAND_RESULT	{"ok": false, "command": "START", "message": "minimum base trade 0.1 BTT", "request_id": "152e87ab-e0b2-443b-a40d-c3af59f4b6c7"}	2026-09-23 05:05:08.837346+07
668	749	\N	COMMAND_RESULT	{"ok": false, "command": "START", "message": "minimum base trade 0.1 BTT", "request_id": "e04acebb-00f0-4332-bd85-2ecbc98e7a89"}	2026-09-23 05:05:20.337421+07
669	749	44024e5f-6920-4c1f-b7a2-5ca036833e90	RUNNER_STATE	{"status": "RUNNING", "message": "Trading dimulai"}	2026-09-23 05:05:35.865279+07
670	749	\N	COMMAND_RESULT	{"ok": true, "command": "START", "message": "", "request_id": "799ca142-9360-4db4-9be0-9aa216af6fdb"}	2026-09-23 05:05:35.868043+07
671	749	44024e5f-6920-4c1f-b7a2-5ca036833e90	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.1", "bet_id": "ddb3d778-4cac-41bd-9cc6-095b7958c644", "losses": 0, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.148691", "gross_profit": "0.148691", "balance_after": "459868.15254368", "session_profit": "0.14869100"}	2026-09-23 05:05:36.23629+07
672	749	44024e5f-6920-4c1f-b7a2-5ca036833e90	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.1", "bet_id": "d017f5ed-3ef8-4203-b91f-6767e765f829", "losses": 1, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459868.05254368", "session_profit": "0.04869100"}	2026-09-23 05:05:36.558314+07
673	749	44024e5f-6920-4c1f-b7a2-5ca036833e90	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.2", "bet_id": "955de60e-fd09-43e9-8346-1827efe9c559", "losses": 2, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459867.85254368", "session_profit": "-0.15130900"}	2026-09-23 05:05:36.903303+07
674	749	44024e5f-6920-4c1f-b7a2-5ca036833e90	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.4", "bet_id": "6970ed23-701b-4edd-a018-3dd99c962f5d", "losses": 3, "result": "LOSS", "streak": 3, "last_result": "LOSS", "user_profit": "-0.4", "gross_profit": "-0.4", "balance_after": "459867.45254368", "session_profit": "-0.55130900"}	2026-09-23 05:05:37.232643+07
675	749	44024e5f-6920-4c1f-b7a2-5ca036833e90	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.8", "bet_id": "4597c2a9-2753-4d49-910b-1d48f98773d2", "losses": 4, "result": "LOSS", "streak": 4, "last_result": "LOSS", "user_profit": "-0.8", "gross_profit": "-0.8", "balance_after": "459866.65254368", "session_profit": "-1.35130900"}	2026-09-23 05:05:37.55486+07
676	749	44024e5f-6920-4c1f-b7a2-5ca036833e90	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "1.6", "bet_id": "0416cc83-5151-45f8-841d-ae1c48a3f26c", "losses": 4, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "2.24712", "gross_profit": "2.24712", "balance_after": "459868.89966368", "session_profit": "0.89581100"}	2026-09-23 05:05:37.875133+07
677	749	44024e5f-6920-4c1f-b7a2-5ca036833e90	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.1", "bet_id": "759282ef-e5f3-4daa-a4ab-c6ebf0e6c089", "losses": 4, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459868.79966368", "session_profit": "0.79581100"}	2026-09-23 05:05:38.19763+07
678	749	44024e5f-6920-4c1f-b7a2-5ca036833e90	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.2", "bet_id": "b48f5529-1ddc-4246-a729-9a836cd149af", "losses": 4, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.384434", "gross_profit": "0.384434", "balance_after": "459869.18409768", "session_profit": "1.18024500"}	2026-09-23 05:05:38.516998+07
679	749	44024e5f-6920-4c1f-b7a2-5ca036833e90	ROLL_SETTLED	{"coin": "BTT", "wins": 2, "amount": "0.1", "bet_id": "b122fd91-d93c-45d3-96f1-2fbdab34c94c", "losses": 4, "result": "WIN", "streak": 2, "last_result": "WIN", "user_profit": "0.141423", "gross_profit": "0.141423", "balance_after": "459869.32552068", "session_profit": "1.32166800"}	2026-09-23 05:05:38.836066+07
680	749	44024e5f-6920-4c1f-b7a2-5ca036833e90	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "ea1c454e-9e39-4611-9ceb-022cd32b8a4e", "losses": 4, "result": "WIN", "streak": 3, "last_result": "WIN", "user_profit": "0.14605", "gross_profit": "0.14605", "balance_after": "459869.47157068", "session_profit": "1.46771800"}	2026-09-23 05:05:39.155029+07
681	749	44024e5f-6920-4c1f-b7a2-5ca036833e90	ROLL_SETTLED	{"coin": "BTT", "wins": 4, "amount": "0.1", "bet_id": "e42f6d04-5c24-4610-a342-11ec4bc2cb55", "losses": 4, "result": "WIN", "streak": 4, "last_result": "WIN", "user_profit": "0.156895", "gross_profit": "0.156895", "balance_after": "459869.62846568", "session_profit": "1.62461300"}	2026-09-23 05:05:39.476953+07
682	749	44024e5f-6920-4c1f-b7a2-5ca036833e90	ROLL_SETTLED	{"coin": "BTT", "wins": 5, "amount": "0.1", "bet_id": "e83ec5b3-9897-46c3-834c-e3fc5098093b", "losses": 4, "result": "WIN", "streak": 5, "last_result": "WIN", "user_profit": "0.14002", "gross_profit": "0.14002", "balance_after": "459869.76848568", "session_profit": "1.76463300"}	2026-09-23 05:05:39.796032+07
683	749	44024e5f-6920-4c1f-b7a2-5ca036833e90	ROLL_SETTLED	{"coin": "BTT", "wins": 6, "amount": "0.1", "bet_id": "9e2c7f1a-f98c-466b-94a8-708aca63745c", "losses": 4, "result": "WIN", "streak": 6, "last_result": "WIN", "user_profit": "0.182569", "gross_profit": "0.182569", "balance_after": "459869.95105468", "session_profit": "1.94720200"}	2026-09-23 05:05:40.11727+07
684	749	44024e5f-6920-4c1f-b7a2-5ca036833e90	ROLL_SETTLED	{"coin": "BTT", "wins": 6, "amount": "0.1", "bet_id": "6ae77da6-8e4c-4375-8f13-d8a095b7ba6c", "losses": 4, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459869.85105468", "session_profit": "1.84720200"}	2026-09-23 05:05:40.42859+07
685	749	44024e5f-6920-4c1f-b7a2-5ca036833e90	ROLL_SETTLED	{"coin": "BTT", "wins": 6, "amount": "0.2", "bet_id": "cecc8f60-a344-4283-92c5-0773efce09f3", "losses": 4, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459869.65105468", "session_profit": "1.64720200"}	2026-09-23 05:05:40.742863+07
686	749	44024e5f-6920-4c1f-b7a2-5ca036833e90	ROLL_SETTLED	{"coin": "BTT", "wins": 6, "amount": "0.4", "bet_id": "8f506c5c-a991-4e94-83e0-d61645d949ee", "losses": 4, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.792716", "gross_profit": "0.792716", "balance_after": "459870.44377068", "session_profit": "2.43991800"}	2026-09-23 05:05:41.058602+07
688	749	44024e5f-6920-4c1f-b7a2-5ca036833e90	ROLL_SETTLED	{"coin": "BTT", "wins": 6, "amount": "0.1", "bet_id": "ee86d9e7-9d6e-4625-bdc8-a23834891569", "losses": 4, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459870.50425868", "session_profit": "2.50040600"}	2026-09-23 05:05:41.696679+07
687	749	44024e5f-6920-4c1f-b7a2-5ca036833e90	ROLL_SETTLED	{"coin": "BTT", "wins": 6, "amount": "0.1", "bet_id": "7187e6fc-2e4d-4fa7-ba42-191bf22051a9", "losses": 4, "result": "WIN", "streak": 2, "last_result": "WIN", "user_profit": "0.160488", "gross_profit": "0.160488", "balance_after": "459870.60425868", "session_profit": "2.60040600"}	2026-09-23 05:05:41.377924+07
689	749	\N	COMMAND_RESULT	{"ok": true, "command": "STOP_ON_WIN", "message": "", "request_id": "d599d267-abcb-426a-8150-1ed4c1ba6147"}	2026-09-23 05:05:41.8346+07
690	749	44024e5f-6920-4c1f-b7a2-5ca036833e90	ROLL_SETTLED	{"coin": "BTT", "wins": 6, "amount": "0.2", "bet_id": "d31cf86f-b252-46d4-898b-10dda87db47e", "losses": 4, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.316304", "gross_profit": "0.316304", "balance_after": "459870.82056268", "session_profit": "2.81671000"}	2026-09-23 05:05:42.015661+07
691	749	44024e5f-6920-4c1f-b7a2-5ca036833e90	RUNNER_STATE	{"status": "COMPLETED", "message": "Stop Win tercapai"}	2026-09-23 05:05:42.020271+07
692	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	RUNNER_STATE	{"status": "RUNNING", "message": "Trading dimulai"}	2026-09-23 05:21:13.466607+07
693	749	\N	COMMAND_RESULT	{"ok": true, "command": "START", "message": "", "request_id": "0a410471-84ed-4593-8c65-6b641eb67cbd"}	2026-09-23 05:21:13.484491+07
694	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.1", "bet_id": "447b4c7c-de11-4cc4-8d41-e0d75c5b3857", "losses": 0, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.213945", "gross_profit": "0.213945", "balance_after": "459871.03450768", "session_profit": "0.21394500"}	2026-09-23 05:21:14.093881+07
695	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.1", "bet_id": "04e4b7a0-1163-42a2-8886-c775a0e49ec7", "losses": 1, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459870.93450768", "session_profit": "0.11394500"}	2026-09-23 05:21:14.445078+07
696	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.2", "bet_id": "2123df6b-e0e0-423f-b6b8-eb6060b72235", "losses": 1, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.276428", "gross_profit": "0.276428", "balance_after": "459871.21093568", "session_profit": "0.39037300"}	2026-09-23 05:21:14.778395+07
697	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.1", "bet_id": "6ae9713f-1e08-4ee4-a4f1-74afba4b0fd1", "losses": 1, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459871.11093568", "session_profit": "0.29037300"}	2026-09-23 05:21:15.100676+07
698	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.2", "bet_id": "466db795-5b57-45b1-bdfa-38054f2db13a", "losses": 2, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459870.91093568", "session_profit": "0.09037300"}	2026-09-23 05:21:15.421922+07
699	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.4", "bet_id": "71f25eae-ab24-42c5-bb91-0986bf6be5e0", "losses": 3, "result": "LOSS", "streak": 3, "last_result": "LOSS", "user_profit": "-0.4", "gross_profit": "-0.4", "balance_after": "459870.51093568", "session_profit": "-0.30962700"}	2026-09-23 05:21:15.741831+07
700	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "0.8", "bet_id": "f37fbb55-247e-46a0-b18d-85c02e0d29be", "losses": 4, "result": "LOSS", "streak": 4, "last_result": "LOSS", "user_profit": "-0.8", "gross_profit": "-0.8", "balance_after": "459869.71093568", "session_profit": "-1.10962700"}	2026-09-23 05:21:16.063086+07
701	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 1, "amount": "1.6", "bet_id": "21a8237a-fab9-4024-8e42-ec3a0f28d8da", "losses": 4, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "2.69256", "gross_profit": "2.69256", "balance_after": "459872.40349568", "session_profit": "1.58293300"}	2026-09-23 05:21:16.388104+07
702	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 2, "amount": "0.1", "bet_id": "4c7b2a32-b827-404a-9724-aa2c0178ff2f", "losses": 4, "result": "WIN", "streak": 2, "last_result": "WIN", "user_profit": "0.187878", "gross_profit": "0.187878", "balance_after": "459872.59137368", "session_profit": "1.77081100"}	2026-09-23 05:21:16.712285+07
703	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 2, "amount": "0.1", "bet_id": "bd3398d5-5d2b-4afd-be80-15bca924423c", "losses": 4, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459872.49137368", "session_profit": "1.67081100"}	2026-09-23 05:21:17.032748+07
704	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 2, "amount": "0.2", "bet_id": "b3cceab1-87c2-4b56-b792-b7cd04d7dae5", "losses": 4, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459872.29137368", "session_profit": "1.47081100"}	2026-09-23 05:21:17.352857+07
705	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 2, "amount": "0.4", "bet_id": "bfde4684-c705-40ae-b044-cb3112131e0d", "losses": 4, "result": "LOSS", "streak": 3, "last_result": "LOSS", "user_profit": "-0.4", "gross_profit": "-0.4", "balance_after": "459871.89137368", "session_profit": "1.07081100"}	2026-09-23 05:21:17.673716+07
706	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 2, "amount": "0.8", "bet_id": "6d00bd5b-63dc-422d-b7e6-54c6f67060e2", "losses": 4, "result": "LOSS", "streak": 4, "last_result": "LOSS", "user_profit": "-0.8", "gross_profit": "-0.8", "balance_after": "459871.09137368", "session_profit": "0.27081100"}	2026-09-23 05:21:17.992444+07
707	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 2, "amount": "1.6", "bet_id": "a09fa708-2e85-4bad-83f2-3873fe4c4ec1", "losses": 5, "result": "LOSS", "streak": 5, "last_result": "LOSS", "user_profit": "-1.6", "gross_profit": "-1.6", "balance_after": "459869.49137368", "session_profit": "-1.32918900"}	2026-09-23 05:21:18.30977+07
708	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 2, "amount": "3.2", "bet_id": "f3868f90-3a66-4b93-874c-23eea841943b", "losses": 5, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "6.426336", "gross_profit": "6.426336", "balance_after": "459875.91770968", "session_profit": "5.09714700"}	2026-09-23 05:21:18.634899+07
709	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 2, "amount": "0.1", "bet_id": "9476aa73-8825-4b23-82ce-df0da85169d7", "losses": 5, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459875.81770968", "session_profit": "4.99714700"}	2026-09-23 05:21:18.956901+07
710	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 2, "amount": "0.2", "bet_id": "49be2446-8871-447f-9995-e9dd24530201", "losses": 5, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459875.61770968", "session_profit": "4.79714700"}	2026-09-23 05:21:19.277229+07
712	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 2, "amount": "0.8", "bet_id": "932f1055-e9ad-44ce-ab01-495d93211536", "losses": 5, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "1.300608", "gross_profit": "1.300608", "balance_after": "459876.51831768", "session_profit": "5.69775500"}	2026-09-23 05:21:19.912472+07
713	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 2, "amount": "0.1", "bet_id": "cbd74007-5636-4bb1-8b51-003a679f56da", "losses": 5, "result": "WIN", "streak": 2, "last_result": "WIN", "user_profit": "0.167454", "gross_profit": "0.167454", "balance_after": "459876.68577168", "session_profit": "5.86520900"}	2026-09-23 05:21:20.229174+07
714	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 2, "amount": "0.1", "bet_id": "4de7ac1c-81f9-4178-9c24-e0615f373d96", "losses": 5, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459876.58577168", "session_profit": "5.76520900"}	2026-09-23 05:21:20.548109+07
716	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 2, "amount": "0.1", "bet_id": "177d6d47-d0bc-4fc5-8b45-e156be71d003", "losses": 5, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459876.86415768", "session_profit": "6.04359500"}	2026-09-23 05:21:21.19266+07
718	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 2, "amount": "0.1", "bet_id": "036f45c6-e106-4cf1-977f-68f8bbc3da5f", "losses": 5, "result": "WIN", "streak": 2, "last_result": "WIN", "user_profit": "0.213738", "gross_profit": "0.213738", "balance_after": "459877.43458968", "session_profit": "6.61402700"}	2026-09-23 05:21:21.832246+07
720	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "271083ca-7f6f-42bb-9e5e-54b505cf97ce", "losses": 5, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459877.48657868", "session_profit": "6.66601600"}	2026-09-23 05:21:22.468818+07
722	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.4", "bet_id": "a63fe8e0-4f1e-4ff2-906e-a7b36ebf663c", "losses": 5, "result": "LOSS", "streak": 3, "last_result": "LOSS", "user_profit": "-0.4", "gross_profit": "-0.4", "balance_after": "459876.88657868", "session_profit": "6.06601600"}	2026-09-23 05:21:23.101357+07
724	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "1.6", "bet_id": "e80c7c2b-bb4b-4891-90fb-22f86410ebb0", "losses": 5, "result": "LOSS", "streak": 5, "last_result": "LOSS", "user_profit": "-1.6", "gross_profit": "-1.6", "balance_after": "459874.48657868", "session_profit": "3.66601600"}	2026-09-23 05:21:23.744561+07
726	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "6.4", "bet_id": "3fdb4b66-afd2-4f73-985e-67040a206157", "losses": 7, "result": "LOSS", "streak": 7, "last_result": "LOSS", "user_profit": "-6.4", "gross_profit": "-6.4", "balance_after": "459864.88657868", "session_profit": "-5.93398400"}	2026-09-23 05:21:24.382858+07
728	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "25.6", "bet_id": "75bfbd7e-72bf-4a79-bc3d-a692ea1d2a23", "losses": 8, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "51.630848", "gross_profit": "51.630848", "balance_after": "459903.71742668", "session_profit": "32.89686400"}	2026-09-23 05:21:25.020839+07
729	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "96e44c09-49eb-4af0-af93-4bc895a35961", "losses": 8, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459903.61742668", "session_profit": "32.79686400"}	2026-09-23 05:21:25.340103+07
730	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "8b4500a2-be69-415a-8a54-515b2cfb2819", "losses": 8, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459903.41742668", "session_profit": "32.59686400"}	2026-09-23 05:21:25.664297+07
732	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.8", "bet_id": "353039ff-afda-43ac-a7c5-d8569fa9188d", "losses": 8, "result": "LOSS", "streak": 4, "last_result": "LOSS", "user_profit": "-0.8", "gross_profit": "-0.8", "balance_after": "459902.21742668", "session_profit": "31.39686400"}	2026-09-23 05:21:26.500343+07
734	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "3.2", "bet_id": "a1a8cda7-85ab-477a-956b-cec0b3909482", "losses": 8, "result": "LOSS", "streak": 6, "last_result": "LOSS", "user_profit": "-3.2", "gross_profit": "-3.2", "balance_after": "459897.41742668", "session_profit": "26.59686400"}	2026-09-23 05:21:27.135599+07
736	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "12.8", "bet_id": "9f11fa13-2a28-40d1-8d15-43ccf88570e1", "losses": 8, "result": "LOSS", "streak": 8, "last_result": "LOSS", "user_profit": "-12.8", "gross_profit": "-12.8", "balance_after": "459878.21742668", "session_profit": "7.39686400"}	2026-09-23 05:21:27.776746+07
738	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "e5739ca9-2448-4fed-ae88-23b2d93e4b3e", "losses": 8, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459925.70424268", "session_profit": "54.88368000"}	2026-09-23 05:21:28.412842+07
740	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "559040d8-6f24-427c-bf99-9950f8d083e9", "losses": 8, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459925.95753268", "session_profit": "55.13697000"}	2026-09-23 05:21:29.048562+07
742	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.4", "bet_id": "bc619d6b-b9ff-4b72-86a5-faf03bcfca28", "losses": 8, "result": "LOSS", "streak": 3, "last_result": "LOSS", "user_profit": "-0.4", "gross_profit": "-0.4", "balance_after": "459925.35753268", "session_profit": "54.53697000"}	2026-09-23 05:21:29.687288+07
743	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.8", "bet_id": "0bd17330-3ff4-40f4-a525-a532b2a6a679", "losses": 8, "result": "LOSS", "streak": 4, "last_result": "LOSS", "user_profit": "-0.8", "gross_profit": "-0.8", "balance_after": "459924.55753268", "session_profit": "53.73697000"}	2026-09-23 05:21:30.003958+07
711	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 2, "amount": "0.4", "bet_id": "74417647-8c36-4b66-852b-fe0caaa30cb8", "losses": 5, "result": "LOSS", "streak": 3, "last_result": "LOSS", "user_profit": "-0.4", "gross_profit": "-0.4", "balance_after": "459875.21770968", "session_profit": "4.39714700"}	2026-09-23 05:21:19.594705+07
715	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 2, "amount": "0.2", "bet_id": "f9526922-75fc-4270-ad67-b7a3ee6bd4b8", "losses": 5, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.378386", "gross_profit": "0.378386", "balance_after": "459876.96415768", "session_profit": "6.14359500"}	2026-09-23 05:21:20.869757+07
717	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 2, "amount": "0.2", "bet_id": "2219ae6a-a89c-45e6-83b5-43a9adeee6bd", "losses": 5, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.356694", "gross_profit": "0.356694", "balance_after": "459877.22085168", "session_profit": "6.40028900"}	2026-09-23 05:21:21.512796+07
719	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "ec008051-76a4-453a-adf7-5bc55bd5a15c", "losses": 5, "result": "WIN", "streak": 3, "last_result": "WIN", "user_profit": "0.151989", "gross_profit": "0.151989", "balance_after": "459877.58657868", "session_profit": "6.76601600"}	2026-09-23 05:21:22.150864+07
721	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "3d692f95-8678-478c-9731-36656158bfed", "losses": 5, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459877.28657868", "session_profit": "6.46601600"}	2026-09-23 05:21:22.784543+07
723	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.8", "bet_id": "b4eb87f4-9e7f-4027-aee7-b47e318d7167", "losses": 5, "result": "LOSS", "streak": 4, "last_result": "LOSS", "user_profit": "-0.8", "gross_profit": "-0.8", "balance_after": "459876.08657868", "session_profit": "5.26601600"}	2026-09-23 05:21:23.421106+07
725	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "3.2", "bet_id": "fbb47fc4-8548-4560-90e0-0d722b4b07e8", "losses": 6, "result": "LOSS", "streak": 6, "last_result": "LOSS", "user_profit": "-3.2", "gross_profit": "-3.2", "balance_after": "459871.28657868", "session_profit": "0.46601600"}	2026-09-23 05:21:24.064843+07
727	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "12.8", "bet_id": "86d65b6f-f5dc-4028-a788-5b3c71d25fe2", "losses": 8, "result": "LOSS", "streak": 8, "last_result": "LOSS", "user_profit": "-12.8", "gross_profit": "-12.8", "balance_after": "459852.08657868", "session_profit": "-18.73398400"}	2026-09-23 05:21:24.703137+07
731	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.4", "bet_id": "d832909a-3bce-4fbb-9488-4408b584ac46", "losses": 8, "result": "LOSS", "streak": 3, "last_result": "LOSS", "user_profit": "-0.4", "gross_profit": "-0.4", "balance_after": "459903.01742668", "session_profit": "32.19686400"}	2026-09-23 05:21:26.182612+07
733	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "1.6", "bet_id": "ceb9fa3a-e725-4b10-bbba-ab4eb478e1be", "losses": 8, "result": "LOSS", "streak": 5, "last_result": "LOSS", "user_profit": "-1.6", "gross_profit": "-1.6", "balance_after": "459900.61742668", "session_profit": "29.79686400"}	2026-09-23 05:21:26.820142+07
735	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "6.4", "bet_id": "abf1ea11-bb0d-49cc-be50-6de8ba1a2611", "losses": 8, "result": "LOSS", "streak": 7, "last_result": "LOSS", "user_profit": "-6.4", "gross_profit": "-6.4", "balance_after": "459891.01742668", "session_profit": "20.19686400"}	2026-09-23 05:21:27.455592+07
737	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "25.6", "bet_id": "adf24130-d312-46f5-b1d1-7f764ef84b3b", "losses": 8, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "47.586816", "gross_profit": "47.586816", "balance_after": "459925.80424268", "session_profit": "54.98368000"}	2026-09-23 05:21:28.095586+07
739	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "32e694a3-bccc-414a-b792-7bd3425a7543", "losses": 8, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.35329", "gross_profit": "0.35329", "balance_after": "459926.05753268", "session_profit": "55.23697000"}	2026-09-23 05:21:28.732279+07
741	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "1b286f7b-b416-4b32-9cc1-8eff05eb143a", "losses": 8, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459925.75753268", "session_profit": "54.93697000"}	2026-09-23 05:21:29.366074+07
744	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "1.6", "bet_id": "bead6e82-c7cc-4242-9899-e59f42800f4d", "losses": 8, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "3.330256", "gross_profit": "3.330256", "balance_after": "459927.88778868", "session_profit": "57.06722600"}	2026-09-23 05:21:30.319807+07
746	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "18f07a07-fdf8-4786-b9f5-458f084994c1", "losses": 8, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.369372", "gross_profit": "0.369372", "balance_after": "459928.15716068", "session_profit": "57.33659800"}	2026-09-23 05:21:30.953459+07
748	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "7e0393fb-d4ee-4114-a9ab-1d083f5d6376", "losses": 8, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.343944", "gross_profit": "0.343944", "balance_after": "459928.40110468", "session_profit": "57.58054200"}	2026-09-23 05:21:31.587934+07
750	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "dfa17c8c-e64f-4dd1-b80a-87c4193bbabd", "losses": 8, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459928.10110468", "session_profit": "57.28054200"}	2026-09-23 05:21:32.219421+07
752	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "f8c7d8a6-b0e2-4b87-a25d-b2119283528d", "losses": 8, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459928.57922468", "session_profit": "57.75866200"}	2026-09-23 05:21:32.856822+07
754	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.4", "bet_id": "a5dc467e-56b5-4011-8e0c-1ac2171b0da8", "losses": 8, "result": "LOSS", "streak": 3, "last_result": "LOSS", "user_profit": "-0.4", "gross_profit": "-0.4", "balance_after": "459927.97922468", "session_profit": "57.15866200"}	2026-09-23 05:21:33.490764+07
745	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "dda910c5-988d-4f4a-beac-522b1da194aa", "losses": 8, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459927.78778868", "session_profit": "56.96722600"}	2026-09-23 05:21:30.636134+07
747	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "b3e3880e-3793-410e-9767-f84e110d0c02", "losses": 8, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459928.05716068", "session_profit": "57.23659800"}	2026-09-23 05:21:31.266747+07
749	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "3ca6643c-1e7e-4f35-9f57-ed9388f4ad34", "losses": 8, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459928.30110468", "session_profit": "57.48054200"}	2026-09-23 05:21:31.903904+07
751	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.4", "bet_id": "5e538cb3-5f61-45c5-8894-16e0062a8f04", "losses": 8, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.57812", "gross_profit": "0.57812", "balance_after": "459928.67922468", "session_profit": "57.85866200"}	2026-09-23 05:21:32.535372+07
753	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "d0e19ef7-6aa5-4714-9517-2cfe2cfd3736", "losses": 8, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459928.37922468", "session_profit": "57.55866200"}	2026-09-23 05:21:33.173407+07
755	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.8", "bet_id": "69aae520-0c4b-4ece-9967-3d0722f7dd21", "losses": 8, "result": "LOSS", "streak": 4, "last_result": "LOSS", "user_profit": "-0.8", "gross_profit": "-0.8", "balance_after": "459927.17922468", "session_profit": "56.35866200"}	2026-09-23 05:21:33.806229+07
756	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "1.6", "bet_id": "db2e1739-40cd-432b-940f-92e68f53506a", "losses": 8, "result": "LOSS", "streak": 5, "last_result": "LOSS", "user_profit": "-1.6", "gross_profit": "-1.6", "balance_after": "459925.57922468", "session_profit": "54.75866200"}	2026-09-23 05:21:34.121735+07
759	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "5d42832e-877f-427d-ba54-70f8b8457ce0", "losses": 8, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459932.30831768", "session_profit": "61.48775500"}	2026-09-23 05:21:35.079605+07
761	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.4", "bet_id": "f13c28cd-7806-4fa7-8fa3-9d29e58d8f40", "losses": 8, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.620408", "gross_profit": "0.620408", "balance_after": "459932.72872568", "session_profit": "61.90816300"}	2026-09-23 05:21:35.71368+07
763	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "e2e47d7a-7fcc-4497-918b-3497cf790dfd", "losses": 8, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459932.77101068", "session_profit": "61.95044800"}	2026-09-23 05:21:36.343669+07
765	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "db35ef83-6e8f-4e6f-8cb8-0176a7bf08bc", "losses": 8, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459933.05436868", "session_profit": "62.23380600"}	2026-09-23 05:21:36.980913+07
767	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.4", "bet_id": "d04bdbcf-e050-4659-a077-de4fcbf29c43", "losses": 8, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.569632", "gross_profit": "0.569632", "balance_after": "459933.42400068", "session_profit": "62.60343800"}	2026-09-23 05:21:37.614031+07
769	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "dd2b4b54-5da9-4d06-8465-b2559fdae082", "losses": 8, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.373498", "gross_profit": "0.373498", "balance_after": "459933.69749868", "session_profit": "62.87693600"}	2026-09-23 05:21:38.248867+07
771	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "3390a4ef-1c4b-4007-ba0c-b4978f2332e0", "losses": 8, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459933.74450768", "session_profit": "62.92394500"}	2026-09-23 05:21:38.882704+07
774	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "129a6084-d3f7-465a-8558-bd5988be6ec6", "losses": 8, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459934.26828368", "session_profit": "63.44772100"}	2026-09-23 05:21:39.843604+07
776	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.4", "bet_id": "cc2ed6f7-e47f-4942-8243-54d3ce0041e9", "losses": 8, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.630648", "gross_profit": "0.630648", "balance_after": "459934.69893168", "session_profit": "63.87836900"}	2026-09-23 05:21:40.477732+07
778	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "dfb237ab-73a6-4ca8-9a5a-8d22afbc260f", "losses": 8, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459934.80617568", "session_profit": "63.98561300"}	2026-09-23 05:21:41.116541+07
781	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "923b2afd-c976-457f-a525-37216d2483cb", "losses": 8, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459935.10250368", "session_profit": "64.28194100"}	2026-09-23 05:21:42.071079+07
784	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "1df9bdd0-f758-4a76-8ad2-c7b77d44ce32", "losses": 8, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459935.53398268", "session_profit": "64.71342000"}	2026-09-23 05:21:43.232069+07
787	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "b7cdb3b2-eaee-425e-ac6e-6ab69d1ba1f7", "losses": 8, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459935.91882868", "session_profit": "65.09826600"}	2026-09-23 05:21:44.186858+07
757	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "3.2", "bet_id": "55119763-a33a-441a-8d80-13128c264220", "losses": 8, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "6.689376", "gross_profit": "6.689376", "balance_after": "459932.26860068", "session_profit": "61.44803800"}	2026-09-23 05:21:34.438593+07
758	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "161ebd47-9fec-4773-9c13-43a811579d8b", "losses": 8, "result": "WIN", "streak": 2, "last_result": "WIN", "user_profit": "0.139717", "gross_profit": "0.139717", "balance_after": "459932.40831768", "session_profit": "61.58775500"}	2026-09-23 05:21:34.761099+07
760	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "8d23efd0-6425-44ea-915e-96b9be7640a8", "losses": 8, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459932.10831768", "session_profit": "61.28775500"}	2026-09-23 05:21:35.39698+07
762	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "bf261614-af16-4b28-8f1c-65e2b4a3c14f", "losses": 8, "result": "WIN", "streak": 2, "last_result": "WIN", "user_profit": "0.142285", "gross_profit": "0.142285", "balance_after": "459932.87101068", "session_profit": "62.05044800"}	2026-09-23 05:21:36.028645+07
764	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "7e8122fa-5e99-41e1-ae1a-b4946570fd9f", "losses": 8, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.383358", "gross_profit": "0.383358", "balance_after": "459933.15436868", "session_profit": "62.33380600"}	2026-09-23 05:21:36.664011+07
766	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "42eb70bb-35b7-46e3-b358-4d2c7782749d", "losses": 8, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459932.85436868", "session_profit": "62.03380600"}	2026-09-23 05:21:37.295198+07
768	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "343e8fe4-da43-482b-9029-c98ffc00179e", "losses": 8, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459933.32400068", "session_profit": "62.50343800"}	2026-09-23 05:21:37.932472+07
770	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "bddd43fa-3f68-4de4-9f0b-bd88d4d733ee", "losses": 8, "result": "WIN", "streak": 2, "last_result": "WIN", "user_profit": "0.147009", "gross_profit": "0.147009", "balance_after": "459933.84450768", "session_profit": "63.02394500"}	2026-09-23 05:21:38.566303+07
772	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "ba2c5219-f742-4c0e-a426-a2daaa8be4ee", "losses": 8, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.431018", "gross_profit": "0.431018", "balance_after": "459934.17552568", "session_profit": "63.35496300"}	2026-09-23 05:21:39.205975+07
773	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "7b9128fb-fdbc-45d1-b1e8-87100addc4d9", "losses": 8, "result": "WIN", "streak": 2, "last_result": "WIN", "user_profit": "0.192758", "gross_profit": "0.192758", "balance_after": "459934.36828368", "session_profit": "63.54772100"}	2026-09-23 05:21:39.527408+07
775	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "c57c4e6c-50e4-4d97-af5e-f04fbfce05ab", "losses": 8, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459934.06828368", "session_profit": "63.24772100"}	2026-09-23 05:21:40.160142+07
777	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "8f7f269f-09ad-44db-ab30-d2ac4961f7e8", "losses": 8, "result": "WIN", "streak": 2, "last_result": "WIN", "user_profit": "0.207244", "gross_profit": "0.207244", "balance_after": "459934.90617568", "session_profit": "64.08561300"}	2026-09-23 05:21:40.798108+07
779	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "aee19b98-a801-4969-9f65-62ff5963712f", "losses": 8, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459934.60617568", "session_profit": "63.78561300"}	2026-09-23 05:21:41.435359+07
780	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.4", "bet_id": "9affffb7-7942-497b-9a63-0ce45af4a148", "losses": 8, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.596328", "gross_profit": "0.596328", "balance_after": "459935.20250368", "session_profit": "64.38194100"}	2026-09-23 05:21:41.75545+07
782	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "3d81f0b9-4d5a-4682-8568-0d525cce51b6", "losses": 8, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.322838", "gross_profit": "0.322838", "balance_after": "459935.42534168", "session_profit": "64.60477900"}	2026-09-23 05:21:42.393008+07
783	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "35138ddd-ab5e-409e-abab-bd3ba924c7b3", "losses": 8, "result": "WIN", "streak": 2, "last_result": "WIN", "user_profit": "0.208641", "gross_profit": "0.208641", "balance_after": "459935.63398268", "session_profit": "64.81342000"}	2026-09-23 05:21:42.711396+07
785	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "b1ba76c4-73f4-40fc-b317-43cf96004d39", "losses": 8, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.333856", "gross_profit": "0.333856", "balance_after": "459935.86783868", "session_profit": "65.04727600"}	2026-09-23 05:21:43.554158+07
786	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "80472829-856d-418a-b42c-652809b4e115", "losses": 8, "result": "WIN", "streak": 2, "last_result": "WIN", "user_profit": "0.15099", "gross_profit": "0.15099", "balance_after": "459936.01882868", "session_profit": "65.19826600"}	2026-09-23 05:21:43.869872+07
788	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "e32274dc-ce9f-4c88-bb3c-07cce1158466", "losses": 8, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459935.71882868", "session_profit": "64.89826600"}	2026-09-23 05:21:44.504232+07
789	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.4", "bet_id": "d1e7b841-7b93-48f5-83b3-0cd877ac545c", "losses": 8, "result": "LOSS", "streak": 3, "last_result": "LOSS", "user_profit": "-0.4", "gross_profit": "-0.4", "balance_after": "459935.31882868", "session_profit": "64.49826600"}	2026-09-23 05:21:44.831899+07
790	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.8", "bet_id": "e099afe4-f238-4354-9395-ca0ea4efef8c", "losses": 8, "result": "LOSS", "streak": 4, "last_result": "LOSS", "user_profit": "-0.8", "gross_profit": "-0.8", "balance_after": "459934.51882868", "session_profit": "63.69826600"}	2026-09-23 05:21:45.173995+07
791	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "1.6", "bet_id": "a4380329-cafb-4b24-9adf-2bcc093598a3", "losses": 8, "result": "LOSS", "streak": 5, "last_result": "LOSS", "user_profit": "-1.6", "gross_profit": "-1.6", "balance_after": "459932.91882868", "session_profit": "62.09826600"}	2026-09-23 05:21:45.498382+07
792	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "3.2", "bet_id": "74c5c9cc-5246-48a7-bb28-6f688574070a", "losses": 8, "result": "LOSS", "streak": 6, "last_result": "LOSS", "user_profit": "-3.2", "gross_profit": "-3.2", "balance_after": "459929.71882868", "session_profit": "58.89826600"}	2026-09-23 05:21:45.818172+07
793	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "6.4", "bet_id": "1f916b1e-855f-4686-a725-fd1b607c51a7", "losses": 8, "result": "LOSS", "streak": 7, "last_result": "LOSS", "user_profit": "-6.4", "gross_profit": "-6.4", "balance_after": "459923.31882868", "session_profit": "52.49826600"}	2026-09-23 05:21:46.136005+07
794	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "12.8", "bet_id": "bc62c642-7f23-461e-9f38-b813a5fa4217", "losses": 8, "result": "LOSS", "streak": 8, "last_result": "LOSS", "user_profit": "-12.8", "gross_profit": "-12.8", "balance_after": "459910.51882868", "session_profit": "39.69826600"}	2026-09-23 05:21:46.452921+07
795	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "25.6", "bet_id": "056b5335-69b1-4f3e-a1b7-dddad5b3e35c", "losses": 9, "result": "LOSS", "streak": 9, "last_result": "LOSS", "user_profit": "-25.6", "gross_profit": "-25.6", "balance_after": "459884.91882868", "session_profit": "14.09826600"}	2026-09-23 05:21:46.774849+07
796	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "51.2", "bet_id": "777a14a7-fc44-4616-b727-0c84593ff7b6", "losses": 9, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "74.712064", "gross_profit": "74.712064", "balance_after": "459959.63089268", "session_profit": "88.81033000"}	2026-09-23 05:21:47.091681+07
797	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "779121e4-7ecc-4155-aaad-6a5e6b17b900", "losses": 9, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459959.53089268", "session_profit": "88.71033000"}	2026-09-23 05:21:47.410282+07
798	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "837a4542-aea1-4a5e-a5b1-6017d08212a0", "losses": 9, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.33251", "gross_profit": "0.33251", "balance_after": "459959.86340268", "session_profit": "89.04284000"}	2026-09-23 05:21:47.731222+07
799	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "f433557d-b3e7-4843-b073-02f7ef07b5f3", "losses": 9, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459959.76340268", "session_profit": "88.94284000"}	2026-09-23 05:21:48.04877+07
800	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "961504c7-40fc-45b8-b536-c9cbd8d5afb3", "losses": 9, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459959.56340268", "session_profit": "88.74284000"}	2026-09-23 05:21:48.368876+07
801	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.4", "bet_id": "d241e92b-dae0-4970-9775-cfa9e46ee33a", "losses": 9, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.715676", "gross_profit": "0.715676", "balance_after": "459960.27907868", "session_profit": "89.45851600"}	2026-09-23 05:21:48.687056+07
802	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "350431e7-83b3-4a3a-bee1-06a2dc295583", "losses": 9, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459960.17907868", "session_profit": "89.35851600"}	2026-09-23 05:21:49.003781+07
803	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "a92dd731-c40c-4ce1-8e5b-8583fe78a20e", "losses": 9, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459959.97907868", "session_profit": "89.15851600"}	2026-09-23 05:21:49.320748+07
804	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.4", "bet_id": "95b8527c-25dd-4849-898a-ab9f60026fda", "losses": 9, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.850408", "gross_profit": "0.850408", "balance_after": "459960.82948668", "session_profit": "90.00892400"}	2026-09-23 05:21:49.640834+07
805	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "26f3b0a8-92b0-411c-9a6f-dc48d5255d71", "losses": 9, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459960.72948668", "session_profit": "89.90892400"}	2026-09-23 05:21:49.956408+07
806	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "0f3b91d1-a2d8-4285-a8df-d4756b213d85", "losses": 9, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459960.52948668", "session_profit": "89.70892400"}	2026-09-23 05:21:50.271735+07
807	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.4", "bet_id": "2f2d94c2-0d9d-4cec-9dd5-e1557b15839e", "losses": 9, "result": "LOSS", "streak": 3, "last_result": "LOSS", "user_profit": "-0.4", "gross_profit": "-0.4", "balance_after": "459960.12948668", "session_profit": "89.30892400"}	2026-09-23 05:21:50.589917+07
808	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.8", "bet_id": "c89a5b86-e411-4010-a67d-efffa0e8458d", "losses": 9, "result": "LOSS", "streak": 4, "last_result": "LOSS", "user_profit": "-0.8", "gross_profit": "-0.8", "balance_after": "459959.32948668", "session_profit": "88.50892400"}	2026-09-23 05:21:50.909872+07
809	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "1.6", "bet_id": "ca1e59a1-3ebc-4261-8f99-b18c22491b67", "losses": 9, "result": "LOSS", "streak": 5, "last_result": "LOSS", "user_profit": "-1.6", "gross_profit": "-1.6", "balance_after": "459957.72948668", "session_profit": "86.90892400"}	2026-09-23 05:21:51.239127+07
811	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "6.4", "bet_id": "ee1ec677-be97-4ce7-9867-9609526d2c20", "losses": 9, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "13.832896", "gross_profit": "13.832896", "balance_after": "459968.36238268", "session_profit": "97.54182000"}	2026-09-23 05:21:51.880471+07
813	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "b6f3dcb5-07c7-4829-985a-4e91f8cc1195", "losses": 9, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459968.06238268", "session_profit": "97.24182000"}	2026-09-23 05:21:52.515924+07
818	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "5c504425-e96b-4635-9f6b-ae20418ac675", "losses": 9, "result": "WIN", "streak": 2, "last_result": "WIN", "user_profit": "0.138933", "gross_profit": "0.138933", "balance_after": "459969.13329468", "session_profit": "98.31273200"}	2026-09-23 05:21:54.119276+07
820	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "cb546f58-c9db-4acf-a2f7-ed9458896251", "losses": 9, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459968.83329468", "session_profit": "98.01273200"}	2026-09-23 05:21:54.758609+07
822	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.8", "bet_id": "0419dc65-5646-46f3-a47f-c7ad3a6d02ce", "losses": 9, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "1.435288", "gross_profit": "1.435288", "balance_after": "459969.86858268", "session_profit": "99.04802000"}	2026-09-23 05:21:55.393324+07
824	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "8ac2dcd0-6878-469b-aa86-69d4a754091e", "losses": 9, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459969.56858268", "session_profit": "98.74802000"}	2026-09-23 05:21:56.029486+07
826	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.8", "bet_id": "1840437d-d149-4db6-b6bd-492adb581016", "losses": 9, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "1.228288", "gross_profit": "1.228288", "balance_after": "459970.39687068", "session_profit": "99.57630800"}	2026-09-23 05:21:56.665861+07
827	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "5504a237-a875-4aa4-b924-7b136153f054", "losses": 9, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459970.29687068", "session_profit": "99.47630800"}	2026-09-23 05:21:56.983314+07
829	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.4", "bet_id": "43cc3e36-727c-492b-ad77-682a9efd1286", "losses": 9, "result": "LOSS", "streak": 3, "last_result": "LOSS", "user_profit": "-0.4", "gross_profit": "-0.4", "balance_after": "459969.69687068", "session_profit": "98.87630800"}	2026-09-23 05:21:57.620507+07
831	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "17a6cbed-5cff-4caa-87a5-d465c1ef8237", "losses": 9, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459971.03019068", "session_profit": "100.20962800"}	2026-09-23 05:21:58.253698+07
833	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.4", "bet_id": "46be9643-c84e-497d-b833-cde7c457c912", "losses": 9, "result": "LOSS", "streak": 3, "last_result": "LOSS", "user_profit": "-0.4", "gross_profit": "-0.4", "balance_after": "459970.43019068", "session_profit": "99.60962800"}	2026-09-23 05:21:58.891634+07
835	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "1.6", "bet_id": "edebd2ba-b219-4795-a9fa-9478d0eb1f32", "losses": 9, "result": "LOSS", "streak": 5, "last_result": "LOSS", "user_profit": "-1.6", "gross_profit": "-1.6", "balance_after": "459968.03019068", "session_profit": "97.20962800"}	2026-09-23 05:21:59.527824+07
837	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "e5884732-d39c-41c6-909a-6143cd645e22", "losses": 9, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459973.00679868", "session_profit": "102.18623600"}	2026-09-23 05:22:00.164626+07
838	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "ad7736d0-6f70-491c-a6b4-b2abe8757177", "losses": 9, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459972.80679868", "session_profit": "101.98623600"}	2026-09-23 05:22:00.683819+07
839	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.4", "bet_id": "78cb4dce-462b-438f-ab65-ba73bd8680f0", "losses": 9, "result": "LOSS", "streak": 3, "last_result": "LOSS", "user_profit": "-0.4", "gross_profit": "-0.4", "balance_after": "459972.40679868", "session_profit": "101.58623600"}	2026-09-23 05:22:01.003647+07
840	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.8", "bet_id": "71be9279-778a-4b58-a284-f7a80649e53f", "losses": 9, "result": "LOSS", "streak": 4, "last_result": "LOSS", "user_profit": "-0.8", "gross_profit": "-0.8", "balance_after": "459971.60679868", "session_profit": "100.78623600"}	2026-09-23 05:22:01.326759+07
842	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "3.2", "bet_id": "1da74e98-6ed3-4118-8aa6-337dfc2af09c", "losses": 9, "result": "LOSS", "streak": 6, "last_result": "LOSS", "user_profit": "-3.2", "gross_profit": "-3.2", "balance_after": "459966.80679868", "session_profit": "95.98623600"}	2026-09-23 05:22:01.972591+07
844	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "12.8", "bet_id": "4035e060-ee0c-4cf0-8501-a4fa093cc8a5", "losses": 9, "result": "LOSS", "streak": 8, "last_result": "LOSS", "user_profit": "-12.8", "gross_profit": "-12.8", "balance_after": "459947.60679868", "session_profit": "76.78623600"}	2026-09-23 05:22:02.61287+07
846	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "5d4ced2e-40c3-48f1-9b95-05c6e7a34519", "losses": 9, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459998.04939068", "session_profit": "127.22882800"}	2026-09-23 05:22:03.248231+07
810	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "3.2", "bet_id": "396e351a-761e-458e-bd84-70f6b09c2034", "losses": 9, "result": "LOSS", "streak": 6, "last_result": "LOSS", "user_profit": "-3.2", "gross_profit": "-3.2", "balance_after": "459954.52948668", "session_profit": "83.70892400"}	2026-09-23 05:21:51.559892+07
812	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "d7e2098d-7cda-497b-8013-3ec972c79e50", "losses": 9, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459968.26238268", "session_profit": "97.44182000"}	2026-09-23 05:21:52.197141+07
814	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.4", "bet_id": "2923e13e-4db6-449b-9246-7393c1580b4e", "losses": 9, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.591908", "gross_profit": "0.591908", "balance_after": "459968.65429068", "session_profit": "97.83372800"}	2026-09-23 05:21:52.841066+07
815	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "39d34a64-50f1-44f6-8f2f-35648078c625", "losses": 9, "result": "WIN", "streak": 2, "last_result": "WIN", "user_profit": "0.154759", "gross_profit": "0.154759", "balance_after": "459968.80904968", "session_profit": "97.98848700"}	2026-09-23 05:21:53.162996+07
816	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "af24e42d-bb19-4d1a-a6a4-c3a614abc7b3", "losses": 9, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459968.70904968", "session_profit": "97.88848700"}	2026-09-23 05:21:53.482252+07
817	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "6651e7ad-c862-4083-83e0-fb87060e4517", "losses": 9, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.285312", "gross_profit": "0.285312", "balance_after": "459968.99436168", "session_profit": "98.17379900"}	2026-09-23 05:21:53.801254+07
819	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "9816ee21-e72c-4ce9-843e-e2e611e981e9", "losses": 9, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459969.03329468", "session_profit": "98.21273200"}	2026-09-23 05:21:54.436761+07
821	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.4", "bet_id": "e571f121-f9fd-45d8-aa6b-a80219992007", "losses": 9, "result": "LOSS", "streak": 3, "last_result": "LOSS", "user_profit": "-0.4", "gross_profit": "-0.4", "balance_after": "459968.43329468", "session_profit": "97.61273200"}	2026-09-23 05:21:55.073778+07
823	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "fc3b8d87-ea26-4935-baa5-b0a2bf11e1a9", "losses": 9, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459969.76858268", "session_profit": "98.94802000"}	2026-09-23 05:21:55.712109+07
825	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.4", "bet_id": "3b473a9e-cdb4-4e4c-b0db-67732b361710", "losses": 9, "result": "LOSS", "streak": 3, "last_result": "LOSS", "user_profit": "-0.4", "gross_profit": "-0.4", "balance_after": "459969.16858268", "session_profit": "98.34802000"}	2026-09-23 05:21:56.346256+07
828	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "7753de30-9741-4bb2-baca-b5cd1d6f141b", "losses": 9, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459970.09687068", "session_profit": "99.27630800"}	2026-09-23 05:21:57.301014+07
830	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.8", "bet_id": "ea97bc61-9a4e-4b51-aeb4-cf0d757a4475", "losses": 9, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "1.43332", "gross_profit": "1.43332", "balance_after": "459971.13019068", "session_profit": "100.30962800"}	2026-09-23 05:21:57.937954+07
832	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "f1cc944d-98fe-4f95-90b1-ac3a08564098", "losses": 9, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459970.83019068", "session_profit": "100.00962800"}	2026-09-23 05:21:58.574853+07
834	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.8", "bet_id": "7aaf22a5-b1a7-4779-a7a3-44261ef27f28", "losses": 9, "result": "LOSS", "streak": 4, "last_result": "LOSS", "user_profit": "-0.8", "gross_profit": "-0.8", "balance_after": "459969.63019068", "session_profit": "98.80962800"}	2026-09-23 05:21:59.207949+07
836	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "3.2", "bet_id": "8bc6f591-9eab-4c0a-a272-f3e00a98acd4", "losses": 9, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "5.076608", "gross_profit": "5.076608", "balance_after": "459973.10679868", "session_profit": "102.28623600"}	2026-09-23 05:21:59.846506+07
841	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "1.6", "bet_id": "4804aa50-83cd-4c3c-8944-a9c4cc2bd4d5", "losses": 9, "result": "LOSS", "streak": 5, "last_result": "LOSS", "user_profit": "-1.6", "gross_profit": "-1.6", "balance_after": "459970.00679868", "session_profit": "99.18623600"}	2026-09-23 05:22:01.645283+07
843	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "6.4", "bet_id": "8c9ada98-d3e2-4c78-9dda-6bb261bc2e36", "losses": 9, "result": "LOSS", "streak": 7, "last_result": "LOSS", "user_profit": "-6.4", "gross_profit": "-6.4", "balance_after": "459960.40679868", "session_profit": "89.58623600"}	2026-09-23 05:22:02.293165+07
845	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "25.6", "bet_id": "095a1d6a-451f-4f08-a4b5-44430a1fbcb8", "losses": 9, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "50.542592", "gross_profit": "50.542592", "balance_after": "459998.14939068", "session_profit": "127.32882800"}	2026-09-23 05:22:02.931813+07
847	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "48646632-52c6-4bcc-9979-83112ac9b993", "losses": 9, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459997.84939068", "session_profit": "127.02882800"}	2026-09-23 05:22:03.566042+07
849	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "10ec364b-df73-4d35-9f5b-1986da76a920", "losses": 9, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459998.38565868", "session_profit": "127.56509600"}	2026-09-23 05:22:04.199205+07
848	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.4", "bet_id": "cb700ab7-2fbc-41bf-9170-7d68ec7aeb9c", "losses": 9, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.636268", "gross_profit": "0.636268", "balance_after": "459998.48565868", "session_profit": "127.66509600"}	2026-09-23 05:22:03.883512+07
850	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "4e470ca8-0e96-4413-87fa-48085d8f37c6", "losses": 9, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.363128", "gross_profit": "0.363128", "balance_after": "459998.74878668", "session_profit": "127.92822400"}	2026-09-23 05:22:04.520675+07
852	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "74d9697d-94b6-4836-97d0-fcf2092656b4", "losses": 9, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.29712", "gross_profit": "0.29712", "balance_after": "459998.94590668", "session_profit": "128.12534400"}	2026-09-23 05:22:05.167491+07
854	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "34bffce7-c085-4dea-a82e-74e445947f41", "losses": 9, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459999.02368368", "session_profit": "128.20312100"}	2026-09-23 05:22:05.80655+07
856	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.4", "bet_id": "c312dc89-a9e8-40e1-9f21-4725ce00af24", "losses": 9, "result": "LOSS", "streak": 3, "last_result": "LOSS", "user_profit": "-0.4", "gross_profit": "-0.4", "balance_after": "459998.42368368", "session_profit": "127.60312100"}	2026-09-23 05:22:06.444626+07
859	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "3.2", "bet_id": "3438953f-54ad-48dc-a595-61ab300320b9", "losses": 9, "result": "LOSS", "streak": 6, "last_result": "LOSS", "user_profit": "-3.2", "gross_profit": "-3.2", "balance_after": "459992.82368368", "session_profit": "122.00312100"}	2026-09-23 05:22:07.399918+07
861	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "12.8", "bet_id": "c71f3fb1-d952-42b3-8fa3-2ecab8343404", "losses": 9, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "25.105152", "gross_profit": "25.105152", "balance_after": "460011.52883568", "session_profit": "140.70827300"}	2026-09-23 05:22:08.03785+07
863	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "4a9c9276-764c-443f-b616-de70051c31c5", "losses": 9, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "460011.61532468", "session_profit": "140.79476200"}	2026-09-23 05:22:08.676124+07
866	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	RUNNER_STATE	{"status": "COMPLETED", "message": "Stop Win tercapai"}	2026-09-23 05:22:08.999704+07
851	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "4275d207-edb6-4c15-979e-c7101345a312", "losses": 9, "result": "LOSS", "streak": 1, "last_result": "LOSS", "user_profit": "-0.1", "gross_profit": "-0.1", "balance_after": "459998.64878668", "session_profit": "127.82822400"}	2026-09-23 05:22:04.843062+07
853	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "9eff1a5c-e5b2-4418-841d-d76df2947bb9", "losses": 9, "result": "WIN", "streak": 2, "last_result": "WIN", "user_profit": "0.177777", "gross_profit": "0.177777", "balance_after": "459999.12368368", "session_profit": "128.30312100"}	2026-09-23 05:22:05.488314+07
855	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "6bd0d300-cc2c-4fec-9937-f1058ba3f24c", "losses": 9, "result": "LOSS", "streak": 2, "last_result": "LOSS", "user_profit": "-0.2", "gross_profit": "-0.2", "balance_after": "459998.82368368", "session_profit": "128.00312100"}	2026-09-23 05:22:06.124259+07
857	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.8", "bet_id": "9fe1b405-05ba-4782-b00e-37d4ac9f899e", "losses": 9, "result": "LOSS", "streak": 4, "last_result": "LOSS", "user_profit": "-0.8", "gross_profit": "-0.8", "balance_after": "459997.62368368", "session_profit": "126.80312100"}	2026-09-23 05:22:06.764129+07
858	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "1.6", "bet_id": "d3b247c1-96ad-4837-a40b-0a8cf9d7e05e", "losses": 9, "result": "LOSS", "streak": 5, "last_result": "LOSS", "user_profit": "-1.6", "gross_profit": "-1.6", "balance_after": "459996.02368368", "session_profit": "125.20312100"}	2026-09-23 05:22:07.082919+07
860	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "6.4", "bet_id": "bbd00383-654b-47d8-ae05-06664b4e6b94", "losses": 9, "result": "LOSS", "streak": 7, "last_result": "LOSS", "user_profit": "-6.4", "gross_profit": "-6.4", "balance_after": "459986.42368368", "session_profit": "115.60312100"}	2026-09-23 05:22:07.719288+07
862	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.1", "bet_id": "9cbeca02-d020-40c9-9075-215e6289e279", "losses": 9, "result": "WIN", "streak": 2, "last_result": "WIN", "user_profit": "0.186489", "gross_profit": "0.186489", "balance_after": "460011.71532468", "session_profit": "140.89476200"}	2026-09-23 05:22:08.356903+07
864	749	\N	COMMAND_RESULT	{"ok": true, "command": "STOP_ON_WIN", "message": "", "request_id": "583bdf41-ae95-428d-a832-d08466e06e39"}	2026-09-23 05:22:08.774825+07
865	749	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	ROLL_SETTLED	{"coin": "BTT", "wins": 3, "amount": "0.2", "bet_id": "338b6d8d-9c44-4d9e-9b6e-688990f43620", "losses": 9, "result": "WIN", "streak": 1, "last_result": "WIN", "user_profit": "0.28818", "gross_profit": "0.28818", "balance_after": "460011.90350468", "session_profit": "141.08294200"}	2026-09-23 05:22:08.994551+07
\.


--
-- Data for Name: trading_fee_balances; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.trading_fee_balances (user_id, coin, holding_pending, kangden_pending, updated_at) FROM stdin;
751	FLOKI	0.00000000	0.00000000	2026-09-21 16:13:49.789388+07
747	TRX	0.00000000	0.00000000	2026-09-21 04:16:42.544596+07
747	FLOKI	0.00000000	0.00000000	2026-09-21 11:17:38.728328+07
747	BTT	0.00000000	0.00000000	2026-09-23 04:53:48.267121+07
751	BTT	0.00000000	0.00000000	2026-09-21 15:57:14.598516+07
\.


--
-- Data for Name: trading_sessions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.trading_sessions (id, user_id, coin, status, settings_snapshot, rule_snapshot, opening_provider_balance, visible_user_balance, current_bet, profit, wins, losses, last_result, started_at, completed_at, updated_at, stop_reason, streak, profit_cycle, next_override, reset_after_pending, worker_id, lease_expires_at, max_win_streak, max_loss_streak) FROM stdin;
44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	COMPLETED	{"BaseBet": 10000000, "DelayMS": 300, "Runtime": {"BaseBet": 10000000, "BoomAfterWins": 0, "BoomWinAmount": 0, "ProfitSession": 500000000, "BoomLossAmount": 0, "ResetAfterWins": 1, "BoomAfterLosses": 0, "MartingaleOnWin": "0", "MartingaleOnLoss": "100", "ResetAfterLosses": 0}, "StopLoss": 0, "ChanceMax": "40", "ChanceMin": "30", "StopOnWin": true, "MaximumBet": 0, "TakeProfit": 0, "BalanceBelow": 0}	{"user_bps": 8600, "holding_bps": 1200, "kangden_bps": 200, "referral_bps": [100, 50, 50], "minimum_bet_units": 10000000, "fee_exempt_username": "kangden69"}	459868.00385268	459870.82056268	0.10000000	2.81671000	11	8	WIN	2026-09-23 05:05:35.838855+07	2026-09-23 05:05:42.018676+07	2026-09-23 05:05:42.018676+07	Stop Win tercapai	1	2.81671000	\N	f	KangDen-9340	2026-09-23 05:06:11.799439+07	6	4
387c7d27-dc7c-4afc-8213-a0910fc9de59	747	BTT	COMPLETED	{"BaseBet": 10000000, "DelayMS": 300, "Runtime": {"BaseBet": 10000000, "BoomAfterWins": 0, "BoomWinAmount": 0, "ProfitSession": 0, "BoomLossAmount": 0, "ResetAfterWins": 1, "BoomAfterLosses": 0, "MartingaleOnWin": "0", "MartingaleOnLoss": "100", "ResetAfterLosses": 0}, "StopLoss": 0, "ChanceMax": "30", "ChanceMin": "20", "StopOnWin": true, "MaximumBet": 0, "TakeProfit": 0, "BalanceBelow": 0}	{"user_bps": 8600, "holding_bps": 1200, "kangden_bps": 200, "referral_bps": [100, 50, 50], "minimum_bet_units": 10000000, "fee_exempt_username": "kangden69"}	24788451.37488757	24788871.01792809	0.10000000	419.64304052	4	22	WIN	2026-09-23 04:52:54.215523+07	2026-09-23 04:53:25.56048+07	2026-09-23 04:53:25.56048+07	Stop Win tercapai	1	419.64304052	\N	f	KangDen-24236	2026-09-23 04:53:55.314815+07	1	12
d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	COMPLETED	{"BaseBet": 10000000, "DelayMS": 300, "Runtime": {"BaseBet": 10000000, "BoomAfterWins": 0, "BoomWinAmount": 0, "ProfitSession": 500000000, "BoomLossAmount": 0, "ResetAfterWins": 1, "BoomAfterLosses": 0, "MartingaleOnWin": "0", "MartingaleOnLoss": "100", "ResetAfterLosses": 0}, "StopLoss": 0, "ChanceMax": "40", "ChanceMin": "30", "StopOnWin": true, "MaximumBet": 0, "TakeProfit": 0, "BalanceBelow": 0}	{"user_bps": 8600, "holding_bps": 1200, "kangden_bps": 200, "referral_bps": [100, 50, 50], "minimum_bet_units": 10000000, "fee_exempt_username": "kangden69"}	459870.82056268	460011.90350468	0.10000000	141.08294200	56	115	WIN	2026-09-23 05:21:13.463088+07	2026-09-23 05:22:08.997848+07	2026-09-23 05:22:08.997848+07	Stop Win tercapai	1	0.37466900	\N	f	KangDen-18240	2026-09-23 05:22:38.780201+07	3	9
\.


--
-- Data for Name: user_pasino_accounts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_pasino_accounts (user_id, provider_username, provider_email, password_ciphertext, access_token_ciphertext, access_token_expires_at, socket_token_ciphertext, socket_token_expires_at, encryption_version, imported_from_legacy, last_authenticated_at, updated_at) FROM stdin;
1109	SASQI367	safariglobal789@gmail.com	v1.pgthBxvP5NUGKwLO.qyeCb9m8gX6XX7BFyo85bA.Kz_PuvJ7QA	v1.Hk4BNDDKDMNXzbYJ.Yy-E6lylbD8OclwpAsSmjA.Xlu7wIsB7_pagwCMNU2zt2-MnLazTmhdGxLu7t70ru_JkBnmFa6e5nW53E2LGKpqmGCu_0d-BFrqXKGTIPdFtg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1111	zrlax01	zrlax01@gmail.com	v1.QjP5dVgpgPTK7Uzy.bHQ0ogaDXdZ_yTQLeJ8gZQ.k9RN8SR3tfNnk56s	v1.GJXB09Q9VtyNhlUO.se0UIIbJBF-BX7vkMxJj-Q.lNaKRo65dQuLepyixtY0XpDmf7rF6VLh1sRaTC-_Hh41DVGMWP5gLxwkf64Go_jRJyNYMchPrWQDtqNyFZjwcA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
767	gudangopit	Bpknana@gmail.com	\N	v1.nHgJgqgsQCIcW-r2.PsWJZgtxtu1JIXQQX06Lbg.fSXj8xb7C2hcRUM9cwXiXSLkZh3ELzch9wHTI-6zuYd5SRJiPGePGrr2Vonlb5yuGc-KuP5Ipay_INJAfvs9HQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1115	ryuboss	bdev88888@gmail.com	v1.H2p5m_bDncSuEgfM.M7l32ytPX4tIDiWts9KXcg.QG1qd_B9K1Y	v1.dwRl3XjqVnjr5ptR.imLBEj5HiI8hjun74SAIVA.ArAXxs6x-UHhuaowCOZUEukPSi0VN0uv7GQRp2QEJxn0ubJLeGBGIeDf_kpRMy21Je6adwaGwF27XIGRS1rA0Q	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1095	sakti12	sakti12@gmail.com	v1.daqohPi5kkgK0JXE.k_AZxPtHAo6ytkxCHMiFUQ.EQEWjRXe2VpPweI	v1.oC5YKYpPUjXrarm8.4Qv4A8HBp8EkfBBhJM3BiQ.PRNmaacNC0sil9fc6D7JAMAKDyAY6nlYQ5Pn9nEe5WCKOByvlWgbWNjVylZgkcOM2JtPiVFHJybspyvaJVQtLA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1097	sakti13	sakti13@gmail.com	v1.v37pxSGWd3ftd5Pd.t91GNRwI-VtrQe9b2UV-Cg.dAAJZPVNFzA2VYk	v1.Yhj5GA6mFYwCGfNo.vJOEpv72nOO8tXrlIoJ7UQ.vyQBwuMqr0AzPMRKPNAof95ccYxubxJXFA6z7lDzCL6a6t6V3Z6zn0p4Eb4Y3MRdRJocxFBOxI1ocQQcKQhEdw	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1099	Bangkaben	taufik0001@gmail.com	v1.msPihM9r71AvL-zz.8Hugo82NYYFM9bGTdvR1iA.S5O-kBENp6I	v1.-cXgHjXL97x96fQI.MJWRjs6G2600HojsGM1hSA.Lf-7-H7h-Wf1Cfe94Vb6QIizTiRpmlunt-b-g41qfotDzOjXFE6bzHcz53hU1YCRnKmh92BBr-jRw7K1ictiXg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
989	BERKAHONLINE	berkahonline1978@gmail.com	\N	v1.r07RX2B8YuIfZTXX.Dty9dzcetQN3-BKJcKzwTw.SHS0NPWY8apIn5d3pWU33hfsekeE3Cc5VfuBFjn26T9SriYYOWRBCsUkDFlIw5LAxcbGiqeWGLX6eMZsz2D-cw	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
929	Ar99	rmnmn311279@gmail.com	\N	v1.g5NQZEXUIv6xDFy8.16B4jNuj90wWyII_mIn_tg.EVf7L_21wQ5JhA3-BHqOT4PTQsrMSjQKRkf15NtzFhgF8z4v2gg6fpopnYpBp8JCoc-AwZeVXeIoIP-ZHRYUHQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1113	cuandong	hahshshs@gmail.com	v1.IY7I0xdKL33TLBYs.YG1B9iYwqas5Kw1P8qNGXg.lfCVj32Lwes	v1.e9ZSsr-p3nSFj9_h.5i4BlYRGOE3-y_8DJndbvQ.TCog0enBr9doMkKjxbdf7wZP-p5bhLzJjuMZIjpaYcZPh3K5ve_51ETv1i9uejjtc0iu4EFjkbtRTv_bbDeFCg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1083	isambotak	hisyamalgifari8@gmail.com	v1.1QH45KKAGoGQf3b5.Sp1b0NfSA8z1pY1By9MVUg.r-tT1Z4M9kqQHw	v1.9M9ikFDhmXN3yOjq._KlFuBM9C9foddOQ4OwQaw.hYnhtDVm7YTeCkqsO4DB4bZAJNA2ZK-MTTKksuv-i9LmZlDWwnd9oY7HSpqDFwmpB3VR4sBWo77vjClRFKxSog	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
863	rajakaya88	selembestore7288@gmail.com	\N	v1.Ibe9D1w4iKlRf8YO.jwlOCYXnXobygTObUkY6MQ.qR5TjdNyTLFVK8uC4W5NL-YbOsoEC8FE1ltIvA42xagx1u0YatlDu24xVvIX-pcw6of2pGASCN9qWo0QDxI4ag	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1105	Evi2909	eviaswandi29@gmail.com	v1.I2qc6nX16MjPVfWi._41YWIRoX_4qQ1sx-kmJiA.9Hpe2XWXOS-kCxQy	v1.kaL0cWqmG64Dqbhn.MCIinXHSsYYcjytEvcovsQ.kCxF8wam8drcJD4O0-B-c8q_2ajOBzKG6M8_jpRArYQ7E7T9Z-Va_Hm7vdM_-FBaSQW_rvOdbwusSolaMYNqdg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1011	Zoelkifli88	zulkifli051@gmail.com	\N	v1.a4g7j-P6l2w1DVxA.bk4F2-mvCPIb7BuAcOpksQ.jhLLf6HcGh1hbxSF5hXmOFZSL9QkFfHWQTm7aArNcEYJqm5Y97HJcKA7CCxv_lnkOGnExqD-1AQIRQcDr_V3JA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
959	bangmanfx	bangmanfx@gmail.com	\N	v1.WfpEECychnGfNlzy.OEKOZaCJtsl5X6LoQikdZQ.j38XGACjnxjkKcQ1ZxdGbpOfkV0oin5tUcR5OYVGE8UAFDp5FHG_JPaNlw-kS-OEaafG0JnciRBTR8S_cBRTHw	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1103	Hery1074	heryjoyo74@gmail.com	v1.D0ZvHg-B7y8IYJRF.SrAzR9ky2Hxfw1G3gOmY0g.junNRjw-TAsz	v1.U--vJ4DQZFmVqC5X.5dc9ZJUJqZZZ0MKC7Xih1g.D0XduZoWiMNYqQ9kSEw6opRhiGwsRmct_LnH8ilvWw-eYr6XHmRFHQUpJ9jLOJdeN2JtZRHj7t395ALz2DEewQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1033	Hastuti	zuraidahhastuti96@gmail.com	\N	v1.jme-j2HYIO-OlksW.oBwgKJf3SqAXOQXBrSpVdQ.gkA5CUwWVEy_5oZh8cZikbpJo6zC631DJ3PlF8-ASy23V1Ndea0t2qaND20sldLhs9bQAL_QzFLmaJ8Sc_OVFA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
987	Widmar888	madona88ptk@gmail.com	\N	v1.IEqgn8DnKUeysp79.bv7h2Cp0MhAX36-Vz9w7Fw.PXLFQrvwjc2Gur9JAftcWvUKvWA55aNV4OnyN2-33V9FU847TZzDEQTTx7B6HRJS2txPWfNUQWSojvPk35tuGA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1107	SUKSESBERHASIL	rejekisupri14@gmail.com	v1.faNy16KEAgeXwxqM.HWA8fyXtP20UwvGIfFJuXg.8jtyLS6ASwA	v1.6CjzFTjqCTCK4DaY.qHbMyDR945JnuaiVezwWHw.FTRB7xjHCQJ_3j6UY2ZfYS1qnP61UXU9vdu9BRdw7gsk-n9cshs5NWGeZW208_WqDrOZrDtNOgSPjyoj1o2EdA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
981	renisanjaya	renijayati271@gmail.com	\N	v1.5yo7s0w7N99bNFl6.YIX8HGH3JBXJn1nl7-6XzQ.CHlQb5m8CiGG_MKLRxIpyPN03SS52Usc_FqPWF4gyH2s3pzEm13MHMBJhbMmSJT2Z2J-qMfj85cpuclW1xTupQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1093	narendraz11	zrlax013@gmail.com	v1.PI8x_7yP7_b3lSAc.BWSWksCVzxDqR7oNDxptuQ.nGOyrqGeMmgg2jLW	v1.CsLG9j4AlzRkexj0.l3TnMv_GUIo4nh5IyJw8cw.ahsDsC0MGWingj9Q5JLv_IvVq9tGs-ep0U3PWlK4AEcv_-QsAHCq5Ra9LB08wBU8vjmWqFhZtcCDXsrPuAb1Og	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
793	BLESSINGSTAR14	bisniskudahsyat2025@gmail.com	\N	v1.jp6sFUVLjRypqmRZ.LuylGhg-wHmKY_BpJ-yx1Q._9ZacuojtdrP_jY88eHXWL7JAykmeQucLXQWIhJTlZxDAeKntzewGACI2oGZxGN9uWv3z2hThPbOvgsKV4o2Qw	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
847	FULUSKATSIR	sudrajatsoni@gmail.com	\N	v1.WI_BtziqA3wnmnlV.ePC7NiHZnLGbFCBKcgTByA.Ow2TJoZa8gM7DvWh4rmwPt2lylIdZ1SQtPxuSK0cB-qSVJiIVkUGyiYk1S53I3l8QOWF0f_sDYkBPMxe1_ARuw	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1101	Permadi	adhierealme2025@gmail.com	v1.CP_Mw3IV1hT6w2jl.-CHUOaaM928lQNYerZ7GXw.AKds0YqqpvZ9	v1.uJkFAkzvs1khRz1D.vAuP-xa0Tg7ar1haEGpPJw.T3cJbsevtWFC4SoqIgV6brrZJgF_7nkof6vZ0KqAk_zS4vrfpZY93M4CyL4QX37iMgNZ-HU_J_GoncBA-CQB0Q	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
919	Obet5893	obetla7@gmail.com	\N	v1.MlnsG2cdhiF0mOiv.jJqrPjF70G7NCiEqcQJS2Q.eZQpD0Vuh7SSBdCX0N7LGB8GKPgXZ8xEqBsLhHjL4KHBrevuM3JPpQAYri_APiiWVhoxJbjTE2iHq2u2f-3fWA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
937	Putramandau	dadiktp7019@gmail.com	\N	v1.Bh0xmr53gVWOE_Fm.DZUivhI_XBnYyMXZul390w.F6TSbbfIWWLIjxeuJVrQL7OVhb98x3j7V2wM377SVkF5jG-pZnkgKETBVv_lKPNOr98d_Es-QpO04G0OY0Nitw	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
939	Marlinok	sumarlinutiarahman79@gmail.com	\N	v1.bu6C9MsaLFcyON5k.1Ak1jop8nQ6a6uXtPiydlQ.Koo_BiPzgRqCsiAwRjrrVHVhKO3Q_fALC69KmyL0R0nMA6dmJBLFyKrlnzMdvZd3WfxbIYEER6ciJw_piBgCIA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
941	Nirwana99	andisuryadi790@gmail.com	\N	v1.JvKJHgR4qswrH1c7.tFQqLjFh9dPHt8VNp5pf5w._mygSngZXp2LdKgM67IJnUJupHcYRdMXRQ_3I3we9NL4bwXBvGJqQnQObRsF6Ql_1EeY7CFBKajVQcE3ICrIsA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
943	Mraj111	Mrajsingh707@gmail.com	\N	v1.BXgaN0KMZSUGr1r1.UIlOt6I6DweMy6HFgdoZdw.Pfa_JTpo2rvw4MmU42Xjdt9FYylBHKM-K_MjtN9FikSxrKgiWfrX-5nSY5FjPocGXcliDb420QfVMTMk74Lj9g	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
945	Piko99	tommysunjoto66@gmail.com	\N	v1.1qHVA4xo5Y1N6cf8.O4kwbcwFWEefHgRsI_odCQ.cc0Rgob05TG_tyv_GTRn87p56gag_zUtKCJ9cet1l2WyPapNh4WahjXlRWlhYiIKR20sGHyTDx-8_xa6PMLCTQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
949	Lifeisgrace	noviiswanty77@gmail.com	\N	v1.chWTVL-zA8ZwlCQL.Usnxbhv3nTAFbRlHvZiS3w.NH3KY3WAumXWtdCP4E2faxEET2jW7pk7n9G81H8S-ewyjzS4N_V_eUB6ulvzJUZAKfVExl4XehqI1zw4FuOuQA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
951	Kingsaphire	eaglemalindo@gmail.com	\N	v1.ebqAbJl9NhqL1ogi.1llMGDiAkkiv1AT7hjXYrA.KCkj9MqXgMm2DDFUzqB9zVovS-TQZEcYYYigz0bSdTTa6CrMc2Le8nlx8HhamCNDww5Ni_RWjnEWbWpsbG_9xQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
955	RoyalAndara123	vieyandra@gmail.com	\N	v1.O6MV6PRn9CWijM9x.DAzzJbI5kuLgBP6wnJGfNg.dQ08sjkyRIMGXAsofOy24rzY2Yu2iQOovV31U42SZDigVQAJwXRx8Wb99jvcfeEFAVHmh8oVEUisE26mJV86Jg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
935	bianc	rmnmn89@gmail.com	\N	v1.9RLDrvUdJSXdqFhJ.SDGj0YONt6qGFA-Fc0nAdQ.G41gg2298Fmws5hsF1NX3IFaO4HPLezkCSL_bRUjCJoc4brMVzmZo0BFBRw7raiUOwfiWplyooe1irs-F1YQdw	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
961	Hermi01	fazilmaulana728@gmail.com	\N	v1.R4nPuJ_eXt7wXhLH.HQ2keJ9qZibUau31OD2sGQ.NdBkOLZ2L_6R4pGT8TG2A3sEyY3imuRv5KsO-zQ7weH7PxyEkUDZVu5LfGNRik8fV_PkNO2g0zQOFo3a2mudLQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
963	Zumbo23	syaifulzumbo23@gmail.com	\N	v1.vn9AKhc6ec8IFUxr.hXEf8pvbEdXpk1fUsxdJqg.LGhGCq78BEVzBqDtuSOUvSG7z9jTezkW91yVayJLDCxvLDzh19JCvfpxnXzbFPY19HZd1zvVNizs6xM8HEhcrg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
965	Kudalumping	mjoshuawijaya@gmail.com	\N	v1.0PfMZDb75-cagUva.5a_a8PjZmzCnyNGHOAlHiw.BMhgTJpjitpoCo9GfzLAl-YIo03DnW5b6gcbGfN-mAg3YFJvo_emiVpLYizkfWaMKh6aM5X_CiAqQJQALlWsZQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
967	izul1976	izul.untan@gmail.com	\N	v1.KPkbZCRWnDD6T0wI.4AJH_0C6qP24OiyMsetxtg.64AGNpLbvkr1Oe-szbpITKMehSveM2FsWnul5yZL4KcQgHyE4P_XKgQNh2PgkDp4Yk16bvbwFw53gUEESiXbpg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
975	Renisejahtera	rherereni140@gmail.com	\N	v1.d2xAKes_1Yjv_AVg.DiQB5B5bs_kcAkRCRkbqCA.kLkRKaf9xzhKHa8o_C0hH993Ss42TIZXU01gIw7rzQVS10B2Ab6G8og6zANsJVC5vp9-ccOBrzF_eRspj9q7gg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
977	Senia99	ptski2024@gmail.com	\N	v1.hjgUKN0cUx76ADpk.LLncs5L9KMA4_4vNwnzaLg.tudGBQUdUKJbvYehpWLI94KObw8BiNX3KXYu4FqH-uSvKD4jeGBvG1cBdWiTEKWkyjP2SnhzvlDrLnPgR2vIeQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
985	Yulieen	yulieen48@gmail.com	\N	v1.tDVyvgXOg79U-23T.XmWIXMpdLxnvoCl9DN0hGg.nX8QSGJfPf4Vwh_155hCQrFz82QzZH0KWM5iVRp_gGc4jQ7bmGfM1VQ6YJattiWRrzgQX5PlSZQ0OcogCLQg0Q	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
831	GUSTI58	nesiasuper@gmail.com	\N	v1.T20TNpUeeVhQwO6t.fbeluN8GFF9v6ogzKj870A.Zg0GZB961mWPhmXTQ6t1_eMOjKAHhQWyfZQH_Nb0PrHiAGy7Ixyj45HFu8HyHxZLeZZPgs6CagHLFo_D1MRS0w	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
991	KINGCUAN19	kingcuanku19@gmail.com	\N	v1.588zBrVpixAjvfKW.6YPq-nNSgBeDhX7M-3dckw.xdO_gupjmWD5CMzXjoTucpkvw1jBM3A8LonO1ebPsW5YNVcww0BFJT6nOsCEp8t_XMTgR2dLLK3ssZqmfve1rw	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
971	Nuruldilla	gadispontianak79@gmail.com	\N	v1.aNY5u7HvIJfQAUDK.dobUfrqRc15dnAJel0nm9g.lMoMDV3xHDiotqh61iI3nVX-rrsisv4zSSlSFyw1OVEQhO1hT6UytnWA0bU6DlgeU91jPsy6ttkjU-6t7IBDIQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
997	Golden234	ariepp5758@gmail.com	\N	v1.kVbQW4I3hzkuvwsI.TkU9YhBDwDPL9tAT8PPvRg.NAUU5mJt4XX6U4vrzYq_HQNNuHo3ed61SPhsRDriN6Zpo8NJW2sYbLbJoH9wpePRiiBjbblklOvFTEWShwuxTQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
933	bi4nc4	rmnmn234@gmail.com	\N	v1.03nFfAVPG1jmNnkK.5qn3ctTWhBbzks0NLbd5yA.m0ZPCqFYTjZzW24R7xBcj87oXqfwFxGz9SUKEgifelNwTLf6D2cxwPby4SVQRYJ0Ub3WPrmvdxjBvXu-CKYudg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
973	nitatajir	princenezardmahmud@gmail.com	\N	v1.pH6O5cgF6AhL88X1.uusqfxi1i0hxa25L67pxqA.JoZGjZFWy-lKyhw0hFc4IBWep9qyWUulgfFKZhzcxQu2X4ueAIXsMMwEZTZQrRR9_-yhUn6tdezRlD5tGIoqgA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
957	Kasmawati73	pesati69@gmail.com	\N	v1.n82ZTI9v54ooQ1os.OMibt7a7DQ8cGpeFwFRMyA.i-C8rPpI7bpXHEm57MXIX57vnKxXrjXwIcA5EBkPr2BR2TTGReprmfn5wRAPYWIt5Qktu9jJbP4hEKmuliGzbg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
947	Sehati69	supripst616@gmail.com	\N	v1.ECctrqVTrBkth3QG.iinHIZlGMhmeqoTDqh4_lg.0y4lNmQY4rU9d7vfBBqtG-FIhwGQRtDix8CIY9Uolq-eHDHNoc3QqO5JQjaSBIK-vthzDk_wf9ELecms-urtdQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
917	gokong79	herrylung7@gmail.com	\N	v1.FDpdaZ_4hviux-IJ.IuGqCmsUchB-hFxmVgBLfA.5IyxwwHoVZIIq_aYLpBWndnk-xhp0V6mkHk3hIYmSLOxcozbFmeiwEbu1Bp6trDVqJpgQTg_nGMMVeUal1FJMA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
953	Adek12	adekosnandar12@gmail.com	\N	v1.6AAM1hFdobZ0mjaW.VfWFO9v7Hmx-DTAu9Q_ByQ.TA0S4h9_hHWtl0wzDEYbrLbXl-aT84gXQC0NXLinKVRB0GNp8wO-ChhI1JjQbzqPAIXUPiaHtvhsJSm6IPTnJA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
931	Ar999	rmnmn432@gmail.com	\N	v1.DgSn2lp3bO6Tfq0N.RoDeSPI826FNPga6d3FNWw.usxKvkXxIgcNOkQZ-xTmnt6XbNHX38_QKL-OJt-eE3iqdI1QgeedEtal1I1lb-XnfTAUigC1lDgXrq9GFRMZsg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
995	Ayukomang001	idaglx288@gmail.com	\N	v1.pEcRi9Ot3hoRDLsh.QJa6GBA11ZwJSBh2Wwb_cQ.KD9rC5O743ywNjkwW7yCwr-iBxcsOope5MOVg5qpecrbpXdcQcFqifssQG1h7ItiKXz8yZAJ2PObDVOuRWERkg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
979	dwi28	samsunga32121112@gmail.com	\N	v1.CSxNED5rcV-7xVzz.kot0JLJ19Qjz1SIAKz4kYw.sMMi7kWFEmisS_LfhG8AgOTxEElkv7RiL7utRKQllvW-mxURJo8Yxvl-QRnetndtaBVVgEJXahGpeJCpFiG9Aw	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
993	Fari789	safarkakap26@gmail.com	\N	v1.U1dkTQvAn0V9sDNM.zcmFVBQqIBsdGFFKgbOSbg.xDv5T23mqznmLc7lLdNgHY6jF10yMqo60MHhPgCPmntcFmiNSdWudF1OEVDkiLWd3uiXBQoMRlHYqvTbpOJ_Xw	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
999	Rikaraisa	rikaraisa88@gmail.com	\N	v1.z36PQcaG1D0zsl6z.rjY-TteNSKNMGDJsGmoLwA.trSDv4V1ibst87Gz_-8_Hs-OOjAahfUXoUmbTgCTXsd2hS9BvTrv6vC7BIbZknCLq6pQpdXZCQhYdiWyl4bFbA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1001	yutt	twobigbrain@gmail.com	\N	v1.xhO30L-o2aM7R6vj.cSaGwLNqYRko7gsoqDrqDw.UomqHI757FxJCQF_N0u2_VqoPydgMwbtmAP-PqZdIp_yfzWQucni7_Wx_ttCpqDcXI4aNsADa04H7STtDjhb-g	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1003	Pidutt	poonzai20p@gmail.com	\N	v1.ebeikcRzDRB3Qp_h.bYGA8IKa2EGxcw46KuXVDg.mlBaDU9my_RQY3-VxsFndxoL99pdiWclfLJu3OPrx1z48PLag_ovhEqeKsj0Yaz-jZuvQLZN1CJA-9yTK4jU-w	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1005	Yongkry	dermawans926@gmail.com	\N	v1.cvdBSSa5EkMStdIN.-Ab77qLK-KcHX_levtTdhw.Vzs9VKwVVRCBCmVK0mdCAX_4VJnr6lO_CeWoWJ4w3-szMwyfNkPI6uxhTw16cl13i45_ERFcEfR1VpGHcSx2-Q	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1007	Sukiliar	nuuxyou5@gmail.com	\N	v1.7SzelaXkSPF3JY5W.chu9D6TNGwqbrEQEA-7nUg.NW5wFEYqx16QM4x9tl9AqCYMxh3HlIaoYT8s7ZQqysy3dF9jhz2Romh_wRN4fVz-Oo4FqooYD2DdYVFcFl4O2A	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1017	SASA88	safaripcex@gmail.com	\N	v1.R48gHWClBSDnaTnO.ENLdwc43OU_ambFqIYDTag.b2Ay8JQ4PRMaBJKNLKYlPwdhwOmBfKYrWFLpstiFkwt643tYbfPitBN2GUu4uTyP0bw9yGpEqidMWgp4VTjRyg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1015	karetlestari	barryzainal79@gmail.com	\N	v1.M9nUQK3_CoLTYqSC.kJuYiGimSV0_BZgZG_1Now.AV7ADyb3Jh0x5_Wh2NtURuzcq1d_269PNuPCSl9u5pc9SIE8_JufqFD3d5Nafen-6zzVP9p53mH35abEJL570g	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1027	Sejati80	muhammadsablii335@gmail.com	\N	v1.zUq6pcx3k9aCBRX4.7Zo_Eb8wk7h_vTB1VvW7Cw.LIWwuvgXsWxIHeMMNqxIDZXbIIuXUyhWbIdZo1tLA9MRZpJN9sKmvxMpEA1RcK2tgTGBDezZYwgwLI6X0_H2Bg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1029	WULANBOJO	samsianizainwabula@gmail.com	\N	v1.X_rXCJcSYX2igo1Y.bY97ONe4Pddwolum-MMhKQ.Wyt9Kiie7OQ8pW7cCiT-_dRT5djFDYX6VWK0tdeOP6qssrzXMb9ZvlzqJGUkuKVT3D9wAoMMFb2KW-fClzJ2tg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1031	SITI99	sakirasakira157@gmail.com	\N	v1.W4nngJRssZkiTF_W.x5LEpW9kxxTJd0qqk6ts5A.10VBlRI18HctQdC_mYVB4ijfSTCy3Du9VNFvdpuN_ewCWuPXkBMMEBazHxZOOrr6nM0CwfOuQEj4xMUF7m904A	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1013	REGISTERS	norqamariah21@gmail.com	\N	v1.yKzDNespVDZmkVAv.iSJkMnLa1Ej3vWItms8Ykw.S2zcDH5FHjT1YYOGhTqGGlkwS_LWpASHSE94cVnQyUkbiRG-3FxGerz0exNCEwFnizVXRIVxKHpMd4csaI5hHQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1035	Iincantik	iindendi260818@gmail.com	\N	v1.lDTn3rVvnsKc9hTM.KtS4YpR8y9qIu83GslUtWQ.76DI12U2qqbR-aGEmo8un794iR7HsgB7hGeJztoXtvUzC_vD5uZvdCJB3dTLGgkDsKwPsFco6wm47YaF6UrILg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1041	jingga235	warnicerah4@gmail.com	\N	v1.IdflwRA4xtKXGg3P.rHOyDc76JLoVWNEcDV-Z4Q.ioCZb-2zpgfCxmZLToK8_aJE8vcxsLcb5ZNTiMGWqJeI2Lt_pLb4-GKAwsf3dCdnv2uS5wZ1ezU1jf4naJg8CA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1043	Pcx99	suharalfathan@gmail.com	\N	v1.AmPjwYSAf-vCJu4L.Ckpi5xEnaRUJniS-wA9DLA.BF3Zv_-qllGd9XJuy3XC_cg6OqppBDR0UGYKfbC-wp8GPOjCsfqPkGZbhXgzCGu5j9xK70eai-HLMcO-1UbNlg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1045	ravi11	ravi65saigon@gmail.com	\N	v1.VBkzvaxk4AjjK5fa.qyN4sqsmwkgZPmGavcbQNQ.VpP3eYKqlZK0Oq_m3hJK74M3vVG3DUeQazKa1VhjRkc6aVMdS1etrhpkW0_5f3SJcnhAwyNJFbgg239pjI33BQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1049	Hasbieuwais	hasbieuwais@gmail.com	\N	v1.IRPl0Ckb3Cd8fHlu.PZWIwS1nSPRlxB8_tQuo1Q.0UpscUCzkFKLCOB4FEcY5iMqBdovN-Gmlr5ohe5ML5MdKpzbSJsDv7n2JOf9vUbH_fMSbP82HnncL5aayxcxXA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1009	almusaid	asyari.almusaid@gmail.com	\N	v1.YM_1EjfnIbw-AmU-.KtLbFEdZ0x_90EILEGxTgQ.V58QvmLNsdUuTYhCAA7F5wthzh9WZ5ifjCaXuCyCh0JPFQ-5v4N8FlZCvPWfPOX7RnAFCrNOfi9pYkjNsSLeiw	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
755	Sukoyo	sukoirmt@gmail.com	\N	v1.3xd-gYltdgNri0F9.uqc-LycDYKJ6WmSOLEFpDg.J5tM93NvBO6mJaIQGxS1_25GWplfi6A_H1BICcQhN1Z17NJlD9DKGekrXSgFdGSjb6XAGmXEe9-08Awe2CssYQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1023	divadollar	nurhalipahnurhalipah110@gmail.com	\N	v1.f7kyfsdyTlQivGG1.zs-oOtqPDQmmfnNRAKd-kw.jPDc6gF6cVxXfMODXKlYBqvxQ5ZYnOQpvJrGMSE_jOLydsWSdG59n9tnUqEmH80WkHset-7kOIkltoahJI4tQQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
751	smartrich88	rajaduit369@gmail.com	\N	v1.S_j9l4DE30zmBs2_.CaABDu6af7MgIGiUnuSA2g.7eSzJhDjmPKiVyxIDTrnd2GJHe7jXKEWk8BqV-SFPedUusSqTUNd35ffinmbl0GJGUd9eMTW4hMftIxoIyLzBg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1025	Bangde123	pontianaksarmawati@gmail.com	\N	v1.LPDKebXF5-r7tuH4.LKYvq119QKi-DHnvs1R2Ug.e3IOhe5hJJVUS8mm99mOV8xstnVNpFlmcKMqad0tSpnwRHDUnuYD3k3582Ae0YfAqP_SYmNZC-9ke6y2xqE_Ig	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
771	Din6237	liza79@gmail.com	\N	v1.0uuYPWLaTksMm3gz.cUYIEek0C5zQe1rV21jsPw.ttnnhdMmtByF_k-fuOfNRiGup5FrawTK6sER_PjjENPLkfKHmUR8HYZxW6hOr53aUN80LXQ6f8-yeMbwS60SnA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1037	fadil111	fadilputrafadil879@gmail.com	\N	v1.nOUU0XkOZxpkFPGk.HKDSq2JU_NNYAymkDYYFaQ.a94O8C7nK0jEfB16RjKXRFCcwLBjnisSm7o_hOmeqzuN7FW8HAWG0uRMy4jpnWAtx9HTszMf1NoHohtqHiOSyA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1047	Greatgirl924	javeedsanam4@gmail.com	\N	v1.S4FcVHhB11Swe5ET.FB6IrRxNGCmIDILqdFLHKw.ljtwpxTGiZswXzfj3pQyxkmP_KSp3-oWSB_hCmYqEyPTNal0FDcFzvSr6x7zFnWWc_V0lcuEZve9RMXBsLKmzA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1019	Faren	goggleid62@gmail.com	\N	v1.x_h2b14LfmlhgqPb.J6bZYBmV0U6twvoN8nxnug.b4L2CD-TXX2h8z5SE3H3JBZNQySnTDVpHuPc3-Gow-oF3nm1aSY2yeutbS5YFjONJzIP9vHBa5k4DKh7lSxm2Q	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1039	Faloga88	falogawijaya@gmail.com	\N	v1.ol8HtBilYk4Z5Opx.Bw1vVN8yaAewm8o8F39BAA.4-cYsglocF3OLb4Kam_1xIcYIf31jfWm5Tv278ZgeH4pCAzy29WQi6Cc3DiYgzTDMISd5Sznm5NkO3xkACmfJg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1021	Mawar81	agustina311024@gmail.com	\N	v1.KE91ozRShyWNd7Ep.pKf56WrdTP3MpZUBdPGIzw.dNnSUZs9lSRKt8NqxRJRymN_Gpw_P9gHtMOH23FvYGsxm7mImtpigJMAsXBTYqcXuBqqY0BFgqloCkQ_1rhKHA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
781	smartbotapp	smartbotapp@gmail.com	v1.B9gyjXuIpMOhJ684.ghu8hi6lFCdapaGFpubi8w.Y5rLggzm00U	v1.SV_UUGSBIXw1q71E.Zpwn9I2u29XyDGl-ZENsug.ZrQWQ0XpWBvmz4e97w8LQBGeOyuL1Z3SLHhxGUvrQzve90_A540uuSx2138Cjw-SoGT76kLP9zmObvTCZ1OKrg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
859	Koong89	basunirindu237@gmail.com	\N	v1.fFBmI7-nne74bdFh.HaMWKzIJme_QTQJ8O2S3hQ.24NrcytoEL4Xx9eT5Fw2kRBvIqX_XHJhRAsl51xmLb6uXgALjzwxNDWcoJGkMOVf89P74VUlc7jhtcW1BU7p7A	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
799	Yudi_Bangli	yudibangli78@gmail.com	\N	v1.R5X5MvkQDeJgQz9l.JVFqvO67kc5bmI6CBqAI3w.VrrpkaY-hIc7vBd9WeHyHLfERaW7WPlT5f6ABogos9P8Lug4VWwdYdqg_xBa9Z_6zqnf8U76J9B-qAv4VHAD7w	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
823	Ichsansukses	ichsannurhakim63@gmail.com	\N	v1.kH-lGhkbwDmBb0ZL.ulXGzyQyLQ9wLq8DO5yYPQ.yDQmz5McdAnM_o-yu44R0Kvjm-9dlRovxESQjaK3ZV8QshrNb8BoOVRndgjOqWkwtZXQUZlLZtxxw-XFx8cehg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
867	RICHMAN99	dedinetizen3@gmail.com	\N	v1.xBXj8hf5xF94HYbY.3abOa55MjIRO-SU83yjZhQ.Aquc-46nvbvn8iBH8tSZTRb_ZYfTH4-0_vUV2FIGzsOVKUTPl2qP0k6hGQY5VlUSl_TVJP2KpSZmuGPPJTVKgg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
883	Stef8844	haryono8844@gmail.com	\N	v1.4iO2_L7ZiC7DKmcM.s5g_CK8Jb7x915-9ZDf8Dw.DH7HCNWCI3TkwCgIX3eYXmxenW8mfCmvtI3AhPxSrOkomgb3iZ2RKexq5EBD5xZxZYaK3GD__LEaVVYF4eslMw	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
903	MARTINI56	martinisri56@gmail.com	\N	v1.P0efWJAU1CHKXs2r.J8THC9V0xzNY7zumFrjYJA.4YF6dopfZ7Bl-J0GuparESFaJCFPwLZv-vV8UUww-l9yoVIjhF6pckkM3lH5xpxuTzDk6QjFMl1QpBlKxSxx4Q	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
891	SOELTAN99	abaa80569@gmail.com	\N	v1.oumE3mvvfhwYKE8v.AkzhXGQY1pPbYrjM-zde_Q.G8xI7DGzXk_VGxzdfWF1sFGS2zsWNPPBi0AToHzc-C-dTHuRmlj-fwlrRmpW1eFEDT1FCkXieRAGU5aHL9EXFA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
969	ayahfeeza	ayahfeeza@gmail.com	\N	v1.LGpPAKUBcgxKvVjP.JHtD6EidDvCldKVO6GFz6Q.DWxUyxgQeTgRksPbtYRMkcrrfu9FAYe4GYaMsNFkUIZFRipYibxJdlWXuHBV9P0J3-ul0s80koCNrUpuL3ebeg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
797	Abah67	eyang.anom1967@gmain.com	\N	v1.wz5YmO2lgbbLxgPR.6FLhdTNvbbuLrnVSJBY3Qw.KVTTQfIBo3BoDoIai0FcGj72ubXnjGh9gMPlTWQNiimDOiifoNr-MBkPHhChiREbqaZ7UmhMsoyYpwi6888x_A	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
983	Ani77	dwirahayuanggraini0909@gmail.com	\N	v1.KZJPPhfJ-RKTl-0I.3fyHt5r5WnhPYX7vSZev0A.dpJkLdiHEUfwNHp5xCgi8gzzT373JTCqxs7DhBbWVC8W742QdT6gcxZGwrWpQd4qQirWi2LuA_vn6PvPWb00_Q	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
887	Vidhi71	widhiyanto210472@gmail.com	\N	v1.djPU4H4AKlNIiAU4.3n1EdrKdDPOuv-iXrrnVSA.KNphm8oe_uFgRc8CLrd3PK9c0u9Ky-vYhCBHYHOB7b9Sv0vFsx6ZOOrGoIWk9sngGy6vj31U9JWA7RafEKMMkA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
909	sudarmaji	sudarmaji@gmail.com	v1.x-071U3CiWTsoOTi.6dHOzROVu0fMzqb6KHdQWg.CnHoqeHRosI	v1.kDdWEHpsc1g_TmxP.N_5l4xKEUOPa1kyNy-nxaw.94pD2oWAsRnK-VRPmt0fSYMk7bFvl_l51tV8vl7YGuRc0M1nhFjKFZ0kV598_xMEbL-D86mkIkOc8QMIpr0B7Q	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
911	smartboss1975	daengmanurung@gmail.com	\N	v1.XxYDWH68DFcXbfGL.JPzMm0knBP867g9EIhGZpA.9egoKbp2YXfhdz66os5cZmFzdcJnkDX5wMbFvpsywq1sKqnNEsFms1AavA5VUBl78ub9nIUVxnc2M9SbP46LAw	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
923	saudagarcoin	support@smartbotapps.com	\N	v1.SOBNci_ZDru1O4iR.2t63PRjK9djHAaov8FiQrQ.6DHshM4WzD0ujvwRhFYIimLP9SiqGd3MWFVs0ose6wBOcN33KFrlsIoh2FQwkqTvTcWvOyRkZUbQ9MFdzJwdLQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1051	opryuubot	opryuubot@gmail.com	v1.xQdHtLk4Z32jqCD8.TbhJNwHHkIqabfLQ9E6-wg.Un5R8SQ8pJA	v1.Cw0tdadZ0kWHH5Md.JPFvGOnv0hDYhW_WVq9iCg._WqjMlPoL1FLiAPu8HF-Wnw_56jQptErAgiOUSR3Bns0tu7kfGB5rlyUbawf0LH8utR5D738n5fte5F7VS6Ang	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1053	langgananbot	langgananbot@gmail.com	v1.kyaF2HWexw0MThb7.uvCjLRjrWFhzSwmH55gvlw.3EFPLs1GA2w	v1.1RmJpqt01A7BYf1-.DnopczxdRKnQ3T0uI13gQw.vcBRUkEBlGOtE1q3LB5P86TzlRt0YShT_bXTGnBGfKGvxmIU_KR597o5UPUSmGJRqJMfL96rCveuBIDQQtvDCA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1055	sifaw001	nana.suka00111@gmail.com	v1.tXQ9BsAatwNeweBQ.LP9wcj86l5CzjNsK7vR17Q.IRvPJ4ih2MU	v1.NxJ-8mbzQ_k4e1wu.68roRHWJuBX3tNUS8I0U0Q.UU1a4lEbBBxZNI1QG40WJpOE5E8nZUnIKjGmWPARfwQUZUO4yQxVtzB581kO0MOa-OCGG3vtX-4JKtWxrECIkA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
745	sudawirat88	sudawirat88@gmail.com	\N	v1.XAycYzdPxf9BDKKf.4_DcYkrE6Tiy6RQaq_t3qw.c8fSpHtOnpjtOqjuJqRTgEOwBsQ7b9tWKNVOUSmm3XOYba89jTUIeoI0eg1M-ugnePWiRh0Qk2su4Mx67i9uVA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1063	nareaz	xgogigagagagigo.01@gmail.com	v1.k1AvjP6JzrCaZGPZ.792_eWEprgIT_D7TRqRchg.RKFCKPrgButNJQ	v1.SesPExadOjZCk3bn.OOKoH1TxIGoi65B10I5WNQ.YDo1hif1LIbOSzOHm_ONniZsPbt4Cw51xxnffabQ-EbQqHHEd92y5smjTNAacjTl9Kr45A1Kw1g9k2Fb8TFZxA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1065	Iman2026	imanuddin2017@gmail.com	v1.X-f-2FqMGJOIcFkg.HtYuUki4BSAXLm1HV8YS4A.apVmkuVSkEP6QQ	v1.lV-8KSDtzZv6iEso.mkYZ9TEVBNWV1StxO9UvbA.PRdrbOfwqI-nvK0cIlYQDufEwdbqAjz2WlKaa2xO44JUmrwW_9X0VVXv9NY9JVuVyt-zBvCNEJJvT1Gpx_DyrQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1067	hijariamin	mhijardjakim75@gmail.com	v1.7RVMvIMZfoadu56S.EQeWybGB0ueJ3BZKAT7jdQ.hnSea53Uu9L8ogo	v1.jZJVIeRB1IZOm6K1.HCMybEBniz6OmoqRNO211g.R_RcynGw4x-NmyDLbcZU4u_hEN8ySHdgsGy40b_zrLdTGJDb14Dr2Afjq2H054gs3Dx1zFllpyTjjdZoo8imNQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1069	mugi331008	ymugi90@gmail.com	v1.p9MeYUBx3USCg4E6.CMzq1OIMmgKD4RLUaTsX4A.0jOukhqYuz4tSSB5	v1.Fxx1L96bL7XJ6LX1.zM4zqufdTPB-t0knku8CkA.UlD2EDmrLKeqyaudEPuCTZ-NHpOwoT5s9Lt58dD5M3-VkHBJ4J0q7Zq6idIHuWtj9jMOaQNDxRJJhU7UmjSJiA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1073	Hisyamalghifari	ssaknahsaknah@gmail.com	v1.7glBeQqaK79O79O2.I1ONlNLec-jOMBaUKhpDBg.ZISq1ja9nElU	v1.pP9iZCfzJqMJk8z1.DJDmoxu1Uy37_MFU3PRdUQ.LRyNhkXND-D1o7bOGfnxfZxGUeEQ_JfA8BhwDRWrkzzI69_jjOP5cBpHdT1d433Ekk0qkeqXjwTWconxRF2UoQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1087	nareaz11	septisuryawann@gmail.com	v1.3wDIMcmOSwOfhU2r.kDPpE8OMpUj9a56i6Ym4zg.PM5FmCn12z6ILzNQ	v1.6seZWpsIMKR26-3Z.CdwwsVSs0sJxGFgW__g4MQ.6iXJvdNkw1qOLEA92eOk-5W2tfWQYO8gAHHmbJmrBVo6hqdRyx4KhZOdv-MK8EbXm4UbgKnY-nigfzXhemyl8g	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1057	kucingkecil99	ptsevenkinternasional@gmail.com	v1.C-3Ynr8icbtrFLjD.5aze2AZfsF_2ahh9lSF75w.RSYg36yF	v1.zklVZvSVD1Dfgkl9.R4fVmX_92iFIe5tuOKyfqQ.0BmP0fC6QxAeKXlr2fsDJO7wg3EvsVxyljdIaSPOpa95Sgh_1o461sxVoJOso3p5-NcbZZRcFc1VeWIRICVqew	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1081	Fitrizakia	syarifahfitrizakia@gmail.com	v1.nh_DNnF020RKTSDg.PvHEZFaoael1Xej3sBJoUQ.FRJD4F2HAjhGP3g	v1.7ZbWzcjXknuav8kl.0zwymeJd09pHdUY4yVzsIA.FUqJO1irjEUn5LrV6NPdA7DWgCPiGmwVRjVhlmoS-J9x0yu5zUb6bZtXbYTppQyLnqb0hJ9advvTdoP48cYyYQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1077	kayaraya889	petronaliaacu@gmail.com	v1.4IforLU6YNEu9EWd.bcB1ktTdEEX-iCSwIC7TZw.STIAG2zgO4Gc	v1.tgcCjrpITD-H3YYV.c-8UewvzpQij5Xh4JqtA7Q.BfMdbD6FEQcpyN8SFro0nqxQxU2xhz3a8Kc4yIo7nL3x1B-W4XYtzAuQPi_tXgWZUebUBqVYJgkgdwgm2Avjbg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
873	abba2026	hasbi.alkhair07@gmail.com	\N	v1.8-FdCIMbSrxJpDKb.sWA0upplyaC_44EydagNvQ.XhFE0c7uVjAyJrMLnXlO7ZSYdjbBFCb0b2aFwPfv-8T6WWJ023TdUeFm3fwurY-nohTEU3sa7unxWf9YvWyATw	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1061	BayoeWest	ciacio.west32@gmail.com	v1.mKpaovADdr4EDdI9.VCIhgoQNP_TKpOWlW8SWjQ.gFldbfLthmItods	v1.7BM9PS-ttSpZ4aVu.YIXtiNYYY5LQUvQHQ2PzuQ.RKmi64Eo4kpa6ATfEdJt_v8yfmRW1sz4AzfdVQj9oWBOLJVUM3rTyoUj3YIf_w1q27OE35nk_dyDQPDf_hcFMQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
907	depot123	ramliasalam10@gmail.com	\N	v1.u-p_0SgexTxx7pwk.3gYyg_RrVXeq4rfanUffOw.Qse-vKOtx-yTlU3OqXtRM_3bybkTVtkRamMOkBZA5hofGjPb78rRCN9Ng2JlEyIa0K7tWFzG2751rLJHF8rfDw	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1085	Kincah	magnum125@gmail.com	v1.nv_hSEdJf7Lzx8y_.7yzbYwoBtsrT3VlDfpM8hg.XRhYUK-AXxQ	v1.HQ_tNJaPgJUvA1S1.XnJJle8pZ6l7gLpr84D5UA.GDKpOuqZXQgFw-H4dkI4LB-UAneNWBHxSjKWyFiLIZp9tvXjrSRjFWWJiyY7ZF39NDJTAaluK2m9elVwwm9fFQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
925	Alamjaya	thzsukses@gmail.com	\N	v1.IRtAn7icCUWZdJY8.mkzKCmc4Mp6q9_iO65amBg.83lPnuOfEU4OrNsDTzIObMeLNBQuVob2GSjNAKdQyG2mFy-_kuIg-AgJrXfDbAHqnJySpPTBswu6xD_YXqkSXg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
747	maklampir88	maklampir88@gmail.com	\N	v1.JXMxfcMuLRsE74_l.ykznRMvVqRgWQB-U_gIM9Q.2cJ-kXeO40jIVMKAOqZa5XsbNfzQ40AZgbnhmYThWie37-BdYjARfdA1rF_aGsM7hdcXJvjbg7_0du6203pLrQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
921	Bro123	jayasaputro999@gmail.com	\N	v1.EWqq5NjtNDrRRjHy.GEyx0ln2sP2doS5XaCGpAA.q1Pl2Hii1Zq-BtAalsjFOoDHJFbH_MK0mC8IEYWh4cDdIceJI97l8JkaV3pYUSw6AsZc2o65TyKaNNo0ENaalQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1071	cacacantik	hycca140705@gmail.com	v1.hayU9MnA2SNV9gaH.hHBWNiwIck0Fx90Rn16G-A.t5uPcu_SVC4	v1.zhleB-CWYrCow0Tr.v0Iflsvicar8hGr83_qY_A.vzCXH5LH_stXeu7qu0OS9IP0XHZW2PMm_A3EG7n0De4gOKzvYbjbFmNahsP8yyFHq8koCDuEjyeZ0QSfvc9o3Q	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
905	ewako	kopisusu2024@gmail.com	\N	v1.LzTbflEQDaJ_vkv0.Ka0sfuzaGd6BYxK5yDLXmQ.5uXA0kpsSUHnBKV7m0kNfGIAiui4sXY9RWeooFKgjF_NdnwN_mrk97XYvb2v2sx-E0vpN8skbfG2qQrqFZ2f1g	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1059	Fadilaja1	fadilnewfadil86@gmail.com	v1.Pzp1fUrCBqmNATnN.2ZxvC0nM-Go-4PZDryAKsw.dkxnJHMg1-WqoF_a	v1.fof5B-mn55ROnxwW.XklEKKtS1X-AAB23f5R5_w.jQwQjhVsyQG3JoRB7gAirG53WUlIQ443jvXpf8YlF31Cml-neuz1NFcKPNYigyHqWhKpsR5IezBmRYDhKdOqyA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
915	GUSMAN962	tugimanpnk98@gmail.com	\N	v1.b2nKooZwCn3p7jRA.kcda1lFipx-cJOZrRHqtzA.wpPRU7NRY2qR5vTPFaeNGF3dJrm0FZ_9Vh8YyDPhMAcCvJ5jgFBp_hGGRiyLwaSzkunl5iir3hFuTjHZwMGQRQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1079	bloggerborneo	bloggerborneo@gmail.com	v1.w9hk-HIiEskH8tcZ.aXAvmQj_yDPh0YoEXsCNLA.H_e42gwBC45NHOA	v1.nQhLw2Xdi_y6XCWR.8wkmmibm4CzFeQ7TUUccpw.IADGxVGbsHYcRA5QPb8yA_Lo3lXnA8dqHrGfBn6JxnOZCkjo45-JmoocfzR0Lz1xeiux1WfXmvpkwZaIWNHLig	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1075	SUMADI77	sumadi.77md@gmail.com	v1.SvcjVt9P6f7ve-_n.1M_h30VazzPWOPQKUzuSqg.CnSA5Rbff-EaDMUT	v1.O_ywe5Sfsuzg61t4.Z8uD8-lcAvSJZnddMRCZ1A.OhHqno6IAVCrlBa7WG8sqd_nIrFPuFkrxDIsM3SpvsW1bS9ncW1Podap5R10teGp6zytP5aJhepcYsghJ_vWlQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1091	MARIAKAYA	bilzarchannel@gmail.com	v1.9JFiWYWxeX0a75bK.X-jJ4QZHx-WeZTwtf5qnmw.BXT3U1AgxVVdmW7e	v1.O79DEneGOQ54u3bJ.oz5NuY5KD1siO0ca4h0Xew.VgtOE-9M7YJ8SXqLR3f7F-NQo01woR_UXSskl3FiOxsiWYIlTt1eWo2n-QzV2lKfidiNtkI3eBomFpGfUA_x8w	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1089	Babakai	eko.saputra.not2@gmail.com	v1.Fx67rFGbxMdY8y8e.Rm_AdJClzE0ROkKRMxWZfQ.NxCNkjqlKlP7kEQ	v1.uoxI_DpdvRGjfsaG.8xJcNge7PWH_CsceG47wIQ.IBB7uQFxsdmld1FgSALhuO3lyiEZsJtjpRW5-bHByBz_-PK6pXP3OXxDbXfjzWQGl8ZgvRzYp6LyVs4lyC73BQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
749	kangden69	kangdeni2988@gmail.com	v1.nNZgW5YuM__ucQtR.E5_sE-8l0xJKkT-1247nKw.DW54qHZ2fbA	v1.q6peYEo1DeLHETOw.2tJpRUBqCfNOYCqZch3kCw.YZ6UWy1Iks8S1shHebh4ztFSA1H1QOkCChIWthc4lNaxsq4zUd3b1ZbKhZ8vXwsA1ylAa6fE81znXUc_sLnaiA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
\.


--
-- Data for Name: user_referrals; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_referrals (user_id, referrer_user_id, provider_referrer, created_at, updated_at) FROM stdin;
745	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
747	745	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
749	\N	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
751	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
753	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
755	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
757	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
759	757	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
761	757	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
763	757	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
765	757	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
767	751	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
769	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
771	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
773	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
775	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
777	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
779	777	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
781	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
783	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
785	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
787	767	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
789	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
791	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
793	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
795	757	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
797	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
799	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
801	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
803	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
805	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
807	797	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
809	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
811	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
813	809	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
815	813	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
817	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
819	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
821	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
823	751	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
825	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
827	825	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
829	825	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
831	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
833	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
835	825	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
837	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
839	751	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
841	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
843	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
845	767	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
847	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
849	809	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
851	813	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
853	767	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
855	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
857	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
859	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
861	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
863	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
865	861	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
867	859	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
869	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
871	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
873	859	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
875	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
877	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
879	877	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
881	877	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
883	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
885	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
887	797	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
889	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
891	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
893	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
895	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
897	859	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
899	873	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
901	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
903	793	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
905	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
907	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
909	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
911	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
913	911	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
915	859	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
917	915	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
919	917	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
921	919	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
923	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
925	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
927	\N	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
929	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
931	929	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
933	931	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
935	933	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
937	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
939	859	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
941	939	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
943	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
945	935	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
947	925	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
949	793	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
951	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
953	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
955	925	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
957	947	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
959	947	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
961	859	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
963	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
965	955	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
967	863	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
969	959	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
971	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
973	971	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
975	973	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
977	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
979	971	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
981	973	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
983	979	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
985	973	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
987	859	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
989	985	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
991	989	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
993	983	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
995	987	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
997	973	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
999	863	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1001	999	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1003	1001	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1005	1001	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1007	1001	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1009	933	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1011	981	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1013	971	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1015	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1017	993	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1019	1013	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1021	981	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1023	981	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1025	993	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1027	983	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1029	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1031	1017	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1033	971	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1035	981	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1037	981	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1039	859	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1041	963	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1043	933	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1045	973	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1047	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1049	973	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1051	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1053	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1055	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1057	971	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1059	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1061	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1063	797	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1065	797	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1067	1065	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1069	1065	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1071	981	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1073	981	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1075	797	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1077	971	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1079	1077	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1081	981	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1083	981	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1085	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1087	797	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1089	797	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1091	1013	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1093	1087	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1095	767	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1097	767	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1099	767	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1101	971	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1103	863	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1105	863	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1107	793	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1109	1017	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1111	1087	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1113	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1115	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
\.


--
-- Data for Name: user_sessions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_sessions (token_hash, user_id, csrf_token, expires_at, created_at) FROM stdin;
\\x95fd1c5dcedc0f73bc855c4184aa2de04b990bbf12d05fd1c524d9fbc69a3886	751	6b78799cb9367d37f5e24f8996b8486c64b85dc69cd562dd	2026-10-21 16:14:42.919238+07	2026-09-21 16:14:42.919238+07
\\x73c804f303f8013a619c6017c67ad6bf3bd5ee17c9ee0a0e58f557057b8e0a3e	747	e135e39b93a19ffcf7f63a1e592a3107c1386d5f22aa3bb8	2026-10-23 10:36:14.054621+07	2026-09-23 10:36:14.054621+07
\.


--
-- Data for Name: user_trading_settings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_trading_settings (user_id, coin, base_bet, chance_min, chance_max, delay_ms, martingale_on_win, martingale_on_loss, reset_after_wins, reset_after_losses, boom_after_wins, boom_win_amount, boom_after_losses, boom_loss_amount, take_profit, stop_loss, balance_below, stop_on_win, maximum_bet, updated_at, profit_session) FROM stdin;
745	BTT	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
753	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
755	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	0.08000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
757	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
759	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
761	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
763	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
765	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
767	BTC	0.00000100	49	49	1000	0	25	1	0	0	0.00000000	0	0.00000000	90000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	10.00000000
769	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
771	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	500.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
773	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
775	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
777	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
779	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
781	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	30000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
783	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
785	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
787	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
789	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
791	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
793	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
795	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
797	BTC	0.00000100	49	49	1000	0	100	2	0	0	0.00000000	0	0.00000000	2000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
799	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	200.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
801	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
803	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
805	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	5.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
807	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
809	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
811	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
813	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
815	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
817	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
819	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
821	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
823	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
825	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
827	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
829	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
831	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
833	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
835	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
837	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
839	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
841	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
843	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
845	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
847	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
849	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
851	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
853	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
855	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
857	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
859	BTC	0.00000100	49	49	1000	0	100	2	0	0	0.00000000	0	0.00000000	500.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	3.00000000
861	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
863	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	10000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	3.00000000
865	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
867	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
869	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
871	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
873	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	10.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
751	FLOKI	0.06000000	41	43	500	0	100	2	0	0	0.00000000	0	0.00000000	10000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-21 16:12:46.820447+07	70000.00000000
749	BTT	0.10000000	30	40	300	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-23 05:21:12.743326+07	5.00000000
875	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
877	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
879	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
881	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
883	BTC	0.00000100	49	49	1000	0	100	2	0	0	0.00000000	0	0.00000000	2.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
885	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
887	BTC	0.00000100	49	49	1000	0	120	2	0	0	0.00000000	0	0.00000000	30000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	5.00000000
889	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
891	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	50.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
893	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
895	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
897	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
899	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
901	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
903	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
905	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	2000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
907	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	250.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
909	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
911	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	1000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
913	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
915	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	200.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
917	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	100000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
919	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	300.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
921	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	20.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
923	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
925	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	2000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
927	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	100000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
929	BTC	0.00000100	49	49	1000	0	100	1	5	0	0.00000000	11	1000.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
931	BTC	0.00000100	49	49	1000	25	100	1	10	0	0.00000000	0	0.00000000	3.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00100000
933	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	9	11.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	1.00000000
935	BTC	0.00000100	49	49	1000	75	100	2	3	0	0.00000000	0	0.00000000	500000000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	1.00000000
937	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
939	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	200.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
941	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	4000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
943	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
945	BTC	0.00000100	49	49	1000	75	100	1	10	0	0.00000000	0	0.00000000	50000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	1.00000000
947	BTC	0.00000100	49	49	1000	0	100	2	0	0	0.00000000	0	0.00000000	0.00005000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
949	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
951	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	10.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.50000000
953	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
955	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	500.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
957	BTC	0.00000100	49	49	1000	0	100	2	0	0	0.00000000	0	0.00000000	100.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
959	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	250.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
961	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	20000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	20.50000000
963	BTC	0.00000100	49	49	1000	100	100	2	0	0	0.00000000	0	0.00000000	35000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.50000000
965	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	200.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
967	BTC	0.00000100	49	49	1000	0	100	2	0	0	0.00000000	0	0.00000000	500.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
969	BTC	0.00000100	49	49	1000	0	25	1	0	0	0.00000000	0	0.00000000	50000000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	5.00000000
971	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	5.00000000
973	BTC	0.00000100	49	49	1000	0	100	2	0	0	0.00000000	0	0.00000000	10000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	1000000000000.00000000
975	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	1000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	10.00000000
977	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	2.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
979	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	50.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
981	BTC	0.00000100	49	49	1000	0	100	2	0	0	0.00000000	0	0.00000000	100000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	5.00000000
983	BTC	0.00000100	49	49	1000	0	100	2	0	0	0.00000000	0	0.00000000	1.00000000	100000.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	3.00000000
985	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	20.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
987	BTC	0.00000100	49	49	1000	0	100	1	0	0	600000000000.00000000	0	0.00000000	1000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
989	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
991	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
993	BTC	0.00000100	49	49	1000	100	15	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
995	BTC	0.00000100	49	49	1000	100	100	2	0	0	0.00000000	0	0.00000000	5.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
997	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
999	BTC	0.00000100	49	49	1000	100	100	1	0	100	0.00000000	50	0.00000000	5000.00000000	500.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	5.00000000
1001	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	1000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1003	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	100.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1005	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	10.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1007	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	9000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1009	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1011	BTC	0.00000100	49	49	1000	0	100	2	0	0	0.00000000	0	0.00000000	10000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	5.00000000
1013	BTC	0.00000100	49	49	1000	0	15	1	0	0	0.00000000	0	0.00000000	1000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1015	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	1000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1017	BTC	0.00000100	49	49	1000	100	80	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1019	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	1000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1021	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	5000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	5.00000000
1023	BTC	0.00000100	49	49	1000	0	100	2	0	0	0.00000000	0	0.00000000	10000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	3.00000000
1025	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1027	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	1000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	10.00000000
1029	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1031	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1033	BTC	0.00000100	49	49	1000	0	100	2	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	5.00000000
1035	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	1000.00000000	30000.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	1.00000000
1037	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	50.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1039	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1041	BTC	0.00000100	49	49	1000	100	100	2	0	0	0.00000000	0	0.00000000	65000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.50000000
1043	BTC	0.00000100	49	49	1000	75	100	2	5	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	10.00000000
1045	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	200.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1047	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1049	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	500.00000000	100.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	2.00000000
1051	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1053	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1055	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1057	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1059	TRX	0.00000100	49	49	1000	0	100	2	0	1	0.00000000	0	0.00000000	1000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	5.00000000
1061	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1063	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1065	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1067	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1069	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1071	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	1000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	5.00000000
1073	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1075	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1077	TRX	0.00000100	49	49	1000	0	100	2	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	10000.00000000
1079	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1081	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1083	TRX	0.00000100	49	49	1000	0	15	1	0	0	0.00000000	0	0.00000000	10000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	100.00000000
1085	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1087	TRX	0.00000100	49	49	1000	0	25	1	0	0	0.00000000	0	0.00000000	100.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1089	TRX	0.00000100	49	49	1000	0	100	2	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1091	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	1000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1093	TRX	0.00000100	49	49	1000	0	25	2	0	0	0.00000000	0	0.00000000	500.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1095	TRX	0.00000100	49	49	1000	20	30	0	0	0	0.00000000	0	0.00000000	90000000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	1000.00000000
1097	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1099	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1101	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1103	TRX	0.00000100	49	49	1000	0	100	2	0	0	0.00000000	0	0.00000000	1000000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	3.00000000
1105	TRX	0.00000100	49	49	1000	0	100	2	0	0	0.00000000	0	0.00000000	10000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	3.00000000
1107	TRX	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1109	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1111	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	5000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1113	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
1115	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
747	BTT	0.10000000	20	30	300	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-23 04:53:07.024361+07	0.00000000
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (id, username, email, password_hash, status, subscription_expires_at, created_at, updated_at, legacy_user_id, subscription_trial_ends_at, last_login_at, last_active_at) FROM stdin;
745	sudawirat88	sudawirat88@gmail.com	$2b$12$6J./S7tFrmwnf5R5eInrGOofKZUID4VMpnWYdO4znFAvC3BLIx/za	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	1	\N	\N	\N
753	Sugito73	sugitoseso06@gmail.com	$2b$12$AlArRebVLD.CUBhY6bc//ebi1aN9H2TdIeXfNuIr.EFdcIxQQTNU.	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	7	\N	\N	\N
755	Sukoyo	sukoirmt@gmail.com	$2b$12$CJKc1j8vDyCNOAc9XqUQT.7SrLRvFQzkXJjgMKmVtlh3iH3FyP12C	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	8	\N	\N	\N
757	onemillion01	onemillionoo777@gmail.com	$2b$12$aJxEjVlNMNdF3bagqyYE3ubeFsF3YJZXTFTTB1gEHGHYn.yrwnXa6	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	9	\N	\N	\N
759	Din1124	liza11241124@gmail.com	$2b$12$azqbCzBG.nsvKPRYiOUPquQhq.uFgjuAwk0kwsKYPOc5u5J0bJzdO	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	10	\N	\N	\N
761	Dwiwahyuni	dwiwahyuni200679@gmail.com	$2b$12$v687Xu95rmzduH4fLOGxruUEO5w0iywTJ.dZ2Q5PBtyxG8jCCs/V.	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	11	\N	\N	\N
763	Shamdin5530	shamdin5530.sd@gmail.com	$2b$12$DbQE0xK64izGnVKyhglSauZwluGRL5PhxsMRPec5BmVn/zmztNjCK	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	12	\N	\N	\N
765	bondajuta1	onemillion11777@gmail.com	$2b$12$Plwy40sgp69rLLf.bYA3L.5PAGVN7YNLMFi.CKRU4IC1EjGGdxC86	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	13	\N	\N	\N
949	Lifeisgrace	noviiswanty77@gmail.com	$2b$10$uvyAWUOFERDPeSFvX52/zObhVtYWCypP.jbPrnCCeP80EWA2D73Hy	ACTIVE	2026-08-27 06:52:33.497+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	141	2026-08-27 06:52:33.497+07	\N	\N
951	Kingsaphire	eaglemalindo@gmail.com	$2b$10$G7HyCI2MrL/.XYRo/AKLiuOO1B1i7C055A1ZGTGMVXp9fSMBgw4Gu	ACTIVE	2026-08-27 11:51:55.986+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	142	2026-08-27 11:51:55.986+07	\N	\N
953	Adek12	adekosnandar12@gmail.com	$2b$12$/p/JlV/MlrvIx/wUpe28BOW0ufyAo6lNStdsL/NnCrCYxbFN2Vm0K	ACTIVE	2026-08-27 12:06:00.232+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	143	2026-08-27 12:06:00.232+07	\N	\N
955	RoyalAndara123	vieyandra@gmail.com	$2b$10$qh8wONB3T/oQ1Vir9oEgO.AkwleSrHAD5TFJlF8YL3zxBpVaEc9LC	ACTIVE	2026-08-27 14:33:36.077+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	146	2026-08-27 14:33:36.077+07	\N	\N
957	Kasmawati73	pesati69@gmail.com	$2b$10$FWmEmmQGDCrO4q1Iwtxw4.YcJCTCQoRO0eKPS9NCejHdaVs0aPsNe	ACTIVE	2026-09-27 15:54:46.515+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	147	2026-08-27 15:54:02.966+07	\N	\N
959	bangmanfx	bangmanfx@gmail.com	$2b$12$TLdgKCqBkNhIs7gmN6/jh.J9sL99jJ2xiRdZPzV78AJgAvk0Pis.u	ACTIVE	2026-09-28 10:42:13.838+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	148	2026-08-28 10:41:00.491+07	\N	\N
751	smartrich88	rajaduit369@gmail.com	$2b$12$1YIUyugJvnuz6M8QX54zzuSWhr/EGxh6wRX/5YdkpyddRKGD5cIqe	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-21 16:14:42.925637+07	5	\N	2026-09-21 16:14:42.925637+07	2026-09-21 16:14:42.925637+07
749	kangden69	kangdeni2988@gmail.com	$2b$12$c5.LgR1jMpy5f.JOKRyv/e4Qjy9AZ8FX5MX5WShl8a8CSzSCowE3y	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-23 05:01:47.503261+07	4	\N	2026-09-23 05:01:47.503261+07	2026-09-23 10:33:23.353435+07
747	maklampir88	maklampir88@gmail.com	$2b$12$hKJ9OdXwJ.GCWDqtkzySCutGnk9eTCvJyS1foOr9WYRKlwttG17NO	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-23 10:36:15.015881+07	3	\N	2026-09-23 10:36:15.015881+07	2026-09-23 10:36:15.015881+07
767	gudangopit	Bpknana@gmail.com	$2b$12$4Fi6RtLDX883y.Bhj3d4UeMVII9bGiSRuvIPYq28lv2odNCAlCzbC	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	14	\N	\N	\N
769	MUHTAR2	muchtar0866@gmail.com	$2b$12$wZ2neERvIGzD8JzOryFVse9gr6GDI.Xzjfeb1txgs2XaI1yNQ.B56	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	15	\N	\N	\N
771	Din6237	liza79@gmail.com	$2b$12$gtXQdhSr1KIgpRVKk1n2AekZ5rW2/9IpwGicSYGFTeXKm/VC3e8Ra	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	16	\N	\N	\N
781	smartbotapp	smartbotapp@gmail.com	$2a$10$VAKiU1cHQjkjukbdHy4FZeeGTddH0hELvd1M.yShpcs4OknQCSShC	ACTIVE	2035-02-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-21 10:29:40.699299+07	21	\N	2026-09-21 10:29:40.699299+07	2026-09-21 10:29:40.699299+07
773	Marnobharja	grahabangunharja2401@gmail.com	$2b$12$0CNMvIs7kIwSBfFolWZtRO8OSa0yuHFxkZY6Fa7lI5pqWqR.vXg7i	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	17	\N	\N	\N
775	robertino123	mangedi256@gmail.com	$2b$12$L0j6utB1CbZMDJZKXbDK4uUw1GAIIrQn0KXRW2pbEnXZIOMxNMS.O	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	18	\N	\N	\N
777	Kingcuan999	jack.soulfis@gmail.com	$2b$12$e63uCwVzzkaPGPZpdJYuOOV/V2BFBqBesXJ41uZ7EyOszOdugPbsK	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	19	\N	\N	\N
779	abdullahbram	abdullahbram.smd@gmail.com	$2b$12$bh2fczCg4rX4JWwCNOXGC.Xjw3fu6y3d6QtHkbnRlDHZ.sGNzlKyC	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	20	\N	\N	\N
783	Koil123	muhammadqhoril26@gmail.com	$2b$12$ykuzrC7a7NZflZNJAGCOeO1Jfec5qPMz/O6IqPQ3tv0RwX74wUNgW	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	22	\N	\N	\N
785	bening888	sumarnotambeng@gmail.com	$2b$12$93.qrrfsYSDJ95C2ymW1peUUTHqk68XsGOGgMGH8MIXUAZDjaJBeK	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	23	\N	\N	\N
787	abah90	abahanom469@gmail.com	$2b$12$D.p/tQtqly7qcFb2NPWm8O4Z0ShfwtpgqMPbJM0bKnKsmTV2Gj/aC	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	24	\N	\N	\N
961	Hermi01	fazilmaulana728@gmail.com	$2b$10$Ldp6BHuYJLvul1CKfUBp1uJORHts9XtIalNXcfr2uZQhGSWWY4G06	ACTIVE	2026-08-28 17:25:01.415+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	150	2026-08-28 17:25:01.415+07	\N	\N
963	Zumbo23	syaifulzumbo23@gmail.com	$2b$12$L861UyyUQvec/ZXUeVw8Peq7gHuVKhT20svvYcj2oE8HubNL7KWB.	ACTIVE	2026-09-28 21:49:05.849+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	159	2026-08-28 18:02:21.328+07	\N	\N
965	Kudalumping	mjoshuawijaya@gmail.com	$2b$10$YpsaMP1SQ/W5G6R8ba.MHO0EebvQv3Xef19.mCk57MPgEfRA4WlO2	ACTIVE	2026-08-28 18:27:01.847+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	160	2026-08-28 18:27:01.847+07	\N	\N
967	izul1976	izul.untan@gmail.com	$2b$10$4jVuL8b9uXCxMABMUgiK7O8OlxHJ14PwMCU522qkEWKFXaUmVzNVq	ACTIVE	2026-08-29 15:39:34.142+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	162	2026-08-29 15:39:34.142+07	\N	\N
969	ayahfeeza	ayahfeeza@gmail.com	$2b$12$hSjrGcbPlQPnsUCC9inB..TNhuMzQa9AZndRHg/YfkR2cm1sW5Feu	ACTIVE	2026-09-29 20:25:11.597+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	163	2026-08-29 16:07:02+07	\N	\N
971	Nuruldilla	gadispontianak79@gmail.com	$2b$12$Em4Z4Jqv5HQbArCj6e4clu4D6lKAB4rz/FPDU3dCJXEyy4VDgfFyC	ACTIVE	2026-09-29 20:23:36.277+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	164	2026-08-29 19:42:04.993+07	\N	\N
789	rhemawunk3	rhemwunk3@gmail.com	$2b$12$M8IlCroKocIoio4Me2jRNuOBsACHm2ddo2SeWqf.p4w7l3DwwagDG	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	25	\N	\N	\N
791	ommuray	bebebtajir@gmail.com	$2b$12$IwPCc4a9/g2F20m.aU2NJe0apSANgYbgBg1QP79sfgAj1GuDaS2oq	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	26	\N	\N	\N
793	BLESSINGSTAR14	bisniskudahsyat2025@gmail.com	$2b$12$ckdSUvo/MCQN0KHPW6w3xeVmWCL1Rf3xT5De9SHVbEIMvDWPo3YpS	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	27	\N	\N	\N
795	fantinuscham	cjerleong@gmail.com	$2b$12$hgEkSB57TC8ca6W6EiKr1ex4SIPdSND0jDSScR/gI.6KWJ4f07fSe	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	28	\N	\N	\N
797	Abah67	eyang.anom1967@gmain.com	$2b$12$S9OiRAEOPfzteTjBpd3glegsWS.HR/jlr6YfcAI1xu0dU6SPm4UbW	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	29	\N	\N	\N
799	Yudi_Bangli	yudibangli78@gmail.com	$2b$12$J/sd0IH1meek3ifVcRipvO4fCaIkm8u9wkY6VWzBzrNsBMo2xx58O	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	30	\N	\N	\N
801	Ayulestari	widagoayulestari@gmail.com	$2b$12$krTOyrZKnmyKWHc3kZUee.X0swRnXtF8zpkwsBVseHDaCG7ZgMUUe	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	31	\N	\N	\N
803	Budiansyah77	edybudiansyah7@gmail.com	$2b$12$Je4LDCkQE/rzl5vMz.alEO/s75TFjSW.QTwdSm.z3BDQeBh5fLEQS	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	32	\N	\N	\N
805	barryzainal9	barryzainal9@gmail.com	$2b$12$jtg9pSEUhHIEBmew4BuAKO7wWdgTyDo5nCEPoxImnslDenozd6srq	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	33	\N	\N	\N
807	Kijang1971	ardhi3026@gmail.com	$2b$12$193k5Z1RMiIIye9qcZtNF.AlJHtbuEZMlZvtgwJFIEONkXC0fTRIW	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	34	\N	\N	\N
809	wijaya789	adhiewijaya678@gmail.com	$2b$12$tJwMdqbZtQL0eKglfyRH/uT4vj.J1iRYaXMwfV5T5DDRu7otH4bHW	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	35	\N	\N	\N
993	Fari789	safarkakap26@gmail.com	$2b$12$XmlWHtnJMOCX2tULQYiWf.ABHzeA4o5I2SLPn6ElSJotLJxQ7kdJe	ACTIVE	2026-09-30 21:19:52.028+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	200	2026-08-30 16:56:26.213+07	\N	\N
995	Ayukomang001	idaglx288@gmail.com	$2b$12$Ku02c.dNLOU/gE3I9hEx2OTC6XMt8byEn1GXJIB0ZRp89B456J6H6	SUSPENDED	2026-08-30 17:12:12.288+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	202	2026-08-30 17:12:12.288+07	\N	\N
997	Golden234	ariepp5758@gmail.com	$2b$12$dafbQD2g0gkbEmuaUQ9WyOz376d6j1O.WAp2/4tEhGPeI0NfWPUqK	ACTIVE	2026-08-30 19:25:05.244+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	203	2026-08-30 19:25:05.244+07	\N	\N
999	Rikaraisa	rikaraisa88@gmail.com	$2b$10$WmKIHXi6BrGbZqa.xgIO2.rqqOjsU5gyQAqCxkTB8dXYeuxEvFzeS	ACTIVE	2026-09-30 22:07:13.851+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	204	2026-08-30 21:28:09.066+07	\N	\N
1001	yutt	twobigbrain@gmail.com	$2b$10$FMZRN5fqTpOxBpFFOiIgH.Tp5Yjt6yfm9cHmaf2EzP90Pg8Ce/NPa	ACTIVE	2026-08-30 22:20:05.253+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	205	2026-08-30 22:20:05.253+07	\N	\N
1003	Pidutt	poonzai20p@gmail.com	$2b$10$nLxy1jtHiPNCBVq/RF4EYe7e9WM8fOOQPvLhzbvWioHY10yaK0a7q	ACTIVE	2026-08-30 22:25:20.843+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	206	2026-08-30 22:25:20.843+07	\N	\N
811	kharis	k99593@gmail.com	$2b$12$jB9RO1OF7hQ04m6iHAYztOiB9rcylEwO.PC3947N9elwb.hA5AfZy	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	36	\N	\N	\N
813	kayaberkah212	muhamadrudi03@gmail.com	$2b$12$zRnJxT4iRjPcn8gktPmNYOQYe.aIli/hcwsljB7zCbCgHHfrZ8kcO	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	38	\N	\N	\N
815	kaya213	santikuat212@gmail.com	$2b$12$3aC3ALNKXkr1rsQUt7wLQuYnY/G7502E58D22zo7lIuaEiPjQ7cwG	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	39	\N	\N	\N
817	Getluck338	rdw3338@gmail.com	$2b$12$B6FedGvq3pIuxSg7z7MV7.iHNWf31DPKu/VN2Kqj3kFzHEDqjsY0u	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	40	\N	\N	\N
819	wid75	widiyanto30@gmail.com	$2b$12$hz.w.VJ0f1cAqjkaMHim0egIBcsm3RlB5V6l9yAMSuQYWKM2pimaC	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	41	\N	\N	\N
821	Kamilibrahim	muhammadkamilrosidi@gmail.com	$2b$12$a1rqXVLLxa0t98qV2LXC3.rOtun5ABXvP4BjMxM10MzbeSGyfSI86	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	42	\N	\N	\N
823	Ichsansukses	ichsannurhakim63@gmail.com	$2b$12$rorSS1BzkRDsUm13dIfrFOrqHrXRITJ3vdBRvovlDEzyvodABbFpq	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	43	\N	\N	\N
825	BOTAI212	team886ok@gmail.com	$2b$12$M9J3.B0GlDoUgQZqKmhFwersIU3hyuVZmtWL70zRfreDfpjInGlAS	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	44	\N	\N	\N
827	Supriadi212	adi699672@gmail.com	$2b$12$8uyDqORh3hP0h0JGcTw20.30Fxo5PuUjBg6JbgMSceM2gMJNgfciu	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	45	\N	\N	\N
829	botai213	batikopi212@gmail.com	$2b$12$xnBhRNufqgfD3EM/V8ri0.gaYEUalE9M9hld2KkcbpHvwLRiHYHB6	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	46	\N	\N	\N
831	GUSTI58	nesiasuper@gmail.com	$2b$12$3JxxT0jaAnO0K5urXXGoneKARmbf1oyP7Ih2r.HJygenFrIy8W6fG	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	47	\N	\N	\N
833	Hermansukses	indhlstrii28@gmail.com	$2b$12$QvFici5LIoEntSx4Q9yWT.8iWQYeTvIOhRKkg9486e28mtM.lfiRO	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	49	\N	\N	\N
1005	Yongkry	dermawans926@gmail.com	$2b$10$nNOGCqVS0u.IAnH9RGXmJeJUAXYFdzlD.lkgHQAn7Z2JfdWx904g2	ACTIVE	2026-08-30 22:25:24.107+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	207	2026-08-30 22:25:24.107+07	\N	\N
1007	Sukiliar	nuuxyou5@gmail.com	$2b$10$LyVxeVhnD19fAoKLR5Ez7.3RpvMqdK0u3L.D68STzpXMuKD2pw.1C	ACTIVE	2026-08-30 22:28:13.081+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	210	2026-08-30 22:28:13.081+07	\N	\N
1009	almusaid	asyari.almusaid@gmail.com	$2b$12$EdjA0DJDkQrDu7eu2RvViuMLW/m.Hc58YtdPBCXqGDiR5amZX/wxW	SUSPENDED	2026-08-31 08:09:32.343+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	211	2026-08-31 08:09:32.343+07	\N	\N
1011	Zoelkifli88	zulkifli051@gmail.com	$2b$10$uVkaTZW8qqiNK6zZsfsS5exboF9RTj9aYyYHSHv/ETtHCYVy/9fpC	ACTIVE	2026-09-30 17:45:37.88+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	217	2026-08-31 16:33:58.067+07	\N	\N
835	Jaya778899	bilqisajizah88@gmail.com	$2b$12$AHte.f0r9cEx2HSFODZJseiY94lPlhYe23F0GCQ24mye2t4U/lNVC	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	51	\N	\N	\N
837	MILYADER2045	iriantoheri653@gmail.com	$2b$12$AGrv49FqYMppMf1amcRcZuQrzuVzCU0RC/F3KzkRPejpFh6IidlnC	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	52	\N	\N	\N
839	Mwayr	personal.mwahyu@gmail.com	$2b$12$qd0lp8fVVLgJg9zrW0iSze5Rb55vLtpk7RPatGIRky6WTtdxwDGyi	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	53	\N	\N	\N
841	niko03	andib8335@gmail.com	$2b$12$3AVHq7lztfHtgalIzHQy2OXE8IN2KxzC3pDpropZ05QcLler8QodO	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	54	\N	\N	\N
843	andiko03	bangdadiko@gmail.com	$2b$12$WS7sPX4FnNpYPXDRAYK.DuwD/fLeZzaezSFCIBIGbyUTQcagwWTva	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	55	\N	\N	\N
845	Cakrawala77	irwansetiawanbsp@gmail.com	$2b$12$YL6fzA/91z6ma.gOULpcguAKPkeoX9C7EDRYNEbumA64P2NjYW6PW	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	56	\N	\N	\N
847	FULUSKATSIR	sudrajatsoni@gmail.com	$2b$12$rBpJ06HTGp5Cn9pU9r4pAeb.F2zazzUOYQcjzi/A/7oOdVV2qqI4y	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	57	\N	\N	\N
849	happynambang	happynambang@gmail.com	$2b$12$HHPUz1IGuzSzS5ykLzCM8urlkrSU.fEl2unLEESX3DZLUuhZgjaRO	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	58	\N	\N	\N
851	cuangacor	sukirman161071@gmail.com	$2b$12$JkK5fW5doN/ve8rYG1iW0O.I3gOFJ.RGAzxS97KC41I3Z31UfeK.W	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	59	\N	\N	\N
853	jember026	jember026@gmail.com	$2b$12$RTE3DQxRLkwX3i5AGJyeyuKHvMqTvtRqGd/ApFEBfbXXrrhMoMrka	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	60	\N	\N	\N
855	rajakaya60	wagunsukses603@gmail.com	$2b$12$fYr0Q.AANnwiYgR1LLSZzOfewo26A3X00VxqMQgOGYGIC61w5ByBK	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	62	\N	\N	\N
1013	REGISTERS	norqamariah21@gmail.com	$2b$12$RP3uWM0x5my97xti0wS6WOd/Z.jrBpZHiSfzIuByzZrJ1CVNTA0bG	ACTIVE	2026-10-01 10:52:37.53+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	219	2026-08-31 20:34:26.67+07	\N	\N
1015	karetlestari	barryzainal79@gmail.com	$2b$10$X3BQwYXApj4hfyIuY5E9B.7spXuAvaCr8bKI6qGq88V.jLqad8oGu	ACTIVE	2026-10-02 10:40:06.354+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	220	2026-08-31 20:45:45.998+07	\N	\N
1017	SASA88	safaripcex@gmail.com	$2b$10$mDSntHfrPSSicikZvcxjHubg7hRM9lj9KQ8Krlbj0KMX1.QBNdJYq	ACTIVE	2026-08-31 21:13:45.993+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	221	2026-08-31 21:13:45.993+07	\N	\N
1019	Faren	goggleid62@gmail.com	$2b$12$ccgbcJPAnqEVgAkbasTvKOx3Heob9gGq9Jmc3VfGRCJlaoLaVTekW	SUSPENDED	2026-09-01 13:29:44.85+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	222	2026-09-01 13:29:44.85+07	\N	\N
1043	Pcx99	suharalfathan@gmail.com	$2b$10$bWdA4Ncyv2rlJqF3KxhrS.CuYOT3uZsa48hPQtjsEfULK8FkJqBGq	ACTIVE	2026-09-04 15:57:55.933+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	245	2026-09-04 15:57:55.933+07	\N	\N
1045	ravi11	ravi65saigon@gmail.com	$2b$10$xUu0PyBAv4UROgd0oKEGjeh923jNwfCExnDvkNia8ahRzW9WSssWy	ACTIVE	2026-09-04 17:46:20.431+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	246	2026-09-04 17:46:20.431+07	\N	\N
857	Gummy2023	wagunsukses@gmail.com	$2b$12$0hqE5g0lUrJCVtVCRcnKwOLiwTTU/MoiLw60vpXUoH5oW1cKr8qL6	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	63	\N	\N	\N
859	Koong89	basunirindu237@gmail.com	$2b$12$xXKyd4gbHEpHapiAf/63PuE1yW8dVa8GK7u1T6KCGdUOP1AHcv2AC	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	64	\N	\N	\N
861	Madgl41	ahmadptk255@gmail.com	$2b$12$S1Jlbi8kPiBFPi/KGowHhOsgOBEsFQ53QDb61xIMSrexIxB17PcxO	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	65	\N	\N	\N
863	rajakaya88	selembestore7288@gmail.com	$2b$12$BQBZXFvjbp1EYfpRuD3E2uQDrUhO/kwJLK/Uf/4MSgeZk.srum42G	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	66	\N	\N	\N
865	Ryanmus	Muspijatkalbar@gmail.com	$2b$12$wVKO3qOG1KLKkIy98Ou3C..qW9wVpRDV3RQcAzuX0pFyFU4LAMCem	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	67	\N	\N	\N
867	RICHMAN99	dedinetizen3@gmail.com	$2b$12$WMHBwZJx/l9.LZ/ODDxtPOTmmV1I4McjL6vWbkGLawLB66Z1fqvBa	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	68	\N	\N	\N
869	kasyifa	cupel1978@gmail.com	$2b$12$n1EdKH7mU2AvFvC3qUiRieNJrgQN//q1VXVH5AutnQ5BSk4q91WzO	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	69	\N	\N	\N
871	lascarya99	malancarjaya77@gmail.com	$2b$12$0WBvcxmj7dHA3uA/3JclkOmVC3m67Ke1qyKjg4c5uX3oDiuQ.bLZ6	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	70	\N	\N	\N
873	abba2026	hasbi.alkhair07@gmail.com	$2b$12$i0id5Dfp40LF/7DhpZBm9.79uDpxYgG6QVLW/MfEQPkVK4Lz.pXbO	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	71	\N	\N	\N
875	Kijang12	nurali.februari@gmail.com	$2b$12$RuSUEoFHV6iEsJyiZbltVe3E2lYlzB.e79Z8uWFXzT2lGcS1TBLl2	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	72	\N	\N	\N
877	mustafa2026	mustafa2251212@gmail.com	$2b$12$28yRXcL.aBZJEdERvrntVugY2q5gEAm.RKU7lv7RczZRzrjT1650C	SUSPENDED	\N	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	73	\N	\N	\N
1047	Greatgirl924	javeedsanam4@gmail.com	$2b$12$oCBHBU4znQWjDxQ1vGKteOSu/d0EcxmFIlMWmNBRpXvoJCJNfiWDS	ACTIVE	2026-09-04 21:07:10.122+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	251	2026-09-04 21:07:10.122+07	\N	\N
1049	Hasbieuwais	hasbieuwais@gmail.com	$2b$10$tHMthkR5e9jkoovTV9V9sODAHCc.5uaq8zgJA4OJaRauye8rFi/2i	ACTIVE	2026-09-04 22:33:28.186+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	252	2026-09-04 22:33:28.186+07	\N	\N
1051	opryuubot	opryuubot@gmail.com	$2b$10$A2sP2BglVW.cmVwwmSsd1.pEz7Fkg51GmKs5tTWx2jQFU1bBbuDz.	ACTIVE	2026-09-07 15:55:26.565163+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	254	2026-09-07 15:55:26.565163+07	\N	\N
1053	langgananbot	langgananbot@gmail.com	$2b$10$rjkalN.H/NvGMwpX55nCke/r6.i1nvHTPcjpEKkQK6jOLJSD6VC2G	ACTIVE	2026-09-07 15:57:40.505862+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	255	2026-09-07 15:57:40.505862+07	\N	\N
1055	sifaw001	nana.suka00111@gmail.com	$2b$10$RUF9l4MpUfKxFFCJiowdC.6ITQzcAkxZmJcgpcIsIUhG9xsv29eZO	ACTIVE	2026-09-07 16:04:53.287094+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	257	2026-09-07 16:04:53.287094+07	\N	\N
1057	kucingkecil99	ptsevenkinternasional@gmail.com	$2b$10$NG7.whkgA9twNRMziqQG.ObxkiOrHzhH8QN10KSohWKlbGDLoGn1W	ACTIVE	2026-09-08 11:15:57.444908+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	258	2026-09-08 11:15:57.444908+07	\N	\N
879	Mahyuddin2026	mahyuddinagun@gmail.com	$2b$12$mMn2par32NgZh.hnXipKpuD3KzdHwVpYZa5164qdPkuvNB.60pF7C	SUSPENDED	\N	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	74	\N	\N	\N
1089	Babakai	eko.saputra.not2@gmail.com	$2a$10$TuqFYo0ZoUJ/A7wipnfF1eln.7zKuNV1e5TDvZ8WBfEuEscvRZZ4i	ACTIVE	2026-09-11 12:08:24.867986+07	2026-09-20 03:05:38.613001+07	2026-09-21 04:48:49.556868+07	296	2026-09-11 12:08:24.867986+07	\N	\N
881	Zidan1307	zidanalazhari1307@gmail.com	$2b$12$vcXDxUst.Q6WkTewmlMu1.eV/s7HNF3Y1Yw7mjb/BudXy7VGoo5VK	SUSPENDED	\N	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	75	\N	\N	\N
883	Stef8844	haryono8844@gmail.com	$2b$12$z8n2JN8kBvSALVtr90fjle5heZHHQYjnpIlru5VCift96caDq/eNW	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	76	\N	\N	\N
885	abdulrasyid992	abdulrasyid992@gmail.com	$2b$12$uIHebl.kHDS1qOWKsMPcS.hPnV5TuiRkts8Rwh5i0arSTrSkKitBq	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	77	\N	\N	\N
887	Vidhi71	widhiyanto210472@gmail.com	$2b$12$ul4cgD2qCG8relMujd5bueodYFxhk3DKrUly//SRwc05fX4OYnbnS	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	78	\N	\N	\N
889	longrudi	rezkibarokah69@gmail.com	$2b$12$18uemNNooCLvjmGr96aNG.wdAFk4MI.UQTQiJLF/rInFR74NKo4Uy	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	79	\N	\N	\N
891	SOELTAN99	abaa80569@gmail.com	$2b$12$AMp0zNaFCy1kXO.YQrAi6.GoalV3JW/No6aTtt6dQQDcAuKI9hIe6	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	80	\N	\N	\N
893	KROWE	ipungkrowe@gmail.com	$2b$12$Xbn6neCoarQ9YRgaxOmXhOJyhmooSDlU/VD8srbcQGCHYFlYwRkAy	SUSPENDED	\N	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	81	\N	\N	\N
895	KROWE1	ipungkrowe1@gmail.com	$2b$12$/n1toxoowoFASkBSUyU0D.IpfSPxRZlY6uymdNl5w.zpy31rXKccO	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	82	\N	\N	\N
897	Rajasultan26	ranasukses15@gmail.com	$2b$12$V7I58hKGsLcCXUKiVkW/mugZdgSlS/MfET72Areqc17LxHyjOHFJi	SUSPENDED	\N	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	83	\N	\N	\N
899	BUDAKPONTI99	rammalik.kurnia@gmail.com	$2b$12$QrPu3xL6CD/imwWkOOA3SO5LI/UJtiFyWWURf9pZ1mWbK.eRlMxqC	SUSPENDED	\N	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	84	\N	\N	\N
901	GUSMAN62	paktugiman1962@gmail.com	$2b$12$wXogfICNOCm3vEoYE3oGV.6l9KDxHXrpohZ48dPdT8WAIeNjOSkIC	ACTIVE	\N	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	85	\N	\N	\N
1059	Fadilaja1	fadilnewfadil86@gmail.com	$2b$12$RjFR5z3IjTQJGO3rJa2tB.5O6/QoW4ulfe55v2EpJ4n0SC1yf42Nm	ACTIVE	2026-09-09 12:10:59.345806+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	263	2026-09-09 12:10:59.345806+07	\N	\N
1061	BayoeWest	ciacio.west32@gmail.com	$2b$12$FYowgHU7AFT6Xfu.V2I5D.AUJVLC68lcLLGdw4W3TCFlWrYDoGP1y	ACTIVE	2026-09-09 12:37:28.825058+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	265	2026-09-09 12:37:28.825058+07	\N	\N
1063	nareaz	xgogigagagagigo.01@gmail.com	$2b$10$LiCtlGP3Qmrk7qi0cRmf/Orp3z21yCAOSO9Rc04fjrqVJ1Fmg2dSG	ACTIVE	2026-09-09 13:44:01.762048+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	266	2026-09-09 13:44:01.762048+07	\N	\N
1065	Iman2026	imanuddin2017@gmail.com	$2b$10$ZloeyWSK4bzT/a3Fcmecju.M9BEfFkRNK5Lya4Gbtne8hkImbbcFa	ACTIVE	2026-09-09 14:09:32.539089+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	267	2026-09-09 14:09:32.539089+07	\N	\N
1097	sakti13	sakti13@gmail.com	$2a$10$/PA2B.doTYlTMmQYmVjTpO1WiSAOKGNqTZ1bStBNZeM5PqnCj3s7C	ACTIVE	2026-09-14 07:47:37.003223+07	2026-09-20 03:05:38.613001+07	2026-09-21 04:45:11.573169+07	302	2026-09-14 07:47:37.003223+07	\N	\N
903	MARTINI56	martinisri56@gmail.com	$2b$12$6MciDxdwhSIXFWJ6jMPiGO73oxY6fPtf7n9Dfd0l1EMG9j707s/Vu	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	86	\N	\N	\N
1095	sakti12	sakti12@gmail.com	$2a$10$M3hC5Mu1qJIg5KpKO1u8iOtRnLz7hEG35P470dKwNuMtOkRyi9/Da	ACTIVE	2026-09-14 07:07:53.761093+07	2026-09-20 03:05:38.613001+07	2026-09-21 04:46:00.351198+07	301	2026-09-14 07:07:53.761093+07	\N	\N
905	ewako	kopisusu2024@gmail.com	$2b$12$5ysJ78F1q1wOtkJwkgSVWOPzL/7Lss2vXKJQ55lzNyrE7vW1o7J9y	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	87	\N	\N	\N
907	depot123	ramliasalam10@gmail.com	$2b$12$8FNWoFx9RwT2AFjTs.K2Hu58BuNtDzzez8bOESgyyMjiJij358C8m	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	88	\N	\N	\N
909	sudarmaji	sudarmaji@gmail.com	$2b$12$BQs402gpEHk6Qp45bMsGUevGNarsqeyxqFCggGbPYt19JgJI/nreu	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	89	\N	\N	\N
1093	narendraz11	zrlax013@gmail.com	$2a$10$VkyFevSERIB8tmEt5SxnlO7h/qqwLbrWnE73Ql8VgR64Dw4kNtoS6	SUSPENDED	2026-09-13 15:30:49.88012+07	2026-09-20 03:05:38.613001+07	2026-09-21 04:47:41.794622+07	300	2026-09-13 15:30:49.88012+07	\N	\N
911	smartboss1975	daengmanurung@gmail.com	$2b$12$3RPPtplwcXUCM9LJBz12KuXh1p3C4CtRt9QrrkSTM.cl8H7k.Ppqi	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	90	\N	\N	\N
913	SERDAM01	badaliimam62@gmail.com	$2b$12$UKxQzOBRfq.PYPuRFP2tj.N/XicC25golpHsL7/hKVvPTOgvjGR0K	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	91	\N	\N	\N
1091	MARIAKAYA	bilzarchannel@gmail.com	$2a$10$xyxn17KDo.vjaeXYbyKG3OVMfEn8FdiF0R3r4ORpVLNvuqzaE5n5u	ACTIVE	2026-09-12 09:02:36.799897+07	2026-09-20 03:05:38.613001+07	2026-09-21 04:48:00.652156+07	299	2026-09-12 09:02:36.799897+07	\N	\N
915	GUSMAN962	tugimanpnk98@gmail.com	$2b$12$1tTDN2J.v5CgxjFQ2d90UeRK2Q1/fMLjBsfWTHsXWT7FKNjIh3/lG	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	92	\N	\N	\N
917	gokong79	herrylung7@gmail.com	$2b$12$T7na7favKrpXVA7ek0LwkeDu6Yo/cpYtd2gTjVKKTMimmtGzuptkS	SUSPENDED	\N	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	93	\N	\N	\N
919	Obet5893	obetla7@gmail.com	$2b$12$kYrkS/hxb2JEBLyM1oqR1OjIqAaAFCzGapXWX4WDVAmGvkxgQDssS	SUSPENDED	\N	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	94	\N	\N	\N
921	Bro123	jayasaputro999@gmail.com	$2b$12$yKvYIFFj0q91IkMRRvw5b.lJqTNE9G919erLa/9iwRb4S/0OxgKcm	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	95	\N	\N	\N
923	saudagarcoin	support@smartbotapps.com	$2b$10$CHYauzY.dRglAovv45ELGuiz0..myD/0THZuzhtvoKZY2n/DUjzbG	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	96	\N	\N	\N
925	Alamjaya	thzsukses@gmail.com	$2b$12$HN6u6O.AupA.iuLMwMi2eusW6uRX8o9yZvu8PsrE3OBYxjr9ICRWe	SUSPENDED	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	97	\N	\N	\N
927	kingprofits	owner@smartbotapps.com	$2b$10$EGlYolbNiVsLtKF8Zfbj5.7vYzRnDBnrZ76Cn71dYZeavOxu2NoIm	ACTIVE	\N	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	98	\N	\N	\N
929	Ar99	rmnmn311279@gmail.com	$2b$10$3UT3aHjGCmNH9z3FnzCTX.aSxsqmLCAD48lJQrfLn5Wgtyn5BdloK	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	116	\N	\N	\N
931	Ar999	rmnmn432@gmail.com	$2b$12$tnsFZK24Wz0BEAO4TChfEOMMjFX3yzyAMIf8wK7gKywS552T.xT.G	SUSPENDED	2026-09-25 19:45:42.305+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	118	2026-08-25 00:52:13.263+07	\N	\N
933	bi4nc4	rmnmn234@gmail.com	$2b$10$O.ijoT4ACuiT1A5a3DSAxeU4/LFz/oJWl2nsa8L/3XTQCKDZG.jWm	ACTIVE	2026-09-25 19:45:29.008+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	121	2026-08-25 00:57:04.035+07	\N	\N
935	bianc	rmnmn89@gmail.com	$2b$10$EnQN2FmpDklN64KmEn3LJOEmxwge1vuXwkINCgDfaPM66ALd1FLF2	ACTIVE	2026-09-25 19:45:17.486+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	124	2026-08-25 01:19:22.13+07	\N	\N
937	Putramandau	dadiktp7019@gmail.com	$2b$10$Q5sjhCFmO7fNq0uKb8I1Du6FnqVLkonTUejrFFRZ.NsiHAL0iQotu	ACTIVE	2026-08-25 16:05:21.97+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	129	2026-08-25 16:05:21.97+07	\N	\N
939	Marlinok	sumarlinutiarahman79@gmail.com	$2b$10$ECF.3wWcI/2z.Q8Pu9YrTOYkki9ij6rJ.GViunwPAvf9H1eIcYx7K	ACTIVE	2026-08-25 16:18:45.471+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	130	2026-08-25 16:18:45.471+07	\N	\N
941	Nirwana99	andisuryadi790@gmail.com	$2b$10$xyBuqFj5cuETjwgGBVtKmOFxRwRp4B/RMcVuhdth9KiZiPDzo9X2K	ACTIVE	2026-08-25 16:26:29.333+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	134	2026-08-25 16:26:29.333+07	\N	\N
943	Mraj111	Mrajsingh707@gmail.com	$2b$10$rOsabC433m5R0uz.ogjfTuBUHnHVI5Xf24soxHHWFSB9EVaIgHHnG	ACTIVE	2026-09-26 13:44:46.144+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	135	2026-08-26 01:24:30.841+07	\N	\N
945	Piko99	tommysunjoto66@gmail.com	$2b$10$iUIP66tCsMAHImXq.cfqpONk4ub4LBkSgNrymxOJNp4AazmwJEdKm	ACTIVE	2026-09-26 15:43:47.489+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	138	2026-08-26 14:40:24.18+07	\N	\N
947	Sehati69	supripst616@gmail.com	$2b$10$neeMob4lDdYV5uUItTkMMO8rjSMqy66R3iAZHAOucoNGd91dvq8wG	ACTIVE	2026-09-26 19:53:31.587+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	140	2026-08-26 17:15:04.026+07	\N	\N
973	nitatajir	princenezardmahmud@gmail.com	$2b$10$9pH3P87BszZNmm7LyMFdEuWKceoiZHWQc2pNDj1vZqYPxkWXiUE/u	ACTIVE	2026-09-29 20:24:07.772+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	166	2026-08-29 20:07:00.132+07	\N	\N
975	Renisejahtera	rherereni140@gmail.com	$2b$10$rdf9KYrPNfr5chVoS8eLx.3DbujlDz/ZlfHEfpzWfpavZKWTxIwWq	ACTIVE	2026-08-29 21:23:02.049+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	169	2026-08-29 21:23:02.049+07	\N	\N
977	Senia99	ptski2024@gmail.com	$2b$10$JcX.ToCt3St/J33kbuLeEuWjzrmddU/gi57Mazh9j4bdgNn8/x9KS	ACTIVE	2026-08-30 09:33:52.605+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	171	2026-08-30 09:33:52.605+07	\N	\N
979	dwi28	samsunga32121112@gmail.com	$2b$12$FmBHIh.GIm05sLU.UirrN.cU2U1eaDgiLWpRyoWL4kbmlu3M94U0.	ACTIVE	2026-08-30 14:44:52.057+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	176	2026-08-30 14:44:52.057+07	\N	\N
981	renisanjaya	renijayati271@gmail.com	$2b$10$QsEW/Z8ZwxoXDVl/6SkvUustGJhg06xjxcpm3BM/Ni0MOGCkLzG7O	ACTIVE	2026-09-30 16:07:05.308+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	181	2026-08-30 15:22:56.623+07	\N	\N
983	Ani77	dwirahayuanggraini0909@gmail.com	$2b$12$0q4ysbKmibVxY7B0b9t9Zu7Tov6oLPuah.qA3MxmL/Y1LIqPQ.4Cq	ACTIVE	2026-09-30 21:58:05.157+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	182	2026-08-30 15:50:36.684+07	\N	\N
985	Yulieen	yulieen48@gmail.com	$2b$10$ZLAhBpQqWHY/jHzj16IG..x22UY0v5uMMURdEOAzagQMzpslh7/8y	ACTIVE	2026-08-30 16:14:54.181+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	183	2026-08-30 16:14:54.181+07	\N	\N
987	Widmar888	madona88ptk@gmail.com	$2b$10$R0X1fzZ915/TfzJrM7z7lO14FDG0Mhpuu9KIJ4IvOfKUCoWNbz8/6	ACTIVE	2026-09-30 18:48:25.935+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	186	2026-08-30 16:18:58.73+07	\N	\N
989	BERKAHONLINE	berkahonline1978@gmail.com	$2b$12$8a86sXJGMFMyZ46u.Rdm1.uT8HcOh3rUFF8CsYJlCdrBeldgTZ49y	ACTIVE	2026-08-30 16:43:01.117+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	187	2026-08-30 16:43:01.117+07	\N	\N
991	KINGCUAN19	kingcuanku19@gmail.com	$2b$10$oy2KRRftvNBKNrSb2iYpA.S6qzwGxzGED2PsfL7JYwzn38cOX8KZm	ACTIVE	2026-08-30 16:45:08.058+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	190	2026-08-30 16:45:08.058+07	\N	\N
1021	Mawar81	agustina311024@gmail.com	$2b$10$WRd/6jcbXoe7NxTzF8xvcO238Vv.NXiuJuLMQpJ99EkT/tdKfoQCC	ACTIVE	2026-10-01 21:22:07.771+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	223	2026-09-01 17:54:24.23+07	\N	\N
1023	divadollar	nurhalipahnurhalipah110@gmail.com	$2b$10$BaLsizfMhq8EAMCy6UhTZeSEZzFr435EF2ig9.DdzUK8Rt4de1.dm	ACTIVE	2026-10-01 21:18:20.677+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	224	2026-09-01 17:58:35.935+07	\N	\N
1025	Bangde123	pontianaksarmawati@gmail.com	$2b$12$8tRIHctxHZWa6tNubz96ce9Kl6VmPjF1Yp6BHHuuiN6JRIy3MtPnG	SUSPENDED	2026-09-01 20:57:47.943+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	225	2026-09-01 20:57:47.943+07	\N	\N
1027	Sejati80	muhammadsablii335@gmail.com	$2b$10$tnIwUcgQsD36Prm5YbfDZ.YMyAfKzmR7KZRik5nULDikeaZIIcrGS	ACTIVE	2026-09-01 21:52:22.069+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	226	2026-09-01 21:52:22.069+07	\N	\N
1029	WULANBOJO	samsianizainwabula@gmail.com	$2b$10$DdRL3ZwlDMb.QDFtWdhIKeBsJYvUBpkub3jte6bzUYJy6VEidhgMC	ACTIVE	2026-09-02 13:34:31.486+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	233	2026-09-02 13:34:31.486+07	\N	\N
1031	SITI99	sakirasakira157@gmail.com	$2b$10$20RSs4zwPBa./Qk1eN.Ev.gLJXGP8Dk1BBPUpZPF3X.emM2Zf4SqS	ACTIVE	2026-09-02 13:55:08.622+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	234	2026-09-02 13:55:08.622+07	\N	\N
1033	Hastuti	zuraidahhastuti96@gmail.com	$2b$12$mJt2TWgwDifex5e1ICIMD..WgJQRXjiPNvyv5LX/PP4F14R0sQf7.	ACTIVE	2026-10-02 16:38:44.328+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	235	2026-09-02 14:27:52.342+07	\N	\N
1035	Iincantik	iindendi260818@gmail.com	$2b$10$ohvPHMrjcb2tHB29OJU4PuonuEkwriFiYq7tYVKZhu6gKvWks5anO	ACTIVE	2026-10-02 15:34:27.094+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	238	2026-09-02 15:10:00.041+07	\N	\N
1037	fadil111	fadilputrafadil879@gmail.com	$2b$12$4UeMmWhILl0fOyTi63et9.nUtlGq82eNSSBeqV0dLd4V5NFPgPuly	ACTIVE	2026-09-02 15:41:58.515+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	239	2026-09-02 15:41:58.515+07	\N	\N
1039	Faloga88	falogawijaya@gmail.com	$2b$12$Ok9up15qKDAlYSePiwfdsOtMvDL0hZMWKsrQrAsDFkElyUReXM5pC	ACTIVE	2026-09-02 17:46:41.851+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	240	2026-09-02 17:46:41.851+07	\N	\N
1041	jingga235	warnicerah4@gmail.com	$2b$10$TEOncPKEVvTaSecm3MPc5eE//lBCzptz0OEXhPSbsYnN.sauJrf3C	ACTIVE	2026-09-02 20:07:51.159+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	244	2026-09-02 20:07:51.159+07	\N	\N
1085	Kincah	magnum125@gmail.com	$2a$10$N7IaM0avYWwmBJA6p3d1ru2Wr55yp44jbluRS78o2YX0ZqS68s5s6	ACTIVE	2026-09-11 06:28:50.346891+07	2026-09-20 03:05:38.613001+07	2026-09-21 04:49:48.758623+07	294	2026-09-11 06:28:50.346891+07	2026-09-21 04:50:01.26399+07	2026-09-21 10:29:05.045456+07
1067	hijariamin	mhijardjakim75@gmail.com	$2b$10$oQxvMJOzcWAvCHFjFj7rxuSRzysZa4rIe7Aan0stC2CZG0vJYvzx2	ACTIVE	2026-09-09 14:15:47.99684+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	269	2026-09-09 14:15:47.99684+07	\N	\N
1069	mugi331008	ymugi90@gmail.com	$2b$10$5hXntIizJC0wBzFEiVb4ZeLKfdVeQyLQstHf4TmLFAZiPJNdwagYq	ACTIVE	2026-09-09 14:26:55.074065+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	272	2026-09-09 14:26:55.074065+07	\N	\N
1071	cacacantik	hycca140705@gmail.com	$2b$12$Y7QwVLDBgzt2oxl8G8iQIOtGPQz4x7ewfxDKOsExyQhbY//eTtu1e	ACTIVE	2026-09-09 21:17:20.169146+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	277	2026-09-09 21:17:20.169146+07	\N	\N
1073	Hisyamalghifari	ssaknahsaknah@gmail.com	$2b$10$k/nXR35zSGvsMosjfR/v7uc1.7lcTKmww80PcgfGr43dFRnnTrbPm	ACTIVE	2026-09-10 05:37:28.764974+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	278	2026-09-10 05:37:28.764974+07	\N	\N
1075	SUMADI77	sumadi.77md@gmail.com	$2b$12$6cDQd4n5DxRwCUzwo6Pi1OQcM31yHermkt5mhEgqJcFk8WNiEFlcS	ACTIVE	2026-09-10 08:09:09.79157+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	288	2026-09-10 08:09:09.79157+07	\N	\N
1077	kayaraya889	petronaliaacu@gmail.com	$2b$10$DRuM8fuh4KcP1Jpd3UbeU..u5xh/Jxk2cOXJuYBFuj0hougMmHEVW	ACTIVE	2026-09-10 13:38:46.323722+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	290	2026-09-10 13:38:46.323722+07	\N	\N
1079	bloggerborneo	bloggerborneo@gmail.com	$2b$12$0AqKTWqUmTJ2DK1KwPaXseoCEQVDgQ9L3ZT3KB1I9.IOdwAO8DiJ6	SUSPENDED	2026-09-10 15:16:53.529191+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	291	2026-09-10 15:16:53.529191+07	\N	\N
1081	Fitrizakia	syarifahfitrizakia@gmail.com	$2b$12$iSJmhXBVmrv70BvFPGxIwObeAapdTq2U2BgIsrh4lekqVjqkSH.cO	SUSPENDED	2026-09-10 16:15:11.796692+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	292	2026-09-10 16:15:11.796692+07	\N	\N
1083	isambotak	hisyamalgifari8@gmail.com	$2b$12$m4v9DHToq7QjkoZeGq76nOjTbkmev77YJN1hWzaqJL1AeYDZlCiAG	SUSPENDED	2026-09-10 17:47:53.235146+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	293	2026-09-10 17:47:53.235146+07	\N	\N
1087	nareaz11	septisuryawann@gmail.com	$2b$12$F74.s.H1f16XHieZdWkYieNVdbl77./.UVJ7dtSL6G/3uw4R9Vlf6	SUSPENDED	2026-10-12 13:37:51.071985+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	295	2026-09-11 08:36:19.533411+07	\N	\N
1113	cuandong	hahshshs@gmail.com	$2a$10$d92jKRPkRLGcmJRrcFrRgOo22alZYfFfqe547KgAR0YTADSP9WbCK	ACTIVE	2026-09-20 20:57:26.991641+07	2026-09-20 03:05:38.613001+07	2026-09-21 04:37:10.36859+07	380	2026-09-20 20:57:26.991641+07	\N	\N
1105	Evi2909	eviaswandi29@gmail.com	$2b$12$mepBVLGb2wQgjfEIYHuzuuE5FUqkjf1xsykpv.w3fZpRZyXFHNUOG	ACTIVE	2026-10-14 19:54:25.010876+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	313	2026-09-14 19:54:25.010876+07	\N	\N
1111	zrlax01	zrlax01@gmail.com	$2a$10$vGYre4k9ECJK.TCjOolMz.YnQt.s3os5pFgWHa6vGjAIzk4aibSwC	ACTIVE	2026-09-19 12:32:59.277454+07	2026-09-20 03:05:38.613001+07	2026-09-21 04:38:04.512213+07	353	2026-09-19 12:32:59.277454+07	\N	\N
1109	SASQI367	safariglobal789@gmail.com	$2a$10$1OTEkHW8dFyLQpqHXCTaiOVLbpKuu0z9gbRu5gQEJgQszhSWd0iqS	ACTIVE	2026-09-18 00:21:12.988535+07	2026-09-20 03:05:38.613001+07	2026-09-21 04:39:03.160736+07	352	2026-09-18 00:21:12.988535+07	\N	\N
1115	ryuboss	bdev88888@gmail.com	$2b$10$RMd3fs.CFaKX9LftNAwAae54GB8xyLRl1eTXcUpBOwPtbBZBZzOqG	ACTIVE	2026-09-21 09:21:38.786432+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	381	2026-09-21 09:21:38.786432+07	\N	\N
1107	SUKSESBERHASIL	rejekisupri14@gmail.com	$2a$10$TKIBh6kU8Sb2mAxteERgduuMn7wy/l.Wu0GXOy8LDJouqPuvNQ0iG	ACTIVE	2026-09-16 13:00:15.806443+07	2026-09-20 03:05:38.613001+07	2026-09-21 04:40:20.998335+07	350	2026-09-16 13:00:15.806443+07	\N	\N
1103	Hery1074	heryjoyo74@gmail.com	$2a$10$OwGFoWakbdPMnFngjfxxh.0Z7OAu/YYs8yJinlDVHPbqhuN45NKca	ACTIVE	2026-09-14 19:53:11.965676+07	2026-09-20 03:05:38.613001+07	2026-09-21 04:41:16.57471+07	312	2026-09-14 19:53:11.965676+07	\N	\N
1101	Permadi	adhierealme2025@gmail.com	$2a$10$qsiic6d5fFi6hoohQb1Nceiphs78QLqTENexZXrQ14SVOsb0RS376	ACTIVE	2026-09-14 16:32:22.253839+07	2026-09-20 03:05:38.613001+07	2026-09-21 04:42:54.704596+07	311	2026-09-14 16:32:22.253839+07	\N	\N
1099	Bangkaben	taufik0001@gmail.com	$2a$10$RbJO/va7lnVcUlONXI0eDewhYisKd0C01ay/Knc71/toKNSBo.h2.	SUSPENDED	2026-09-14 10:52:16.156938+07	2026-09-20 03:05:38.613001+07	2026-09-21 04:44:57.156642+07	303	2026-09-14 10:52:16.156938+07	\N	\N
\.


--
-- Data for Name: wallet_operations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wallet_operations (request_id, user_id, operation, coin, amount, destination, status, provider_response, failure_reason, created_at, updated_at, completed_at) FROM stdin;
e44492f4-669f-4a64-9deb-85eab4525e07	749	TRANSFER	TRX	0.00002938	maklampir88	FAILED	\N	Proses aplikasi terputus sebelum respons selesai	2026-09-20 15:00:13.382043+07	2026-09-20 15:16:16.083031+07	\N
fd9239be-09df-4648-aaa3-98405e94d404	749	TRANSFER	FLOKI	56831.09572828	maklampir88	PROCESSING	\N	\N	2026-09-20 15:16:56.45155+07	2026-09-20 15:16:56.45155+07	\N
b23daa95-1a2e-4e23-b7d6-a1b529240f41	749	TRANSFER	BTT	2045031.44725445	maklampir88	PROCESSING	\N	\N	2026-09-20 15:21:35.671509+07	2026-09-20 15:21:35.671509+07	\N
7948f9b5-1eb2-4f46-a70e-49dc420be814	1103	TRANSFER	BTT	9273437.42242567	maklampir88	PROCESSING	\N	\N	2026-09-21 04:42:20.021099+07	2026-09-21 04:42:20.021099+07	\N
b123f895-03c4-4ca6-a792-775677a75397	1095	TRANSFER	BTT	1530062.58978139	maklampir88	PROCESSING	\N	\N	2026-09-21 04:46:35.929363+07	2026-09-21 04:46:35.929363+07	\N
65c0ec54-ad1c-47c0-8fcf-8f8e9f65b336	1093	TRANSFER	BTT	541464.27043744	maklampir88	PROCESSING	\N	\N	2026-09-21 04:47:30.830424+07	2026-09-21 04:47:30.830424+07	\N
92da856d-b797-4cdf-9ac1-8dbee1682f19	749	TRANSFER	BTT	162739.59840780	maklampir88	PROCESSING	\N	\N	2026-09-21 16:48:02.147988+07	2026-09-21 16:48:02.147988+07	\N
eb7231b0-f68e-4a6d-9d12-535a4ca89e2b	749	TRANSFER	FLOKI	693.18541611	maklampir88	PROCESSING	\N	\N	2026-09-21 16:48:26.470599+07	2026-09-21 16:48:26.470599+07	\N
cc382e81-eb93-4b6a-a738-4d782386d225	749	TRANSFER	TRX	1.33200140	maklampir88	COMPLETED	{"coin": "TRX", "amount": "1.33200140", "balance": "0.00000000", "message": "Successfully transferred to user", "success": true}	\N	2026-09-23 10:21:52.43178+07	2026-09-23 10:21:52.738314+07	2026-09-23 10:21:52.738314+07
413dd927-9768-455d-aaba-868a1e4ea94e	749	TRANSFER	DOGE	132.33221608	maklampir88	COMPLETED	{"coin": "DOGE", "amount": "132.33221608", "balance": "0.00000000", "message": "Successfully transferred to user", "success": true}	\N	2026-09-23 10:35:02.084181+07	2026-09-23 10:35:02.418382+07	2026-09-23 10:35:02.418382+07
8267c20c-df7c-4c57-893e-5146230d78c1	749	TRANSFER	FLOKI	3134198.56301864	maklampir88	COMPLETED	{"coin": "FLOKI", "amount": "3134198.56301864", "balance": "0.00000000", "message": "Successfully transferred to user", "success": true}	\N	2026-09-23 10:35:22.960689+07	2026-09-23 10:35:23.279593+07	2026-09-23 10:35:23.279593+07
62f85e1d-a134-4302-bd32-99ac39561589	749	TRANSFER	BTT	114483138.91926335	maklampir88	COMPLETED	{"coin": "BTT", "amount": "114483138.91926335", "balance": "0.00000000", "message": "Successfully transferred to user", "success": true}	\N	2026-09-23 10:35:43.221517+07	2026-09-23 10:35:43.531814+07	2026-09-23 10:35:43.531814+07
9acfd273-70b2-4ecb-8084-9dfdd15df51a	747	WITHDRAW	DOGE	133.91591444	DAVAirc3y8RQMzUDM7DUGtK75vkQ7VC534	COMPLETED	{"coin": "DOGE", "balance": "0.00000000", "message": "Your withdrawal has been placed successfully. It will be processed shortly after moderator review.", "success": true}	\N	2026-09-23 10:37:54.404793+07	2026-09-23 10:37:54.820379+07	2026-09-23 10:37:54.820379+07
f71f8c5a-977d-4443-ac73-9f007454f044	747	WITHDRAW	FLOKI	3327198.01611195	0x1ab09ce9a78bd167e84d43df877a7e1b3a6c8ff0	COMPLETED	{"coin": "FLOKI", "balance": "0.00000000", "message": "Your withdrawal has been placed successfully. It will be processed shortly after moderator review.", "success": true}	\N	2026-09-23 10:38:39.874834+07	2026-09-23 10:38:40.399236+07	2026-09-23 10:38:40.399236+07
618bf20b-19ef-47c1-987d-bef717c347f9	747	WITHDRAW	BTT	139272009.93719143	TWESo9Qfa1Gdxo7vomDVunZV26eNTmcw3d	COMPLETED	{"coin": "BTT", "balance": "0.00000000", "message": "Your withdrawal has been placed successfully. It will be processed shortly after moderator review.", "success": true}	\N	2026-09-23 10:39:37.95178+07	2026-09-23 10:39:38.274562+07	2026-09-23 10:39:38.274562+07
\.


--
-- Name: admin_business_rule_audit_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.admin_business_rule_audit_id_seq', 2, true);


--
-- Name: admin_user_actions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.admin_user_actions_id_seq', 24, true);


--
-- Name: admin_users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.admin_users_id_seq', 2, true);


--
-- Name: app_settings_audit_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.app_settings_audit_id_seq', 14, true);


--
-- Name: business_rule_versions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.business_rule_versions_id_seq', 1, true);


--
-- Name: trading_events_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.trading_events_id_seq', 866, true);


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.users_id_seq', 2232, true);


--
-- Name: admin_business_rule_audit admin_business_rule_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.admin_business_rule_audit
    ADD CONSTRAINT admin_business_rule_audit_pkey PRIMARY KEY (id);


--
-- Name: admin_sessions admin_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.admin_sessions
    ADD CONSTRAINT admin_sessions_pkey PRIMARY KEY (token_hash);


--
-- Name: admin_user_actions admin_user_actions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.admin_user_actions
    ADD CONSTRAINT admin_user_actions_pkey PRIMARY KEY (id);


--
-- Name: admin_users admin_users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT admin_users_pkey PRIMARY KEY (id);


--
-- Name: app_setting_categories app_setting_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.app_setting_categories
    ADD CONSTRAINT app_setting_categories_pkey PRIMARY KEY (key);


--
-- Name: app_settings_audit app_settings_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.app_settings_audit
    ADD CONSTRAINT app_settings_audit_pkey PRIMARY KEY (id);


--
-- Name: app_settings app_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.app_settings
    ADD CONSTRAINT app_settings_pkey PRIMARY KEY (key);


--
-- Name: business_rule_versions business_rule_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.business_rule_versions
    ADD CONSTRAINT business_rule_versions_pkey PRIMARY KEY (id);


--
-- Name: business_rule_versions business_rule_versions_version_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.business_rule_versions
    ADD CONSTRAINT business_rule_versions_version_key UNIQUE (version);


--
-- Name: coin_rule_versions coin_rule_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.coin_rule_versions
    ADD CONSTRAINT coin_rule_versions_pkey PRIMARY KEY (business_rule_version_id, coin);


--
-- Name: import_runs import_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.import_runs
    ADD CONSTRAINT import_runs_pkey PRIMARY KEY (id);


--
-- Name: management_fee_payouts management_fee_payouts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.management_fee_payouts
    ADD CONSTRAINT management_fee_payouts_pkey PRIMARY KEY (id);


--
-- Name: owner_cutoff_batches owner_cutoff_batches_business_date_cutoff_slot_coin_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.owner_cutoff_batches
    ADD CONSTRAINT owner_cutoff_batches_business_date_cutoff_slot_coin_key UNIQUE (business_date, cutoff_slot, coin);


--
-- Name: owner_cutoff_batches owner_cutoff_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.owner_cutoff_batches
    ADD CONSTRAINT owner_cutoff_batches_pkey PRIMARY KEY (id);


--
-- Name: owner_cutoff_payouts owner_cutoff_payouts_batch_id_allocation_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.owner_cutoff_payouts
    ADD CONSTRAINT owner_cutoff_payouts_batch_id_allocation_key UNIQUE (batch_id, allocation);


--
-- Name: owner_cutoff_payouts owner_cutoff_payouts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.owner_cutoff_payouts
    ADD CONSTRAINT owner_cutoff_payouts_pkey PRIMARY KEY (id);


--
-- Name: provider_bets provider_bets_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.provider_bets
    ADD CONSTRAINT provider_bets_pkey PRIMARY KEY (id);


--
-- Name: provider_bets provider_bets_provider_reference_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.provider_bets
    ADD CONSTRAINT provider_bets_provider_reference_key UNIQUE (provider_reference);


--
-- Name: referral_bonus_balances referral_bonus_balances_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.referral_bonus_balances
    ADD CONSTRAINT referral_bonus_balances_pkey PRIMARY KEY (user_id, coin);


--
-- Name: referral_bonus_events referral_bonus_events_event_type_source_external_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.referral_bonus_events
    ADD CONSTRAINT referral_bonus_events_event_type_source_external_id_key UNIQUE (event_type, source_external_id);


--
-- Name: referral_bonus_events referral_bonus_events_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.referral_bonus_events
    ADD CONSTRAINT referral_bonus_events_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (name);


--
-- Name: trading_commands trading_commands_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trading_commands
    ADD CONSTRAINT trading_commands_pkey PRIMARY KEY (id);


--
-- Name: trading_commands trading_commands_request_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trading_commands
    ADD CONSTRAINT trading_commands_request_id_key UNIQUE (request_id);


--
-- Name: trading_events trading_events_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trading_events
    ADD CONSTRAINT trading_events_pkey PRIMARY KEY (id);


--
-- Name: trading_fee_balances trading_fee_balances_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trading_fee_balances
    ADD CONSTRAINT trading_fee_balances_pkey PRIMARY KEY (user_id, coin);


--
-- Name: trading_sessions trading_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trading_sessions
    ADD CONSTRAINT trading_sessions_pkey PRIMARY KEY (id);


--
-- Name: user_pasino_accounts user_pasino_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_pasino_accounts
    ADD CONSTRAINT user_pasino_accounts_pkey PRIMARY KEY (user_id);


--
-- Name: user_pasino_accounts user_pasino_accounts_provider_username_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_pasino_accounts
    ADD CONSTRAINT user_pasino_accounts_provider_username_key UNIQUE (provider_username);


--
-- Name: user_referrals user_referrals_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_referrals
    ADD CONSTRAINT user_referrals_pkey PRIMARY KEY (user_id);


--
-- Name: user_sessions user_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT user_sessions_pkey PRIMARY KEY (token_hash);


--
-- Name: user_trading_settings user_trading_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_trading_settings
    ADD CONSTRAINT user_trading_settings_pkey PRIMARY KEY (user_id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: wallet_operations wallet_operations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_operations
    ADD CONSTRAINT wallet_operations_pkey PRIMARY KEY (request_id);


--
-- Name: admin_business_rule_audit_version_time; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX admin_business_rule_audit_version_time ON public.admin_business_rule_audit USING btree (business_rule_version_id, created_at DESC);


--
-- Name: admin_sessions_expiry; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX admin_sessions_expiry ON public.admin_sessions USING btree (expires_at);


--
-- Name: admin_user_actions_user_time; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX admin_user_actions_user_time ON public.admin_user_actions USING btree (user_id, created_at DESC);


--
-- Name: admin_users_username_lower_unique; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX admin_users_username_lower_unique ON public.admin_users USING btree (lower((username)::text));


--
-- Name: app_settings_category_order; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX app_settings_category_order ON public.app_settings USING btree (category, sort_order, key);


--
-- Name: business_rule_versions_one_active; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX business_rule_versions_one_active ON public.business_rule_versions USING btree (status) WHERE ((status)::text = 'ACTIVE'::text);


--
-- Name: management_fee_payouts_one_unresolved; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX management_fee_payouts_one_unresolved ON public.management_fee_payouts USING btree (source_user_id, coin, allocation) WHERE ((status)::text = ANY ((ARRAY['PREPARED'::character varying, 'SENT'::character varying, 'REVIEW_REQUIRED'::character varying])::text[]));


--
-- Name: provider_bets_one_pending_session; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX provider_bets_one_pending_session ON public.provider_bets USING btree (session_id) WHERE ((status)::text = ANY ((ARRAY['PREPARED'::character varying, 'SENT'::character varying, 'RECONCILIATION_REQUIRED'::character varying])::text[]));


--
-- Name: provider_bets_user_time; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX provider_bets_user_time ON public.provider_bets USING btree (user_id, prepared_at DESC);


--
-- Name: referral_bonus_events_user_time; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX referral_bonus_events_user_time ON public.referral_bonus_events USING btree (user_id, occurred_at DESC);


--
-- Name: trading_commands_pending_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX trading_commands_pending_idx ON public.trading_commands USING btree (created_at) WHERE ((status)::text = 'PENDING'::text);


--
-- Name: trading_commands_processing_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX trading_commands_processing_idx ON public.trading_commands USING btree (updated_at) WHERE ((status)::text = 'PROCESSING'::text);


--
-- Name: trading_events_user_id_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX trading_events_user_id_idx ON public.trading_events USING btree (user_id, id DESC);


--
-- Name: trading_sessions_one_unresolved_user; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX trading_sessions_one_unresolved_user ON public.trading_sessions USING btree (user_id) WHERE ((status)::text = ANY ((ARRAY['RUNNING'::character varying, 'STOP_REQUESTED'::character varying, 'RECONCILIATION_REQUIRED'::character varying])::text[]));


--
-- Name: trading_sessions_recoverable_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX trading_sessions_recoverable_idx ON public.trading_sessions USING btree (lease_expires_at) WHERE ((status)::text = ANY ((ARRAY['RUNNING'::character varying, 'STOP_REQUESTED'::character varying])::text[]));


--
-- Name: user_pasino_accounts_access_expiry; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX user_pasino_accounts_access_expiry ON public.user_pasino_accounts USING btree (access_token_expires_at);


--
-- Name: user_referrals_referrer_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX user_referrals_referrer_idx ON public.user_referrals USING btree (referrer_user_id);


--
-- Name: user_sessions_user_expiry; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX user_sessions_user_expiry ON public.user_sessions USING btree (user_id, expires_at);


--
-- Name: users_email_lower_unique; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX users_email_lower_unique ON public.users USING btree (lower((email)::text));


--
-- Name: users_last_active_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX users_last_active_idx ON public.users USING btree (last_active_at DESC NULLS LAST);


--
-- Name: users_legacy_user_id_unique; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX users_legacy_user_id_unique ON public.users USING btree (legacy_user_id) WHERE (legacy_user_id IS NOT NULL);


--
-- Name: users_username_lower_unique; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX users_username_lower_unique ON public.users USING btree (lower((username)::text));


--
-- Name: wallet_operations_user_created_idx; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX wallet_operations_user_created_idx ON public.wallet_operations USING btree (user_id, created_at DESC);


--
-- Name: trading_commands trading_commands_notify; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trading_commands_notify AFTER INSERT ON public.trading_commands FOR EACH ROW EXECUTE FUNCTION public.notify_ryubot_trading_command();


--
-- Name: trading_events trading_events_notify; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trading_events_notify AFTER INSERT ON public.trading_events FOR EACH ROW EXECUTE FUNCTION public.notify_ryubot_trading_event();


--
-- Name: admin_business_rule_audit admin_business_rule_audit_admin_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.admin_business_rule_audit
    ADD CONSTRAINT admin_business_rule_audit_admin_user_id_fkey FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id) ON DELETE RESTRICT;


--
-- Name: admin_business_rule_audit admin_business_rule_audit_business_rule_version_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.admin_business_rule_audit
    ADD CONSTRAINT admin_business_rule_audit_business_rule_version_id_fkey FOREIGN KEY (business_rule_version_id) REFERENCES public.business_rule_versions(id) ON DELETE RESTRICT;


--
-- Name: admin_sessions admin_sessions_admin_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.admin_sessions
    ADD CONSTRAINT admin_sessions_admin_user_id_fkey FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id) ON DELETE CASCADE;


--
-- Name: admin_user_actions admin_user_actions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.admin_user_actions
    ADD CONSTRAINT admin_user_actions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: app_settings_audit app_settings_audit_admin_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.app_settings_audit
    ADD CONSTRAINT app_settings_audit_admin_user_id_fkey FOREIGN KEY (admin_user_id) REFERENCES public.admin_users(id) ON DELETE RESTRICT;


--
-- Name: app_settings app_settings_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.app_settings
    ADD CONSTRAINT app_settings_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.admin_users(id) ON DELETE RESTRICT;


--
-- Name: business_rule_versions business_rule_versions_activated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.business_rule_versions
    ADD CONSTRAINT business_rule_versions_activated_by_fkey FOREIGN KEY (activated_by) REFERENCES public.admin_users(id) ON DELETE RESTRICT;


--
-- Name: business_rule_versions business_rule_versions_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.business_rule_versions
    ADD CONSTRAINT business_rule_versions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.admin_users(id) ON DELETE RESTRICT;


--
-- Name: coin_rule_versions coin_rule_versions_business_rule_version_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.coin_rule_versions
    ADD CONSTRAINT coin_rule_versions_business_rule_version_id_fkey FOREIGN KEY (business_rule_version_id) REFERENCES public.business_rule_versions(id) ON DELETE CASCADE;


--
-- Name: management_fee_payouts management_fee_payouts_source_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.management_fee_payouts
    ADD CONSTRAINT management_fee_payouts_source_user_id_fkey FOREIGN KEY (source_user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: owner_cutoff_payouts owner_cutoff_payouts_batch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.owner_cutoff_payouts
    ADD CONSTRAINT owner_cutoff_payouts_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES public.owner_cutoff_batches(id) ON DELETE RESTRICT;


--
-- Name: provider_bets provider_bets_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.provider_bets
    ADD CONSTRAINT provider_bets_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.trading_sessions(id) ON DELETE CASCADE;


--
-- Name: provider_bets provider_bets_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.provider_bets
    ADD CONSTRAINT provider_bets_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: referral_bonus_balances referral_bonus_balances_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.referral_bonus_balances
    ADD CONSTRAINT referral_bonus_balances_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: referral_bonus_events referral_bonus_events_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.referral_bonus_events
    ADD CONSTRAINT referral_bonus_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: trading_commands trading_commands_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trading_commands
    ADD CONSTRAINT trading_commands_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.trading_sessions(id) ON DELETE RESTRICT;


--
-- Name: trading_commands trading_commands_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trading_commands
    ADD CONSTRAINT trading_commands_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: trading_events trading_events_session_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trading_events
    ADD CONSTRAINT trading_events_session_id_fkey FOREIGN KEY (session_id) REFERENCES public.trading_sessions(id) ON DELETE RESTRICT;


--
-- Name: trading_events trading_events_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trading_events
    ADD CONSTRAINT trading_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: trading_fee_balances trading_fee_balances_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trading_fee_balances
    ADD CONSTRAINT trading_fee_balances_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: trading_sessions trading_sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.trading_sessions
    ADD CONSTRAINT trading_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: user_pasino_accounts user_pasino_accounts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_pasino_accounts
    ADD CONSTRAINT user_pasino_accounts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_referrals user_referrals_referrer_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_referrals
    ADD CONSTRAINT user_referrals_referrer_user_id_fkey FOREIGN KEY (referrer_user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- Name: user_referrals user_referrals_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_referrals
    ADD CONSTRAINT user_referrals_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_sessions user_sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_sessions
    ADD CONSTRAINT user_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_trading_settings user_trading_settings_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_trading_settings
    ADD CONSTRAINT user_trading_settings_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: wallet_operations wallet_operations_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.wallet_operations
    ADD CONSTRAINT wallet_operations_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;


--
-- PostgreSQL database dump complete
--

\unrestrict uBPMUAW8Mb52sF6IKPBBKG1n2S24dThEdeNMwSGCGabVdCNZHOzX9TdCcfwVUkB

