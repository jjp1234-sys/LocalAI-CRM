class Conversation < ApplicationRecord
  include TenantOwned
  include Tracked

  CHANNELS = %w[sms web_chat email phone facebook instagram other].freeze

  belongs_to :lead
  belongs_to :assigned_user, class_name: "User", optional: true
  has_many :messages, -> { order(:created_at, :id) }, dependent: :restrict_with_error

  enum :channel, CHANNELS.index_by(&:itself), validate: true
  enum :status, %w[open closed].index_by(&:itself), prefix: true, validate: true

  tracks_values_of :status, :channel, :assigned_user_id

  validate { validate_member(:assigned_user) }
  validate :lead_in_same_business

  private

  def lead_in_same_business
    errors.add(:lead, "must belong to the same business") if lead && lead.business_id != business_id
  end
end
