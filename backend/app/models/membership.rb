# A user's role in one business.
#   owner: everything, including changing other owners
#   admin: manage members (except owners) and intake keys
#   agent: work with leads, conversations and appointments
class Membership < ApplicationRecord
  include TenantOwned

  ROLE_RANK = { "agent" => 0, "admin" => 1, "owner" => 2 }.freeze

  belongs_to :user

  enum :role, ROLE_RANK.keys.index_by(&:itself), validate: true

  validates :user_id, uniqueness: { scope: :business_id }
  validate :keeps_an_owner, on: :update
  before_destroy :prevent_removing_last_owner

  # True if this role is at least as powerful as `role`.
  def at_least?(role)
    ROLE_RANK.fetch(self.role) >= ROLE_RANK.fetch(role.to_s)
  end

  private

  # Locks the business's owner rows (SELECT ... FOR UPDATE) before counting.
  # Without the lock, two owners demoting each other at the same moment could
  # each see the other as the remaining owner, and both changes would go
  # through, leaving no owner. With it, the second waits for the first.
  def other_owners?
    Membership.where(business_id: business_id, role: "owner").lock.pluck(:id).any? { |owner_id| owner_id != id }
  end

  def keeps_an_owner
    if role_changed?(from: "owner") && !other_owners?
      errors.add(:role, "can't be changed: a business needs at least one owner")
    end
  end

  def prevent_removing_last_owner
    if role == "owner" && !other_owners?
      errors.add(:base, "A business needs at least one owner")
      throw :abort
    end
  end
end
