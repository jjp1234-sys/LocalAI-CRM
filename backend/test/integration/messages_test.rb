require "test_helper"

class MessagesTest < ActionDispatch::IntegrationTest
  def messages_path(business = :acme, conversation = :sarah_chat)
    biz_path(business, "conversations", conversations(conversation).id, "messages")
  end

  test "lists a conversation's messages, oldest first" do
    post messages_path, headers: auth_headers(:bob), as: :json, params: { message: { body: "Happy to help!" } }
    assert_response :created

    get messages_path, headers: auth_headers(:bob)
    assert_response :ok
    assert_equal [ "We need displays and mics for a 30 person room.", "Happy to help!" ], data.map { |m| m["body"] }
    assert_equal 2, json.dig("meta", "total")
    assert_equal %w[body conversation_id created_at direction id sender_kind sender_user_id], data.first.keys.sort
  end

  test "records an outbound staff message from the current user" do
    assert_difference -> { Message.count }, 1 do
      post messages_path, headers: auth_headers(:carol), as: :json, params: { message: { body: "  We can do that.  " } }
    end
    assert_response :created
    assert_equal "We can do that.", data["body"]
    assert_equal "outbound", data["direction"]
    assert_equal "staff", data["sender_kind"]
    assert_equal users(:carol).id, data["sender_user_id"]
    assert_equal conversations(:sarah_chat).id, data["conversation_id"]

    message = Message.find(data["id"])
    assert_equal businesses(:acme), message.business
  end

  test "bumps the conversation's last_message_at and the lead's last_activity_at" do
    conversation_before = conversations(:sarah_chat).last_message_at
    lead_before = leads(:sarah).last_activity_at

    post messages_path, headers: auth_headers(:bob), as: :json, params: { message: { body: "Following up" } }
    assert_response :created
    created_at = Time.iso8601(data["created_at"])

    conversation = conversations(:sarah_chat).reload
    lead = leads(:sarah).reload
    assert_operator conversation.last_message_at, :>, conversation_before
    assert_operator lead.last_activity_at, :>, lead_before
    assert_in_delta created_at, conversation.last_message_at, 0.001
    assert_in_delta created_at, lead.last_activity_at, 0.001
  end

  test "clients can't choose the direction, sender kind or sender" do
    post messages_path, headers: auth_headers(:bob), as: :json, params: {
      message: {
        body: "Pretending to be the customer",
        direction: "inbound",
        sender_kind: "customer",
        sender_user_id: users(:alice).id,
        business_id: businesses(:globex).id
      }
    }
    assert_response :created
    assert_equal "outbound", data["direction"]
    assert_equal "staff", data["sender_kind"]
    assert_equal users(:bob).id, data["sender_user_id"]
    assert_equal businesses(:acme).id, Message.find(data["id"]).business_id
  end

  test "rejects an empty body" do
    assert_no_difference -> { Message.count } do
      post messages_path, headers: auth_headers(:bob), as: :json, params: { message: { body: "   " } }
    end
    assert_response :unprocessable_content
    assert json.dig("error", "details", "body").present?
  end

  test "rejects a body over 10,000 characters" do
    post messages_path, headers: auth_headers(:bob), as: :json, params: { message: { body: "a" * 10_000 } }
    assert_response :created

    assert_no_difference -> { Message.count } do
      post messages_path, headers: auth_headers(:bob), as: :json, params: { message: { body: "a" * 10_001 } }
    end
    assert_response :unprocessable_content
    assert json.dig("error", "details", "body").present?
  end

  test "a failed message doesn't bump timestamps" do
    before = conversations(:sarah_chat).last_message_at
    post messages_path, headers: auth_headers(:bob), as: :json, params: { message: { body: "" } }
    assert_response :unprocessable_content
    assert_equal before.to_i, conversations(:sarah_chat).reload.last_message_at.to_i
  end

  test "another business's conversation is 404, for reading and writing" do
    get messages_path(:acme, :globex_chat), headers: auth_headers(:bob)
    assert_response :not_found

    assert_no_difference -> { Message.count } do
      post messages_path(:acme, :globex_chat), headers: auth_headers(:bob), as: :json, params: { message: { body: "hi" } }
    end
    assert_response :not_found

    get messages_path(:acme, :sarah_chat), headers: auth_headers(:mallory)
    assert_response :not_found

    post messages_path(:globex, :sarah_chat), headers: auth_headers(:mallory), as: :json, params: { message: { body: "hi" } }
    assert_response :not_found
    assert_equal 1, conversations(:sarah_chat).messages.count
  end
end
