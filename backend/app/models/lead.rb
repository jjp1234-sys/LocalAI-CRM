class Lead < ApplicationRecord
  include TenantOwned
  include Tracked

  SOURCES = %w[website facebook instagram google referral phone walk_in manual other].freeze
  STATUSES = %w[new contacted qualified appointment won lost].freeze

  belongs_to :assigned_user, class_name: "User", optional: true
  has_many :conversations, dependent: :restrict_with_error
  has_many :appointments, dependent: :restrict_with_error

  # `prefix` because a status named "new" would otherwise create a
  # `Lead.new` scope that clashes with the constructor.
  enum :status, STATUSES.index_by(&:itself), prefix: true, validate: true
  enum :source, SOURCES.index_by(&:itself), prefix: true, validate: true

  tracks_values_of :status, :source, :score, :assigned_user_id, :archived_at

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
  validate :has_contact_method
  validate { validate_member(:assigned_user) }

  before_create { self.last_activity_at ||= Time.current }

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

  def has_contact_method
    errors.add(:base, "An email address or phone number is required") if email.blank? && phone.blank?
  end
end
