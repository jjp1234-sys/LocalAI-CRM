require "test_helper"

# The API side of notes, follow-ups, deal value and the revenue summary.
class NotesAndFollowUpsTest < ActionDispatch::IntegrationTest
  test "notes: add and list on a lead; another business gets 404" do
    post biz_path(:acme, "leads", leads(:sarah).id, "notes"), headers: auth_headers(:bob), as: :json,
      params: { note: { body: "  prefers mornings  " } }
    assert_response :created
    assert_equal "prefers mornings", data["body"]
    assert_equal users(:bob).id, data["author_user_id"]

    get biz_path(:acme, "leads", leads(:sarah).id, "notes"), headers: auth_headers(:bob)
    assert_equal [ "prefers mornings" ], data.map { |n| n["body"] }

    get biz_path(:globex, "leads", leads(:sarah).id, "notes"), headers: auth_headers(:mallory)
    assert_response :not_found
    post biz_path(:acme, "leads", leads(:sarah).id, "notes"), headers: auth_headers(:mallory), as: :json,
      params: { note: { body: "x" } }
    assert_response :not_found
  end

  test "notes can't be empty or too long" do
    post biz_path(:acme, "leads", leads(:sarah).id, "notes"), headers: auth_headers(:bob), as: :json, params: { note: { body: " " } }
    assert_response :unprocessable_content
    post biz_path(:acme, "leads", leads(:sarah).id, "notes"), headers: auth_headers(:bob), as: :json, params: { note: { body: "x" * 5001 } }
    assert_response :unprocessable_content
  end

  test "follow-ups: create for yourself by default, list open ones, complete and reschedule" do
    post biz_path(:acme, "follow_ups"), headers: auth_headers(:bob), as: :json,
      params: { follow_up: { body: "call back", due_at: 1.day.from_now.iso8601, lead_id: leads(:michael).id } }
    assert_response :created
    id = data["id"]
    assert_equal users(:bob).id, data["assigned_user_id"]

    get biz_path(:acme, "follow_ups"), params: { mine: "true" }, headers: auth_headers(:bob)
    assert_equal [ id ], data.map { |f| f["id"] }
    get biz_path(:acme, "follow_ups"), params: { mine: "true" }, headers: auth_headers(:alice)
    assert_empty data

    later = 3.days.from_now.change(usec: 0)
    patch biz_path(:acme, "follow_ups", id), headers: auth_headers(:bob), as: :json, params: { follow_up: { due_at: later.iso8601 } }
    assert_equal later, Time.iso8601(data["due_at"])
    assert_nil data["reminded_at"]

    patch biz_path(:acme, "follow_ups", id), headers: auth_headers(:bob), as: :json, params: { follow_up: { outcome: "completed" } }
    assert data["completed_at"]
    get biz_path(:acme, "follow_ups"), headers: auth_headers(:bob)
    assert_empty data

    patch biz_path(:acme, "follow_ups", id), headers: auth_headers(:bob), as: :json, params: { follow_up: { outcome: "exploded" } }
    assert_response :bad_request
  end

  test "follow-ups can't be assigned outside the business or point at another business's lead" do
    post biz_path(:acme, "follow_ups"), headers: auth_headers(:bob), as: :json,
      params: { follow_up: { body: "x", due_at: 1.day.from_now.iso8601, assigned_user_id: users(:mallory).id } }
    assert_response :unprocessable_content

    post biz_path(:acme, "follow_ups"), headers: auth_headers(:bob), as: :json,
      params: { follow_up: { body: "x", due_at: 1.day.from_now.iso8601, lead_id: leads(:globex_lead).id } }
    assert_response :not_found
  end

  test "lead value and cost are settable; won_at is set by the app, not the client" do
    patch biz_path(:acme, "leads", leads(:michael).id), headers: auth_headers(:bob), as: :json,
      params: { lead: { value_cents: 450_000, acquisition_cost_cents: 2_500, status: "won", won_at: "2001-01-01T00:00:00Z" } }
    assert_response :ok
    assert_equal 450_000, data["value_cents"]
    assert_equal 2_500, data["acquisition_cost_cents"]
    assert_in_delta Time.current, Time.iso8601(data["won_at"]), 5

    patch biz_path(:acme, "leads", leads(:michael).id), headers: auth_headers(:bob), as: :json, params: { lead: { value_cents: -1 } }
    assert_response :unprocessable_content
  end

  test "the summary reports pipeline value, revenue this month and results by source" do
    patch biz_path(:acme, "leads", leads(:sarah).id), headers: auth_headers(:alice), as: :json,
      params: { lead: { value_cents: 1_000_000, acquisition_cost_cents: 5_000, source: "purchased", status: "won" } }
    patch biz_path(:acme, "leads", leads(:michael).id), headers: auth_headers(:alice), as: :json,
      params: { lead: { value_cents: 300_000 } }

    get biz_path(:acme, "summary"), headers: auth_headers(:bob)
    assert_equal 1_000_000, data["won_this_month_cents"]
    assert_equal 300_000, data["pipeline_value_cents"]
    assert_equal({ "leads" => 1, "won" => 1, "revenue_cents" => 1_000_000, "cost_cents" => 5_000 }, data.dig("by_source", "purchased"))
    assert_nil data.dig("by_source", "globex"), "only this business's leads"
  end

  test "website intake can't label a lead as purchased" do
    post "/api/v1/intake/leads", headers: { "Authorization" => "Bearer #{INTAKE_TOKEN}" }, as: :json,
      params: { lead: { name: "Web", email: "w@example.com", source: "purchased" } }
    assert_response :unprocessable_content
  end

  test "the app can't edit or delete notes, even with raw SQL" do
    note = Tenant.with(businesses(:acme)) { leads(:sarah).notes.create!(body: "original") }
    Tenant.with(businesses(:acme)) do
      conn = ActiveRecord::Base.connection
      conn.transaction(requires_new: true) do
        assert_raises(ActiveRecord::StatementInvalid) { conn.execute("UPDATE notes SET body = 'edited'") }
        raise ActiveRecord::Rollback
      end
    end
    assert_equal "original", Note.find(note.id).body
  end
end
