--
-- PostgreSQL database dump
--

\restrict LMpLma6X3zLGrnXWQVGJHQdClDI7csh8ctoGa2eL32Ow4QiSxtgDtEcZcbGr74a

-- Dumped from database version 18.6
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
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
814547ba-3db3-4ac4-88ff-bb406059b6ec	751	BTT	KANGDEN	kangden69	0.01777776	COMPLETED	{"coin": "BTT", "amount": "0.01777776", "balance": "13584085.09174796", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:50:49.012337+07	2026-09-21 15:50:49.49589+07	2026-09-21 15:50:49.894809+07	2026-09-21 15:50:49.894809+07
36c9e1aa-3275-40bc-a06a-d07bed3f1a17	751	BTT	HOLDING	smartbotapp	1088.66691072	COMPLETED	{"coin": "BTT", "amount": "1088.66691072", "balance": "13585532.71247488", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:57:03.946865+07	2026-09-21 15:57:03.984473+07	2026-09-21 15:57:04.34423+07	2026-09-21 15:57:04.34423+07
7c28c817-09ba-4d04-8a50-e6820b37fcd3	751	BTT	KANGDEN	kangden69	181.44448512	COMPLETED	{"coin": "BTT", "amount": "181.44448512", "balance": "13585351.26798976", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:57:03.981571+07	2026-09-21 15:57:04.348505+07	2026-09-21 15:57:04.678302+07	2026-09-21 15:57:04.678302+07
21a9bf03-d3a4-44e8-8091-e2047b7ccb2c	751	BTT	HOLDING	smartbotapp	975302.51575296	COMPLETED	{"coin": "BTT", "amount": "975302.51575296", "balance": "17388680.11684480", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:57:13.946662+07	2026-09-21 15:57:13.965674+07	2026-09-21 15:57:14.27351+07	2026-09-21 15:57:14.27351+07
55d9972e-3031-41e7-bbe7-9ecf01710bbe	751	BTT	KANGDEN	kangden69	162550.41929216	COMPLETED	{"coin": "BTT", "amount": "162550.41929216", "balance": "17226129.69755264", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:57:13.962095+07	2026-09-21 15:57:14.281232+07	2026-09-21 15:57:14.598516+07	2026-09-21 15:57:14.598516+07
6a34d15c-37c2-4aba-b449-5c200fd7ed8f	751	FLOKI	HOLDING	smartbotapp	0.10053344	COMPLETED	{"coin": "FLOKI", "amount": "0.10053344", "balance": "16273.13793355", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:11:44.058423+07	2026-09-21 16:11:44.070882+07	2026-09-21 16:11:44.491803+07	2026-09-21 16:11:44.491803+07
f3fcf39c-c7b0-4735-8477-720e5b0631bf	751	FLOKI	KANGDEN	kangden69	0.01675556	COMPLETED	{"coin": "FLOKI", "amount": "0.01675556", "balance": "16272.64117799", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:11:44.066877+07	2026-09-21 16:11:44.499704+07	2026-09-21 16:11:44.849507+07	2026-09-21 16:11:44.849507+07
5e318b25-b561-431b-ae26-0f696e92ad11	751	FLOKI	HOLDING	smartbotapp	0.37772883	COMPLETED	{"coin": "FLOKI", "amount": "0.37772883", "balance": "16291.52157238", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:04.042309+07	2026-09-21 16:12:04.046862+07	2026-09-21 16:12:04.348773+07	2026-09-21 16:12:04.348773+07
5fed0f39-6e01-4240-99ad-0c52d07686d5	751	FLOKI	KANGDEN	kangden69	0.06295479	COMPLETED	{"coin": "FLOKI", "amount": "0.06295479", "balance": "16291.21861759", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:12:04.044351+07	2026-09-21 16:12:04.352735+07	2026-09-21 16:12:04.6618+07	2026-09-21 16:12:04.6618+07
cb5c5114-c195-4a00-87d2-158b4399d6c7	751	BTT	HOLDING	smartbotapp	0.10666656	COMPLETED	{"coin": "BTT", "amount": "0.10666656", "balance": "13584085.90952572", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:50:48.948077+07	2026-09-21 15:50:49.032588+07	2026-09-21 15:50:49.482976+07	2026-09-21 15:50:49.482976+07
efc9345a-85c1-4980-8957-161d26f2a18b	751	BTT	HOLDING	smartbotapp	0.45333288	COMPLETED	{"coin": "BTT", "amount": "0.45333288", "balance": "13584088.11618908", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:50:53.966943+07	2026-09-21 15:50:53.979214+07	2026-09-21 15:50:54.310258+07	2026-09-21 15:50:54.310258+07
bba1b9ee-e31f-4670-8a87-6b0a9cbeef2c	751	BTT	KANGDEN	kangden69	0.07555548	COMPLETED	{"coin": "BTT", "amount": "0.07555548", "balance": "13584088.04063360", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:50:53.970438+07	2026-09-21 15:50:54.332566+07	2026-09-21 15:50:54.713512+07	2026-09-21 15:50:54.713512+07
51ec225e-0ccd-4cf6-b84d-e40988b7f306	751	BTT	HOLDING	smartbotapp	2.03923200	COMPLETED	{"coin": "BTT", "amount": "2.03923200", "balance": "13584138.59708160", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:56:58.946908+07	2026-09-21 15:56:58.954325+07	2026-09-21 15:56:59.584055+07	2026-09-21 15:56:59.584055+07
f405a2ba-a039-436f-aef4-76e8bf27c61f	751	BTT	KANGDEN	kangden69	0.33987200	COMPLETED	{"coin": "BTT", "amount": "0.33987200", "balance": "13584112.65720960", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 15:56:58.951735+07	2026-09-21 15:56:59.591849+07	2026-09-21 15:56:59.942974+07	2026-09-21 15:56:59.942974+07
8a9438e4-1659-4bf5-8f30-3ab41eec8a31	751	FLOKI	HOLDING	smartbotapp	7.45592831	COMPLETED	{"coin": "FLOKI", "amount": "7.45592831", "balance": "47147.79903504", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:11:14.043539+07	2026-09-21 16:11:14.052459+07	2026-09-21 16:11:14.70785+07	2026-09-21 16:11:14.70785+07
992f5a8e-b37c-4bfd-ac3c-d222e2827508	751	FLOKI	KANGDEN	kangden69	1.24265471	COMPLETED	{"coin": "FLOKI", "amount": "1.24265471", "balance": "47146.55638033", "message": "Successfully transferred to user", "success": true}	\N	2026-09-21 16:11:14.049413+07	2026-09-21 16:11:14.718934+07	2026-09-21 16:11:15.024655+07	2026-09-21 16:11:15.024655+07
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
ddb3d778-4cac-41bd-9cc6-095b7958c644	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.10000000	38.2000	COMPLETED	34019643941	459868.00385268	459868.15254368	0.14869100	0.14869100	WIN	2026-09-23 05:05:35.991421+07	2026-09-23 05:05:36.022154+07	2026-09-23 05:05:36.23629+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.48691", "profit": "0.14869100", "bet_amt": "0.10000000", "client_seed": "5be9d4a7340c8f4d64094471fe949f61", "winning_chance": "38.20"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019643941", "payout": "2.48691", "profit": "0.14869100", "balance": "459868.15254368", "time_taken": 0.030183076858520508, "roll_number": 191}	0.00000000	0.00000000	2026-09-23 05:05:36.23629+07
e099afe4-f238-4354-9395-ca0ea4efef8c	d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	0.80000000	39.6900	COMPLETED	34019693509	459935.31882868	459934.51882868	-0.80000000	-0.80000000	LOSS	2026-09-23 05:21:44.953773+07	2026-09-23 05:21:44.964025+07	2026-09-23 05:21:45.173995+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.39355", "profit": "1.11484000", "bet_amt": "0.80000000", "client_seed": "39015b6d2660a9a05a66a6b64a4bfca8", "winning_chance": "39.69"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019693509", "payout": "2.39355", "profit": "-0.80000000", "balance": "459934.51882868", "time_taken": 0.026136159896850586, "roll_number": 3195}	0.00000000	0.00000000	2026-09-23 05:21:45.173995+07
d017f5ed-3ef8-4203-b91f-6767e765f829	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.10000000	37.1000	COMPLETED	34019643961	459868.15254368	459868.05254368	-0.10000000	-0.10000000	LOSS	2026-09-23 05:05:36.346905+07	2026-09-23 05:05:36.34898+07	2026-09-23 05:05:36.558314+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.56064", "profit": "0.15606400", "bet_amt": "0.10000000", "client_seed": "5042a90d68632ee9ec4e65c31bc1f27e", "winning_chance": "37.10"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019643961", "payout": "2.56064", "profit": "-0.10000000", "balance": "459868.05254368", "time_taken": 0.026312828063964844, "roll_number": 8143}	0.00000000	0.00000000	2026-09-23 05:05:36.558314+07
0416cc83-5151-45f8-841d-ae1c48a3f26c	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	1.60000000	39.5100	COMPLETED	34019644029	459866.65254368	459868.89966368	2.24712000	2.24712000	WIN	2026-09-23 05:05:37.663089+07	2026-09-23 05:05:37.665543+07	2026-09-23 05:05:37.875133+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.40445", "profit": "2.24712000", "bet_amt": "1.60000000", "client_seed": "688266200bd18ccbcf2d4499890af406", "winning_chance": "39.51"}	{"win": 1, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019644029", "payout": "2.40445", "profit": "2.24712000", "balance": "459868.89966368", "time_taken": 0.026983022689819336, "roll_number": 1363}	0.00000000	0.00000000	2026-09-23 05:05:37.875133+07
955de60e-fd09-43e9-8346-1827efe9c559	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.20000000	33.5300	COMPLETED	34019643973	459868.05254368	459867.85254368	-0.20000000	-0.20000000	LOSS	2026-09-23 05:05:36.681054+07	2026-09-23 05:05:36.691647+07	2026-09-23 05:05:36.903303+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.83328", "profit": "0.36665600", "bet_amt": "0.20000000", "client_seed": "40a03dca3b59278a0fddebe1e26fe21a", "winning_chance": "33.53"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019643973", "payout": "2.83328", "profit": "-0.20000000", "balance": "459867.85254368", "time_taken": 0.02712082862854004, "roll_number": 632}	0.00000000	0.00000000	2026-09-23 05:05:36.903303+07
6970ed23-701b-4edd-a018-3dd99c962f5d	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.40000000	33.5700	COMPLETED	34019643985	459867.85254368	459867.45254368	-0.40000000	-0.40000000	LOSS	2026-09-23 05:05:37.019719+07	2026-09-23 05:05:37.024103+07	2026-09-23 05:05:37.232643+07	{"coin": "BTT", "type": 2, "method": "place_bet", "payout": "2.82990", "profit": "0.73196000", "bet_amt": "0.40000000", "client_seed": "cc44e6ae41a79e7f76df59ce8dd48899", "winning_chance": "33.57"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019643985", "payout": "2.82990", "profit": "-0.40000000", "balance": "459867.45254368", "time_taken": 0.025092124938964844, "roll_number": 4735}	0.00000000	0.00000000	2026-09-23 05:05:37.232643+07
4597c2a9-2753-4d49-910b-1d48f98773d2	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.80000000	32.2400	COMPLETED	34019644007	459867.45254368	459866.65254368	-0.80000000	-0.80000000	LOSS	2026-09-23 05:05:37.342515+07	2026-09-23 05:05:37.344694+07	2026-09-23 05:05:37.55486+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.94665", "profit": "1.55732000", "bet_amt": "0.80000000", "client_seed": "76213da4366bf2aa6360d7382151cb8d", "winning_chance": "32.24"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019644007", "payout": "2.94665", "profit": "-0.80000000", "balance": "459866.65254368", "time_taken": 0.027385950088500977, "roll_number": 4936}	0.00000000	0.00000000	2026-09-23 05:05:37.55486+07
759282ef-e5f3-4daa-a4ab-c6ebf0e6c089	44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	0.10000000	33.8500	COMPLETED	34019644041	459868.89966368	459868.79966368	-0.10000000	-0.10000000	LOSS	2026-09-23 05:05:37.986691+07	2026-09-23 05:05:37.990533+07	2026-09-23 05:05:38.19763+07	{"coin": "BTT", "type": 1, "method": "place_bet", "payout": "2.80649", "profit": "0.18064900", "bet_amt": "0.10000000", "client_seed": "97ac6404842156f81d1a02e2ccea57af", "winning_chance": "33.85"}	{"win": 0, "coin": "BTT", "error": null, "action": "bet_update", "bet_id": "34019644041", "payout": "2.80649", "profit": "-0.10000000", "balance": "459868.79966368", "time_taken": 0.025659799575805664, "roll_number": 4923}	0.00000000	0.00000000	2026-09-23 05:05:38.19763+07
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
863	BTT	0.00000000	0.00000000	2026-09-23 10:17:25.119474+07
863	TRX	0.00000000	0.00000000	2026-09-23 10:17:25.414266+07
751	BTT	0.00000000	0.00000000	2026-09-23 10:17:26.928615+07
751	DOGE	0.00000000	0.00000000	2026-09-23 10:17:27.429768+07
751	FLOKI	0.00000000	0.00000000	2026-09-23 10:17:27.73322+07
751	TRX	0.00000000	0.00000000	2026-09-23 10:17:28.037904+07
749	BTT	0.00000000	0.00000000	2026-09-23 10:17:20.873561+07
749	FLOKI	0.00000000	0.00000000	2026-09-23 10:17:21.175438+07
749	TRX	0.00000000	0.00000000	2026-09-23 10:17:21.473788+07
\.


--
-- Data for Name: referral_bonus_events; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.referral_bonus_events (id, user_id, coin, amount, event_type, source_external_id, occurred_at, created_at) FROM stdin;
89d4d1ec-99a8-4563-9839-089d7de74e69	749	BTT	0.00155895	TRADING_ACCRUAL	provider-bet:6e58f47b-3438-4474-ac5e-f9f9daf307f5:referral:2	2026-09-23 04:52:55.259075+07	2026-09-23 04:52:55.259075+07
fb6813c3-8944-4100-89a1-847917fcc808	749	BTT	4.73108480	TRADING_ACCRUAL	provider-bet:cfbd6ae8-f00b-4bbd-8fbe-6c9ebb131d9a:referral:2	2026-09-23 04:53:11.258295+07	2026-09-23 04:53:11.258295+07
c7f4ebb6-f6fe-47ef-82b2-87b0e3f818b0	749	BTT	0.01879824	TRADING_ACCRUAL	provider-bet:46817c3b-cecd-4e5d-8e80-3112ae1137d8:referral:2	2026-09-23 04:53:17.258179+07	2026-09-23 04:53:17.258179+07
0c0171ff-f0af-4d94-a898-ea67e6e10cc0	749	BTT	0.11450592	TRADING_ACCRUAL	provider-bet:b8b36047-e4dd-49a2-9843-9d7d302e3a94:referral:2	2026-09-23 04:53:25.58513+07	2026-09-23 04:53:25.58513+07
896bc5ca-80fa-4240-aa2d-7267415e0b06	749	BTT	-81960.11323597	CLAIM_REVERSAL	admin:bonus-move:749:749:BTT	2026-09-23 10:17:20.873561+07	2026-09-23 10:17:20.873561+07
01082e00-81e9-4f2a-9ee4-162c1c6c020a	749	FLOKI	-346.59073643	CLAIM_REVERSAL	admin:bonus-move:749:749:FLOKI	2026-09-23 10:17:21.175438+07	2026-09-23 10:17:21.175438+07
c8526d67-30cc-4c2f-b4e4-e1f16262f241	749	TRX	-0.00000261	CLAIM_REVERSAL	admin:bonus-move:749:749:TRX	2026-09-23 10:17:21.473788+07	2026-09-23 10:17:21.473788+07
61ec2b2a-17fc-45c0-8ebd-a833755c4f43	863	BTT	-500925.66822683	CLAIM_REVERSAL	admin:bonus-move:749:863:BTT	2026-09-23 10:17:25.119474+07	2026-09-23 10:17:25.119474+07
74694e4d-e4cc-48f8-9dac-3d190dbb9d03	863	TRX	-0.02199383	CLAIM_REVERSAL	admin:bonus-move:749:863:TRX	2026-09-23 10:17:25.414266+07	2026-09-23 10:17:25.414266+07
5d660278-3221-4ebf-ba49-913cbd4aa012	751	BTT	-97945.04349517	CLAIM_REVERSAL	admin:bonus-move:749:751:BTT	2026-09-23 10:17:26.928615+07	2026-09-23 10:17:26.928615+07
97ff7beb-3c7a-4f1e-a352-299021fecd19	751	DOGE	-0.00713606	CLAIM_REVERSAL	admin:bonus-move:749:751:DOGE	2026-09-23 10:17:27.429768+07	2026-09-23 10:17:27.429768+07
23f7e546-b9cf-4b06-ae14-6b045f3e34b9	751	FLOKI	-1923.11231095	CLAIM_REVERSAL	admin:bonus-move:749:751:FLOKI	2026-09-23 10:17:27.73322+07	2026-09-23 10:17:27.73322+07
0ff15094-aaf6-4356-9bd9-563f6b34a003	751	TRX	-0.45546349	CLAIM_REVERSAL	admin:bonus-move:749:751:TRX	2026-09-23 10:17:28.037904+07	2026-09-23 10:17:28.037904+07
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
751	BTT	0.00000000	0.00000000	2026-09-21 15:57:14.598516+07
\.


--
-- Data for Name: trading_sessions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.trading_sessions (id, user_id, coin, status, settings_snapshot, rule_snapshot, opening_provider_balance, visible_user_balance, current_bet, profit, wins, losses, last_result, started_at, completed_at, updated_at, stop_reason, streak, profit_cycle, next_override, reset_after_pending, worker_id, lease_expires_at, max_win_streak, max_loss_streak) FROM stdin;
44024e5f-6920-4c1f-b7a2-5ca036833e90	749	BTT	COMPLETED	{"BaseBet": 10000000, "DelayMS": 300, "Runtime": {"BaseBet": 10000000, "BoomAfterWins": 0, "BoomWinAmount": 0, "ProfitSession": 500000000, "BoomLossAmount": 0, "ResetAfterWins": 1, "BoomAfterLosses": 0, "MartingaleOnWin": "0", "MartingaleOnLoss": "100", "ResetAfterLosses": 0}, "StopLoss": 0, "ChanceMax": "40", "ChanceMin": "30", "StopOnWin": true, "MaximumBet": 0, "TakeProfit": 0, "BalanceBelow": 0}	{"user_bps": 8600, "holding_bps": 1200, "kangden_bps": 200, "referral_bps": [100, 50, 50], "minimum_bet_units": 10000000, "fee_exempt_username": "kangden69"}	459868.00385268	459870.82056268	0.10000000	2.81671000	11	8	WIN	2026-09-23 05:05:35.838855+07	2026-09-23 05:05:42.018676+07	2026-09-23 05:05:42.018676+07	Stop Win tercapai	1	2.81671000	\N	f	KangDen-9340	2026-09-23 05:06:11.799439+07	6	4
d4c0dcd6-6ecd-4079-ac8d-fd4cfca62ab2	749	BTT	COMPLETED	{"BaseBet": 10000000, "DelayMS": 300, "Runtime": {"BaseBet": 10000000, "BoomAfterWins": 0, "BoomWinAmount": 0, "ProfitSession": 500000000, "BoomLossAmount": 0, "ResetAfterWins": 1, "BoomAfterLosses": 0, "MartingaleOnWin": "0", "MartingaleOnLoss": "100", "ResetAfterLosses": 0}, "StopLoss": 0, "ChanceMax": "40", "ChanceMin": "30", "StopOnWin": true, "MaximumBet": 0, "TakeProfit": 0, "BalanceBelow": 0}	{"user_bps": 8600, "holding_bps": 1200, "kangden_bps": 200, "referral_bps": [100, 50, 50], "minimum_bet_units": 10000000, "fee_exempt_username": "kangden69"}	459870.82056268	460011.90350468	0.10000000	141.08294200	56	115	WIN	2026-09-23 05:21:13.463088+07	2026-09-23 05:22:08.997848+07	2026-09-23 05:22:08.997848+07	Stop Win tercapai	1	0.37466900	\N	f	KangDen-18240	2026-09-23 05:22:38.780201+07	3	9
\.


--
-- Data for Name: user_pasino_accounts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_pasino_accounts (user_id, provider_username, provider_email, password_ciphertext, access_token_ciphertext, access_token_expires_at, socket_token_ciphertext, socket_token_expires_at, encryption_version, imported_from_legacy, last_authenticated_at, updated_at) FROM stdin;
767	gudangopit	Bpknana@gmail.com	\N	v1.nHgJgqgsQCIcW-r2.PsWJZgtxtu1JIXQQX06Lbg.fSXj8xb7C2hcRUM9cwXiXSLkZh3ELzch9wHTI-6zuYd5SRJiPGePGrr2Vonlb5yuGc-KuP5Ipay_INJAfvs9HQ	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
863	rajakaya88	selembestore7288@gmail.com	\N	v1.Ibe9D1w4iKlRf8YO.jwlOCYXnXobygTObUkY6MQ.qR5TjdNyTLFVK8uC4W5NL-YbOsoEC8FE1ltIvA42xagx1u0YatlDu24xVvIX-pcw6of2pGASCN9qWo0QDxI4ag	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
751	smartrich88	rajaduit369@gmail.com	\N	v1.S_j9l4DE30zmBs2_.CaABDu6af7MgIGiUnuSA2g.7eSzJhDjmPKiVyxIDTrnd2GJHe7jXKEWk8BqV-SFPedUusSqTUNd35ffinmbl0GJGUd9eMTW4hMftIxoIyLzBg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
781	smartbotapp	smartbotapp@gmail.com	v1.B9gyjXuIpMOhJ684.ghu8hi6lFCdapaGFpubi8w.Y5rLggzm00U	v1.SV_UUGSBIXw1q71E.Zpwn9I2u29XyDGl-ZENsug.ZrQWQ0XpWBvmz4e97w8LQBGeOyuL1Z3SLHhxGUvrQzve90_A540uuSx2138Cjw-SoGT76kLP9zmObvTCZ1OKrg	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
1051	opryuubot	opryuubot@gmail.com	v1.xQdHtLk4Z32jqCD8.TbhJNwHHkIqabfLQ9E6-wg.Un5R8SQ8pJA	v1.Cw0tdadZ0kWHH5Md.JPFvGOnv0hDYhW_WVq9iCg._WqjMlPoL1FLiAPu8HF-Wnw_56jQptErAgiOUSR3Bns0tu7kfGB5rlyUbawf0LH8utR5D738n5fte5F7VS6Ang	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
749	kangden69	kangdeni2988@gmail.com	v1.nNZgW5YuM__ucQtR.E5_sE-8l0xJKkT-1247nKw.DW54qHZ2fbA	v1.q6peYEo1DeLHETOw.2tJpRUBqCfNOYCqZch3kCw.YZ6UWy1Iks8S1shHebh4ztFSA1H1QOkCChIWthc4lNaxsq4zUd3b1ZbKhZ8vXwsA1ylAa6fE81znXUc_sLnaiA	\N	\N	\N	0	t	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07
\.


--
-- Data for Name: user_referrals; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_referrals (user_id, referrer_user_id, provider_referrer, created_at, updated_at) FROM stdin;
749	\N	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
751	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
767	751	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
781	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
863	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
1051	749	277064	2026-09-20 09:35:33.544227+07	2026-09-20 09:35:33.544227+07
\.


--
-- Data for Name: user_sessions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_sessions (token_hash, user_id, csrf_token, expires_at, created_at) FROM stdin;
\\x95fd1c5dcedc0f73bc855c4184aa2de04b990bbf12d05fd1c524d9fbc69a3886	751	6b78799cb9367d37f5e24f8996b8486c64b85dc69cd562dd	2026-10-21 16:14:42.919238+07	2026-09-21 16:14:42.919238+07
\.


--
-- Data for Name: user_trading_settings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.user_trading_settings (user_id, coin, base_bet, chance_min, chance_max, delay_ms, martingale_on_win, martingale_on_loss, reset_after_wins, reset_after_losses, boom_after_wins, boom_win_amount, boom_after_losses, boom_loss_amount, take_profit, stop_loss, balance_below, stop_on_win, maximum_bet, updated_at, profit_session) FROM stdin;
767	BTC	0.00000100	49	49	1000	0	25	1	0	0	0.00000000	0	0.00000000	90000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	10.00000000
781	BTC	0.00000100	49	49	1000	100	100	1	0	0	0.00000000	0	0.00000000	30000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
863	BTC	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	10000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	3.00000000
751	FLOKI	0.06000000	41	43	500	0	100	2	0	0	0.00000000	0	0.00000000	10000.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-21 16:12:46.820447+07	70000.00000000
749	BTT	0.10000000	30	40	300	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-23 05:21:12.743326+07	5.00000000
1051	TRX	0.00000100	49	49	1000	0	100	1	0	0	0.00000000	0	0.00000000	0.00000000	0.00000000	0.00000000	f	0.00000000	2026-09-20 09:35:33.544227+07	0.00000000
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (id, username, email, password_hash, status, subscription_expires_at, created_at, updated_at, legacy_user_id, subscription_trial_ends_at, last_login_at, last_active_at) FROM stdin;
751	smartrich88	rajaduit369@gmail.com	$2b$12$1YIUyugJvnuz6M8QX54zzuSWhr/EGxh6wRX/5YdkpyddRKGD5cIqe	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-21 16:14:42.925637+07	5	\N	2026-09-21 16:14:42.925637+07	2026-09-21 16:14:42.925637+07
749	kangden69	kangdeni2988@gmail.com	$2b$12$c5.LgR1jMpy5f.JOKRyv/e4Qjy9AZ8FX5MX5WShl8a8CSzSCowE3y	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-23 05:01:47.503261+07	4	\N	2026-09-23 05:01:47.503261+07	2026-09-23 10:33:23.353435+07
767	gudangopit	Bpknana@gmail.com	$2b$12$4Fi6RtLDX883y.Bhj3d4UeMVII9bGiSRuvIPYq28lv2odNCAlCzbC	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	14	\N	\N	\N
781	smartbotapp	smartbotapp@gmail.com	$2a$10$VAKiU1cHQjkjukbdHy4FZeeGTddH0hELvd1M.yShpcs4OknQCSShC	ACTIVE	2035-02-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-21 10:29:40.699299+07	21	\N	2026-09-21 10:29:40.699299+07	2026-09-21 10:29:40.699299+07
863	rajakaya88	selembestore7288@gmail.com	$2b$12$BQBZXFvjbp1EYfpRuD3E2uQDrUhO/kwJLK/Uf/4MSgeZk.srum42G	ACTIVE	2026-10-05 00:00:00+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	66	\N	\N	\N
1051	opryuubot	opryuubot@gmail.com	$2b$10$A2sP2BglVW.cmVwwmSsd1.pEz7Fkg51GmKs5tTWx2jQFU1bBbuDz.	ACTIVE	2026-09-07 15:55:26.565163+07	2026-09-20 03:05:38.613001+07	2026-09-20 09:35:33.544227+07	254	2026-09-07 15:55:26.565163+07	\N	\N
\.


--
-- Data for Name: wallet_operations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.wallet_operations (request_id, user_id, operation, coin, amount, destination, status, provider_response, failure_reason, created_at, updated_at, completed_at) FROM stdin;
e44492f4-669f-4a64-9deb-85eab4525e07	749	TRANSFER	TRX	0.00002938	maklampir88	FAILED	\N	Proses aplikasi terputus sebelum respons selesai	2026-09-20 15:00:13.382043+07	2026-09-20 15:16:16.083031+07	\N
fd9239be-09df-4648-aaa3-98405e94d404	749	TRANSFER	FLOKI	56831.09572828	maklampir88	PROCESSING	\N	\N	2026-09-20 15:16:56.45155+07	2026-09-20 15:16:56.45155+07	\N
b23daa95-1a2e-4e23-b7d6-a1b529240f41	749	TRANSFER	BTT	2045031.44725445	maklampir88	PROCESSING	\N	\N	2026-09-20 15:21:35.671509+07	2026-09-20 15:21:35.671509+07	\N
92da856d-b797-4cdf-9ac1-8dbee1682f19	749	TRANSFER	BTT	162739.59840780	maklampir88	PROCESSING	\N	\N	2026-09-21 16:48:02.147988+07	2026-09-21 16:48:02.147988+07	\N
eb7231b0-f68e-4a6d-9d12-535a4ca89e2b	749	TRANSFER	FLOKI	693.18541611	maklampir88	PROCESSING	\N	\N	2026-09-21 16:48:26.470599+07	2026-09-21 16:48:26.470599+07	\N
cc382e81-eb93-4b6a-a738-4d782386d225	749	TRANSFER	TRX	1.33200140	maklampir88	COMPLETED	{"coin": "TRX", "amount": "1.33200140", "balance": "0.00000000", "message": "Successfully transferred to user", "success": true}	\N	2026-09-23 10:21:52.43178+07	2026-09-23 10:21:52.738314+07	2026-09-23 10:21:52.738314+07
413dd927-9768-455d-aaba-868a1e4ea94e	749	TRANSFER	DOGE	132.33221608	maklampir88	COMPLETED	{"coin": "DOGE", "amount": "132.33221608", "balance": "0.00000000", "message": "Successfully transferred to user", "success": true}	\N	2026-09-23 10:35:02.084181+07	2026-09-23 10:35:02.418382+07	2026-09-23 10:35:02.418382+07
8267c20c-df7c-4c57-893e-5146230d78c1	749	TRANSFER	FLOKI	3134198.56301864	maklampir88	COMPLETED	{"coin": "FLOKI", "amount": "3134198.56301864", "balance": "0.00000000", "message": "Successfully transferred to user", "success": true}	\N	2026-09-23 10:35:22.960689+07	2026-09-23 10:35:23.279593+07	2026-09-23 10:35:23.279593+07
62f85e1d-a134-4302-bd32-99ac39561589	749	TRANSFER	BTT	114483138.91926335	maklampir88	COMPLETED	{"coin": "BTT", "amount": "114483138.91926335", "balance": "0.00000000", "message": "Successfully transferred to user", "success": true}	\N	2026-09-23 10:35:43.221517+07	2026-09-23 10:35:43.531814+07	2026-09-23 10:35:43.531814+07
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

\unrestrict LMpLma6X3zLGrnXWQVGJHQdClDI7csh8ctoGa2eL32Ow4QiSxtgDtEcZcbGr74a

