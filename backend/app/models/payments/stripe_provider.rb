module Payments
  # Stripe Checkout, charging on the business's own connected Stripe account
  # (Stripe Connect "direct charges"), so money goes straight to them.
  #
  # Needs STRIPE_SECRET_KEY (the platform's key) and, per business, a
  # connected account ID (acct_...).
  class StripeProvider
    API = "https://api.stripe.com/v1/checkout/sessions"
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 15

    def initialize(business)
      @business = business
    end

    def create_checkout(payment, success_url:, cancel_url:)
      key = Rails.application.config.x.stripe.secret_key
      raise Provider::Error, "Stripe isn't configured" if key.blank? || @business.stripe_account_id.blank?

      uri = URI(API)
      request = Net::HTTP::Post.new(uri)
      request.basic_auth(key, "")
      request["Stripe-Account"] = @business.stripe_account_id
      # Stripe returns the same session for a repeated request with this key,
      # so a retried click can't create two charges.
      request["Idempotency-Key"] = "payment-#{payment.id}-#{payment.updated_at.to_i}"
      request.set_form_data(
        "mode" => "payment",
        "client_reference_id" => payment.id,
        "metadata[payment_id]" => payment.id,
        "payment_intent_data[metadata][payment_id]" => payment.id,
        "line_items[0][quantity]" => "1",
        "line_items[0][price_data][currency]" => payment.currency,
        "line_items[0][price_data][unit_amount]" => payment.amount_cents.to_s,
        "line_items[0][price_data][product_data][name]" => "#{@business.name}: #{payment.description}".first(250),
        "success_url" => success_url,
        "cancel_url" => cancel_url
      )
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) { |http| http.request(request) }
      body = JSON.parse(response.body.to_s) rescue {}
      raise Provider::Error, "Stripe: #{body.dig("error", "message") || response.code}" unless response.is_a?(Net::HTTPSuccess) && body["url"]

      { id: body["id"], url: body["url"] }
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, OpenSSL::SSL::SSLError => e
      raise Provider::Error, "Stripe unreachable (#{e.class})"
    end
  end
end
