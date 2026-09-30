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
-- Name: current_business_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.current_business_id() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$ SELECT NULLIF(current_setting('app.current_business_id', true), '')::uuid $$;


--
-- Name: forbid_accepted_quote_changes(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.forbid_accepted_quote_changes() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF OLD.accepted_at IS NOT NULL THEN
    RAISE EXCEPTION 'quote % is accepted and can no longer change', OLD.id;
  END IF;
  RETURN NEW;
END $$;


--
-- Name: forbid_accepted_quote_item_changes(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.forbid_accepted_quote_item_changes() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM quotes WHERE id = COALESCE(NEW.quote_id, OLD.quote_id) AND accepted_at IS NOT NULL) THEN
    RAISE EXCEPTION 'quote is accepted; its items can no longer change';
  END IF;
  RETURN COALESCE(NEW, OLD);
END $$;


--
-- Name: forbid_signed_contract_changes(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.forbid_signed_contract_changes() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF OLD.signed_at IS NOT NULL THEN
    RAISE EXCEPTION 'contract % is signed and can no longer change', OLD.id;
  END IF;
  RETURN NEW;
END $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: activities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activities (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_id uuid NOT NULL,
    actor_user_id uuid,
    subject_type character varying NOT NULL,
    subject_id uuid NOT NULL,
    action character varying NOT NULL,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: appointments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.appointments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_id uuid NOT NULL,
    lead_id uuid NOT NULL,
    assigned_user_id uuid,
    kind character varying DEFAULT 'consultation'::character varying NOT NULL,
    status character varying DEFAULT 'tentative'::character varying NOT NULL,
    starts_at timestamp(6) without time zone NOT NULL,
    ends_at timestamp(6) without time zone NOT NULL,
    location character varying,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT appointments_ends_after_start CHECK ((ends_at > starts_at)),
    CONSTRAINT appointments_kind_valid CHECK (((kind)::text = ANY ((ARRAY['consultation'::character varying, 'site_visit'::character varying, 'call'::character varying, 'other'::character varying])::text[]))),
    CONSTRAINT appointments_location_length CHECK ((char_length((location)::text) <= 300)),
    CONSTRAINT appointments_notes_length CHECK ((char_length(notes) <= 5000)),
    CONSTRAINT appointments_status_valid CHECK (((status)::text = ANY ((ARRAY['tentative'::character varying, 'confirmed'::character varying, 'cancelled'::character varying, 'completed'::character varying, 'no_show'::character varying])::text[])))
);


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: assistant_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assistant_sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_id uuid NOT NULL,
    user_id uuid NOT NULL,
    state jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: businesses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.businesses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    slug character varying NOT NULL,
    time_zone character varying DEFAULT 'UTC'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    default_tax_rate_bps integer DEFAULT 0 NOT NULL,
    quote_valid_days integer DEFAULT 30 NOT NULL,
    contract_terms text,
    CONSTRAINT businesses_contract_terms_length CHECK ((char_length(contract_terms) <= 50000)),
    CONSTRAINT businesses_name_length CHECK (((char_length((name)::text) >= 1) AND (char_length((name)::text) <= 120))),
    CONSTRAINT businesses_quote_valid_days_range CHECK (((quote_valid_days >= 1) AND (quote_valid_days <= 365))),
    CONSTRAINT businesses_slug_format CHECK (((slug)::text ~ '^[a-z0-9]([a-z0-9-]{1,61})[a-z0-9]$'::text)),
    CONSTRAINT businesses_tax_rate_range CHECK (((default_tax_rate_bps >= 0) AND (default_tax_rate_bps <= 3000)))
);


--
-- Name: channel_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.channel_accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_id uuid NOT NULL,
    provider character varying NOT NULL,
    phone_number_id character varying NOT NULL,
    display_phone character varying NOT NULL,
    access_token text,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT channel_accounts_provider_valid CHECK (((provider)::text = ANY ((ARRAY['whatsapp_cloud'::character varying, 'simulator'::character varying])::text[])))
);


--
-- Name: contracts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contracts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_id uuid NOT NULL,
    lead_id uuid NOT NULL,
    quote_id uuid,
    created_by_id uuid,
    number integer NOT NULL,
    status character varying DEFAULT 'draft'::character varying NOT NULL,
    body text NOT NULL,
    token_digest character varying NOT NULL,
    token text,
    sent_at timestamp(6) without time zone,
    viewed_at timestamp(6) without time zone,
    signed_at timestamp(6) without time zone,
    signer_name character varying,
    signer_ip character varying,
    signer_user_agent character varying,
    signed_body_sha256 character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT contracts_body_length CHECK (((char_length(body) >= 1) AND (char_length(body) <= 100000))),
    CONSTRAINT contracts_signed_consistent CHECK ((((status)::text = 'signed'::text) = (signed_at IS NOT NULL))),
    CONSTRAINT contracts_status_valid CHECK (((status)::text = ANY ((ARRAY['draft'::character varying, 'sent'::character varying, 'signed'::character varying, 'void'::character varying])::text[])))
);


