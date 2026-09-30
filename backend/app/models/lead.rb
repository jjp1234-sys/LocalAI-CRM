class Lead < ApplicationRecord
  include TenantOwned
  include Tracked

  # "purchased": a lead the business bought from us.
  SOURCES = %w[website facebook instagram google whatsapp referral phone walk_in manual purchased other].freeze
  MAX_CENTS = 100_000_000_000
  STATUSES = %w[new contacted qualified appointment won lost].freeze

  belongs_to :assigned_user, class_name: "User", optional: true
  has_many :conversations, dependent: :restrict_with_error
  has_many :appointments, dependent: :restrict_with_error
  has_many :notes, -> { order(:created_at, :id) }, dependent: :restrict_with_error
  has_many :follow_ups, dependent: :restrict_with_error

  # `prefix` because a status named "new" would otherwise create a
  # `Lead.new` scope that clashes with the constructor.
  enum :status, STATUSES.index_by(&:itself), prefix: true, validate: true
  enum :source, SOURCES.index_by(&:itself), prefix: true, validate: true

  tracks_values_of :status, :source, :score, :assigned_user_id, :archived_at, :value_cents, :acquisition_cost_cents

  normalizes :name, with: ->(v) { v.squish }
  normalizes :email, with: ->(v) { v.strip.downcase.presence }
  normalizes :phone, with: ->(v) { v.strip.presence }
  normalizes :need, with: ->(v) { v.strip.presence }
  normalizes :external_id, with: ->(v) { v.strip.presence }

  validates :name, presence: true, length: { maximum: 120 }
  validates :email, length: { maximum: 254 }, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :phone, format: { with: /\A\+?[0-9 ().-]{7,25}\z/, message: "doesn't look like a phone number" }, allow_nil: true
  validates :need, length: { maximum: 2000 }
  validates :external_id, length: { maximum: 200 }
  validates :score, numericality: { only_integer: true, in: 0..100 }, allow_nil: true
  validates :value_cents, :acquisition_cost_cents, numericality: { only_integer: true, in: 0..MAX_CENTS }, allow_nil: true
  validate :has_contact_method
  validate { validate_member(:assigned_user) }

  before_create { self.last_activity_at ||= Time.current }
  # won_at records when the deal closed, for revenue reports. Moving a lead
  # off "won" clears it.
  before_save { self.won_at = (status_won? ? (won_at || Time.current) : nil) if will_save_change_to_status? || new_record? }
  # The phone in E.164 form, so a WhatsApp sender can be matched to their lead.
  before_save { self.phone_e164 = PhoneNumber.normalize(phone) }
  # A deal that's won or lost closes its conversations. If the customer writes
  # again later, that starts a fresh conversation, which is how the team gets
  # asked whether to reopen the lead or start a new one.
  after_update :close_conversations, if: -> { saved_change_to_status? && status.in?(%w[won lost]) }

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  # Search across name, email, phone and need. `sanitize_sql_like` escapes
  # % and _ in the user's text so they're matched literally.
  scope :matching, ->(query) {
    pattern = "%#{sanitize_sql_like(query.to_s.strip)}%"
    where("name ILIKE :p OR email ILIKE :p OR phone ILIKE :p OR need ILIKE :p", p: pattern)
  }

  def archived?
    archived_at.present?
  end

  private

  def close_conversations
    conversations.status_open.find_each { |c| c.update!(status: "closed") }
  end

  def has_contact_method
    errors.add(:base, "An email address or phone number is required") if email.blank? && phone.blank?
  end
end
