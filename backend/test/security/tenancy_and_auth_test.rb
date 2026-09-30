require "test_helper"

class TenancyAndAuthSecurityTest < ActionDispatch::IntegrationTest
  def globex_id(label)
    ActiveRecord::FixtureSet.identify(label, :uuid)
  end

  # --- Logging -------------------------------------------------------------

  def filtered(params)
    ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(params)
  end

  test "intake customer message is filtered from logs" do
    assert_equal "[FILTERED]", filtered({ "lead" => { "message" => "my home address is ..." } }).dig("lead", "message")
  end

  test "customer names are filtered from logs" do
    assert_equal "[FILTERED]", filtered({ "lead" => { "name" => "Sarah Johnson" } }).dig("lead", "name")
  end

  test "lead search text is filtered from logs" do
    assert_equal "[FILTERED]", filtered({ "q" => "sarah@example.com" })["q"]
  end

  test "secrets and contact fields are filtered from logs" do
    f = filtered({ "password" => "x", "email_address" => "x", "token" => "x", "phone" => "x", "body" => "x" })
    assert f.values.all?("[FILTERED]")
  end

  # --- Account enumeration -------------------------------------------------

  test "signup doesn't reveal that an email already has an account" do
    post "/api/v1/signup", as: :json, params: {
      user: { name: "Probe", email_address: "alice@example.com", password: "a long enough password" },
      business: { name: "Probe Biz", time_zone: "UTC" }
    }
    assert_nil json.dig("error", "details", "email_address"),
      "signup says the email is taken, confirming alice@example.com has an account"
  end

  # --- Cross-tenant IDOR (held up) -----------------------------------------

  test "another business's lead, conversation and appointment are 404" do
    [
      [ "leads", globex_id(:globex_lead) ],
      [ "conversations", globex_id(:globex_chat) ],
      [ "appointments", globex_id(:globex_visit) ]
    ].each do |resource, id|
      get biz_path(:acme, resource, id), headers: auth_headers(:alice)
      assert_response :not_found, resource
    end
  end

  test "another business's lead can't be updated, archived or read through activities" do
    id = globex_id(:globex_lead)
    patch biz_path(:acme, "leads", id), headers: auth_headers(:alice), as: :json, params: { lead: { status: "lost" } }
    assert_response :not_found
    post biz_path(:acme, "leads", id, "archive"), headers: auth_headers(:alice)
    assert_response :not_found
    get biz_path(:acme, "leads", id, "activities"), headers: auth_headers(:alice)
    assert_response :not_found
  end

  test "another business's conversation messages can't be read or written" do
    path = biz_path(:acme, "conversations", globex_id(:globex_chat), "messages")
    get path, headers: auth_headers(:alice)
    assert_response :not_found
    post path, headers: auth_headers(:alice), as: :json, params: { message: { body: "hi" } }
    assert_response :not_found
  end

  test "conversation and appointment can't point at another business's lead" do
    post biz_path(:acme, "conversations"), headers: auth_headers(:alice), as: :json,
      params: { conversation: { lead_id: globex_id(:globex_lead), channel: "sms" } }
    assert_response :not_found

    post biz_path(:acme, "appointments"), headers: auth_headers(:alice), as: :json, params: {
      appointment: { lead_id: globex_id(:globex_lead), kind: "call", status: "confirmed",
                     starts_at: 1.day.from_now.iso8601, ends_at: (1.day.from_now + 1.hour).iso8601 }
    }
    assert_response :not_found
  end

  test "records can't be assigned to a user from another business" do
    patch biz_path(:acme, "leads", leads(:sarah).id), headers: auth_headers(:alice), as: :json,
      params: { lead: { assigned_user_id: users(:mallory).id } }
    assert_response :unprocessable_content
  end

  test "list filters can't reach another business's rows" do
    get biz_path(:acme, "conversations"), params: { lead_id: globex_id(:globex_lead) }, headers: auth_headers(:alice)
    assert_empty data
    get biz_path(:acme, "appointments"), params: { lead_id: globex_id(:globex_lead) }, headers: auth_headers(:alice)
    assert_empty data
  end

  test "another business's intake key can't be revoked" do
    other = Tenant.with(businesses(:globex)) { IntakeKey.create!(name: "Globex form") }
    delete biz_path(:acme, "intake_keys", other.id), headers: auth_headers(:alice)
    assert_response :not_found
    assert_nil IntakeKey.find(other.id).revoked_at
  end

  test "non-member gets the same 404 for a real and a made-up business" do
    get biz_path(:acme), headers: auth_headers(:mallory)
    real = [ response.status, response.body ]
    get "/api/v1/businesses/#{SecureRandom.uuid}", headers: auth_headers(:mallory)
    assert_equal real, [ response.status, response.body ]
  end

  test "agent can't list or create intake keys" do
    get biz_path(:acme, "intake_keys"), headers: auth_headers(:bob)
    assert_response :forbidden
    post biz_path(:acme, "intake_keys"), headers: auth_headers(:bob), as: :json, params: { intake_key: { name: "x" } }
    assert_response :forbidden
  end

  test "admin can't change business settings" do
    patch biz_path(:acme), headers: auth_headers(:carol), as: :json, params: { business: { name: "Pwned" } }
    assert_response :forbidden
  end

  test "business slug and id can't be mass-assigned" do
    patch biz_path(:acme), headers: auth_headers(:alice), as: :json,
      params: { business: { name: "Acme 2", slug: "stolen", id: SecureRandom.uuid } }
    assert_response :ok
    assert_equal "acme-av", businesses(:acme).reload.slug
  end

  # --- Tenant.with cleanup (held up) ---------------------------------------

  test "the restricted role and tenant setting don't outlive a request" do
    get biz_path(:acme, "leads"), headers: auth_headers(:alice)
    assert_response :ok
    conn = ActiveRecord::Base.connection
    assert_not_equal Tenant::ROLE, conn.select_value("SELECT current_user")
    assert_nil conn.select_value("SELECT current_business_id()")
  end

  test "the restricted role doesn't outlive an early `next` from the tenant block" do
    Tenant.with(businesses(:acme)) { next :early }
    assert_not_equal Tenant::ROLE, ActiveRecord::Base.connection.select_value("SELECT current_user")
  end

  test "the restricted role can't read sessions or rewrite messages" do
    Tenant.with(businesses(:acme)) do
      assert_raises(ActiveRecord::StatementInvalid) do
        ActiveRecord::Base.connection.transaction(requires_new: true) { Session.count }
      end
    end
    Tenant.with(businesses(:acme)) do
      assert_raises(ActiveRecord::StatementInvalid) do
        ActiveRecord::Base.connection.transaction(requires_new: true) { Message.update_all(body: "x") }
      end
    end
  end

  # --- Tokens (held up) ----------------------------------------------------

  test "intake key doesn't work as a login token and vice versa" do
    get "/api/v1/me", headers: { "Authorization" => "Bearer #{INTAKE_TOKEN}" }
    assert_response :unauthorized

    post "/api/v1/intake/leads", headers: auth_headers(:alice), as: :json,
      params: { lead: { name: "X", email: "x@example.com" } }
    assert_response :unauthorized
  end

  test "revoked intake key and expired session are refused" do
    post "/api/v1/intake/leads", headers: { "Authorization" => "Bearer #{REVOKED_INTAKE_TOKEN}" }, as: :json,
      params: { lead: { name: "X", email: "x@example.com" } }
    assert_response :unauthorized

    get "/api/v1/me", headers: { "Authorization" => "Bearer fds_expired_token" }
    assert_response :unauthorized
  end

  test "token digest from the database doesn't work as a token" do
    digest = sessions(:alice).token_digest
    get "/api/v1/me", headers: { "Authorization" => "Bearer #{digest}" }
    assert_response :unauthorized
    get "/api/v1/me", headers: { "Authorization" => "Bearer fds_#{digest}" }
    assert_response :unauthorized
  end

  test "logout only ends the session used for the request" do
    delete "/api/v1/session", headers: auth_headers(:alice)
    assert_response :no_content
    get "/api/v1/me", headers: auth_headers(:alice)
    assert_response :unauthorized
    get "/api/v1/me", headers: auth_headers(:bob)
    assert_response :ok
  end

  test "login rate limit per email ignores case and whitespace variants" do
    10.times do |i|
      post "/api/v1/session", params: { email_address: "alice@example.com", password: "wrong" },
        env: { "REMOTE_ADDR" => "203.0.113.#{i + 1}" }
    end
    post "/api/v1/session", params: { email_address: "  ALICE@Example.com ", password: "wrong" },
      env: { "REMOTE_ADDR" => "203.0.113.99" }
    assert_response :too_many_requests
  end

  test "client-supplied X-Forwarded-For (no proxy in front) doesn't reset the login IP limit" do
    11.times do |i|
      post "/api/v1/session", params: { email_address: "user#{i}@example.com", password: "wrong" },
        headers: { "X-Forwarded-For" => "198.51.100.#{i}" }, env: { "REMOTE_ADDR" => "203.0.113.5" }
    end
    assert_response :too_many_requests
  end

  test "intake response never includes lead data" do
    post "/api/v1/intake/leads", headers: { "Authorization" => "Bearer #{INTAKE_TOKEN}" }, as: :json,
      params: { lead: { name: "Dup", phone: "305-555-0199", source: "website", external_id: "form-123" } }
    assert_response :ok
    assert_equal %w[duplicate id], data.keys.sort
  end

  test "intake can't set assigned user, status or business" do
    post "/api/v1/intake/leads", headers: { "Authorization" => "Bearer #{INTAKE_TOKEN}" }, as: :json, params: {
      lead: { name: "Web", email: "web2@example.com", status: "won", assigned_user_id: users(:alice).id,
              business_id: businesses(:globex).id, source: "manual" }
    }
    assert_response :unprocessable_content
  end
end