--
-- Name: conversations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_id uuid NOT NULL,
    lead_id uuid NOT NULL,
    assigned_user_id uuid,
    channel character varying NOT NULL,
    status character varying DEFAULT 'open'::character varying NOT NULL,
    last_message_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT conversations_channel_valid CHECK (((channel)::text = ANY ((ARRAY['sms'::character varying, 'whatsapp'::character varying, 'web_chat'::character varying, 'email'::character varying, 'phone'::character varying, 'facebook'::character varying, 'instagram'::character varying, 'other'::character varying])::text[]))),
    CONSTRAINT conversations_status_valid CHECK (((status)::text = ANY ((ARRAY['open'::character varying, 'closed'::character varying])::text[])))
);


--
-- Name: follow_ups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.follow_ups (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_id uuid NOT NULL,
    lead_id uuid,
    assigned_user_id uuid NOT NULL,
    created_by_id uuid,
    body character varying NOT NULL,
    due_at timestamp(6) without time zone NOT NULL,
    reminded_at timestamp(6) without time zone,
    completed_at timestamp(6) without time zone,
    cancelled_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT follow_ups_body_length CHECK (((char_length((body)::text) >= 1) AND (char_length((body)::text) <= 500))),
    CONSTRAINT follow_ups_single_outcome CHECK ((NOT ((completed_at IS NOT NULL) AND (cancelled_at IS NOT NULL))))
);


--
-- Name: inbound_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.inbound_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_id uuid NOT NULL,
    channel_account_id uuid NOT NULL,
    kind character varying NOT NULL,
    provider_event_id character varying NOT NULL,
    from_phone character varying,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    processed_at timestamp(6) without time zone,
    error character varying,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT inbound_events_kind_valid CHECK (((kind)::text = ANY ((ARRAY['message'::character varying, 'status'::character varying])::text[])))
);


--
-- Name: intake_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.intake_keys (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_id uuid NOT NULL,
    created_by_id uuid,
    name character varying NOT NULL,
    token_digest character varying NOT NULL,
    token_prefix character varying NOT NULL,
    last_used_at timestamp(6) without time zone,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT intake_keys_name_length CHECK (((char_length((name)::text) >= 1) AND (char_length((name)::text) <= 80)))
);


--
-- Name: invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invitations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_id uuid NOT NULL,
    invited_by_id uuid,
    email_address character varying NOT NULL,
    role character varying DEFAULT 'agent'::character varying NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    accepted_at timestamp(6) without time zone,
    declined_at timestamp(6) without time zone,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT invitations_email_length CHECK ((char_length((email_address)::text) <= 254)),
    CONSTRAINT invitations_email_lowercase CHECK (((email_address)::text = lower((email_address)::text))),
    CONSTRAINT invitations_role_valid CHECK (((role)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'agent'::character varying])::text[])))
);


--
-- Name: job_costs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.job_costs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_id uuid NOT NULL,
    lead_id uuid NOT NULL,
    created_by_id uuid,
    description character varying NOT NULL,
    amount_cents bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT job_costs_amount_range CHECK (((amount_cents >= 0) AND (amount_cents <= '100000000000'::bigint))),
    CONSTRAINT job_costs_description_length CHECK (((char_length((description)::text) >= 1) AND (char_length((description)::text) <= 200)))
);


--
-- Name: leads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leads (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_id uuid NOT NULL,
    assigned_user_id uuid,
    name character varying NOT NULL,
    email character varying,
    phone character varying,
    need text,
    source character varying DEFAULT 'manual'::character varying NOT NULL,
    status character varying DEFAULT 'new'::character varying NOT NULL,
    score integer,
    external_id character varying,
    archived_at timestamp(6) without time zone,
    last_activity_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    phone_e164 character varying,
    value_cents bigint,
    acquisition_cost_cents bigint,
    won_at timestamp(6) without time zone,
    CONSTRAINT leads_contact_present CHECK (((email IS NOT NULL) OR (phone IS NOT NULL))),
    CONSTRAINT leads_cost_range CHECK (((acquisition_cost_cents IS NULL) OR ((acquisition_cost_cents >= 0) AND (acquisition_cost_cents <= '100000000000'::bigint)))),
    CONSTRAINT leads_external_id_length CHECK ((char_length((external_id)::text) <= 200)),
    CONSTRAINT leads_name_length CHECK (((char_length((name)::text) >= 1) AND (char_length((name)::text) <= 120))),
    CONSTRAINT leads_need_length CHECK ((char_length(need) <= 2000)),
    CONSTRAINT leads_score_range CHECK (((score IS NULL) OR ((score >= 0) AND (score <= 100)))),
    CONSTRAINT leads_source_valid CHECK (((source)::text = ANY ((ARRAY['website'::character varying, 'facebook'::character varying, 'instagram'::character varying, 'google'::character varying, 'whatsapp'::character varying, 'referral'::character varying, 'phone'::character varying, 'walk_in'::character varying, 'manual'::character varying, 'purchased'::character varying, 'other'::character varying])::text[]))),
    CONSTRAINT leads_status_valid CHECK (((status)::text = ANY ((ARRAY['new'::character varying, 'contacted'::character varying, 'qualified'::character varying, 'appointment'::character varying, 'won'::character varying, 'lost'::character varying])::text[]))),
    CONSTRAINT leads_value_range CHECK (((value_cents IS NULL) OR ((value_cents >= 0) AND (value_cents <= '100000000000'::bigint))))
);


