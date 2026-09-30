# One message in a conversation. Messages are never edited or deleted; the
# database role the app runs as isn't allowed to (see db/app_role.sql).
class Message < ApplicationRecord
  include TenantOwned

  belongs_to :conversation
  belongs_to :sender_user, class_name: "User", optional: true

  enum :direction, %w[inbound outbound].index_by(&:itself), validate: true
  enum :sender_kind, %w[customer staff system].index_by(&:itself), prefix: :sent_by, validate: true

  normalizes :body, with: ->(v) { v.strip }
  validates :body, presence: true, length: { maximum: 10_000 }
  validate :customer_messages_are_inbound
  validate :conversation_in_same_business
  validate { validate_member(:sender_user) }

  after_create :bump_timestamps

  def readonly?
    persisted?
  end

  private

  def customer_messages_are_inbound
    if sent_by_customer? != inbound?
      errors.add(:direction, "must be inbound for customer messages and outbound otherwise")
    end
  end

  def conversation_in_same_business
    if conversation && conversation.business_id != business_id
      errors.add(:conversation, "must belong to the same business")
    end
  end

  def bump_timestamps
    conversation.update_columns(last_message_at: created_at, updated_at: Time.current)
    Lead.where(id: conversation.lead_id).update_all(last_activity_at: created_at)
  end
end
