ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# The restricted role's permissions aren't part of structure.sql (see
# db/app_role.sql), so apply them to each test database before tests run.
APP_ROLE_SQL = Rails.root.join("db/app_role.sql").read

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    parallelize_setup { |_worker| ActiveRecord::Base.connection.execute(APP_ROLE_SQL) }

    fixtures :all

    # The plain-text tokens behind the digests in the fixtures.
    SESSION_TOKENS = {
      "alice" => "fds_alice_test_token",
      "bob" => "fds_bob_test_token",
      "carol" => "fds_carol_test_token",
      "mallory" => "fds_mallory_test_token"
    }.freeze
    INTAKE_TOKEN = "fdi_acme_test_token"
    REVOKED_INTAKE_TOKEN = "fdi_acme_revoked_token"
    PASSWORD = "correct horse battery staple"

    setup do
      Rails.application.config.x.rate_limit_store.clear
    end
  end
end

ActiveRecord::Base.connection.execute(APP_ROLE_SQL)

module IntegrationHelpers
  def auth_headers(user_fixture_name)
    { "Authorization" => "Bearer #{ActiveSupport::TestCase::SESSION_TOKENS.fetch(user_fixture_name.to_s)}" }
  end

  def json
    JSON.parse(response.body)
  end

  def data
    json.fetch("data")
  end

  def error_code
    json.dig("error", "code")
  end

  # Builds a path under one business: biz_path(:acme, "leads") -> "/api/v1/businesses/<id>/leads"
  def biz_path(business_fixture_name, *segments)
    ([ "/api/v1/businesses", businesses(business_fixture_name).id ] + segments).join("/")
  end
end

class ActionDispatch::IntegrationTest
  include IntegrationHelpers
end