--
-- Name: memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role character varying DEFAULT 'agent'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT memberships_role_valid CHECK (((role)::text = ANY ((ARRAY['owner'::character varying, 'admin'::character varying, 'agent'::character varying])::text[])))
);


--
-- Name: messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_id uuid NOT NULL,
    conversation_id uuid NOT NULL,
    sender_user_id uuid,
    direction character varying NOT NULL,
    sender_kind character varying NOT NULL,
    body text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT messages_body_length CHECK (((char_length(body) >= 1) AND (char_length(body) <= 10000))),
    CONSTRAINT messages_customer_is_inbound CHECK ((((sender_kind)::text = 'customer'::text) = ((direction)::text = 'inbound'::text))),
    CONSTRAINT messages_direction_valid CHECK (((direction)::text = ANY ((ARRAY['inbound'::character varying, 'outbound'::character varying])::text[]))),
    CONSTRAINT messages_sender_kind_valid CHECK (((sender_kind)::text = ANY ((ARRAY['customer'::character varying, 'staff'::character varying, 'system'::character varying])::text[])))
);


--
-- Name: notes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_id uuid NOT NULL,
    lead_id uuid NOT NULL,
    author_user_id uuid,
    body text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT notes_body_length CHECK (((char_length(body) >= 1) AND (char_length(body) <= 5000)))
);


--
-- Name: outbound_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.outbound_messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_id uuid NOT NULL,
    channel_account_id uuid NOT NULL,
    message_id uuid,
    lead_id uuid,
    to_phone character varying NOT NULL,
    kind character varying DEFAULT 'text'::character varying NOT NULL,
    body text NOT NULL,
    buttons jsonb DEFAULT '[]'::jsonb NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    provider_message_id character varying,
    attempts integer DEFAULT 0 NOT NULL,
    last_error character varying,
    sent_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT outbound_messages_body_length CHECK (((char_length(body) >= 1) AND (char_length(body) <= 4096))),
    CONSTRAINT outbound_messages_kind_valid CHECK (((kind)::text = ANY ((ARRAY['text'::character varying, 'buttons'::character varying])::text[]))),
    CONSTRAINT outbound_messages_status_valid CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'sent'::character varying, 'delivered'::character varying, 'read'::character varying, 'failed'::character varying])::text[])))
);


--
-- Name: quote_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.quote_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_id uuid NOT NULL,
    quote_id uuid NOT NULL,
    description character varying NOT NULL,
    quantity numeric(10,2) DEFAULT 1.0 NOT NULL,
    unit_price_cents bigint NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT quote_items_description_length CHECK (((char_length((description)::text) >= 1) AND (char_length((description)::text) <= 300))),
    CONSTRAINT quote_items_price_range CHECK (((unit_price_cents >= 0) AND (unit_price_cents <= '10000000000'::bigint))),
    CONSTRAINT quote_items_quantity_range CHECK (((quantity > (0)::numeric) AND (quantity <= (100000)::numeric)))
);


--
-- Name: quotes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.quotes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    business_id uuid NOT NULL,
    lead_id uuid NOT NULL,
    created_by_id uuid,
    number integer NOT NULL,
    status character varying DEFAULT 'draft'::character varying NOT NULL,
    tax_rate_bps integer DEFAULT 0 NOT NULL,
    notes text,
    valid_until date,
    token_digest character varying NOT NULL,
    token text,
    sent_at timestamp(6) without time zone,
    viewed_at timestamp(6) without time zone,
    accepted_at timestamp(6) without time zone,
    accepted_name character varying,
    accepted_ip character varying,
    declined_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT quotes_accepted_consistent CHECK ((((status)::text = 'accepted'::text) = (accepted_at IS NOT NULL))),
    CONSTRAINT quotes_notes_length CHECK ((char_length(notes) <= 5000)),
    CONSTRAINT quotes_status_valid CHECK (((status)::text = ANY ((ARRAY['draft'::character varying, 'sent'::character varying, 'accepted'::character varying, 'declined'::character varying, 'void'::character varying])::text[]))),
    CONSTRAINT quotes_tax_rate_range CHECK (((tax_rate_bps >= 0) AND (tax_rate_bps <= 3000)))
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    token_digest character varying NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    last_used_at timestamp(6) without time zone,
    ip_address character varying,
    user_agent character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email_address character varying NOT NULL,
    password_digest character varying NOT NULL,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    phone character varying,
    CONSTRAINT users_email_length CHECK ((char_length((email_address)::text) <= 254)),
    CONSTRAINT users_email_lowercase CHECK (((email_address)::text = lower((email_address)::text))),
    CONSTRAINT users_name_length CHECK (((char_length((name)::text) >= 1) AND (char_length((name)::text) <= 120))),
    CONSTRAINT users_phone_e164 CHECK (((phone)::text ~ '^\+[1-9][0-9]{6,14}$'::text))
);


