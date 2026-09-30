require_relative "whatsapp_test_helper"

class WhatsappCustomerInboxTest < ActionDispatch::IntegrationTest
  include WhatsappTestHelpers

  setup { give_staff_phones }

  test "a new number becomes a lead with a WhatsApp conversation, and owners and admins are told" do
    assert_difference -> { Lead.count } => 1, -> { Conversation.count } => 1, -> { Message.count } => 1 do
      send_whatsapp(from: CUSTOMER_PHONE, text: "Hi, do you install projectors?", name: "Maria Lopez")
    end

    lead = acme_lead_with_phone(CUSTOMER_PHONE)
    assert_equal "Maria Lopez", lead.name
    assert_equal "whatsapp", lead.source
    assert_equal "new", lead.status
    assert_equal businesses(:acme).id, lead.business_id

    conversation = lead.conversations.sole
    assert_equal "whatsapp", conversation.channel
    assert_equal "open", conversation.status

    message = conversation.messages.sole
    assert_equal "Hi, do you install projectors?", message.body
    assert_equal "inbound", message.direction
    assert_equal "customer", message.sender_kind

    notified = OutboundMessage.where(lead: lead).to_a
    assert_equal [ ALICE_PHONE, CAROL_PHONE ].sort, notified.map(&:to_phone).sort
    notified.each do |outbound|
      assert_includes outbound.body, "Maria Lopez"
      assert_includes outbound.body, "Hi, do you install projectors?"
      assert_equal "sent", outbound.status
      assert outbound.provider_message_id.present?
      assert_equal account.id, outbound.channel_account_id
    end
    assert_empty outbound_to(BOB_PHONE), "agents aren't told about unassigned leads"
    assert_empty outbound_to(CUSTOMER_PHONE), "the customer gets no automatic reply"
  end

  test "owners and admins without a phone aren't notified" do
    users(:carol).update_column(:phone, nil)
    send_whatsapp(from: CUSTOMER_PHONE, text: "hi")
    assert_equal [ ALICE_PHONE ], OutboundMessage.pluck(:to_phone)
  end

  test "nobody with a phone means no notifications, but the lead is still recorded" do
    User.update_all(phone: nil)
    assert_no_difference -> { OutboundMessage.count } do
      send_whatsapp(from: CUSTOMER_PHONE, text: "hi")
    end
    assert acme_lead_with_phone(CUSTOMER_PHONE)
  end

  test "only the assigned team member is told when they have a phone" do
    send_whatsapp(from: CUSTOMER_PHONE, text: "first")
    lead = acme_lead_with_phone(CUSTOMER_PHONE)
    lead.update_column(:assigned_user_id, users(:bob).id)

    before = OutboundMessage.pluck(:id)
    send_whatsapp(from: CUSTOMER_PHONE, text: "second")
    assert_equal [ BOB_PHONE ], OutboundMessage.where.not(id: before).pluck(:to_phone)
  end

  test "an assigned team member without a phone falls back to owners and admins" do
    send_whatsapp(from: CUSTOMER_PHONE, text: "first")
    acme_lead_with_phone(CUSTOMER_PHONE).update_column(:assigned_user_id, users(:bob).id)
    users(:bob).update_column(:phone, nil)

    before = OutboundMessage.pluck(:id)
    travel Whatsapp::CustomerInbox::QUIET_WINDOW + 1.minute # past the quiet window after "first"
    send_whatsapp(from: CUSTOMER_PHONE, text: "second")
    assert_equal [ ALICE_PHONE, CAROL_PHONE ].sort, OutboundMessage.where.not(id: before).pluck(:to_phone).sort
  end

  test "a returning number continues the same lead and conversation" do
    send_whatsapp(from: CUSTOMER_PHONE, text: "first", name: "Maria Lopez")
    assert_difference -> { Lead.count } => 0, -> { Conversation.count } => 0, -> { Message.count } => 1 do
      send_whatsapp(from: CUSTOMER_PHONE, text: "second", name: "Someone Else")
    end
    lead = acme_lead_with_phone(CUSTOMER_PHONE)
    assert_equal "Maria Lopez", lead.name
    assert_equal %w[first second], lead.conversations.sole.messages.map(&:body)
  end

  test "a returning customer whose conversation was closed gets a new conversation on the same lead" do
    send_whatsapp(from: CUSTOMER_PHONE, text: "first")
    lead = acme_lead_with_phone(CUSTOMER_PHONE)
    lead.conversations.sole.update_column(:status, "closed")

    assert_difference -> { Lead.count } => 0, -> { Conversation.count } => 1 do
      send_whatsapp(from: CUSTOMER_PHONE, text: "back again")
    end
    assert_equal 1, lead.conversations.status_open.count
  end

  test "a lead created in the CRM with the same number is matched, whatever the formatting" do
    lead = Tenant.with(businesses(:acme)) do
      Lead.create!(name: "Dana Cruz", phone: "(305) 555-0177", source: "phone", status: "contacted")
    end
    assert_no_difference -> { Lead.count } do
      send_whatsapp(from: CUSTOMER_PHONE, text: "It's Dana")
    end
    assert_equal "whatsapp", lead.conversations.sole.channel
  end

  test "a lead that existed before WhatsApp was added is matched by phone" do
    # Leads saved before WhatsApp existed got phone_e164 from the backfill
    # migration (db/migrate/*_backfill_lead_phone_e164.rb); the fixture mirrors that.
    michael = leads(:michael)
    assert_no_difference -> { Lead.count } do
      send_whatsapp(from: "+13055550142", text: "Following up on my estimate")
    end
    assert_equal 1, michael.conversations.where(channel: "whatsapp").count
  end

  test "archived leads aren't reused" do
    send_whatsapp(from: CUSTOMER_PHONE, text: "first", name: "Maria Lopez")
    old = acme_lead_with_phone(CUSTOMER_PHONE)
    old.update_column(:archived_at, 1.minute.ago)

    assert_difference -> { Lead.count }, 1 do
      send_whatsapp(from: CUSTOMER_PHONE, text: "hello again", name: "Maria Lopez")
    end
    fresh = Lead.active.find_by!(phone_e164: CUSTOMER_PHONE)
    assert_not_equal old.id, fresh.id
    assert_equal [ "first" ], old.conversations.sole.messages.map(&:body)
    assert_equal [ "hello again" ], fresh.conversations.sole.messages.map(&:body)
  end

  test "unsupported message types are recorded with a placeholder" do
    send_whatsapp(from: CUSTOMER_PHONE, type: "image", name: "Maria Lopez")

    message = acme_lead_with_phone(CUSTOMER_PHONE).conversations.sole.messages.sole
    assert_includes message.body, "image"
    assert_includes message.body, "can't be shown"
    assert_includes outbound_to(ALICE_PHONE).sole.body, "image"
  end

  test "an empty text is recorded with a placeholder" do
    send_whatsapp(from: CUSTOMER_PHONE, text: "   ")
    assert_equal "(empty message)", acme_lead_with_phone(CUSTOMER_PHONE).conversations.sole.messages.sole.body
  end

  test "without a WhatsApp profile name the lead is named after the number" do
    send_whatsapp(from: CUSTOMER_PHONE, text: "hi", name: nil)
    assert_equal CUSTOMER_PHONE, acme_lead_with_phone(CUSTOMER_PHONE).name
  end

  test "long messages are shortened in the team notification but kept whole in the CRM" do
    text = "a" * 1000
    send_whatsapp(from: CUSTOMER_PHONE, text: text)
    assert_equal text, acme_lead_with_phone(CUSTOMER_PHONE).conversations.sole.messages.sole.body
    body = outbound_to(ALICE_PHONE).sole.body
    assert_includes body, "#{"a" * 300}…"
    assert_not_includes body, "a" * 301
  end
end
