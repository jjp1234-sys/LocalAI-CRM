class Appointment < ApplicationRecord
  include TenantOwned
  include Tracked

  MAX_LENGTH = 12.hours
  # Postgres can't store years past 294276, and nobody books appointments in
  # the year 300000; out-of-range years get a validation error, not a crash.
  YEARS = 1900..9999

  belongs_to :lead
  belongs_to :assigned_user, class_name: "User", optional: true

  enum :kind, %w[consultation site_visit call other].index_by(&:itself), validate: true
  enum :status, %w[tentative confirmed cancelled completed no_show].index_by(&:itself), prefix: true, validate: true

  tracks_values_of :status, :kind, :starts_at, :ends_at, :assigned_user_id

  normalizes :location, with: ->(v) { v.strip.presence }
  normalizes :notes, with: ->(v) { v.strip.presence }

  validates :starts_at, :ends_at, presence: true
  validates :location, length: { maximum: 300 }
  validates :notes, length: { maximum: 5000 }
  validate :ends_after_start
  validate :lead_in_same_business
  validate { validate_member(:assigned_user) }

  scope :upcoming, -> { where("starts_at >= ?", Time.current).where.not(status: %w[cancelled]) }

  private

  def ends_after_start
    %i[starts_at ends_at].each do |attribute|
      time = public_send(attribute)
      errors.add(attribute, "must be between the years #{YEARS.min} and #{YEARS.max}") if time && !YEARS.cover?(time.year)
    end
    return unless starts_at && ends_at

    errors.add(:ends_at, "must be after the start time") if ends_at <= starts_at
    errors.add(:ends_at, "must be within #{MAX_LENGTH.inspect} of the start") if ends_at - starts_at > MAX_LENGTH
  end

  def lead_in_same_business
    errors.add(:lead, "must belong to the same business") if lead && lead.business_id != business_id
  end
end