--
-- Name: activities activities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT activities_pkey PRIMARY KEY (id);


--
-- Name: appointments appointments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: assistant_sessions assistant_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assistant_sessions
    ADD CONSTRAINT assistant_sessions_pkey PRIMARY KEY (id);


--
-- Name: businesses businesses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.businesses
    ADD CONSTRAINT businesses_pkey PRIMARY KEY (id);


--
-- Name: channel_accounts channel_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_accounts
    ADD CONSTRAINT channel_accounts_pkey PRIMARY KEY (id);


--
-- Name: contracts contracts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_pkey PRIMARY KEY (id);


--
-- Name: conversations conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_pkey PRIMARY KEY (id);


--
-- Name: follow_ups follow_ups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.follow_ups
    ADD CONSTRAINT follow_ups_pkey PRIMARY KEY (id);


--
-- Name: inbound_events inbound_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbound_events
    ADD CONSTRAINT inbound_events_pkey PRIMARY KEY (id);


--
-- Name: intake_keys intake_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.intake_keys
    ADD CONSTRAINT intake_keys_pkey PRIMARY KEY (id);


--
-- Name: invitations invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_pkey PRIMARY KEY (id);


--
-- Name: job_costs job_costs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_costs
    ADD CONSTRAINT job_costs_pkey PRIMARY KEY (id);


--
-- Name: leads leads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT leads_pkey PRIMARY KEY (id);


--
-- Name: memberships memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT memberships_pkey PRIMARY KEY (id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);


--
-- Name: notes notes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notes
    ADD CONSTRAINT notes_pkey PRIMARY KEY (id);


--
-- Name: outbound_messages outbound_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbound_messages
    ADD CONSTRAINT outbound_messages_pkey PRIMARY KEY (id);


--
-- Name: quote_items quote_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quote_items
    ADD CONSTRAINT quote_items_pkey PRIMARY KEY (id);


--
-- Name: quotes quotes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quotes
    ADD CONSTRAINT quotes_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_on_business_id_assigned_user_id_due_at_f0daf7d57f; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_business_id_assigned_user_id_due_at_f0daf7d57f ON public.follow_ups USING btree (business_id, assigned_user_id, due_at);


--
-- Name: idx_on_business_id_from_phone_created_at_2a81b6a486; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_business_id_from_phone_created_at_2a81b6a486 ON public.inbound_events USING btree (business_id, from_phone, created_at);


--
-- Name: idx_on_business_id_status_last_message_at_d4a1d84710; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_business_id_status_last_message_at_d4a1d84710 ON public.conversations USING btree (business_id, status, last_message_at);


--
-- Name: idx_on_business_id_to_phone_created_at_61a5255b6e; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_business_id_to_phone_created_at_61a5255b6e ON public.outbound_messages USING btree (business_id, to_phone, created_at);


--
-- Name: index_activities_on_business_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activities_on_business_id_and_created_at ON public.activities USING btree (business_id, created_at);


--
-- Name: index_activities_on_subject; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activities_on_subject ON public.activities USING btree (business_id, subject_type, subject_id, created_at);


--
-- Name: index_appointments_on_assigned_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_appointments_on_assigned_user_id ON public.appointments USING btree (assigned_user_id);


--
-- Name: index_appointments_on_business_id_and_starts_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_appointments_on_business_id_and_starts_at ON public.appointments USING btree (business_id, starts_at);


--
-- Name: index_appointments_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_appointments_on_lead_id ON public.appointments USING btree (lead_id);


--
-- Name: index_assistant_sessions_on_business_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_assistant_sessions_on_business_id_and_user_id ON public.assistant_sessions USING btree (business_id, user_id);


--
-- Name: index_assistant_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_assistant_sessions_on_user_id ON public.assistant_sessions USING btree (user_id);


--
-- Name: index_businesses_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_businesses_on_slug ON public.businesses USING btree (slug);


--
-- Name: index_channel_accounts_on_business_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_channel_accounts_on_business_id ON public.channel_accounts USING btree (business_id);


--
-- Name: index_channel_accounts_on_id_and_business_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_channel_accounts_on_id_and_business_id ON public.channel_accounts USING btree (id, business_id);


--
-- Name: index_channel_accounts_on_phone_number_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_channel_accounts_on_phone_number_id ON public.channel_accounts USING btree (phone_number_id);


--
-- Name: index_contracts_on_business_id_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_contracts_on_business_id_and_number ON public.contracts USING btree (business_id, number);


--
-- Name: index_contracts_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contracts_on_created_by_id ON public.contracts USING btree (created_by_id);


--
-- Name: index_contracts_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_contracts_on_lead_id ON public.contracts USING btree (lead_id);


--
-- Name: index_contracts_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_contracts_on_token_digest ON public.contracts USING btree (token_digest);


