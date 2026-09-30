class User < ApplicationRecord
  # bcrypt-hashed password, with password/password_confirmation attributes and
  # `authenticate_by`, which takes the same time whether or not the email
  # exists (so response timing doesn't reveal which emails have accounts).
  has_secure_password

  has_many :sessions, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :businesses, through: :memberships

  normalizes :email_address, with: ->(email) { email.strip.downcase }
  normalizes :name, with: ->(name) { name.squish }

  validates :email_address, presence: true, uniqueness: true, length: { maximum: 254 },
    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true, length: { maximum: 120 }
  # bcrypt ignores everything past 72 bytes; has_secure_password enforces that
  # maximum, and this sets the minimum.
  validates :password, length: { minimum: 12 }, allow_nil: true
end
