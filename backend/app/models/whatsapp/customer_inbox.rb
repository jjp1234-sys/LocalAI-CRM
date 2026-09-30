module Whatsapp
  # A customer messaged the business. Finds (or creates) their lead and open
  # WhatsApp conversation, records the message, and tells the right person.
  #
  # Who hears about it: the lead's assigned team member, or if nobody is
  # assigned, the owners and admins. Only people with a saved phone count.
  #
  # Bursts stay quiet: after one notification about a customer, their next
  # messages within QUIET_WINDOW don't notify again, unless they contain an
  # URGENT_WORDS word. Every message is still recorded ("lead 2" shows them).
  #
  # A customer whose lead was won or lost starting a new conversation gets a
  # question to the team instead: reopen the old lead, or start a new one?
  class CustomerInbox
    SNIPPET = 300
    QUIET_WINDOW = 15.minutes
    URGENT_WORDS = %w[
      urgent emergency asap cancel cancelled canceling reschedule today tonight now
      price prices quote cost how\ much
    ].freeze
    URGENT_PATTERN = /\b(?:#{URGENT_WORDS.map { |w| Regexp.escape(w) }.join("|")})\b/i
    CLOSED_STAGES = %w[won lost].freeze

    def initialize(account:, event:)
      @account = account
      @event = event
    end

    def call
      lead = find_or_create_lead
      conversation = lead.conversations.status_open.find_by(channel: "whatsapp")
      returning = conversation.nil? && CLOSED_STAGES.include?(lead.status)
      conversation ||= lead.conversations.create!(channel: "whatsapp")
      conversation.messages.create!(body: body, direction: "inbound", sender_kind: "customer")

      if returning
        ask_about_returning(lead, conversation)
      else
        notify(lead)
      end
    end

    private

    # Their text, or a note saying what kind of thing they sent that we
    # can't show yet (a photo, a voice note...).
    def body
      return "(sent a #{@event.unsupported_type}, which can't be shown yet)" if @event.unsupported_type

      @event.text.presence || "(empty message)"
    end

    # The customer's words, shown as a WhatsApp quote ("> " on every line).
    # A customer can't then write lines that look like the assistant talking
    # (a fake "✅ Booked" or fake instructions) inside the notification.
    def snippet
      text = body.length > SNIPPET ? "#{body.first(SNIPPET)}…" : body
      text.lines.map { |line| "> #{line.chomp}" }.join("\n")
    end

    # Names come from the customer's WhatsApp profile. Strip WhatsApp's
    # formatting characters and line breaks so a name can't restyle or add
    # lines to the message.
    def display_name(lead)
      lead.name.to_s.gsub(/[*_~`>\r\n]/, " ").squish.first(60).presence || "Customer"
    end

    # The most recently active lead with this number, archived ones aside.
    def find_or_create_lead
      Lead.active.where(phone_e164: @event.from_phone).order(last_activity_at: :desc, id: :desc).first ||
        Lead.create!(
          name: @event.profile_name || @event.from_phone,
          phone: @event.from_phone,
          source: "whatsapp",
          status: "new"
        )
    end

    # Only current members: someone removed from the business stops getting
    # its customers' messages, even if a lead is still assigned to them.
    def recipients(lead)
      Team.recipients(lead)
    end

    def notify(lead)
      urgent = body.match?(URGENT_PATTERN)
      recipients(lead).each do |user|
        next if !urgent && recently_notified?(user, lead)

        OutboundMessage.queue!(
          account: @account, to: user.phone, lead: lead,
          body: "#{urgent ? "❗" : "💬"} *#{display_name(lead)}*\n#{snippet}\n\n_Swipe to reply to this message to answer them._"
        )
      end
    end

    # Notifications are the outbox rows about this lead sent to a staff phone
    # (replies to the customer go to the customer's phone instead).
    def recently_notified?(user, lead)
      OutboundMessage.where(lead_id: lead.id, to_phone: user.phone).where(created_at: QUIET_WINDOW.ago..).exists?
    end

    def ask_about_returning(lead, conversation)
      recipients(lead).each do |user|
        nonce = AssistantSession.for(user).add_pending!(
          { "action" => "returning", "lead_id" => lead.id, "conversation_id" => conversation.id }, ttl: 7.days
        )
        OutboundMessage.queue!(
          account: @account, to: user.phone, lead: lead,
          body: "👋 *#{display_name(lead)}* is back (their lead was #{lead.status}):\n#{snippet}\n\nReopen their lead, or start a new one?",
          buttons: [
            { "id" => "reopen:#{nonce}", "title" => "Reopen" },
            { "id" => "newlead:#{nonce}", "title" => "New lead" },
            { "id" => "leave:#{nonce}", "title" => "Leave it" }
          ]
        )
      end
    end
  end
end
