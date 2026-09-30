require_relative "whatsapp_test_helper"

class WhatsappTenancyTest < ActionDispatch::IntegrationTest
  include WhatsappTestHelpers

  setup do
    give_staff_phones
    give_mallory_a_phone
  end

  def acme_counts
    acme = businesses(:acme)
    [ Lead, Conversation, Message, InboundEvent, OutboundMessage, AssistantSession, Appointment ].to_h do |model|
      [ model.name, model.where(business: acme).count ]
    end
  end

  test "a member of another business texting acme is acme's customer, not staff" do
    send_whatsapp(from: MALLORY_PHONE, text: "leads", name: "Mallory")

    lead = acme_lead_with_phone(MALLORY_PHONE)
    assert_equal "Mallory", lead.name
    assert_equal "whatsapp", lead.source
    assert_equal [ "leads" ], lead.conversations.sole.messages.map(&:body)

    assert_empty outbound_to(MALLORY_PHONE), "she gets no assistant reply"
    assert_not AssistantSession.exists?(user: users(:mallory))
    assert_equal 2, OutboundMessage.where(lead: lead).count, "acme's owner and admin are told"
  end

  test "another business's member can't use acme's commands to read acme's leads" do
    send_whatsapp(from: MALLORY_PHONE, text: "lead sarah")
    send_whatsapp(from: MALLORY_PHONE, text: "reply 1 hi")
    assert_empty outbound_to(MALLORY_PHONE)
    assert_empty OutboundMessage.where(to_phone: [ leads(:sarah).phone_e164, CUSTOMER_PHONE ].compact)
  end

  test "an event for globex's number never touches acme" do
    before = acme_counts

    send_whatsapp(from: CUSTOMER_PHONE, text: "Leaking pipe!", name: "Pat", account_label: :globex_whatsapp)

    assert_equal before, acme_counts
    lead = Lead.find_by!(phone_e164: CUSTOMER_PHONE)
    assert_equal businesses(:globex).id, lead.business_id
    assert_equal businesses(:globex).id, InboundEvent.sole.business_id

    notified = OutboundMessage.sole
    assert_equal MALLORY_PHONE, notified.to_phone
    assert_equal businesses(:globex).id, notified.business_id
    assert_equal channel_accounts(:globex_whatsapp).id, notified.channel_account_id
    assert_equal "sent", notified.status
  end

  test "mallory is staff on her own business's number" do
    send_whatsapp(from: MALLORY_PHONE, text: "leads", account_label: :globex_whatsapp)
    reply = outbound_to(MALLORY_PHONE).sole
    assert_includes reply.body, "Secret Globex Customer"
    assert_not_includes reply.body, "Sarah"
    assert_equal businesses(:globex).id, reply.business_id
  end

  test "acme's owner texting globex's number is globex's customer" do
    send_whatsapp(from: ALICE_PHONE, text: "leads", name: "Alice", account_label: :globex_whatsapp)

    assert_empty outbound_to(ALICE_PHONE)
    lead = Lead.find_by!(business: businesses(:globex), phone_e164: ALICE_PHONE)
    assert_equal "Alice", lead.name
    assert_not Lead.exists?(business: businesses(:acme), phone_e164: ALICE_PHONE)
  end

  test "the same customer texting two businesses gets a separate lead in each" do
    send_whatsapp(from: CUSTOMER_PHONE, text: "hi acme")
    send_whatsapp(from: CUSTOMER_PHONE, text: "hi globex", account_label: :globex_whatsapp)

    leads = Lead.where(phone_e164: CUSTOMER_PHONE).to_a
    assert_equal [ businesses(:acme).id, businesses(:globex).id ].sort, leads.map(&:business_id).sort
  end

  test "a status update for acme's message sent to globex's number doesn't change it" do
    send_whatsapp(from: CUSTOMER_PHONE, text: "hi")
    outbound = outbound_to(ALICE_PHONE).sole

    status = { "id" => outbound.provider_message_id, "status" => "read", "timestamp" => Time.current.to_i.to_s }
    perform_enqueued_jobs { post_webhook(payload_for(statuses: [ status ], account_label: :globex_whatsapp)) }
    assert_response :ok
    assert_equal "sent", outbound.reload.status
  end

  test "a swipe-reply can't reach another business's notification" do
    send_whatsapp(from: CUSTOMER_PHONE, text: "hi acme")
    acme_notification = outbound_to(ALICE_PHONE).sole
    # Mallory swipe-replies on globex's number, naming acme's notification.
    send_whatsapp(from: MALLORY_PHONE, text: "gotcha", replying_to: acme_notification.provider_message_id, account_label: :globex_whatsapp)

    assert_empty outbound_to(CUSTOMER_PHONE)
    assert_includes outbound_to(MALLORY_PHONE).sole.body, "Sorry, I didn't catch that"
  end
end
