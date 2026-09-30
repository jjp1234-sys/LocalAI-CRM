module Whatsapp
  # Meta signs each webhook body with the app secret (HMAC-SHA256) and sends
  # the result as "X-Hub-Signature-256: sha256=<hex>".
  module Signature
    module_function

    def sign(body, secret = Rails.application.config.x.whatsapp.app_secret)
      "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", secret, body)}"
    end

    # Constant-time comparison, so the check doesn't leak how many characters
    # of a guessed signature were right.
    def valid?(body, header, secret = Rails.application.config.x.whatsapp.app_secret)
      header.present? && ActiveSupport::SecurityUtils.secure_compare(sign(body, secret), header.to_s)
    end
  end
end