--
-- Name: index_conversations_on_assigned_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_conversations_on_assigned_user_id ON public.conversations USING btree (assigned_user_id);


--
-- Name: index_conversations_on_id_and_business_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_conversations_on_id_and_business_id ON public.conversations USING btree (id, business_id);


--
-- Name: index_conversations_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_conversations_on_lead_id ON public.conversations USING btree (lead_id);


--
-- Name: index_follow_ups_awaiting_reminder; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_follow_ups_awaiting_reminder ON public.follow_ups USING btree (due_at) WHERE ((reminded_at IS NULL) AND (completed_at IS NULL) AND (cancelled_at IS NULL));


--
-- Name: index_follow_ups_on_assigned_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_follow_ups_on_assigned_user_id ON public.follow_ups USING btree (assigned_user_id);


--
-- Name: index_follow_ups_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_follow_ups_on_created_by_id ON public.follow_ups USING btree (created_by_id);


--
-- Name: index_follow_ups_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_follow_ups_on_lead_id ON public.follow_ups USING btree (lead_id);


--
-- Name: index_inbound_events_on_provider_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_inbound_events_on_provider_event_id ON public.inbound_events USING btree (provider_event_id);


--
-- Name: index_intake_keys_on_business_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_intake_keys_on_business_id ON public.intake_keys USING btree (business_id);


--
-- Name: index_intake_keys_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_intake_keys_on_created_by_id ON public.intake_keys USING btree (created_by_id);


--
-- Name: index_intake_keys_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_intake_keys_on_token_digest ON public.intake_keys USING btree (token_digest);


--
-- Name: index_invitations_on_email_address; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invitations_on_email_address ON public.invitations USING btree (email_address);


--
-- Name: index_invitations_on_invited_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invitations_on_invited_by_id ON public.invitations USING btree (invited_by_id);


--
-- Name: index_invitations_one_open_per_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invitations_one_open_per_email ON public.invitations USING btree (business_id, email_address) WHERE ((accepted_at IS NULL) AND (declined_at IS NULL) AND (revoked_at IS NULL));


--
-- Name: index_job_costs_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_job_costs_on_created_by_id ON public.job_costs USING btree (created_by_id);


--
-- Name: index_job_costs_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_job_costs_on_lead_id ON public.job_costs USING btree (lead_id);


--
-- Name: index_leads_on_assigned_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_assigned_user_id ON public.leads USING btree (assigned_user_id);


--
-- Name: index_leads_on_business_id_and_phone_e164; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_business_id_and_phone_e164 ON public.leads USING btree (business_id, phone_e164);


--
-- Name: index_leads_on_business_id_and_source_and_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_leads_on_business_id_and_source_and_external_id ON public.leads USING btree (business_id, source, external_id) WHERE (external_id IS NOT NULL);


--
-- Name: index_leads_on_business_id_and_status_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_business_id_and_status_and_created_at ON public.leads USING btree (business_id, status, created_at);


--
-- Name: index_leads_on_business_id_and_won_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_business_id_and_won_at ON public.leads USING btree (business_id, won_at);


--
-- Name: index_leads_on_id_and_business_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_leads_on_id_and_business_id ON public.leads USING btree (id, business_id);


--
-- Name: index_memberships_on_business_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_memberships_on_business_id_and_user_id ON public.memberships USING btree (business_id, user_id);


--
-- Name: index_memberships_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_memberships_on_user_id ON public.memberships USING btree (user_id);


--
-- Name: index_messages_on_conversation_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_conversation_id_and_created_at ON public.messages USING btree (conversation_id, created_at);


--
-- Name: index_messages_on_sender_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_sender_user_id ON public.messages USING btree (sender_user_id);


--
-- Name: index_notes_on_author_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notes_on_author_user_id ON public.notes USING btree (author_user_id);


--
-- Name: index_notes_on_lead_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notes_on_lead_id_and_created_at ON public.notes USING btree (lead_id, created_at);


--
-- Name: index_outbound_messages_on_message_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_outbound_messages_on_message_id ON public.outbound_messages USING btree (message_id);


--
-- Name: index_outbound_messages_on_provider_message_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_outbound_messages_on_provider_message_id ON public.outbound_messages USING btree (provider_message_id) WHERE (provider_message_id IS NOT NULL);


--
-- Name: index_outbound_messages_on_status_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_outbound_messages_on_status_and_created_at ON public.outbound_messages USING btree (status, created_at);


--
-- Name: index_quote_items_on_quote_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_quote_items_on_quote_id_and_position ON public.quote_items USING btree (quote_id, "position");


--
-- Name: index_quotes_on_business_id_and_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_quotes_on_business_id_and_number ON public.quotes USING btree (business_id, number);


--
-- Name: index_quotes_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_quotes_on_created_by_id ON public.quotes USING btree (created_by_id);


--
-- Name: index_quotes_on_id_and_business_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_quotes_on_id_and_business_id ON public.quotes USING btree (id, business_id);


