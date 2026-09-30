# A reminder for one team member: "call Sarah Friday 10am", "order cables".
# When it's due, FollowUpRemindersJob sends it to them on WhatsApp once.
class FollowUp < ApplicationRecord
  include TenantOwned
  include Tracked

  belongs_to :lead, optional: true
  belongs_to :assigned_user, class_name: "User"
  belongs_to :created_by, class_name: "User", optional: true

  tracks_values_of :due_at, :assigned_user_id, :completed_at, :cancelled_at

  normalizes :body, with: ->(v) { v.squish }
  validates :body, presence: true, length: { maximum: 500 }
  validates :due_at, presence: true
  validate { validate_member(:assigned_user) }
  validate :lead_in_same_business
  validate :one_outcome

  scope :open, -> { where(completed_at: nil, cancelled_at: nil) }
  scope :awaiting_reminder, -> { open.where(reminded_at: nil).where(due_at: ..Time.current) }

  def open?
    completed_at.nil? && cancelled_at.nil?
  end

  def complete!
    update!(completed_at: Time.current) if open?
  end

  def cancel!
    update!(cancelled_at: Time.current) if open?
  end

  # Moving the due time means it should remind again.
  def reschedule!(time)
    update!(due_at: time, reminded_at: nil)
  end

  private

  def lead_in_same_business
    errors.add(:lead, "must belong to the same business") if lead && lead.business_id != business_id
  end

  def one_outcome
    errors.add(:base, "A follow-up can't be both completed and cancelled") if completed_at && cancelled_at
  end
end
