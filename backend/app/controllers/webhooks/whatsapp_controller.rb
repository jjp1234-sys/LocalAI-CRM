module Webhooks
  # Where Meta delivers WhatsApp messages and status updates.
  #
  #   GET  /webhooks/whatsapp  one-time handshake when the URL is registered
  #   POST /webhooks/whatsapp  events, signed with the app secret
  #
  # Every POST's signature is checked against the raw body before anything
  # else happens, so a forged request can't inject messages.
  class WhatsappController < ActionController::API
    MAX_BODY = 1.megabyte

    def verify
      if params["hub.mode"] == "subscribe" &&
          ActiveSupport::SecurityUtils.secure_compare(params["hub.verify_token"].to_s, Rails.application.config.x.whatsapp.verify_token)
        render plain: params["hub.challenge"].to_s
      else
        head :forbidden
      end
    end

    def receive
      body = request.raw_post.to_s
      return head(:payload_too_large) if body.bytesize > MAX_BODY
      return head(:unauthorized) unless Whatsapp::Signature.valid?(body, request.headers["X-Hub-Signature-256"])

      payload = JSON.parse(body)
      Whatsapp::Webhook.new(payload).ingest if payload.is_a?(Hash)
      head :ok
    rescue JSON::ParserError
      head :bad_request
    end
  end
end
