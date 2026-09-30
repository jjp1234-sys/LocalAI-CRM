require "test_helper"

class IntakeLeadsTest < ActionDispatch::IntegrationTest
  def intake_headers(token = INTAKE_TOKEN)
    { "Authorization" => "Bearer #{token}" }
  end

  def post_lead(lead, headers: intake_headers, **extra)
    post "/api/v1/intake/leads", headers: headers, as: :json, params: { lead: lead }.merge(extra)
  end

  test "creates a new lead in the key's business" do
    assert_difference -> { Lead.count }, 1 do
      post_lead({ name: "Pat Visitor", email: "pat@example.com", phone: "305-555-0199", need: "Speakers" })
    end
    assert_response :created
    assert_equal false, json.dig("data", "duplicate")

    lead = Lead.find(data["id"])
    assert_equal businesses(:acme), lead.business
    assert_equal "new", lead.status
    assert_equal "website", lead.source
    assert_equal "Speakers", lead.need
    assert_empty lead.conversations
  end

  test "the response contains only the lead's id and whether it was a duplicate" do
    post_lead({ name: "Pat Visitor", email: "pat@example.com" })
    assert_equal %w[data], json.keys
    assert_equal %w[duplicate id], data.keys.sort
  end

  test "clients can't choose the status" do
    post_lead({ name: "Pat Visitor", email: "pat@example.com", status: "won", score: 100 })
    assert_response :created
    lead = Lead.find(data["id"])
    assert_equal "new", lead.status
    assert_nil lead.score
  end

  test "with a message, creates a conversation on the matching channel and an inbound customer message" do
    { "facebook" => "facebook", "instagram" => "instagram", "website" => "web_chat", "google" => "other" }.each do |source, channel|
      assert_difference -> { Conversation.count } => 1, -> { Message.count } => 1 do
        post_lead({ name: "From #{source}", email: "#{source}@example.com", source: source, message: "  Hi there  " })
      end
      assert_response :created

      conversation = Lead.find(data["id"]).conversations.sole
      assert_equal channel, conversation.channel, "source #{source}"
      assert_equal "open", conversation.status
      assert_equal businesses(:acme), conversation.business

      message = conversation.messages.sole
      assert_equal "Hi there", message.body
      assert_equal "inbound", message.direction
      assert_equal "customer", message.sender_kind
      assert_nil message.sender_user_id
      assert_equal message.created_at.to_i, conversation.last_message_at.to_i
    end
  end

  test "the same source and external_id twice returns the first lead, creating nothing" do
    post_lead({ name: "Meta Lead", email: "meta@example.com", source: "facebook", external_id: "fb-777" })
    assert_response :created
    first_id = data["id"]

    assert_no_difference [ -> { Lead.count }, -> { Conversation.count }, -> { Message.count }, -> { Activity.count } ] do
      post_lead({ name: "Meta Lead again", email: "meta@example.com", source: "facebook", external_id: " fb-777 ", message: "Retry" })
    end
    assert_response :ok
    assert_equal({ "id" => first_id, "duplicate" => true }, data)
    assert_equal "Meta Lead", Lead.find(first_id).name
  end

  test "matches an existing lead's external_id" do
    post_lead({ name: "Michael again", phone: "305-555-0142", source: "website", external_id: "form-123" })
    assert_response :ok
    assert_equal({ "id" => leads(:michael).id, "duplicate" => true }, data)
  end

  test "the same external_id from a different source is a different lead" do
    post_lead({ name: "Other", email: "other@example.com", source: "instagram", external_id: "form-123" })
    assert_response :created
    assert_not_equal leads(:michael).id, data["id"]
  end

  test "without an external_id, every post is a new lead" do
    2.times { post_lead({ name: "No ID", email: "noid@example.com" }) }
    assert_response :created
    assert_equal 2, Lead.where(name: "No ID").count
  end

  test "a missing, malformed, revoked or login token is refused" do
    [ {}, intake_headers("nonsense"), intake_headers(REVOKED_INTAKE_TOKEN), auth_headers(:alice),
      { "Authorization" => "Basic #{INTAKE_TOKEN}" } ].each do |headers|
      assert_no_difference -> { Lead.count } do
        post_lead({ name: "X", email: "x@example.com" }, headers: headers)
      end
      assert_response :unauthorized, "expected 401 for #{headers.inspect}"
      assert_equal "unauthorized", error_code
    end
  end

  test "manual and unknown sources are rejected" do
    %w[manual carrier_pigeon].each do |source|
      assert_no_difference -> { Lead.count } do
        post_lead({ name: "X", email: "x@example.com", source: source })
      end
      assert_response :unprocessable_content, "source #{source}"
      assert json.dig("error", "details", "source").present?
    end
  end

  test "invalid leads get field errors and create nothing" do
    assert_no_difference [ -> { Lead.count }, -> { Conversation.count }, -> { Message.count } ] do
      post_lead({ name: "", message: "hello" })
    end
    assert_response :unprocessable_content
    assert json.dig("error", "details", "name").present?
    assert json.dig("error", "details", "base").present?
  end

  test "the lead lands in the key's business whatever business_id is sent" do
    globex = businesses(:globex).id
    post_lead({ name: "Sneaky", email: "sneaky@example.com", business_id: globex }, business_id: globex)
    assert_response :created
    assert_equal businesses(:acme).id, Lead.find(data["id"]).business_id
  end

  test "records when the key was last used" do
    assert_nil intake_keys(:acme_website).last_used_at
    post_lead({ name: "Pat", email: "pat@example.com" })
    assert intake_keys(:acme_website).reload.last_used_at.present?
  end

  test "logs the new lead with no actor" do
    post_lead({ name: "Pat", email: "pat@example.com" })
    activity = Activity.find_by!(subject_type: "Lead", subject_id: data["id"], action: "created")
    assert_nil activity.actor_user_id
    assert_equal businesses(:acme).id, activity.business_id
  end
end
