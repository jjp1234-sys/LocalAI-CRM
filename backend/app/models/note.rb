# A free-text note on a lead. Added, never edited or deleted (the database
# role the app runs as can't; see db/app_role.sql).
class Note < ApplicationRecord
  include TenantOwned

  belongs_to :lead
  belongs_to :author_user, class_name: "User", optional: true

  normalizes :body, with: ->(v) { v.strip }
  validates :body, presence: true, length: { maximum: 5000 }
  validate :lead_in_same_business

  after_create { lead.update_columns(last_activity_at: created_at) }

  def readonly?
    persisted?
  end

  private

  def lead_in_same_business
    errors.add(:lead, "must belong to the same business") if lead && lead.business_id != business_id
  end
end
