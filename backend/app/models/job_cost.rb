# Something a job cost: materials, a subcontractor, labor. A record, not
# edited once added. A lead's profit is its value minus these.
class JobCost < ApplicationRecord
  include TenantOwned

  belongs_to :lead
  belongs_to :created_by, class_name: "User", optional: true

  normalizes :description, with: ->(v) { v.squish }
  validates :description, presence: true, length: { maximum: 200 }
  validates :amount_cents, numericality: { only_integer: true, in: 0..Lead::MAX_CENTS }
  validate { errors.add(:lead, "must belong to the same business") if lead && lead.business_id != business_id }

  def readonly?
    persisted?
  end
end
