module Dev
  # A fake WhatsApp for trying the product on your own machine. Development
  # only: the routes don't exist in any other environment, and this refuses to
  # run outside development even if they did.
  #
  # Sending builds exactly the payload Meta would, signs it with the app
  # secret, and posts it through the real webhook endpoint, so everything from
  # the signature check onwards is the production code path.
  class WhatsappSimulatorController < ActionController::API
    before_action { head :not_found unless Rails.env.development? }

    def show
      render html: PAGE.html_safe
    end

    # Everything a phone number sent to, or received from, simulator numbers.
    def feed
      phone = PhoneNumber.normalize(params[:phone].to_s)
      return render(json: { messages: [] }) unless phone

      accounts = ChannelAccount.where(provider: "simulator").pluck(:id)
      sent = InboundEvent.where(channel_account_id: accounts, kind: "message", from_phone: phone).map do |e|
        { id: e.provider_event_id, at: e.created_at, from_me: true, body: e.text.presence || e.payload["type"], replying_to: e.replying_to }
      end
      received = OutboundMessage.where(channel_account_id: accounts, to_phone: phone).map do |m|
        { id: m.provider_message_id || "pending-#{m.id}", at: m.created_at, from_me: false, body: m.body, buttons: m.buttons, status: m.status }
      end
      render json: { messages: (sent + received).sort_by { |m| m[:at] }.last(200) }
    end

    # Production runs these on a schedule (config/recurring.yml); the dev
    # server doesn't run scheduled jobs, so the simulator page calls this.
    def tick
      FollowUpRemindersJob.perform_now
      DailyDigestJob.perform_now
      head :no_content
    end

    def deliver
      account = ChannelAccount.find_by!(provider: "simulator")
      from = PhoneNumber.normalize(params[:from].to_s)
      return render(json: { error: "bad phone" }, status: :unprocessable_content) unless from

      message = { "from" => from.delete("+"), "id" => "wamid.sim.#{SecureRandom.hex(10)}", "timestamp" => Time.current.to_i.to_s }
      if params[:button_id].present?
        message.merge!("type" => "interactive", "interactive" => { "type" => "button_reply", "button_reply" => { "id" => params[:button_id].to_s, "title" => params[:text].to_s } })
      else
        message.merge!("type" => "text", "text" => { "body" => params[:text].to_s })
      end
      message["context"] = { "id" => params[:replying_to].to_s } if params[:replying_to].present?

      payload = { "object" => "whatsapp_business_account", "entry" => [ { "changes" => [ { "field" => "messages", "value" => {
        "messaging_product" => "whatsapp",
        "metadata" => { "phone_number_id" => account.phone_number_id, "display_phone_number" => account.display_phone },
        "contacts" => [ { "wa_id" => message["from"], "profile" => { "name" => params[:name].to_s.presence || "Customer" } } ],
        "messages" => [ message ]
      } } ] } ] }
      body = JSON.generate(payload)
      env = Rack::MockRequest.env_for("/webhooks/whatsapp", method: "POST", input: body,
        "HTTP_HOST" => request.host_with_port,
        "CONTENT_TYPE" => "application/json", "HTTP_X_HUB_SIGNATURE_256" => Whatsapp::Signature.sign(body))
      status, = Rails.application.call(env)
      render json: { status: status }, status: status == 200 ? :ok : :bad_gateway
    end

    PAGE = <<~HTML
      <!doctype html>
      <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
      <title>WhatsApp simulator</title>
      <style>
        :root{--bg:#efeae2;--panel:#fff;--me:#d9fdd3;--them:#fff;--ink:#111b21;--muted:#667781;--accent:#00a884;--line:#e9edef}
        @media (prefers-color-scheme:dark){:root{--bg:#0b141a;--panel:#111b21;--me:#005c4b;--them:#202c33;--ink:#e9edef;--muted:#8696a0;--line:#222d34}}
        *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.4 -apple-system,system-ui,sans-serif}
        header{padding:12px 16px;font-weight:600}header small{color:var(--muted);font-weight:400;margin-left:8px}
        .phones{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:16px;padding:0 16px 16px}
        .phone{background:var(--panel);border-radius:12px;display:flex;flex-direction:column;height:calc(100vh - 70px);min-height:420px;overflow:hidden;border:1px solid var(--line)}
        .top{padding:10px 12px;border-bottom:1px solid var(--line);display:flex;gap:8px;align-items:center;flex-wrap:wrap}
        .top b{margin-right:auto}.top input{width:130px;padding:4px 6px;border:1px solid var(--line);border-radius:6px;background:transparent;color:var(--ink)}
        .log{flex:1;overflow-y:auto;padding:12px;display:flex;flex-direction:column;gap:6px;background:var(--bg)}
        .msg{max-width:85%;padding:7px 9px;border-radius:8px;white-space:pre-wrap;word-wrap:break-word;cursor:pointer}
        .msg.me{align-self:flex-end;background:var(--me)}.msg.them{align-self:flex-start;background:var(--them)}
        .msg .meta{font-size:11px;color:var(--muted);margin-top:2px}.msg .quote{font-size:12px;color:var(--muted);border-left:3px solid var(--accent);padding-left:6px;margin-bottom:4px}
        .btns{display:flex;gap:6px;margin-top:6px;flex-wrap:wrap}.btns button{flex:1;border:1px solid var(--line);background:transparent;color:var(--accent);border-radius:6px;padding:6px;cursor:pointer;font-weight:600}
        .reply-bar{display:none;padding:6px 12px;font-size:12px;color:var(--muted);border-top:1px solid var(--line)}.reply-bar.on{display:flex;justify-content:space-between}
        form{display:flex;gap:8px;padding:10px;border-top:1px solid var(--line)}form input{flex:1;padding:9px 12px;border-radius:20px;border:1px solid var(--line);background:transparent;color:var(--ink)}
        form button{border:0;background:var(--accent);color:#fff;border-radius:20px;padding:0 16px;font-weight:600;cursor:pointer}
      </style></head><body>
      <header>WhatsApp simulator<small>Click a received message to swipe-reply to it. Development only.</small></header>
      <div class="phones">
        <section class="phone" data-phone="+13055550100" data-name="Owner"><div class="top"><b>Owner</b><input class="num" value="+13055550100"></div><div class="log"></div><div class="reply-bar"><span></span><a href="#">✕</a></div><form><input placeholder="Try: help"><button>Send</button></form></section>
        <section class="phone" data-phone="+13055550177" data-name="Maria Lopez"><div class="top"><b>Customer</b><input class="name" value="Maria Lopez"><input class="num" value="+13055550177"></div><div class="log"></div><div class="reply-bar"><span></span><a href="#">✕</a></div><form><input placeholder="Hi, do you install projectors?"><button>Send</button></form></section>
      </div>
      <script>
      document.querySelectorAll(".phone").forEach(phone => {
        const log = phone.querySelector(".log"), form = phone.querySelector("form"), input = form.querySelector("input");
        const bar = phone.querySelector(".reply-bar"); let replyingTo = null, lastJson = "";
        const num = () => phone.querySelector(".num").value, name = () => (phone.querySelector(".name") || {}).value || "Owner";
        const send = (text, buttonId) => fetch("/dev/whatsapp/send", {method:"POST", headers:{"Content-Type":"application/json"},
          body: JSON.stringify({from:num(), name:name(), text, button_id:buttonId, replying_to:replyingTo})})
          .then(async r => { if (!r.ok) alert("Webhook rejected the message: " + await r.text()); clearReply(); refresh(); });
        const clearReply = () => { replyingTo = null; bar.classList.remove("on"); };
        bar.querySelector("a").onclick = e => { e.preventDefault(); clearReply(); };
        form.onsubmit = e => { e.preventDefault(); if (!input.value.trim()) return; send(input.value.trim()); input.value = ""; };
        async function refresh() {
          const res = await fetch("/dev/whatsapp/feed?phone=" + encodeURIComponent(num())); const json = await res.text();
          if (json === lastJson) return; lastJson = json; const {messages} = JSON.parse(json); const byId = {};
          messages.forEach(m => byId[m.id] = m); log.innerHTML = "";
          messages.forEach(m => {
            const el = document.createElement("div"); el.className = "msg " + (m.from_me ? "me" : "them");
            if (m.replying_to && byId[m.replying_to]) { const q = document.createElement("div"); q.className = "quote"; q.textContent = byId[m.replying_to].body.slice(0, 80); el.append(q); }
            const b = document.createElement("div"); b.textContent = m.body; el.append(b);
            if (m.buttons && m.buttons.length) { const row = document.createElement("div"); row.className = "btns";
              m.buttons.forEach(btn => { const x = document.createElement("button"); x.textContent = btn.title; x.onclick = ev => { ev.stopPropagation(); send(btn.title, btn.id); }; row.append(x); }); el.append(row); }
            const meta = document.createElement("div"); meta.className = "meta"; meta.textContent = new Date(m.at).toLocaleTimeString([], {hour:"numeric", minute:"2-digit"}) + (m.status ? " · " + m.status : ""); el.append(meta);
            if (!m.from_me) el.onclick = () => { replyingTo = m.id; bar.querySelector("span").textContent = "Replying to: " + m.body.slice(0, 60); bar.classList.add("on"); input.focus(); };
            log.append(el);
          });
          log.scrollTop = log.scrollHeight;
        }
        refresh(); setInterval(refresh, 1200);
      });
      // Fire due reminders and the morning digest (the dev server has no scheduler).
      const tick = () => fetch("/dev/whatsapp/tick", {method:"POST"}); tick(); setInterval(tick, 20000);
      </script></body></html>
    HTML
  end
end
