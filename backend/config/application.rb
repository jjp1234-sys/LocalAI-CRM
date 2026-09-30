require_relative "boot"

require "rails"
# Only the parts of Rails this API uses. Fewer frameworks loaded means less
# code that can have a security problem.
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

module Backend
  class Application < Rails::Application
    config.load_defaults 8.1

    config.autoload_lib(ignore: %w[assets tasks])

    # JSON API only: no views, cookies or sessions. Clients authenticate with
    # a bearer token, which also means there is no CSRF surface.
    config.api_only = true

    # Row-level security policies and Postgres functions can't be expressed in
    # schema.rb, so the schema is kept as raw SQL (db/structure.sql).
    config.active_record.schema_format = :sql

    # New tables get random UUID primary keys, so record IDs can't be guessed
    # by counting.
    config.generators do |g|
      g.orm :active_record, primary_key_type: :uuid
    end

    # Where rate-limit counters live. An in-process store is fine for a single
    # server; running several app servers needs a shared store (Redis or
    # Solid Cache), or each one counts separately.
    config.x.rate_limit_store = ActiveSupport::Cache::MemoryStore.new

    # Where customers open quote and contract links. Production must set it.
    config.x.public_base_url = ENV.fetch("APP_PUBLIC_URL") { Rails.env.production? ? raise("Set APP_PUBLIC_URL, e.g. https://app.example.com") : "http://localhost:3000" }
  end
end
