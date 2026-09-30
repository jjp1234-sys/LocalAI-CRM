module Payments
  # Stripe signs each webhook: header "Stripe-Signature: t=<time>,v1=<hmac>",
  # where hmac = HMAC-SHA256(secret, "<time>.<raw body>"). Old timestamps are
  # refused so a captured webhook can't be replayed later.
  module StripeSignature
    TOLERANCE = 5.minutes

    module_function

    def valid?(body, header, secret: Rails.application.config.x.stripe.webhook_secret, now: Time.current)
      return false if secret.blank? || header.blank?

      parts = header.to_s.split(",").map { |p| p.split("=", 2) }.select { |p| p.size == 2 }
      timestamp = parts.find { |k, _| k == "t" }&.last.to_i
      signatures = parts.select { |k, _| k == "v1" }.map(&:last)
      return false if timestamp.zero? || signatures.empty? || (now.to_i - timestamp).abs > TOLERANCE

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
      signatures.any? { |sig| ActiveSupport::SecurityUtils.secure_compare(expected, sig) }
    end

    def header_for(body, secret: Rails.application.config.x.stripe.webhook_secret, now: Time.current)
      "t=#{now.to_i},v1=#{OpenSSL::HMAC.hexdigest("SHA256", secret, "#{now.to_i}.#{body}")}"
    end
  end
end
