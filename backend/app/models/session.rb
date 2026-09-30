# A logged-in client. The client holds the token; we hold its digest.
class Session < ApplicationRecord
  include SecureTokenDigest
  token_marker "fds_"

  LIFETIME = 14.days
  # Don't write to the database on every request just to record activity.
  TOUCH_INTERVAL = 5.minutes

  belongs_to :user

  before_validation(on: :create) do
    generate_token
    self.expires_at ||= LIFETIME.from_now
  end

  scope :active, -> { where("expires_at > ?", Time.current) }

  def self.authenticate(token)
    session = active.find_by_token(token)
    session&.touch_last_used
    session
  end

  def touch_last_used
    if last_used_at.nil? || last_used_at < TOUCH_INTERVAL.ago
      update_column(:last_used_at, Time.current)
    end
  end
end
