require "test_helper"

class ActivitiesTest < ActionDispatch::IntegrationTest
  def activities_path(lead = :sarah, business = :acme)
    biz_path(business, "leads", leads(lead).id, "activities")
  end

  test "records conversation and appointment changes and lists them with the lead's history, newest first" do
    patch biz_path(:acme, "conversations", conversations(:sarah_chat).id), headers: auth_headers(:carol), as: :json,
      params: { conversation: { status: "closed", assigned_user_id: users(:bob).id } }
    assert_response :ok
    patch biz_path(:acme, "appointments", appointments(:sarah_consult).id), headers: auth_headers(:bob), as: :json,
      params: { appointment: { status: "cancelled", notes: "Client asked to cancel" } }
    assert_response :ok
    post biz_path(:acme, "conversations"), headers: auth_headers(:bob), as: :json,
      params: { conversation: { lead_id: leads(:sarah).id, channel: "email" } }
    assert_response :created
    new_conversation_id = data["id"]
    patch biz_path(:acme, "leads", leads(:sarah).id), headers: auth_headers(:alice), as: :json,
      params: { lead: { status: "appointment" } }
    assert_response :ok

    get activities_path, headers: auth_headers(:bob)
    assert_response :ok
    assert_equal 4, json.dig("meta", "total")
    assert_equal(
      [ [ "Lead", leads(:sarah).id, "updated" ],
        [ "Conversation", new_conversation_id, "created" ],
        [ "Appointment", appointments(:sarah_consult).id, "updated" ],
        [ "Conversation", conversations(:sarah_chat).id, "updated" ] ],
      data.map { |a| [ a["subject_type"], a["subject_id"], a["action"] ] }
    )

    conversation_change = data.last
    assert_equal users(:carol).id, conversation_change["actor_user_id"]
    assert_equal({ "status" => [ "open", "closed" ], "assigned_user_id" => [ nil, users(:bob).id ] },
      conversation_change.dig("details", "changes"))

    appointment_change = data[2]
    assert_equal users(:bob).id, appointment_change["actor_user_id"]
    assert_equal({ "status" => [ "confirmed", "cancelled" ] }, appointment_change.dig("details", "changes"))
    assert_equal %w[notes status], appointment_change.dig("details", "changed_fields")
  end

  test "sending a message doesn't add an activity for the conversation's timestamp bump" do
    assert_no_difference -> { Activity.count } do
      post biz_path(:acme, "conversations", conversations(:sarah_chat).id, "messages"), headers: auth_headers(:bob), as: :json,
        params: { message: { body: "Hello" } }
    end
  end

  test "other leads' activity isn't included" do
    patch biz_path(:acme, "leads", leads(:michael).id), headers: auth_headers(:bob), as: :json, params: { lead: { status: "contacted" } }
    get activities_path(:sarah), headers: auth_headers(:bob)
    assert_empty data
  end

  test "another business's lead is 404" do
    get activities_path(:globex_lead, :acme), headers: auth_headers(:bob)
    assert_response :not_found
    get activities_path(:sarah, :acme), headers: auth_headers(:mallory)
    assert_response :not_found
  end
end
