require_relative "whatsapp_test_helper"

class DeliverOutboundMessageJobTest < ActiveJob::TestCase
  include WhatsappTestHelpers

  class FakeTransport
    attr_reader :calls

    def initialize(&behaviour)
      @behaviour = behaviour
      @calls = 0
    end

    def deliver(outbound)
      @calls += 1
      @behaviour.call(outbound)
    end
  end

  def queue_outbound(**attributes)
    Tenant.with(businesses(:acme)) do
      OutboundMessage.queue!(account: account, to: CUSTOMER_PHONE, body: "Hello", **attributes)
    end
  ensure
    Current.reset
  end

  test "queueing a message enqueues its delivery" do
    outbound = nil
    assert_enqueued_jobs 1, only: DeliverOutboundMessageJob do
      outbound = queue_outbound
    end
    assert_enqueued_with job: DeliverOutboundMessageJob, args: [ outbound.id ]
    assert_equal "pending", outbound.status
  end

  test "the simulator marks the message sent with a provider ID" do
    outbound = queue_outbound
    DeliverOutboundMessageJob.perform_now(outbound.id)

    outbound.reload
    assert_equal "sent", outbound.status
    assert_match(/\Asim\.\h{24}\z/, outbound.provider_message_id)
    assert_equal 1, outbound.attempts
    assert outbound.sent_at.present?
    assert_nil outbound.last_error
  end

  test "button messages are delivered too" do
    outbound = queue_outbound(buttons: [ { "id" => "confirm:abc", "title" => "Book it" } ])
    assert_equal "buttons", outbound.kind
    DeliverOutboundMessageJob.perform_now(outbound.id)
    assert_equal "sent", outbound.reload.status
  end

  test "a permanent error marks the message failed with the reason" do
    outbound = queue_outbound
    fake = FakeTransport.new { raise Whatsapp::Transport::PermanentError, "HTTP 400: invalid number" }

    with_transport(fake) do
      assert_no_enqueued_jobs { DeliverOutboundMessageJob.perform_now(outbound.id) }
    end

    outbound.reload
    assert_equal "failed", outbound.status
    assert_equal "HTTP 400: invalid number", outbound.last_error
    assert_equal 1, outbound.attempts
    assert_nil outbound.provider_message_id
  end

  test "a retryable error keeps the message pending, saves the attempt and retries" do
    outbound = queue_outbound
    fake = FakeTransport.new { raise Whatsapp::Transport::RetryableError, "Net::ReadTimeout" }

    with_transport(fake) do
      assert_enqueued_with(job: DeliverOutboundMessageJob, args: [ outbound.id ]) do
        DeliverOutboundMessageJob.perform_now(outbound.id)
      end
    end

    outbound.reload
    assert_equal "pending", outbound.status
    assert_equal 1, outbound.attempts
    assert_equal "Net::ReadTimeout", outbound.last_error
  end

  test "a retry that then succeeds marks the message sent" do
    outbound = queue_outbound
    tries = 0
    fake = FakeTransport.new do
      tries += 1
      raise Whatsapp::Transport::RetryableError, "busy" if tries == 1

      "wamid.ok"
    end

    with_transport(fake) do
      DeliverOutboundMessageJob.perform_now(outbound.id)
      perform_enqueued_jobs(only: DeliverOutboundMessageJob)
    end

    outbound.reload
    assert_equal "sent", outbound.status
    assert_equal "wamid.ok", outbound.provider_message_id
    assert_equal 2, outbound.attempts
    assert_nil outbound.last_error
  end

  test "after repeated retryable errors the message is marked failed" do
    outbound = queue_outbound
    fake = FakeTransport.new { raise Whatsapp::Transport::RetryableError, "HTTP 503" }

    with_transport(fake) do
      DeliverOutboundMessageJob.perform_now(outbound.id)
      # Run each scheduled retry in turn, the way a real queue would.
      10.times do
        retry_job = enqueued_jobs.pop or break
        ActiveJob::Base.execute(retry_job.stringify_keys)
      end
    end

    outbound.reload
    assert_equal "failed", outbound.status
    assert_equal "gave up: HTTP 503", outbound.last_error
    assert_equal 6, fake.calls
  end

  test "a message that isn't pending isn't sent again" do
    %w[sent delivered read failed].each do |status|
      outbound = queue_outbound
      outbound.update_columns(status: status, attempts: 1)
      fake = FakeTransport.new { flunk "should not deliver a #{status} message" }

      with_transport(fake) { DeliverOutboundMessageJob.perform_now(outbound.id) }

      assert_equal 0, fake.calls
      assert_equal status, outbound.reload.status
      assert_equal 1, outbound.attempts
    end
  end

  test "running the job twice sends once" do
    outbound = queue_outbound
    fake = FakeTransport.new { "wamid.#{SecureRandom.hex(4)}" }
    with_transport(fake) do
      2.times { DeliverOutboundMessageJob.perform_now(outbound.id) }
    end
    assert_equal 1, fake.calls
  end

  test "an unknown ID is ignored" do
    assert_nothing_raised { DeliverOutboundMessageJob.perform_now(SecureRandom.uuid) }
  end

  test "an unknown provider fails loudly rather than silently" do
    assert_raises(ArgumentError) { Whatsapp::Transport.for(ChannelAccount.new(provider: "carrier_pigeon")) }
    assert_instance_of Whatsapp::SimulatorTransport, Whatsapp::Transport.for(account)
  end
end
