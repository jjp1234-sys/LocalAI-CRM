# An offer to join a business. The invitee accepts it while logged in as the
# account with that email address; until then they're not a member and the
# business can't see anything about them.
#
# Known gap: email addresses aren't verified yet, so whoever registers an
# address first can accept invitations sent to it. Email verification closes
# this once the app can send email.
class Invitation < ApplicationRecord
  include TenantOwned

  LIFETIME = 14.days

  belongs_to :invited_by, class_name: "User", optional: true

  enum :role, Membership::ROLE_RANK.keys.index_by(&:itself), validate: true

  normalizes :email_address, with: ->(email) { email.strip.downcase }
  validates :email_address, presence: true, length: { maximum: 254 }, format: { with: URI::MailTo::EMAIL_REGEXP }

  before_validation(on: :create) { self.expires_at ||= LIFETIME.from_now }

  scope :open, -> { where(accepted_at: nil, declined_at: nil, revoked_at: nil) }
  scope :pending, -> { open.where("expires_at > ?", Time.current) }

  # Creates the membership and closes the invitation. Must run inside
  # Tenant.with(business). Already being a member isn't an error: the
  # invitation is just closed.
  def accept!(user)
    transaction do
      Membership.create!(user: user, role: role) unless Membership.exists?(user_id: user.id)
      update!(accepted_at: Time.current)
    end
  end

  def decline!
    update!(declined_at: Time.current)
  end

  def revoke!
    update!(revoked_at: Time.current)
  end
end
