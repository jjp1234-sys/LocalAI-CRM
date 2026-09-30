require "test_helper"

class LeadsTest < ActionDispatch::IntegrationTest
  test "lists active leads in the business, newest first, paginated" do
    get biz_path(:acme, "leads"), headers: auth_headers(:bob)
    assert_response :ok
    names = data.map { |l| l["name"] }
    assert_includes names, "Sarah Johnson"
    assert_not_includes names, "Old Lead"
    assert_not_includes names, "Secret Globex Customer"
    assert_equal({ "page" => 1, "per_page" => 25, "total" => 2 }, json["meta"])
  end

  test "filters and searches" do
    get biz_path(:acme, "leads"), params: { status: "qualified" }, headers: auth_headers(:bob)
    assert_equal [ "Sarah Johnson" ], data.map { |l| l["name"] }

    get biz_path(:acme, "leads"), params: { q: "estimate" }, headers: auth_headers(:bob)
    assert_equal [ "Michael Reed" ], data.map { |l| l["name"] }

    get biz_path(:acme, "leads"), params: { q: "%" }, headers: auth_headers(:bob)
    assert_empty data, "% should be matched literally, not as a wildcard"

    get biz_path(:acme, "leads"), params: { archived: "true" }, headers: auth_headers(:bob)
    assert_equal [ "Old Lead" ], data.map { |l| l["name"] }
  end

  test "creates a lead and logs who did it" do
    post biz_path(:acme, "leads"), headers: auth_headers(:bob), as: :json,
      params: { lead: { name: "New Person", phone: "305-555-0100", need: "Projector", source: "phone" } }
    assert_response :created
    lead = Lead.find(data["id"])
    assert_equal businesses(:acme), lead.business

    activity = Activity.find_by!(subject: lead, action: "created")
    assert_equal users(:bob), activity.actor_user
    assert_not_includes activity.details["changes"].keys, "phone", "contact details stay out of the log"
  end

  test "rejects invalid leads with field errors" do
    post biz_path(:acme, "leads"), headers: auth_headers(:bob), as: :json,
      params: { lead: { name: "No Contact", status: "bogus" } }
    assert_response :unprocessable_content
    assert json.dig("error", "details", "status").present?
    assert json.dig("error", "details", "base").present?
  end

  test "ignores business_id sent by the client" do
    post biz_path(:acme, "leads"), headers: auth_headers(:bob), as: :json,
      params: { lead: { name: "Sneaky", email: "s@example.com", business_id: businesses(:globex).id } }
    assert_response :created
    assert_equal businesses(:acme).id, Lead.find(data["id"]).business_id
  end

  test "updates status and archives" do
    patch biz_path(:acme, "leads", leads(:michael).id), headers: auth_headers(:bob), as: :json,
      params: { lead: { status: "contacted" } }
    assert_response :ok
    assert_equal "contacted", data["status"]

    post biz_path(:acme, "leads", leads(:michael).id, "archive"), headers: auth_headers(:bob)
    assert_response :ok
    assert data["archived_at"].present?

    get biz_path(:acme, "leads", leads(:michael).id, "activities"), headers: auth_headers(:bob)
    assert_equal [ "updated", "updated" ], data.map { |a| a["action"] }
  end

  test "can't assign a lead to someone outside the business" do
    patch biz_path(:acme, "leads", leads(:michael).id), headers: auth_headers(:bob), as: :json,
      params: { lead: { assigned_user_id: users(:mallory).id } }
    assert_response :unprocessable_content
  end

  test "another business's owner gets 404 for everything here" do
    get biz_path(:acme, "leads"), headers: auth_headers(:mallory)
    assert_response :not_found
    get biz_path(:acme, "leads", leads(:sarah).id), headers: auth_headers(:mallory)
    assert_response :not_found
  end

  test "a lead ID from another business is 404 even through your own business" do
    get biz_path(:globex, "leads", leads(:sarah).id), headers: auth_headers(:mallory)
    assert_response :not_found
    patch biz_path(:globex, "leads", leads(:sarah).id), headers: auth_headers(:mallory), as: :json,
      params: { lead: { name: "pwned" } }
    assert_response :not_found
    assert_equal "Sarah Johnson", leads(:sarah).reload.name
  end

  test "a malformed ID is a 404, not a crash" do
    get biz_path(:acme, "leads", "not-a-uuid"), headers: auth_headers(:bob)
    assert_response :not_found
    get "/api/v1/businesses/not-a-uuid/leads", headers: auth_headers(:bob)
    assert_response :not_found
  end

  test "per_page is capped" do
    get biz_path(:acme, "leads"), params: { per_page: 100_000 }, headers: auth_headers(:bob)
    assert_equal 100, json.dig("meta", "per_page")
  end
end
