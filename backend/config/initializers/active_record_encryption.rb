# Keys for Active Record encryption, which encrypts sensitive columns (like a
# WhatsApp access token) before they reach the database.
#
# Production must supply real keys through the environment; generate them with
# `bin/rails db:encryption:init`. Development and test use fixed throwaway
# keys so the app runs out of the box. Never reuse these anywhere real.
Rails.application.configure do
  if Rails.env.production?
    config.active_record.encryption.primary_key = ENV.fetch("AR_ENCRYPTION_PRIMARY_KEY")
    config.active_record.encryption.deterministic_key = ENV.fetch("AR_ENCRYPTION_DETERMINISTIC_KEY")
    config.active_record.encryption.key_derivation_salt = ENV.fetch("AR_ENCRYPTION_KEY_DERIVATION_SALT")
  else
    config.active_record.encryption.primary_key = "dev-only-primary-key-not-secret-0000"
    config.active_record.encryption.deterministic_key = "dev-only-deterministic-key-not-secret"
    config.active_record.encryption.key_derivation_salt = "dev-only-key-derivation-salt-not-secret"
  end
end