--
-- Name: index_quotes_on_lead_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_quotes_on_lead_id ON public.quotes USING btree (lead_id);


--
-- Name: index_quotes_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_quotes_on_token_digest ON public.quotes USING btree (token_digest);


--
-- Name: index_sessions_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sessions_on_token_digest ON public.sessions USING btree (token_digest);


--
-- Name: index_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_user_id ON public.sessions USING btree (user_id);


--
-- Name: index_users_on_email_address; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email_address ON public.users USING btree (email_address);


--
-- Name: index_users_on_phone; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_phone ON public.users USING btree (phone) WHERE (phone IS NOT NULL);


--
-- Name: contracts contracts_frozen_once_signed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER contracts_frozen_once_signed BEFORE DELETE OR UPDATE ON public.contracts FOR EACH ROW EXECUTE FUNCTION public.forbid_signed_contract_changes();


--
-- Name: quote_items quote_items_frozen_once_accepted; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER quote_items_frozen_once_accepted BEFORE INSERT OR DELETE OR UPDATE ON public.quote_items FOR EACH ROW EXECUTE FUNCTION public.forbid_accepted_quote_item_changes();


--
-- Name: quotes quotes_frozen_once_accepted; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER quotes_frozen_once_accepted BEFORE DELETE OR UPDATE ON public.quotes FOR EACH ROW EXECUTE FUNCTION public.forbid_accepted_quote_changes();


--
-- Name: messages fk_rails_083d4489a7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT fk_rails_083d4489a7 FOREIGN KEY (conversation_id, business_id) REFERENCES public.conversations(id, business_id);


--
-- Name: job_costs fk_rails_0c7f640658; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_costs
    ADD CONSTRAINT fk_rails_0c7f640658 FOREIGN KEY (lead_id, business_id) REFERENCES public.leads(id, business_id);


--
-- Name: outbound_messages fk_rails_119dcdbe29; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbound_messages
    ADD CONSTRAINT fk_rails_119dcdbe29 FOREIGN KEY (lead_id, business_id) REFERENCES public.leads(id, business_id);


