require "test_helper"

# Malformed input must produce a 4xx, never an unhandled exception (a 500 in
# production). Each request is wrapped so an exception fails the assertion
# instead of erroring the test.
class InputHandlingSecurityTest < ActionDispatch::IntegrationTest
  def assert_client_error(&request)
    raised = begin
      request.call
      nil
    rescue StandardError => e
      "#{e.class}: #{e.message.lines.first.to_s.strip}"
    end
    # Flunk outside the rescue so the (unmarshalable) PG error isn't attached as the cause.
    flunk "expected a 4xx response, but the request raised #{raised}" if raised
    assert_includes 400..499, response.status, "expected a 4xx, got #{response.status}"
  end

  # NULL bytes: Postgres text can't hold \u0000, and the pg driver raises
  # ArgumentError before the query is sent.

  test "NULL byte in a lead name is rejected, not a 500" do
    assert_client_error do
      post biz_path(:acme, "leads"), headers: auth_headers(:bob), as: :json,
        params: { lead: { name: "a\u0000b", email: "nul@example.com" } }
    end
  end

  test "NULL byte in the lead search query is rejected, not a 500" do
    assert_client_error do
      get biz_path(:acme, "leads"), params: { q: "a\u0000b" }, headers: auth_headers(:bob)
    end
  end

  test "NULL byte in the login email is rejected, not a 500 (unauthenticated)" do
    assert_client_error do
      post "/api/v1/session", as: :json, params: { email_address: "a\u0000b@example.com", password: "x" }
    end
  end

  test "NULL byte in signup is rejected, not a 500 (unauthenticated)" do
    assert_client_error do
      post "/api/v1/signup", as: :json, params: {
        user: { name: "Nul", email_address: "n\u0000ul@example.com", password: "a long enough password" },
        business: { name: "Nul Biz", time_zone: "UTC" }
      }
    end
  end

  test "NULL byte in an intake message is rejected, not a 500" do
    assert_client_error do
      post "/api/v1/intake/leads", headers: { "Authorization" => "Bearer #{INTAKE_TOKEN}" }, as: :json,
        params: { lead: { name: "Web", email: "web@example.com", message: "hi\u0000there" } }
    end
  end

  test "NULL byte in a message body is rejected, not a 500" do
    assert_client_error do
      post biz_path(:acme, "conversations", conversations(:sarah_chat).id, "messages"),
        headers: auth_headers(:bob), as: :json, params: { message: { body: "a\u0000b" } }
    end
  end

  # Arrays and hashes where scalars are expected.

  test "page[] array is rejected, not a 500" do
    assert_client_error do
      get biz_path(:acme, "leads"), params: { page: [ "1" ] }, headers: auth_headers(:bob)
    end
  end

  test "per_page as a hash is rejected, not a 500" do
    assert_client_error do
      get biz_path(:acme, "leads"), params: { per_page: { a: "1" } }, headers: auth_headers(:bob)
    end
  end

  test "lead status filter as a hash is rejected, not a 500" do
    assert_client_error do
      get biz_path(:acme, "leads"), params: { status: { a: "b" } }, headers: auth_headers(:bob)
    end
  end

  test "appointment status filter as a hash is rejected, not a 500" do
    assert_client_error do
      get biz_path(:acme, "appointments"), params: { status: { a: "b" } }, headers: auth_headers(:bob)
    end
  end

  # Times outside Postgres's timestamp range.

  test "appointment with an out-of-range year is rejected, not a 500" do
    assert_client_error do
      post biz_path(:acme, "appointments"), headers: auth_headers(:bob), as: :json, params: {
        appointment: { lead_id: leads(:sarah).id, kind: "call", status: "confirmed",
                       starts_at: "300000-01-01T00:00:00Z", ends_at: "300000-01-01T01:00:00Z" }
      }
    end
  end

  test "appointments ?from= with an out-of-range year is rejected, not a 500" do
    assert_client_error do
      get biz_path(:acme, "appointments"), params: { from: "300000-01-01T00:00:00Z" }, headers: auth_headers(:bob)
    end
  end

  # Things that held up.

  test "deeply nested JSON is a 400" do
    post biz_path(:acme, "leads"), headers: auth_headers(:bob).merge("CONTENT_TYPE" => "application/json"),
      params: ("[" * 10_000) + ("]" * 10_000)
    assert_response :bad_request
  end

  test "huge score is a validation error" do
    post biz_path(:acme, "leads"), headers: auth_headers(:bob), as: :json,
      params: { lead: { name: "Big", email: "big@example.com", score: 2**70 } }
    assert_response :unprocessable_content
  end

  test "unknown sort falls back to the default instead of reaching SQL" do
    get biz_path(:acme, "leads"), params: { sort: "name; DROP TABLE leads" }, headers: auth_headers(:bob)
    assert_response :ok
  end

  test "LIKE wildcards in ?q= are matched literally" do
    get biz_path(:acme, "leads"), params: { q: "_" }, headers: auth_headers(:bob)
    assert_response :ok
    assert_empty data
  end

  test "extreme page and per_page values are clamped" do
    get biz_path(:acme, "leads"), params: { page: "-5", per_page: "1000000" }, headers: auth_headers(:bob)
    assert_response :ok
    assert_equal 1, json.dig("meta", "page")
    assert_equal Paginated::MAX_PER_PAGE, json.dig("meta", "per_page")
  end
end
