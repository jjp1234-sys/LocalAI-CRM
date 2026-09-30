# For records authenticated by a random token (login sessions, intake keys).
#
# The token is generated here, shown to the client exactly once, and only its
# SHA-256 digest is stored. Someone who reads the database can't log in with
# what they find. A plain SHA-256 is enough because the tokens are long and
# random. Passwords need bcrypt's deliberate slowness; these don't.
module SecureTokenDigest
  extend ActiveSupport::Concern

  class_methods do
    # prefix: short marker ("fds_", "fdi_") that says what kind of token it
    # is, so a leaked one is easy to recognise in logs or secret scanners.
    def token_marker(prefix = nil)
      prefix ? @token_marker = prefix : @token_marker
    end

    def digest(token)
      OpenSSL::Digest::SHA256.hexdigest(token.to_s)
    end

    def find_by_token(token)
      return nil if token.blank? || !token.start_with?(token_marker)

      find_by(token_digest: digest(token))
    end
  end

  # Only set on a record created in this request.
  attr_reader :token

  def generate_token
    @token = "#{self.class.token_marker}#{SecureRandom.base58(40)}"
    self.token_digest = self.class.digest(@token)
    @token
  end
end
