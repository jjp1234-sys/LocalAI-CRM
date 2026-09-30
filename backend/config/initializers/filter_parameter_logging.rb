# Keep secrets and customer PII out of the logs. Rails matches these as
# partial, case-insensitive names, so :phone also hides :phone_number.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  :phone, :body, :need, :notes, :message, :name, :q, :location, :external_id
]