--
-- Name: messages fk_rails_3197d016f7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT fk_rails_3197d016f7 FOREIGN KEY (sender_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: outbound_messages fk_rails_3915211714; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbound_messages
    ADD CONSTRAINT fk_rails_3915211714 FOREIGN KEY (message_id) REFERENCES public.messages(id) ON DELETE SET NULL;


--
-- Name: inbound_events fk_rails_3d24060cb0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbound_events
    ADD CONSTRAINT fk_rails_3d24060cb0 FOREIGN KEY (business_id) REFERENCES public.businesses(id);


--
-- Name: conversations fk_rails_435181481e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT fk_rails_435181481e FOREIGN KEY (assigned_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: conversations fk_rails_4bcf8099db; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT fk_rails_4bcf8099db FOREIGN KEY (business_id) REFERENCES public.businesses(id);


--
-- Name: quotes fk_rails_4d07b0b28d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quotes
    ADD CONSTRAINT fk_rails_4d07b0b28d FOREIGN KEY (created_by_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: leads fk_rails_4e4210c325; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT fk_rails_4e4210c325 FOREIGN KEY (assigned_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: intake_keys fk_rails_558c7ca6c0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.intake_keys
    ADD CONSTRAINT fk_rails_558c7ca6c0 FOREIGN KEY (business_id) REFERENCES public.businesses(id);


--
-- Name: notes fk_rails_55e2791a07; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notes
    ADD CONSTRAINT fk_rails_55e2791a07 FOREIGN KEY (author_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: assistant_sessions fk_rails_565ace800e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assistant_sessions
    ADD CONSTRAINT fk_rails_565ace800e FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: appointments fk_rails_589d62205e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT fk_rails_589d62205e FOREIGN KEY (business_id) REFERENCES public.businesses(id);


--
-- Name: job_costs fk_rails_59d50a32d1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_costs
    ADD CONSTRAINT fk_rails_59d50a32d1 FOREIGN KEY (business_id) REFERENCES public.businesses(id);


--
-- Name: outbound_messages fk_rails_5b34023d73; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbound_messages
    ADD CONSTRAINT fk_rails_5b34023d73 FOREIGN KEY (business_id) REFERENCES public.businesses(id);


--
-- Name: contracts fk_rails_6c6a2f6411; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT fk_rails_6c6a2f6411 FOREIGN KEY (business_id) REFERENCES public.businesses(id);


--
-- Name: notes fk_rails_748111e3dd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notes
    ADD CONSTRAINT fk_rails_748111e3dd FOREIGN KEY (business_id) REFERENCES public.businesses(id);


--
-- Name: sessions fk_rails_758836b4f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_758836b4f0 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: invitations fk_rails_7f80f50dbc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_rails_7f80f50dbc FOREIGN KEY (business_id) REFERENCES public.businesses(id);


--
-- Name: contracts fk_rails_7f9e013711; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT fk_rails_7f9e013711 FOREIGN KEY (lead_id, business_id) REFERENCES public.leads(id, business_id);


--
-- Name: outbound_messages fk_rails_82890691a1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.outbound_messages
    ADD CONSTRAINT fk_rails_82890691a1 FOREIGN KEY (channel_account_id, business_id) REFERENCES public.channel_accounts(id, business_id);


--
-- Name: follow_ups fk_rails_855c6701d2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.follow_ups
    ADD CONSTRAINT fk_rails_855c6701d2 FOREIGN KEY (business_id) REFERENCES public.businesses(id);


--
-- Name: activities fk_rails_90e481b9ed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT fk_rails_90e481b9ed FOREIGN KEY (business_id) REFERENCES public.businesses(id);


--
-- Name: memberships fk_rails_99326fb65d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_rails_99326fb65d FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: follow_ups fk_rails_9a9989f30f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.follow_ups
    ADD CONSTRAINT fk_rails_9a9989f30f FOREIGN KEY (created_by_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: channel_accounts fk_rails_9abdbdc879; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.channel_accounts
    ADD CONSTRAINT fk_rails_9abdbdc879 FOREIGN KEY (business_id) REFERENCES public.businesses(id);


--
-- Name: memberships fk_rails_a5acc905ee; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.memberships
    ADD CONSTRAINT fk_rails_a5acc905ee FOREIGN KEY (business_id) REFERENCES public.businesses(id);


--
-- Name: appointments fk_rails_a5b8c50aca; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT fk_rails_a5b8c50aca FOREIGN KEY (lead_id, business_id) REFERENCES public.leads(id, business_id);


--
-- Name: intake_keys fk_rails_ab1fadf7d8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.intake_keys
    ADD CONSTRAINT fk_rails_ab1fadf7d8 FOREIGN KEY (created_by_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: assistant_sessions fk_rails_ad593a141e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assistant_sessions
    ADD CONSTRAINT fk_rails_ad593a141e FOREIGN KEY (business_id) REFERENCES public.businesses(id);


--
-- Name: appointments fk_rails_afc391ba1a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT fk_rails_afc391ba1a FOREIGN KEY (assigned_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: quote_items fk_rails_b28ccd5e35; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quote_items
    ADD CONSTRAINT fk_rails_b28ccd5e35 FOREIGN KEY (quote_id, business_id) REFERENCES public.quotes(id, business_id) ON DELETE CASCADE;


--
-- Name: messages fk_rails_b44cadb953; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT fk_rails_b44cadb953 FOREIGN KEY (business_id) REFERENCES public.businesses(id);


--
-- Name: quotes fk_rails_be2c911c9c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quotes
    ADD CONSTRAINT fk_rails_be2c911c9c FOREIGN KEY (lead_id, business_id) REFERENCES public.leads(id, business_id);


--
-- Name: notes fk_rails_c57a878880; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notes
    ADD CONSTRAINT fk_rails_c57a878880 FOREIGN KEY (lead_id, business_id) REFERENCES public.leads(id, business_id);


--
-- Name: quote_items fk_rails_c976806706; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quote_items
    ADD CONSTRAINT fk_rails_c976806706 FOREIGN KEY (business_id) REFERENCES public.businesses(id);


--
-- Name: follow_ups fk_rails_ce23273073; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.follow_ups
    ADD CONSTRAINT fk_rails_ce23273073 FOREIGN KEY (lead_id, business_id) REFERENCES public.leads(id, business_id);


--
-- Name: activities fk_rails_d4f1085fbd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT fk_rails_d4f1085fbd FOREIGN KEY (actor_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: contracts fk_rails_d6942a7d49; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT fk_rails_d6942a7d49 FOREIGN KEY (quote_id, business_id) REFERENCES public.quotes(id, business_id);


--
-- Name: contracts fk_rails_d6e4b5b205; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT fk_rails_d6e4b5b205 FOREIGN KEY (created_by_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: quotes fk_rails_d70dd27f25; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quotes
    ADD CONSTRAINT fk_rails_d70dd27f25 FOREIGN KEY (business_id) REFERENCES public.businesses(id);


--
-- Name: invitations fk_rails_d799c974a1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_rails_d799c974a1 FOREIGN KEY (invited_by_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: conversations fk_rails_d8825cdf80; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT fk_rails_d8825cdf80 FOREIGN KEY (lead_id, business_id) REFERENCES public.leads(id, business_id);


--
-- Name: follow_ups fk_rails_d93e073010; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.follow_ups
    ADD CONSTRAINT fk_rails_d93e073010 FOREIGN KEY (assigned_user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: job_costs fk_rails_e94fd397d2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.job_costs
    ADD CONSTRAINT fk_rails_e94fd397d2 FOREIGN KEY (created_by_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: inbound_events fk_rails_f647b8d021; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.inbound_events
    ADD CONSTRAINT fk_rails_f647b8d021 FOREIGN KEY (channel_account_id, business_id) REFERENCES public.channel_accounts(id, business_id);


--
-- Name: leads fk_rails_f9ae891732; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT fk_rails_f9ae891732 FOREIGN KEY (business_id) REFERENCES public.businesses(id);


--
-- Name: activities; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.activities ENABLE ROW LEVEL SECURITY;

--
-- Name: activities activities_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY activities_tenant ON public.activities USING ((business_id = public.current_business_id())) WITH CHECK ((business_id = public.current_business_id()));


--
-- Name: appointments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;

--
-- Name: appointments appointments_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY appointments_tenant ON public.appointments USING ((business_id = public.current_business_id())) WITH CHECK ((business_id = public.current_business_id()));


--
-- Name: assistant_sessions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.assistant_sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: assistant_sessions assistant_sessions_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY assistant_sessions_tenant ON public.assistant_sessions USING ((business_id = public.current_business_id())) WITH CHECK ((business_id = public.current_business_id()));


--
-- Name: businesses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.businesses ENABLE ROW LEVEL SECURITY;

--
-- Name: businesses businesses_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY businesses_tenant ON public.businesses USING ((id = public.current_business_id())) WITH CHECK ((id = public.current_business_id()));


--
-- Name: channel_accounts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.channel_accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: channel_accounts channel_accounts_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY channel_accounts_tenant ON public.channel_accounts USING ((business_id = public.current_business_id())) WITH CHECK ((business_id = public.current_business_id()));


--
-- Name: contracts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contracts ENABLE ROW LEVEL SECURITY;

--
-- Name: contracts contracts_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contracts_tenant ON public.contracts USING ((business_id = public.current_business_id())) WITH CHECK ((business_id = public.current_business_id()));


--
-- Name: conversations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

--
-- Name: conversations conversations_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY conversations_tenant ON public.conversations USING ((business_id = public.current_business_id())) WITH CHECK ((business_id = public.current_business_id()));


--
-- Name: follow_ups; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.follow_ups ENABLE ROW LEVEL SECURITY;

--
-- Name: follow_ups follow_ups_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY follow_ups_tenant ON public.follow_ups USING ((business_id = public.current_business_id())) WITH CHECK ((business_id = public.current_business_id()));


--
-- Name: inbound_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.inbound_events ENABLE ROW LEVEL SECURITY;

--
-- Name: inbound_events inbound_events_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY inbound_events_tenant ON public.inbound_events USING ((business_id = public.current_business_id())) WITH CHECK ((business_id = public.current_business_id()));


--
-- Name: intake_keys; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.intake_keys ENABLE ROW LEVEL SECURITY;

--
-- Name: intake_keys intake_keys_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY intake_keys_tenant ON public.intake_keys USING ((business_id = public.current_business_id())) WITH CHECK ((business_id = public.current_business_id()));


--
-- Name: invitations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;

--
-- Name: invitations invitations_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY invitations_tenant ON public.invitations USING ((business_id = public.current_business_id())) WITH CHECK ((business_id = public.current_business_id()));


--
-- Name: job_costs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.job_costs ENABLE ROW LEVEL SECURITY;

--
-- Name: job_costs job_costs_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY job_costs_tenant ON public.job_costs USING ((business_id = public.current_business_id())) WITH CHECK ((business_id = public.current_business_id()));


--
-- Name: leads; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leads ENABLE ROW LEVEL SECURITY;

--
-- Name: leads leads_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leads_tenant ON public.leads USING ((business_id = public.current_business_id())) WITH CHECK ((business_id = public.current_business_id()));


--
-- Name: memberships; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.memberships ENABLE ROW LEVEL SECURITY;

--
-- Name: memberships memberships_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY memberships_tenant ON public.memberships USING ((business_id = public.current_business_id())) WITH CHECK ((business_id = public.current_business_id()));


--
-- Name: messages; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

--
-- Name: messages messages_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY messages_tenant ON public.messages USING ((business_id = public.current_business_id())) WITH CHECK ((business_id = public.current_business_id()));


--
-- Name: notes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notes ENABLE ROW LEVEL SECURITY;

--
-- Name: notes notes_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notes_tenant ON public.notes USING ((business_id = public.current_business_id())) WITH CHECK ((business_id = public.current_business_id()));


--
-- Name: outbound_messages; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.outbound_messages ENABLE ROW LEVEL SECURITY;

--
-- Name: outbound_messages outbound_messages_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY outbound_messages_tenant ON public.outbound_messages USING ((business_id = public.current_business_id())) WITH CHECK ((business_id = public.current_business_id()));


--
-- Name: quote_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.quote_items ENABLE ROW LEVEL SECURITY;

--
-- Name: quote_items quote_items_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY quote_items_tenant ON public.quote_items USING ((business_id = public.current_business_id())) WITH CHECK ((business_id = public.current_business_id()));


--
-- Name: quotes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.quotes ENABLE ROW LEVEL SECURITY;

--
-- Name: quotes quotes_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY quotes_tenant ON public.quotes USING ((business_id = public.current_business_id())) WITH CHECK ((business_id = public.current_business_id()));


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260930000006'),
('20260930000005'),
('20260930000004'),
('20260930000003'),
('20260930000002'),
('20260930000001');

