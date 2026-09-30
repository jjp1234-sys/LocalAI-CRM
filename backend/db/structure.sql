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
-- Name: businesses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.businesses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    slug character varying NOT NULL,
    time_zone character varying DEFAULT 'UTC'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT businesses_name_length CHECK (((char_length((name)::text) >= 1) AND (char_length((name)::text) <= 120))),
    CONSTRAINT businesses_slug_format CHECK (((slug)::text ~ '^[a-z0-9]([a-z0-9-]{1,61})[a-z0-9]$'::text))
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
    CONSTRAINT conversations_channel_valid CHECK (((channel)::text = ANY ((ARRAY['sms'::character varying, 'web_chat'::character varying, 'email'::character varying, 'phone'::character varying, 'facebook'::character varying, 'instagram'::character varying, 'other'::character varying])::text[]))),
    CONSTRAINT conversations_status_valid CHECK (((status)::text = ANY ((ARRAY['open'::character varying, 'closed'::character varying])::text[])))
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
    CONSTRAINT leads_contact_present CHECK (((email IS NOT NULL) OR (phone IS NOT NULL))),
    CONSTRAINT leads_external_id_length CHECK ((char_length((external_id)::text) <= 200)),
    CONSTRAINT leads_name_length CHECK (((char_length((name)::text) >= 1) AND (char_length((name)::text) <= 120))),
    CONSTRAINT leads_need_length CHECK ((char_length(need) <= 2000)),
    CONSTRAINT leads_score_range CHECK (((score IS NULL) OR ((score >= 0) AND (score <= 100)))),
    CONSTRAINT leads_source_valid CHECK (((source)::text = ANY ((ARRAY['website'::character varying, 'facebook'::character varying, 'instagram'::character varying, 'google'::character varying, 'referral'::character varying, 'phone'::character varying, 'walk_in'::character varying, 'manual'::character varying, 'other'::character varying])::text[]))),
    CONSTRAINT leads_status_valid CHECK (((status)::text = ANY ((ARRAY['new'::character varying, 'contacted'::character varying, 'qualified'::character varying, 'appointment'::character varying, 'won'::character varying, 'lost'::character varying])::text[])))
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
    CONSTRAINT users_email_length CHECK ((char_length((email_address)::text) <= 254)),
    CONSTRAINT users_email_lowercase CHECK (((email_address)::text = lower((email_address)::text))),
    CONSTRAINT users_name_length CHECK (((char_length((name)::text) >= 1) AND (char_length((name)::text) <= 120)))
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
-- Name: businesses businesses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.businesses
    ADD CONSTRAINT businesses_pkey PRIMARY KEY (id);


--
-- Name: conversations conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_pkey PRIMARY KEY (id);


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
-- Name: idx_on_business_id_status_last_message_at_d4a1d84710; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_business_id_status_last_message_at_d4a1d84710 ON public.conversations USING btree (business_id, status, last_message_at);


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
-- Name: index_businesses_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_businesses_on_slug ON public.businesses USING btree (slug);


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
-- Name: index_leads_on_assigned_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_assigned_user_id ON public.leads USING btree (assigned_user_id);


--
-- Name: index_leads_on_business_id_and_source_and_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_leads_on_business_id_and_source_and_external_id ON public.leads USING btree (business_id, source, external_id) WHERE (external_id IS NOT NULL);


--
-- Name: index_leads_on_business_id_and_status_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_business_id_and_status_and_created_at ON public.leads USING btree (business_id, status, created_at);


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
-- Name: messages fk_rails_083d4489a7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT fk_rails_083d4489a7 FOREIGN KEY (conversation_id, business_id) REFERENCES public.conversations(id, business_id);


--
-- Name: messages fk_rails_3197d016f7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT fk_rails_3197d016f7 FOREIGN KEY (sender_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


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
-- Name: appointments fk_rails_589d62205e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT fk_rails_589d62205e FOREIGN KEY (business_id) REFERENCES public.businesses(id);


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
-- Name: appointments fk_rails_afc391ba1a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT fk_rails_afc391ba1a FOREIGN KEY (assigned_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: messages fk_rails_b44cadb953; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT fk_rails_b44cadb953 FOREIGN KEY (business_id) REFERENCES public.businesses(id);


--
-- Name: activities fk_rails_d4f1085fbd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT fk_rails_d4f1085fbd FOREIGN KEY (actor_user_id) REFERENCES public.users(id) ON DELETE SET NULL;


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
-- Name: businesses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.businesses ENABLE ROW LEVEL SECURITY;

--
-- Name: businesses businesses_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY businesses_tenant ON public.businesses USING ((id = public.current_business_id())) WITH CHECK ((id = public.current_business_id()));


--
-- Name: conversations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

--
-- Name: conversations conversations_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY conversations_tenant ON public.conversations USING ((business_id = public.current_business_id())) WITH CHECK ((business_id = public.current_business_id()));


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
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260930000002'),
('20260930000001');

