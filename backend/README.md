# LocalAI backend

A JSON API for the CRM underneath the assistant: businesses and their teams, leads, conversations, messages, appointments, and an audit log. It doesn't depend on any particular front end, and it has no AI in it yet. That comes once the product decides what the assistant needs.

Ruby 4.0, Rails 8.1 (API-only), PostgreSQL 17.

## Running it

```sh
# once
brew install ruby postgresql@17
brew services start postgresql@17
export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/opt/postgresql@17/bin:$PATH"   # add to ~/.zshrc
cd backend
bundle config set --local path vendor/bundle   # keep this project's gems in vendor/bundle
bundle install
bin/rails db:prepare

# every time
bin/rails server           # http://localhost:3000
bin/rails test             # the whole suite
bin/rubocop                # style
bin/brakeman               # security static analysis
```

## How business data is kept separate

Each business's data must never reach another business. Three independent layers enforce this, so a bug in one doesn't leak anything:

1. **App code.** Every request under `/api/v1/businesses/:business_id/` first checks that the user is a member of that business (`app/controllers/concerns/business_scoped.rb`). Non-members get a 404, the same as for a business that doesn't exist.
2. **Postgres row-level security.** The rest of the request runs inside `Tenant.with(business)` (`app/models/tenant.rb`). That switches the database connection to a restricted role, `frontdesk_app`, and records which business it's acting for. Policies on every business-owned table then hide all other businesses' rows, even from a query that forgets its `where`. `db/app_role.sql` lists what that role may do at all. For example, it can add messages and activity entries but never edit or delete them.
3. **Composite foreign keys.** A conversation's `(lead_id, business_id)` must match a lead's `(id, business_id)`, so records can't point across businesses.

`test/models/row_level_security_test.rb` checks the database layer directly with raw SQL. It fails if a table with a `business_id` has no policy.

## Other security choices

- **Tokens are stored only as SHA-256 digests.** This covers login tokens (`fds_…`) and intake keys (`fdi_…`), so a copy of the database contains no usable credentials. Passwords use bcrypt, minimum 12 characters.
- **Rate limits.** Signup, login (per IP and per email) and lead intake are rate limited. `X-Forwarded-For` is only trusted when the connection comes from a trusted proxy, so clients can't fake their IP to reset a limit.
- **Login doesn't reveal which emails have accounts.** A wrong password and an unknown email get the same response, and so do invitations.
- **New teammates are invited, never added directly.** An invitation only takes effect when the invitee accepts it.
- **JSON responses list their fields explicitly** (`app/serializers/serializers.rb`), so a new column never leaks by accident.
- **Customer details and secrets are filtered from logs.**
- **Leads are archived rather than deleted.** Appointments are cancelled rather than deleted. Every change to leads, conversations and appointments is written to an append-only activity log with who made it.
- **Malformed input returns a 4xx, never a crash.** This covers NULL bytes, arrays where single values are expected, and absurd dates. Errors always have the same shape: `{ "error": { "code", "message", "details" } }`.
- **In production, the app only answers to hostnames listed in `APP_HOSTS`, and forces HTTPS.**

## API

All endpoints are JSON under `/api/v1`. Authenticated endpoints need `Authorization: Bearer <token>`. List endpoints take `page` and `per_page` (max 100) and return `{ data, meta: { page, per_page, total } }`.

| Endpoint | What it does |
|---|---|
| `POST /signup` | Create an account and its business; returns a token |
| `POST /session` / `DELETE /session` | Log in / log out |
| `GET /me` | Current user and their businesses |
| `GET /invitations`, `POST /invitations/:id/accept` or `/decline` | Your pending invitations |
| `GET`/`PATCH /businesses/:id` | Business settings (owners edit) |
| `GET /businesses/:id/summary` | Dashboard numbers |
| `…/leads` (list, show, create, update), `POST …/leads/:id/archive` or `/unarchive` | Leads; list filters `status`, `source`, `assigned_user_id`, `q`, `archived`, `sort` |
| `GET …/leads/:id/activities` | A lead's history |
| `…/conversations` and `…/conversations/:id/messages` | Inbox. Posting a message records a staff reply; nothing is sent yet |
| `…/appointments` | Bookings; list filters `from`, `to`, `status`, `lead_id` |
| `…/memberships` | The team; admins change roles, anyone can leave |
| `…/invitations` | Invite by email (admins) |
| `…/intake_keys` | Keys for website forms and webhooks (admins) |
| `POST /intake/leads` | Public lead intake, authenticated with an intake key; `external_id` makes retries safe |

Roles: **owner** (everything), **admin** (team and intake keys, but not owners), **agent** (leads, conversations, appointments).

## WhatsApp

The product runs over WhatsApp: customers message a business's number and become leads, and the team runs the business by texting the same number. Staff are recognised by their saved phone number.

