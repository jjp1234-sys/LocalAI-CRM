# A business's WhatsApp number. Incoming webhooks name the number
# (phone_number_id), which is how a message is matched to its business.
#
# provider "whatsapp_cloud" talks to Meta; "simulator" is the local fake used
# for development and tests.
class ChannelAccount < ApplicationRecord
  include TenantOwned

  PROVIDERS = %w[whatsapp_cloud simulator].freeze

  # Encrypted before it's written to the database (see
  # config/initializers/active_record_encryption.rb).
  encrypts :access_token

  has_many :outbound_messages, dependent: :restrict_with_error
  has_many :inbound_events, dependent: :restrict_with_error

  validates :provider, inclusion: { in: PROVIDERS }
  validates :phone_number_id, presence: true, uniqueness: true
  validates :display_phone, presence: true
  validates :access_token, presence: true, if: -> { provider == "whatsapp_cloud" }

  scope :active, -> { where(active: true) }

  def transport
    Whatsapp::Transport.for(self)
  end
end
