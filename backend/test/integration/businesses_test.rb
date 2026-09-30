require "test_helper"

class BusinessesTest < ActionDispatch::IntegrationTest
  test "any member can see the business" do
    %i[alice carol bob].each do |user|
      get biz_path(:acme), headers: auth_headers(user)
      assert_response :ok, "expected 200 for #{user}"
      assert_equal businesses(:acme).id, data["id"]
      assert_equal "Acme AV", data["name"]
      assert_equal "acme-av", data["slug"]
      assert_equal "America/New_York", data["time_zone"]
    end
  end

  test "a non-member gets 404, the same as a business that doesn't exist" do
    get biz_path(:acme), headers: auth_headers(:mallory)
    assert_response :not_found
    assert_equal "not_found", error_code

    get "/api/v1/businesses/00000000-0000-0000-0000-000000000000", headers: auth_headers(:mallory)
    assert_response :not_found
  end

  test "requires a login" do
    get biz_path(:acme)
    assert_response :unauthorized
  end

  test "the owner can rename the business and change its time zone" do
    patch biz_path(:acme), headers: auth_headers(:alice), as: :json,
      params: { business: { name: "  Acme   Audio Visual ", time_zone: "America/Los_Angeles" } }
    assert_response :ok
    assert_equal "Acme Audio Visual", data["name"]
    assert_equal "America/Los_Angeles", data["time_zone"]
    assert_equal "America/Los_Angeles", businesses(:acme).reload.time_zone
  end

  test "the slug can't be changed through update" do
    patch biz_path(:acme), headers: auth_headers(:alice), as: :json,
      params: { business: { name: "Acme", slug: "hijacked" } }
    assert_response :ok
    assert_equal "acme-av", businesses(:acme).reload.slug
  end

  test "admins and agents can't update the business" do
    %i[carol bob].each do |user|
      patch biz_path(:acme), headers: auth_headers(user), as: :json,
        params: { business: { name: "Renamed by #{user}" } }
      assert_response :forbidden, "expected 403 for #{user}"
      assert_equal "forbidden", error_code
    end
    assert_equal "Acme AV", businesses(:acme).reload.name
  end

  test "another business's owner can't update it" do
    patch biz_path(:acme), headers: auth_headers(:mallory), as: :json,
      params: { business: { name: "pwned" } }
    assert_response :not_found
    assert_equal "Acme AV", businesses(:acme).reload.name
  end

  test "rejects an unknown time zone" do
    patch biz_path(:acme), headers: auth_headers(:alice), as: :json,
      params: { business: { time_zone: "Mars/Olympus_Mons" } }
    assert_response :unprocessable_content
    assert json.dig("error", "details", "time_zone").present?
    assert_equal "America/New_York", businesses(:acme).reload.time_zone
  end

  test "rejects a blank name" do
    patch biz_path(:acme), headers: auth_headers(:alice), as: :json, params: { business: { name: "   " } }
    assert_response :unprocessable_content
    assert json.dig("error", "details", "name").present?
  end
end
