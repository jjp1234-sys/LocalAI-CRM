require "test_helper"

class ConversationsTest < ActionDispatch::IntegrationTest
  test "lists the business's conversations only" do
    get biz_path(:acme, "conversations"), headers: auth_headers(:bob)
    assert_response :ok
    assert_equal [ conversations(:sarah_chat).id ], data.map { |c| c["id"] }
    assert_equal 1, json.dig("meta", "total")
  end

  test "filters by status and lead_id" do
    closed = conversations(:sarah_chat)
    post biz_path(:acme, "conversations"), headers: auth_headers(:bob), as: :json,
      params: { conversation: { lead_id: leads(:michael).id, channel: "sms" } }
    assert_response :created
    other = data["id"]
    patch biz_path(:acme, "conversations", closed.id), headers: auth_headers(:bob), as: :json,
      params: { conversation: { status: "closed" } }
    assert_response :ok

    get biz_path(:acme, "conversations"), params: { status: "open" }, headers: auth_headers(:bob)
    assert_equal [ other ], data.map { |c| c["id"] }

    get biz_path(:acme, "conversations"), params: { status: "closed" }, headers: auth_headers(:bob)
    assert_equal [ closed.id ], data.map { |c| c["id"] }

    get biz_path(:acme, "conversations"), params: { lead_id: leads(:michael).id }, headers: auth_headers(:bob)
    assert_equal [ other ], data.map { |c| c["id"] }

    get biz_path(:acme, "conversations"), params: { lead_id: leads(:globex_lead).id }, headers: auth_headers(:bob)
    assert_response :ok
    assert_empty data
  end

  test "filters by assigned_user_id" do
    patch biz_path(:acme, "conversations", conversations(:sarah_chat).id), headers: auth_headers(:bob), as: :json,
      params: { conversation: { assigned_user_id: users(:carol).id } }
    assert_response :ok

    get biz_path(:acme, "conversations"), params: { assigned_user_id: users(:carol).id }, headers: auth_headers(:bob)
    assert_equal [ conversations(:sarah_chat).id ], data.map { |c| c["id"] }
    get biz_path(:acme, "conversations"), params: { assigned_user_id: users(:bob).id }, headers: auth_headers(:bob)
    assert_empty data
  end

  test "shows a conversation" do
    get biz_path(:acme, "conversations", conversations(:sarah_chat).id), headers: auth_headers(:bob)
    assert_response :ok
    assert_equal leads(:sarah).id, data["lead_id"]
    assert_equal "facebook", data["channel"]
    assert_equal "open", data["status"]
    assert_equal %w[assigned_user_id channel created_at id last_message_at lead_id status updated_at], data.keys.sort
  end

  test "creates a conversation for a lead in the business" do
    assert_difference -> { Conversation.count }, 1 do
      post biz_path(:acme, "conversations"), headers: auth_headers(:bob), as: :json,
        params: { conversation: { lead_id: leads(:michael).id, channel: "phone", assigned_user_id: users(:bob).id } }
    end
    assert_response :created
    conversation = Conversation.find(data["id"])
    assert_equal businesses(:acme), conversation.business
    assert_equal leads(:michael), conversation.lead
    assert_equal "open", conversation.status
    assert_equal users(:bob), conversation.assigned_user
    assert_nil data["last_message_at"]
  end

  test "can't create a conversation for another business's lead" do
    assert_no_difference -> { Conversation.count } do
      post biz_path(:acme, "conversations"), headers: auth_headers(:bob), as: :json,
        params: { conversation: { lead_id: leads(:globex_lead).id, channel: "sms" } }
    end
    assert_response :not_found
  end

  test "rejects an invalid channel" do
    post biz_path(:acme, "conversations"), headers: auth_headers(:bob), as: :json,
      params: { conversation: { lead_id: leads(:michael).id, channel: "carrier_pigeon" } }
    assert_response :unprocessable_content
    assert json.dig("error", "details", "channel").present?
  end

  test "rejects an assignee who isn't a member, on create and update" do
    post biz_path(:acme, "conversations"), headers: auth_headers(:bob), as: :json,
      params: { conversation: { lead_id: leads(:michael).id, channel: "sms", assigned_user_id: users(:mallory).id } }
    assert_response :unprocessable_content
    assert json.dig("error", "details", "assigned_user").present?

    patch biz_path(:acme, "conversations", conversations(:sarah_chat).id), headers: auth_headers(:bob), as: :json,
      params: { conversation: { assigned_user_id: users(:mallory).id } }
    assert_response :unprocessable_content
    assert_nil conversations(:sarah_chat).reload.assigned_user_id
  end

  test "closes, reopens, assigns and unassigns" do
    path = biz_path(:acme, "conversations", conversations(:sarah_chat).id)

    patch path, headers: auth_headers(:bob), as: :json, params: { conversation: { status: "closed" } }
    assert_response :ok
    assert_equal "closed", data["status"]

    patch path, headers: auth_headers(:bob), as: :json, params: { conversation: { status: "open" } }
    assert_equal "open", data["status"]

    patch path, headers: auth_headers(:bob), as: :json, params: { conversation: { assigned_user_id: users(:carol).id } }
    assert_response :ok
    assert_equal users(:carol).id, data["assigned_user_id"]

    patch path, headers: auth_headers(:bob), as: :json, params: { conversation: { assigned_user_id: nil } }
    assert_response :ok
    assert_nil data["assigned_user_id"]
  end

  test "rejects an invalid status" do
    patch biz_path(:acme, "conversations", conversations(:sarah_chat).id), headers: auth_headers(:bob), as: :json,
      params: { conversation: { status: "snoozed" } }
    assert_response :unprocessable_content
    assert_equal "open", conversations(:sarah_chat).reload.status
  end

  test "only status and assignee can be changed" do
    patch biz_path(:acme, "conversations", conversations(:sarah_chat).id), headers: auth_headers(:bob), as: :json,
      params: { conversation: { channel: "sms", lead_id: leads(:michael).id, status: "closed" } }
    assert_response :ok
    conversation = conversations(:sarah_chat).reload
    assert_equal "facebook", conversation.channel
    assert_equal leads(:sarah).id, conversation.lead_id
  end

  test "another business's conversations are 404" do
    get biz_path(:acme, "conversations"), headers: auth_headers(:mallory)
    assert_response :not_found
    get biz_path(:acme, "conversations", conversations(:sarah_chat).id), headers: auth_headers(:mallory)
    assert_response :not_found

    get biz_path(:acme, "conversations", conversations(:globex_chat).id), headers: auth_headers(:bob)
    assert_response :not_found
    patch biz_path(:acme, "conversations", conversations(:globex_chat).id), headers: auth_headers(:alice), as: :json,
      params: { conversation: { status: "closed" } }
    assert_response :not_found
    assert_equal "open", conversations(:globex_chat).reload.status

    patch biz_path(:globex, "conversations", conversations(:sarah_chat).id), headers: auth_headers(:mallory), as: :json,
      params: { conversation: { status: "closed" } }
    assert_response :not_found
    assert_equal "open", conversations(:sarah_chat).reload.status
  end
end
