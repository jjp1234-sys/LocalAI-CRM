require_relative "whatsapp_test_helper"

class WhatsappWebhookTest < ActionDispatch::IntegrationTest
  include WhatsappTestHelpers

  VERIFY_TOKEN = Rails.application.config.x.whatsapp.verify_token

  setup { give_staff_phones }

  # --- GET handshake --------------------------------------------------------

  test "the verify handshake echoes the challenge for the right token" do
    get "/webhooks/whatsapp", params: { "hub.mode" => "subscribe", "hub.verify_token" => VERIFY_TOKEN, "hub.challenge" => "1158201444" }
    assert_response :ok
    assert_equal "1158201444", response.body
  end

  test "the verify handshake refuses a wrong or missing token" do
    get "/webhooks/whatsapp", params: { "hub.mode" => "subscribe", "hub.verify_token" => "guess", "hub.challenge" => "1" }
    assert_response :forbidden
    assert_not_equal "1", response.body

    get "/webhooks/whatsapp", params: { "hub.mode" => "subscribe", "hub.challenge" => "1" }
    assert_response :forbidden

    get "/webhooks/whatsapp", params: { "hub.mode" => "unsubscribe", "hub.verify_token" => VERIFY_TOKEN, "hub.challenge" => "1" }
    assert_response :forbidden
  end

  # --- POST: rejected requests ---------------------------------------------

  test "a bad or missing signature is refused and nothing is stored" do
    payload = payload_for(messages: [ message_event(from: CUSTOMER_PHONE, text: "hi") ])
    body = JSON.generate(payload)

    [
      false, # no header
      "sha256=#{"0" * 64}",
      "garbage",
      Whatsapp::Signature.sign(body, "some-other-secret"),
      Whatsapp::Signature.sign("#{body} ")
    ].each do |signature|
      assert_no_difference -> { InboundEvent.count } do
        assert_no_enqueued_jobs do
          post_webhook(body, signature: signature)
        end
      end
      assert_response :unauthorized, "signature #{signature.inspect}"
    end
  end

  test "an oversized body is refused" do
    body = JSON.generate(payload_for(messages: [ message_event(from: CUSTOMER_PHONE, text: "x" * 1.megabyte) ]))
    assert_no_difference -> { InboundEvent.count } do
      post_webhook(body)
    end
    assert_response :content_too_large
  end

  test "invalid JSON is a bad request" do
    assert_no_difference -> { InboundEvent.count } do
      post_webhook("{not json")
    end
    assert_response :bad_request
  end

  test "JSON that isn't an object is accepted and ignored" do
    assert_no_difference -> { InboundEvent.count } do
      post_webhook("[1, 2, 3]")
    end
    assert_response :ok
  end

  test "an unknown phone number ID is acknowledged and ignored" do
    payload = payload_for(messages: [ message_event(from: CUSTOMER_PHONE, text: "hi") ], phone_number_id: "999999")
    assert_no_difference -> { InboundEvent.count } do
      assert_no_enqueued_jobs { post_webhook(payload) }
    end
    assert_response :ok
  end

  test "a switched-off number is ignored" do
    account.update_column(:active, false)
    assert_no_difference -> { InboundEvent.count } do
      post_webhook(payload_for(messages: [ message_event(from: CUSTOMER_PHONE, text: "hi") ]))
    end
    assert_response :ok
  end

  test "messages missing an id or sender are skipped" do
    event = message_event(from: CUSTOMER_PHONE, text: "hi")
    assert_no_difference -> { InboundEvent.count } do
      post_webhook(payload_for(messages: [ event.merge("id" => ""), event.merge("from" => nil) ]))
    end
    assert_response :ok
  end

  # --- POST: accepted -------------------------------------------------------

  test "a valid message is stored for the number's business and processed" do
    event = message_event(from: CUSTOMER_PHONE, text: "hi")
    assert_enqueued_jobs 1, only: ProcessInboundEventJob do
      post_webhook(payload_for(messages: [ event ], name: "Maria Lopez"))
    end
    assert_response :ok

    stored = InboundEvent.find_by!(provider_event_id: event["id"])
    assert_equal businesses(:acme).id, stored.business_id
    assert_equal account.id, stored.channel_account_id
    assert_equal "message", stored.kind
    assert_equal CUSTOMER_PHONE, stored.from_phone
    assert_equal "Maria Lopez", stored.profile_name
    assert_nil stored.processed_at

    perform_enqueued_jobs
    assert stored.reload.processed?
    assert_nil stored.error
  end

  test "the same message delivered twice is stored and processed once" do
    event = message_event(from: CUSTOMER_PHONE, text: "Do you install projectors?")
    payload = payload_for(messages: [ event ], name: "Maria Lopez")

    assert_difference -> { InboundEvent.count } => 1, -> { Lead.count } => 1, -> { Message.count } => 1 do
      2.times do
        perform_enqueued_jobs { post_webhook(payload) }
        assert_response :ok
      end
    end
  end

  test "the processing job is idempotent" do
    event = message_event(from: CUSTOMER_PHONE, text: "hello")
    post_webhook(payload_for(messages: [ event ]))
    id = InboundEvent.find_by!(provider_event_id: event["id"]).id

    assert_difference -> { Message.count }, 1 do
      perform_enqueued_jobs
      ProcessInboundEventJob.perform_now(id)
    end
  end

  # --- Status updates -------------------------------------------------------

  def notification
    send_whatsapp(from: CUSTOMER_PHONE, text: "hi", name: "Maria Lopez")
    outbound = outbound_to(ALICE_PHONE).sole
    assert outbound.status_sent?
    outbound
  end

  test "status updates move an outbound message forward" do
    outbound = notification

    send_status(outbound.provider_message_id, "delivered")
    assert_equal "delivered", outbound.reload.status

    send_status(outbound.provider_message_id, "read")
    assert_equal "read", outbound.reload.status
  end

  test "status updates never move backwards" do
    outbound = notification

    send_status(outbound.provider_message_id, "read")
    send_status(outbound.provider_message_id, "delivered")
    send_status(outbound.provider_message_id, "sent")
    assert_equal "read", outbound.reload.status
  end

  test "a failed status records the error" do
    outbound = notification

    send_status(outbound.provider_message_id, "failed", errors: [ { "code" => 131_047, "title" => "Re-engagement message" } ])
    outbound.reload
    assert_equal "failed", outbound.status
    assert_equal "Re-engagement message", outbound.last_error
  end

  test "a status for a message we don't know is ignored" do
    outbound = notification
    send_status("wamid.unknown", "read")
    assert_equal "sent", outbound.reload.status
    assert InboundEvent.where(kind: "status").all?(&:processed?)
  end

  test "status updates don't create leads or messages" do
    outbound = notification
    assert_no_difference -> { Lead.count + Message.count + OutboundMessage.count } do
      send_status(outbound.provider_message_id, "delivered")
    end
  end
end
