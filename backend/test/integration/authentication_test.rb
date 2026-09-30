require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  test "signup creates a user, a business they own, and a working token" do
    post "/api/v1/signup", params: {
      user: { name: "Dana", email_address: "Dana@Example.com ", password: "a long enough password" },
      business: { name: "Dana's Detailing", time_zone: "America/New_York" }
    }, as: :json

    assert_response :created
    assert_match(/\Afds_/, data["token"])
    assert_equal "dana@example.com", data.dig("user", "email_address")
    assert_equal "dana-s-detailing", data.dig("business", "slug")

    get "/api/v1/me", headers: { "Authorization" => "Bearer #{data["token"]}" }
    assert_response :ok
    assert_equal "owner", data["memberships"].first["role"]
  end

  test "signup rolls everything back if any part is invalid" do
    assert_no_difference -> { User.count } do
      post "/api/v1/signup", params: {
        user: { name: "Dana", email_address: "dana@example.com", password: "a long enough password" },
        business: { name: "" }
      }, as: :json
    end
    assert_response :unprocessable_content
  end

  test "signup rejects short passwords" do
    post "/api/v1/signup", params: {
      user: { name: "Dana", email_address: "dana@example.com", password: "short" },
      business: { name: "Dana Co" }
    }, as: :json
    assert_response :unprocessable_content
    assert json.dig("error", "details", "password").present?
  end

  test "login returns a token; only its digest is stored" do
    post "/api/v1/session", params: { email_address: "alice@example.com", password: PASSWORD }, as: :json
    assert_response :created
    token = data["token"]
    assert_nil Session.find_by(token_digest: token)
    assert Session.find_by(token_digest: Session.digest(token))
  end

  test "wrong password and unknown email give the same answer" do
    post "/api/v1/session", params: { email_address: "alice@example.com", password: "wrong password!!" }, as: :json
    wrong_password = [ response.status, json ]
    post "/api/v1/session", params: { email_address: "nobody@example.com", password: "wrong password!!" }, as: :json
    assert_equal wrong_password, [ response.status, json ]
    assert_equal 401, response.status
  end

  test "login is rate limited per email address" do
    10.times do
      post "/api/v1/session", params: { email_address: "alice@example.com", password: "wrong password!!" }, as: :json
    end
    post "/api/v1/session", params: { email_address: "alice@example.com", password: PASSWORD }, as: :json
    assert_response :too_many_requests
  end

  test "requests without a valid token are refused" do
    get "/api/v1/me"
    assert_response :unauthorized
    assert_equal 'Bearer realm="api"', response.headers["WWW-Authenticate"]

    [ "Bearer ", "Bearer nonsense", "Basic abc", "Bearer fds_expired_token", "Bearer #{INTAKE_TOKEN}" ].each do |header|
      get "/api/v1/me", headers: { "Authorization" => header }
      assert_response :unauthorized, "expected 401 for #{header.inspect}"
    end
  end

  test "logout stops the token working" do
    delete "/api/v1/session", headers: auth_headers(:bob)
    assert_response :no_content
    get "/api/v1/me", headers: auth_headers(:bob)
    assert_response :unauthorized
  end

  test "me lists only the user's own businesses" do
    get "/api/v1/me", headers: auth_headers(:mallory)
    assert_equal [ "Globex Plumbing" ], data["memberships"].map { |m| m.dig("business", "name") }
  end
end
