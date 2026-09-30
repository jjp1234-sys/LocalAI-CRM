# For documents a customer opens through a private link (quotes, contracts).
#
# The link's token is random and long. Its SHA-256 digest is stored for
# looking it up, and the token itself is stored encrypted so the team can
# re-send the link later. Neither is ever shown in API responses.
module PublicLink
  extend ActiveSupport::Concern

  included do
    encrypts :token
    before_validation(on: :create) do
      self.token ||= SecureRandom.base58(32)
      self.token_digest = self.class.digest(token)
    end
  end

  class_methods do
    def digest(token)
      OpenSSL::Digest::SHA256.hexdigest(token.to_s)
    end

    def find_by_public_token(token)
      return nil if token.blank? || token.length > 100

      find_by(token_digest: digest(token))
    end

    # Per-business numbering (Q-1001, C-1001). A unique index catches two
    # documents grabbing the same number at once; the loser just retries.
    def create_numbered!(**attrs)
      attempts = 0
      begin
        transaction(requires_new: true) do
          create!(**attrs, number: (maximum(:number) || 1000) + 1)
        end
      rescue ActiveRecord::RecordNotUnique
        attempts += 1
        retry if attempts < 3
        raise
      end
    end
  end

  def public_url
    "#{Rails.application.config.x.public_base_url}/#{self.class::URL_PREFIX}/#{token}"
  end

  def mark_viewed!
    update_columns(viewed_at: Time.current) if viewed_at.nil?
  end
end
