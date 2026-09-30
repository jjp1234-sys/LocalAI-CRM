module Webhooks
  # Stripe tells us here when a checkout is paid (or expires). Set this URL
  # as a Connect webhook in Stripe, since payments happen on the businesses'
  # connected accounts.
  #
  # Every request's signature is checked against the raw body, and each event
  # ID is recorded once, so a replayed or retried event changes nothing.
  class StripeController < ActionController::API
    MAX_BODY = 512.kilobytes
    PAID_EVENTS = %w[checkout.session.completed checkout.session.async_payment_succeeded].freeze

    def receive
      body = request.raw_post.to_s
      return head(:payload_too_large) if body.bytesize > MAX_BODY
      return head(:bad_request) unless Payments::StripeSignature.valid?(body, request.headers["Stripe-Signature"])

      event = JSON.parse(body)
      return head(:ok) unless first_time?(event["id"])

      session = event.dig("data", "object") || {}
      case event["type"]
      when *PAID_EVENTS
        # "completed" can arrive before a bank transfer clears; only "paid" counts.
        Payments::Settle.call(session_id: session["id"], amount_cents: session["amount_total"]) if session["payment_status"] == "paid"
      when "checkout.session.expired"
        expire(session["id"])
      end
      head :ok
    rescue JSON::ParserError
      head :bad_request
    end

    private

    def first_time?(event_id)
      return false if event_id.blank?

      WebhookReceipt.insert_all([ { provider: "stripe", event_id: event_id.to_s.first(255), created_at: Time.current } ],
        unique_by: [ :provider, :event_id ], returning: :id).rows.any?
    end

    def expire(session_id)
      payment = Payment.find_by(provider_session_id: session_id.to_s)
      Tenant.with(payment.business) { Payment.find(payment.id).checkout_expired! } if payment
    end
  end
end
