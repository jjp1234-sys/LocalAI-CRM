module Api
  module V1
    module Intake
      # POST /api/v1/intake/leads
      #   Authorization: Bearer fdi_...   (an intake key, not a login token)
      #   { "lead": { "name", "email", "phone", "need", "source", "external_id", "message" } }
      #
      # For website forms and lead webhooks. If `external_id` is sent and a
      # lead with the same source and external_id already exists, nothing new
      # is created and the existing lead's ID is returned with 200, so a
      # retried webhook can't create duplicates. A new lead returns 201.
      #
      # The response contains only the lead's ID: whoever holds an intake key
      # can add leads but can't read anything back.
      class LeadsController < Api::V1::BaseController
        # "purchased" is reserved for leads we sell the business, so a form
        # can't claim it and skew the report of what those leads earned.
        SOURCES = Lead::SOURCES - %w[manual purchased]
        CHANNEL_FOR_SOURCE = { "facebook" => "facebook", "instagram" => "instagram", "website" => "web_chat" }.freeze

        allow_unauthenticated
        rate_limit to: 30, within: 1.minute, name: "intake-ip", by: -> { client_ip },
          store: Rails.application.config.x.rate_limit_store, with: -> { rate_limited }
        rate_limit to: 120, within: 1.minute, name: "intake-key",
          by: -> { IntakeKey.digest(bearer_token) },
          store: Rails.application.config.x.rate_limit_store, with: -> { rate_limited }

        before_action :authenticate_intake_key!

        def create
          attrs = params.expect(lead: [ :name, :email, :phone, :need, :source, :external_id, :message ])
          source = attrs[:source].presence || "website"
          unless SOURCES.include?(source)
            return render_error(:unprocessable_content, "invalid", "Validation failed", { source: [ "Source is not allowed" ] })
          end

          Tenant.with(@intake_key.business) do
            existing = find_existing(source, attrs[:external_id])
            next render_data({ id: existing.id, duplicate: true }, status: :ok) if existing

            lead = create_lead(attrs, source)
            render_data({ id: lead.id, duplicate: false }, status: :created)
          end
        rescue ActiveRecord::RecordNotUnique
          # Two copies of the same webhook arrived at the same moment and the
          # other one won. Return the lead it created.
          Tenant.with(@intake_key.business) do
            render_data({ id: find_existing(source, attrs[:external_id]).id, duplicate: true }, status: :ok)
          end
        end

        private

        def authenticate_intake_key!
          @intake_key = IntakeKey.authenticate(bearer_token)
          render_error(:unauthorized, "unauthorized", "A valid intake key is required") unless @intake_key
        end

        def find_existing(source, external_id)
          return nil if external_id.blank?

          Lead.find_by(source: source, external_id: external_id.to_s.strip)
        end

        def create_lead(attrs, source)
          Lead.transaction(requires_new: true) do
            lead = Lead.create!(attrs.except(:message).merge(source: source, status: "new"))
            if attrs[:message].present?
              conversation = lead.conversations.create!(channel: CHANNEL_FOR_SOURCE.fetch(source, "other"))
              conversation.messages.create!(body: attrs[:message], direction: "inbound", sender_kind: "customer")
            end
            lead
          end
        end
      end
    end
  end
end
