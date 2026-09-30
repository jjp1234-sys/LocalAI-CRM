# Lets an outside system (a website form, a lead-ads webhook) post leads into
# one business, without a user login. Revoking a key cuts it off at once.
class IntakeKey < ApplicationRecord
  include TenantOwned
  include SecureTokenDigest
  token_marker "fdi_"

  belongs_to :created_by, class_name: "User", optional: true

  before_validation(on: :create) do
    generate_token
    self.token_prefix = token.first(10)
  end

  normalizes :name, with: ->(name) { name.squish }
  validates :name, presence: true, length: { maximum: 80 }

  scope :active, -> { where(revoked_at: nil) }

  def self.authenticate(token)
    key = active.find_by_token(token)
    if key && (key.last_used_at.nil? || key.last_used_at < 5.minutes.ago)
      key.update_column(:last_used_at, Time.current)
    end
    key
  end

  def revoked?
    revoked_at.present?
  end

  def revoke!
    update!(revoked_at: Time.current) unless revoked?
  end
end
