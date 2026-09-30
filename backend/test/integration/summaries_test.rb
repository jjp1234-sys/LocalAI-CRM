require "test_helper"

class SummariesTest < ActionDispatch::IntegrationTest
  test "counts the business's own active data" do
    get biz_path(:acme, "summary"), headers: auth_headers(:bob)
    assert_response :ok
    assert_equal(
      { "new" => 1, "contacted" => 0, "qualified" => 1, "appointment" => 0, "won" => 0, "lost" => 0 },
      data["leads_by_status"],
      "archived_lead (lost) and globex_lead (new) must not be counted"
    )
    assert_equal 2, data["new_leads_last_7_days"]
    assert_equal 1, data["open_conversations"]
    assert_equal 1, data["upcoming_appointments"]
  end

  test "another business sees only its own numbers" do
    get biz_path(:globex, "summary"), headers: auth_headers(:mallory)
    assert_response :ok
    assert_equal 1, data["leads_by_status"]["new"]
    assert_equal 0, data["leads_by_status"]["qualified"]
    assert_equal 1, data["new_leads_last_7_days"]
    assert_equal 1, data["open_conversations"]
    assert_equal 1, data["upcoming_appointments"]
  end

  test "reflects changes: closed conversations, cancelled and past appointments, old leads" do
    patch biz_path(:acme, "conversations", conversations(:sarah_chat).id), headers: auth_headers(:bob), as: :json,
      params: { conversation: { status: "closed" } }
    patch biz_path(:acme, "appointments", appointments(:sarah_consult).id), headers: auth_headers(:bob), as: :json,
      params: { appointment: { status: "cancelled" } }
    post biz_path(:acme, "appointments"), headers: auth_headers(:bob), as: :json, params: {
      appointment: { lead_id: leads(:michael).id, starts_at: 1.day.ago.iso8601, ends_at: (1.day.ago + 1.hour).iso8601 }
    }
    assert_response :created
    leads(:michael).update_columns(created_at: 8.days.ago)

    get biz_path(:acme, "summary"), headers: auth_headers(:bob)
    assert_equal 0, data["open_conversations"]
    assert_equal 0, data["upcoming_appointments"]
    assert_equal 1, data["new_leads_last_7_days"]
    assert_equal 1, data["leads_by_status"]["new"], "older leads still count by status"
  end

  test "a non-member gets 404" do
    get biz_path(:acme, "summary"), headers: auth_headers(:mallory)
    assert_response :not_found
  end
end
