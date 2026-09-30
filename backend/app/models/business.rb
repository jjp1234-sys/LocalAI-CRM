class Business < ApplicationRecord
  has_many :memberships, dependent: :restrict_with_error
  has_many :users, through: :memberships
  has_many :intake_keys, dependent: :restrict_with_error
  has_many :leads, dependent: :restrict_with_error
  has_many :conversations, dependent: :restrict_with_error
  has_many :appointments, dependent: :restrict_with_error
  has_many :activities, dependent: :restrict_with_error

  normalizes :name, with: ->(name) { name.squish }
  normalizes :slug, with: ->(slug) { slug.strip.downcase }

  validates :name, presence: true, length: { maximum: 120 }
  validates :slug, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9][a-z0-9-]{1,61}[a-z0-9]\z/, message: "must be 3-63 lowercase letters, digits or hyphens" }
  validates :time_zone, inclusion: { in: ActiveSupport::TimeZone.all.map { |z| z.tzinfo.name }.uniq }

  # Turns a business name into a unique URL-safe slug: "Bob's AV" -> "bob-s-av".
  def self.unique_slug_for(name)
    base = name.to_s.parameterize.first(50).presence || "business"
    base = base.ljust(3, "x")
    slug = base
    slug = "#{base}-#{SecureRandom.alphanumeric(6).downcase}" while exists?(slug: slug)
    slug
  end
end
