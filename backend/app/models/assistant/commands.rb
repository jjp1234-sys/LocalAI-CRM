module Assistant
  # A staff member texted the business's number. Works out what they want and
  # answers them on WhatsApp. Runs inside Tenant.with(business).
  #
  # Scripted for now: fixed command words, no AI. Anything that changes data
  # in a way that's hard to undo (booking) asks for a yes/no first.
  #
  # Swipe-replying to one of our "💬 new message from <customer>" notifications
  # always sends the text to that customer. That's an explicit gesture, so it
  # never gets mistaken for a command.
  class Commands
    OPEN_STAGES = %w[new contacted qualified appointment].freeze
    STAGE_WORDS = %w[new contacted qualified won lost].freeze
    LIST_LIMIT = 10
    CUSTOMER_WINDOW = 24.hours
    APPOINTMENT_LENGTH = 1.hour

    HELP = <<~TEXT.strip
      Here's what I understand:
      *today*: your day at a glance
      *leads*: your open leads, numbered
      *lead 2* or *lead sarah*: one lead's details
      *reply 2 See you Thursday!*: message a customer
      _(or swipe-reply to my message about them)_
      *book 2 thu 2pm*: book an appointment
      *week*: appointments this week
      *note 2 wants black speakers*: add a note
      *remind 2 fri 10am call about quote*: set a reminder
      _(or *remind me tomorrow 9am order cables*)_
      *tasks*, then *done 1*: your reminders
      *value 2 4500*: what the deal is worth
      *won 2 4500*, *lost 2*, *qualified 2*: move a lead along
    TEXT

    def initialize(account:, user:, event:)
      @account = account
      @user = user
      @event = event
      @business = account.business
      @session = AssistantSession.for(user)
    end

    def call
      # Changes made through the assistant are logged as this person's.
      Current.user = @user
      body, buttons = handle
      OutboundMessage.queue!(account: @account, to: @user.phone, body: body, buttons: buttons || [])
    end

    private

    def handle
      if (lead = swipe_reply_lead)
        return send_to_customer(lead, @event.text)
      end
      return button(@event.button_id) if @event.button_id

      text = @event.text.to_s.strip
      words = text.downcase

      case words
      when "", "help", "menu", "?", "hi", "hello" then HELP
      when "yes", "y", "ok", "confirm" then confirm(@session.latest_pending("book")&.first)
      when "no", "n", "cancel" then cancel(@session.latest_pending("book")&.first)
      when "today", "digest", "summary", "home" then Digest.new(business: @business, user: @user).text
      when "leads", "new", "new leads", "open" then list_leads
      when "week", "appointments", "appts", "schedule" then list_appointments(:week)
      when "tasks", "todo", "to do", "reminders", "follow ups", "followups" then list_tasks
      when /\Adone\s+(\d{1,2})\z/ then complete_task(Regexp.last_match(1).to_i)
      when /\Anote\s+(.+)\z/m then add_note(text.split(/\s+/, 2).last)
      when /\A(?:remind|reminder|fu)\s+(.+)\z/m then remind(text.split(/\s+/, 2).last)
      when /\Avalue\s+(.+)\z/ then set_value(text.split(/\s+/, 2).last)
      when /\A(?:lead|show|l)\s+(.+)\z/ then show_lead(text.split(/\s+/, 2).last)
      when /\A(?:reply|r)\s+(.+)\z/m then reply_command(text.split(/\s+/, 2).last)
      when /\Abook\s+(.+)\z/ then book(text.split(/\s+/, 2).last)
      when /\A(#{STAGE_WORDS.join("|")})\s+(.+)\z/ then set_stage(Regexp.last_match(1), text.split(/\s+/, 2).last)
      else
        "Sorry, I didn't catch that. Send *help* to see what I can do."
      end
    end

    # --- Leads -------------------------------------------------------------

    def list_leads
      leads = Lead.active.where(status: OPEN_STAGES).order(last_activity_at: :desc, id: :desc).limit(LIST_LIMIT).to_a
      return "No open leads right now. 🎉" if leads.empty?

      @session.remember_list!(leads.map(&:id))
      lines = leads.each_with_index.map { |l, i| "#{i + 1}. *#{l.name}* · #{l.status} · #{ago(l.last_activity_at)}" }
      "Open leads:\n#{lines.join("\n")}\n\nSend *lead 1* for details."
    end

    def show_lead(ref)
      lead, problem = resolve(ref)
      return problem unless lead

      lines = [ "*#{lead.name}* · #{lead.status}" ]
      lines << [ lead.phone, lead.email ].compact.join(" · ")
      lines << "Needs: #{lead.need}" if lead.need
      lines << "Worth: #{Money.format(lead.value_cents)}" if lead.value_cents
      lead.notes.last(2).each { |n| lines << "📝 #{n.body.truncate(120)}" }
      lead.follow_ups.open.order(:due_at).limit(2).each { |f| lines << "⏰ #{f.body} · #{when_text(f.due_at)}" }
      if (appointment = lead.appointments.upcoming.order(:starts_at).first)
        lines << "Next: #{appointment.kind.humanize} #{when_text(appointment.starts_at)}"
      end
      recent = Message.joins(:conversation).where(conversations: { lead_id: lead.id }).order(created_at: :desc).limit(3).to_a.reverse
      if recent.any?
        lines << ""
        recent.each { |m| lines << "#{m.inbound? ? "👤" : "↩️"} #{m.body.truncate(120)}" }
      end
      lines.reject(&:nil?).join("\n")
    end

    # "won 2", "won 2 4500", "won sarah $4,500": an amount on the end sets
    # the deal's value at the same time.
    def set_stage(stage, rest)
      *ref_words, last = rest.split
      cents = Money.parse(last) if stage == "won" && ref_words.any?
      ref = cents ? ref_words.join(" ") : rest
      lead, problem = resolve(ref)
      return problem unless lead

      lead.update!(status: stage, value_cents: cents || lead.value_cents)
      worth = lead.value_cents ? " (#{Money.format(lead.value_cents)})" : ""
      "✓ *#{lead.name}* is now #{stage}#{worth}."
    end

    # "value 2 4500", "value sarah $4,500"
    def set_value(rest)
      *ref_words, last = rest.split
      cents = Money.parse(last)
      return "Try *value 2 4500*: the lead, then the amount in dollars." unless cents && ref_words.any?

      lead, problem = resolve(ref_words.join(" "))
      return problem unless lead

      lead.update!(value_cents: cents)
      "✓ *#{lead.name}* is worth #{Money.format(cents)}."
    end

    # --- Notes and reminders -----------------------------------------------

    def add_note(rest)
      ref, body = split_ref_and_text(rest)
      return "What's the note? Try *note 2 wants black speakers*." if body.blank?

      lead, problem = resolve(ref, verb: "note")
      return problem unless lead

      lead.notes.create!(body: body, author_user: @user)
      "📝 Noted on *#{lead.name}*."
    end

    # "remind 2 fri 10am call about quote", "remind me tomorrow 9am order
    # cables", "remind sarah johnson fri 10am: call about quote". Tries each
    # way of splitting "who / when / what" until one makes sense.
    def remind(rest)
      tokens = rest.split
      (1...tokens.size).each do |who_end|
        (tokens.size - 1).downto(who_end + 1).each do |when_end|
          due = WhenParser.parse(tokens[who_end...when_end].join(" ").delete_suffix(":"), zone: @business.time_zone)
          next unless due

          what = tokens[when_end..].join(" ").delete_prefix(":").strip
          next if what.empty?

          who = tokens[0...who_end].join(" ")
          lead = nil
          unless %w[me myself].include?(who.downcase)
            lead, problem = resolve(who, verb: "remind")
            return problem unless lead
          end
          return "That time has already passed." if due <= Time.current

          FollowUp.create!(body: what, due_at: due, lead: lead, assigned_user: @user, created_by: @user)
          return "⏰ I'll remind you #{when_text(due)}: #{what}#{lead ? " (#{lead.name})" : ""}"
        end
      end
      "Try *remind 2 fri 10am call about quote* or *remind me tomorrow 9am order cables*."
    end

    def list_tasks
      tasks = FollowUp.open.where(assigned_user_id: @user.id).includes(:lead).order(:due_at, :id).limit(LIST_LIMIT).to_a
      return "No reminders waiting. ✨" if tasks.empty?

      @session.remember_tasks!(tasks.map(&:id))
      lines = tasks.each_with_index.map do |t, i|
        overdue = t.due_at < Time.current ? " ⚠️" : ""
        "#{i + 1}. #{t.body}#{t.lead ? " · #{t.lead.name}" : ""} · #{when_text(t.due_at)}#{overdue}"
      end
      "Your reminders:\n#{lines.join("\n")}\n\nSend *done 1* when one's done."
    end

    def complete_task(number)
      id = number.positive? ? @session.tasks[number - 1] : nil
      task = id && FollowUp.open.find_by(id: id, assigned_user_id: @user.id)
      return "I don't have a reminder #{number}. Send *tasks* for a fresh list." unless task

      task.complete!
      "✓ Done: #{task.body}"
    end

    # Buttons on a reminder: "fudone:<id>", "futomorrow:<id>". Only the person
    # it's assigned to can act on it.
    def follow_up_button(answer, id)
      task = FollowUp.find_by(id: id, assigned_user_id: @user.id)
      return "That reminder isn't available." unless task
      return "That one's already closed." unless task.open?

      if answer == "fudone"
        task.complete!
        "✓ Done: #{task.body}"
      else
        zone = ActiveSupport::TimeZone[@business.time_zone]
        task.reschedule!(zone.now.tomorrow.change(hour: 9))
        "⏰ Moved to #{when_text(task.due_at)}: #{task.body}"
      end
    end

    # "2 text" (a number first), or "sarah johnson: text" (a name needs a colon).
    def split_ref_and_text(rest)
      ref, text =
        if rest.match?(/\A\d{1,2}\s/) then rest.split(/\s+/, 2)
        elsif rest.include?(":") then rest.split(":", 2)
        else rest.split(/\s+/, 2)
        end
      [ ref.to_s.strip, text.to_s.strip ]
    end

    # --- Replying to customers ---------------------------------------------

    # The lead behind a notification the staff member swipe-replied to.
    def swipe_reply_lead
      return nil unless @event.replying_to

      lead = OutboundMessage.where(provider_message_id: @event.replying_to, to_phone: @user.phone)
        .where.not(lead_id: nil).first&.lead
      return lead unless lead && lead.conversations.status_open.where(channel: "whatsapp").none?

      # The conversation moved (e.g. to a new lead for a returning customer):
      # follow the phone number to whichever lead is current.
      Lead.active.where(phone_e164: lead.phone_e164).order(last_activity_at: :desc, id: :desc).first || lead
    end

    # "reply 2 text", "reply sarah: text", "reply sarah johnson: text"
    def reply_command(rest)
      # "reply 2 text" (the number always comes first, even if the text has
      # a colon) or "reply sarah johnson: text" (a name needs the colon).
      ref, message = split_ref_and_text(rest)
      return "What should I send? Try *reply 2 See you Thursday!*" if message.blank?

      lead, problem = resolve(ref, verb: "reply")
      return problem unless lead

      send_to_customer(lead, message)
    end

    # WhatsApp only lets a business send free text within 24 hours of the
    # customer's last message. Outside that it needs a pre-approved template,
    # which isn't set up yet, so say so rather than fail silently.
    def send_to_customer(lead, text)
      return "Nothing to send." if text.blank?

      conversation = lead.conversations.status_open.find_by(channel: "whatsapp")
      last_heard = conversation&.messages&.where(direction: "inbound")&.maximum(:created_at)
      if conversation.nil? || lead.phone_e164.blank?
        return "*#{lead.name}* hasn't messaged us on WhatsApp, so I can't start a chat with them yet."
      end
      if last_heard.nil? || last_heard < CUSTOMER_WINDOW.ago
        return "*#{lead.name}* last wrote #{ago(last_heard)}. WhatsApp only allows replies within 24 hours of their last message; after that it needs an approved template, which isn't set up yet."
      end

      message = conversation.messages.create!(body: text, direction: "outbound", sender_kind: "staff", sender_user: @user)
      OutboundMessage.queue!(account: @account, to: lead.phone_e164, body: text, lead: lead, message: message)
      "✓ Sent to *#{lead.name}*."
    end

    # --- Appointments --------------------------------------------------------

    # "book 2 thu 2pm", "book sarah johnson tomorrow 10am"
    def book(rest)
      tokens = rest.split
      (1...tokens.size).each do |split|
        starts_at = WhenParser.parse(tokens[split..].join(" "), zone: @business.time_zone)
        next unless starts_at

        lead, problem = resolve(tokens[0...split].join(" "), verb: "book")
        return problem unless lead
        return "That time has already passed. When should I book *#{lead.name}*?" if starts_at <= Time.current

        return propose_booking(lead, starts_at)
      end
      "I couldn't tell who or when. Try *book 2 thu 2pm* or *book sarah tomorrow 10am*."
    end

    def propose_booking(lead, starts_at)
      # Only one booking can be waiting at a time: a new proposal replaces an
      # older one, so tapping "Book it" on a stale question can't book it.
      nonce = @session.add_pending!({ "action" => "book", "lead_id" => lead.id, "starts_at" => starts_at.iso8601 }, replacing: "book")
      clash = Appointment.where.not(status: %w[cancelled]).where("starts_at < ? AND ends_at > ?", starts_at + APPOINTMENT_LENGTH, starts_at).first
      text = "Book *#{lead.name}* #{when_text(starts_at)}?"
      text += "\n⚠️ Overlaps #{clash.lead.name} #{when_text(clash.starts_at)}." if clash
      [ text, [ { "id" => "confirm:#{nonce}", "title" => "Book it" }, { "id" => "cancel:#{nonce}", "title" => "Cancel" } ] ]
    end

    # Button IDs are "<answer>:<nonce>". The nonce ties the tap to the exact
    # question asked, so an old button can't answer a newer question.
    def button(id)
      answer, nonce = id.to_s.split(":", 2)
      case answer
      when "confirm" then confirm(nonce)
      when "cancel" then cancel(nonce)
      when "reopen", "newlead", "leave" then returning_customer(answer, nonce)
      when "fudone", "futomorrow" then follow_up_button(answer, nonce)
      else "That button has expired."
      end
    end

    def confirm(nonce)
      pending = nonce && @session.take_pending!(nonce)
      return "There's nothing waiting for a yes." unless pending && pending["action"] == "book"

      complete_booking(pending)
    end

    def cancel(nonce)
      return "Nothing to cancel." unless nonce && @session.take_pending!(nonce)

      "OK, cancelled."
    end

    def complete_booking(pending)
      lead = Lead.active.find_by(id: pending["lead_id"])
      return "That lead is no longer available." unless lead

      starts_at = Time.iso8601(pending["starts_at"])
      Appointment.create!(
        lead: lead, starts_at: starts_at, ends_at: starts_at + APPOINTMENT_LENGTH,
        kind: "consultation", status: "confirmed", assigned_user: @user
      )
      lead.update!(status: "appointment") if %w[new contacted qualified].include?(lead.status)

      told = tell_customer(lead, "✅ You're booked with #{@business.name}: #{when_text(starts_at)}.\nReply here if you need to change it.")
      note = told ? "I've let them know." : "I couldn't message them (they haven't written in the last 24 hours), so let them know yourself."
      "✅ Booked *#{lead.name}* #{when_text(starts_at)}. #{note}"
    end

    # An automatic message to the customer, recorded in their conversation.
    # Only possible inside WhatsApp's 24-hour window; returns whether it was sent.
    def tell_customer(lead, text)
      conversation = lead.conversations.status_open.find_by(channel: "whatsapp")
      last_heard = conversation&.messages&.where(direction: "inbound")&.maximum(:created_at)
      return false unless conversation && lead.phone_e164 && last_heard && last_heard >= CUSTOMER_WINDOW.ago

      message = conversation.messages.create!(body: text, direction: "outbound", sender_kind: "system")
      OutboundMessage.queue!(account: @account, to: lead.phone_e164, body: text, lead: lead, message: message)
      true
    end

    # Answers to "👋 <name> is back: reopen, new lead, or leave it?"
    # Several team members may get the question; whoever answers first wins,
    # and later answers see that it was already handled.
    def returning_customer(answer, nonce)
      pending = nonce && @session.take_pending!(nonce)
      return "That question has expired or was already answered." unless pending && pending["action"] == "returning"

      lead = Lead.active.find_by(id: pending["lead_id"])
      conversation = Conversation.find_by(id: pending["conversation_id"])
      return "That lead is no longer available." unless lead && conversation
      return "Someone already moved this conversation to a new lead." unless conversation.lead_id == lead.id

      case answer
      when "reopen"
        return "*#{lead.name}* is already open (#{lead.status})." unless lead.status.in?(%w[won lost])

        lead.update!(status: "new")
        "✓ Reopened *#{lead.name}*. They're back in your leads as new."
      when "newlead"
        fresh = Lead.create!(name: lead.name, phone: lead.phone, email: lead.email, source: "whatsapp", status: "new")
        conversation.update!(lead: fresh)
        "✓ Started a new lead for *#{fresh.name}*. Their old one stays #{lead.status}."
      else
        "OK, leaving *#{lead.name}* as #{lead.status}."
      end
    end

    def list_appointments(range)
      zone = ActiveSupport::TimeZone[@business.time_zone]
      finish = range == :today ? zone.now.end_of_day : zone.now + 7.days
      appointments = Appointment.upcoming.where(starts_at: ..finish).includes(:lead).order(:starts_at).limit(20).to_a
      label = range == :today ? "today" : "in the next 7 days"
      return "Nothing booked #{label}." if appointments.empty?

      lines = appointments.map { |a| "• #{when_text(a.starts_at)}: *#{a.lead.name}* (#{a.kind.humanize.downcase})" }
      "Booked #{label}:\n#{lines.join("\n")}"
    end

    # --- Helpers -------------------------------------------------------------

    # A lead from "2" (a number from the last list) or a name. Returns
    # [lead, nil] or [nil, message explaining the problem].
    def resolve(ref, verb: "lead")
      ref = ref.to_s.strip
      if ref.match?(/\A\d{1,2}\z/)
        id = @session.list[ref.to_i - 1]
        lead = id && ref.to_i.positive? ? Lead.active.find_by(id: id) : nil
        return [ lead, nil ] if lead

        return [ nil, "I don't have a lead #{ref}. Send *leads* for a fresh list." ]
      end

      matches = Lead.active.where("name ILIKE ?", "%#{Lead.sanitize_sql_like(ref)}%")
        .order(last_activity_at: :desc, id: :desc).limit(5).to_a
      # Several matches but only one still in play (the others won/lost):
      # that's almost certainly the one meant.
      open = matches.select { |l| OPEN_STAGES.include?(l.status) }
      matches = open if open.size == 1

      case matches.size
      when 0 then [ nil, "I couldn't find a lead called \"#{ref.truncate(40)}\"." ]
      when 1 then [ matches.first, nil ]
      else
        @session.remember_list!(matches.map(&:id))
        options = matches.each_with_index.map { |l, i| "#{i + 1}. #{l.name} · #{l.status}" }.join("\n")
        [ nil, "Which one?\n#{options}\n\nUse the number instead, e.g. *#{verb} 1 …*" ]
      end
    end

    def when_text(time)
      local = time.in_time_zone(@business.time_zone)
      day = if local.to_date == Time.current.in_time_zone(@business.time_zone).to_date then "today"
      elsif local.to_date == Time.current.in_time_zone(@business.time_zone).to_date + 1 then "tomorrow"
      else local.strftime("%a %b %-d")
      end
      "#{day} at #{local.strftime("%-l:%M%P")}"
    end

    def ago(time)
      return "never" unless time

      seconds = (Time.current - time).to_i
      if seconds < 3600 then "#{[ seconds / 60, 1 ].max}m ago"
      elsif seconds < 86_400 then "#{seconds / 3600}h ago"
      else "#{seconds / 86_400}d ago"
      end
    end
  end
end