- **Try it locally:** `bin/rails db:seed`, start the server, open http://localhost:3000/dev/whatsapp. The simulator has two phones (owner and customer) and goes through the real, signed webhook. Development only.
- **Commands** (scripted, no AI yet): `today` (the daily digest), `leads`, `lead 2`, `reply 2 …` (or swipe-reply to a notification), `book 2 thu 2pm`, `week`, `note 2 …`, `remind 2 fri 10am …`, `tasks` / `done 1`, `value 2 4500`, `won 2 4500`. Send `help` for the list.
- **Behaviour:**
  - Notifications go to the lead's assigned person, otherwise owners and admins.
  - After one notification, more messages from the same customer stay quiet for 15 minutes unless they contain a word like "urgent", "cancel" or "price".
  - A returning won/lost customer prompts "Reopen / New lead / Leave it".
  - Booking confirms to the customer automatically.
  - Reminders arrive when due, and a digest goes out at 7:30 local time.
- **How it works:**
  - Webhooks are signature-checked and stored once per Meta message ID (`inbound_events`).
  - Processing runs in jobs.
  - Every message we send goes through an outbox (`outbound_messages`) until Meta confirms it.
  - `bin/rails whatsapp:redeliver` re-queues anything whose job was lost, and runs every 5 minutes in production.
- **Production needs:**
  - `WHATSAPP_APP_SECRET` and `WHATSAPP_VERIFY_TOKEN`.
  - Active Record encryption keys (`AR_ENCRYPTION_*`, from `bin/rails db:encryption:init`).
  - The Solid Queue database (`backend_production_queue`), and the job worker: `bin/jobs`, or `SOLID_QUEUE_IN_PUMA=1`.

## Quotes, contracts and job costs

- **Over WhatsApp:**
  - `quote 2`, then `add 4 speakers 350` / `remove 2` / `tax 7`, then `send quote`.
  - `contract 2` makes the contract from the lead's accepted quote.
  - `docs 2` lists a lead's documents with their links.
  - `cost 2 1800 speakers` records a job cost; profit is value minus costs.
- **The customer's side:**
  - Each quote and contract has a private link (`/q/…`, `/c/…`) to a printable page. Print saves a PDF.
  - Customers accept a quote by typing their name, and sign a contract by typing their name and agreeing to sign electronically.
  - We keep the time, IP, browser and a SHA-256 of the signed text.
- **What happens on accept and sign:** accepting sets the lead's value. Signing marks it won and notifies the team.
- **Nothing changes after agreement:** once accepted or signed, database triggers refuse any change to the quote, its items or the contract, from anyone.
- **Contract terms:** each business sets its own (`contract_terms`). The built-in default is a short generic template, flagged in the text as needing a lawyer's review.
- **Production needs `APP_PUBLIC_URL`,** the base URL for customer links.

## Deposits, payments and revisions

- **Deposits:** `deposit 50%` or `deposit 500` on a quote. The deposit shows on the quote and contract. Signing the contract creates the deposit request, and the signed page shows "Pay deposit".
- **Payment links:**
  - `request 2 balance`, `request 2 deposit` or `request 2 500 materials` sends a private link (`/p/…`).
  - The customer pays on the provider's hosted checkout, so card details never touch this app.
  - When the payment lands, the team is told (with the balance left) and the customer is thanked.
  - Paid payments are frozen by a database trigger.
- **Stripe:**
  - Charges go directly to each business's own connected account (Stripe Connect), so the money is theirs.
  - Needs `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET`, plus `payments_provider: "stripe"` and the business's `stripe_account_id`.
  - Point a Connect webhook at `/webhooks/stripe` for `checkout.session.completed`, `checkout.session.async_payment_succeeded` and `checkout.session.expired`.
  - Webhook signatures are checked, events older than 5 minutes are refused, and each event is handled once.
  - Development uses a simulated checkout (`payments_provider: "simulator"`).
- **Revisions:** `revise 2` makes "Q-1001 rev 2" from their latest quote. Sending it withdraws earlier versions they haven't accepted, and old links point to the new one. An accepted quote stays on file as it was.

## Known gaps

- **Email addresses aren't verified.** Whoever registers an address first can accept invitations sent to it. Signup still reveals that an address is taken, by failing where a new address would succeed. Both need the app to send email.
- **Rate-limit counters live in each server process.** That's fine for one server; more than one needs a shared store such as Redis or Solid Cache.
- **The `frontdesk_app` role can read every column of `users`, including password hashes.** It never does in practice, but a column-level grant would be stricter.
- **WhatsApp's 24-hour rule.** Messages the business starts need Meta-approved templates, which aren't set up yet. That covers digests, reminders, alerts to staff who haven't texted in a day, and replies to customers who went quiet. The simulator doesn't enforce this; real WhatsApp will.
- **No Google/Outlook calendar sync, SMS or email yet.**
- **Businesses connect Stripe by hand** (an `acct_…` ID) until Stripe Connect onboarding is built. There are no refunds or partial payments through the app yet.
- **No CORS.** Cross-origin browser requests are refused until the front end's origin is known and allowed.
