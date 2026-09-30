module Whatsapp
  # Turns one webhook delivery from Meta into InboundEvent rows and queues
  # them for processing. It does no business logic itself, so it answers Meta
  # quickly (Meta retries webhooks that are slow or fail).
  #
  # Payload shape (trimmed):
  #   { "entry": [ { "changes": [ { "value": {
  #       "metadata": { "phone_number_id": "..." },
  #       "contacts": [ { "wa_id": "13055550142", "profile": { "name": "Sarah" } } ],
  #       "messages": [ { "id": "wamid...", "from": "13055550142", "type": "text", "text": { "body": "hi" } } ],
  #       "statuses": [ { "id": "wamid...", "status": "delivered" } ]
  #   } } ] } ] }
  class Webhook
    def initialize(payload)
      @payload = payload
    end

    # Returns the IDs of events that were new (a repeated delivery adds none).
    def ingest
      rows = Array(@payload["entry"]).flat_map do |entry|
        Array(entry["changes"]).flat_map { |change| rows_for(change["value"] || {}) }
      end
      return [] if rows.empty?

      inserted = InboundEvent.insert_all(rows, unique_by: :provider_event_id, returning: :id)
      ids = inserted.rows.flatten
      ids.each { |id| ProcessInboundEventJob.perform_later(id) }
      ids
    end

    private

    def rows_for(value)
      account = ChannelAccount.active.find_by(phone_number_id: value.dig("metadata", "phone_number_id").to_s)
      # A number we don't know (or one that was switched off): ignore it.
      return [] unless account

      names = Array(value["contacts"]).to_h { |c| [ c["wa_id"].to_s, c.dig("profile", "name") ] }
      now = Time.current

      messages = Array(value["messages"]).filter_map do |message|
        next if message["id"].blank? || message["from"].blank?
        # A sender that isn't a valid number can't be matched to anyone, and
        # a nil phone would match every lead without one. Drop it.
        next unless PhoneNumber.normalize("+#{message["from"]}")

        {
          business_id: account.business_id, channel_account_id: account.id, kind: "message",
          provider_event_id: message["id"].to_s.first(200),
          from_phone: PhoneNumber.normalize("+#{message["from"]}"),
          payload: message.merge("profile_name" => names[message["from"].to_s]),
          created_at: now
        }
      end

      statuses = Array(value["statuses"]).filter_map do |status|
        next if status["id"].blank? || status["status"].blank?

        {
          business_id: account.business_id, channel_account_id: account.id, kind: "status",
          provider_event_id: "status:#{status["id"]}:#{status["status"]}".first(200),
          from_phone: nil, payload: status, created_at: now
        }
      end

      messages + statuses
    end
  end
end
