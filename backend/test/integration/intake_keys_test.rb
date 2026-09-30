require "test_helper"

class IntakeKeysTest < ActionDispatch::IntegrationTest
  def intake(token)
    post "/api/v1/intake/leads", headers: { "Authorization" => "Bearer #{token}" }, as: :json,
      params: { lead: { name: "Form Visitor", email: "visitor@example.com" } }
  end

  test "admins and owners list keys; the token and its digest are never returned" do
    %i[carol alice].each do |user|
      get biz_path(:acme, "intake_keys"), headers: auth_headers(user)
      assert_response :ok, "expected 200 for #{user}"
      assert_equal [ intake_keys(:acme_website).id, intake_keys(:acme_revoked).id ].sort, data.map { |k| k["id"] }.sort
      data.each do |key|
        assert_equal %w[created_at id last_used_at name revoked_at token_prefix], key.keys.sort
      end
    end
    assert_not_includes response.body, intake_keys(:acme_website).token_digest
  end

  test "agents can't see or manage keys" do
    get biz_path(:acme, "intake_keys"), headers: auth_headers(:bob)
    assert_response :forbidden
    post biz_path(:acme, "intake_keys"), headers: auth_headers(:bob), as: :json, params: { intake_key: { name: "Mine" } }
    assert_response :forbidden
    delete biz_path(:acme, "intake_keys", intake_keys(:acme_website).id), headers: auth_headers(:bob)
    assert_response :forbidden
    assert_nil intake_keys(:acme_website).reload.revoked_at
  end

  test "create returns the full token once; after that only its prefix" do
    post biz_path(:acme, "intake_keys"), headers: auth_headers(:carol), as: :json, params: { intake_key: { name: " Landing  page " } }
    assert_response :created
    token = data["token"]
    assert_match(/\Afdi_\S{30,}\z/, token)
    assert_equal "Landing page", data["name"]
    assert_equal token.first(10), data["token_prefix"]
    assert_nil data["revoked_at"]

    key = IntakeKey.find(data["id"])
    assert_equal businesses(:acme), key.business
    assert_equal users(:carol), key.created_by
    assert_equal IntakeKey.digest(token), key.token_digest
    assert_not_equal token, key.token_digest

    get biz_path(:acme, "intake_keys"), headers: auth_headers(:carol)
    assert_not_includes response.body, token
    assert_not_includes response.body, key.token_digest
    assert(data.none? { |k| k.key?("token") || k.key?("token_digest") })

    intake(token)
    assert_response :created
  end

  test "a blank name is rejected" do
    post biz_path(:acme, "intake_keys"), headers: auth_headers(:carol), as: :json, params: { intake_key: { name: "  " } }
    assert_response :unprocessable_content
    assert json.dig("error", "details", "name").present?
  end

  test "revoking a key stops it working at once; it stays listed as revoked" do
    intake(INTAKE_TOKEN)
    assert_response :created

    delete biz_path(:acme, "intake_keys", intake_keys(:acme_website).id), headers: auth_headers(:carol)
    assert_response :no_content

    intake(INTAKE_TOKEN)
    assert_response :unauthorized

    get biz_path(:acme, "intake_keys"), headers: auth_headers(:carol)
    listed = data.find { |k| k["id"] == intake_keys(:acme_website).id }
    assert listed["revoked_at"].present?
  end

  test "revoking twice is harmless and keeps the first revocation time" do
    revoked_at = intake_keys(:acme_revoked).revoked_at
    delete biz_path(:acme, "intake_keys", intake_keys(:acme_revoked).id), headers: auth_headers(:carol)
    assert_response :no_content
    assert_equal revoked_at.to_i, intake_keys(:acme_revoked).reload.revoked_at.to_i
  end

  test "another business's keys are 404" do
    get biz_path(:acme, "intake_keys"), headers: auth_headers(:mallory)
    assert_response :not_found

    delete biz_path(:globex, "intake_keys", intake_keys(:acme_website).id), headers: auth_headers(:mallory)
    assert_response :not_found
    assert_nil intake_keys(:acme_website).reload.revoked_at
  end
end
