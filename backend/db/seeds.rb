# Demo data for local development: `bin/rails db:seed`. Safe to run twice.
# Refuses to run in production.
abort "Seeds are for development only" if Rails.env.production?

business = Business.find_or_create_by!(slug: "south-florida-av") do |b|
  b.name = "South Florida AV"
  b.time_zone = "America/New_York"
end

owner = User.find_or_initialize_by(email_address: "owner@example.com")
owner.update!(name: "Demo Owner", password: "demo password 123", phone: "+13055550100")
Membership.find_or_create_by!(business: business, user: owner) { |m| m.role = "owner" }

# WhatsApp numbers are set up by an administrator, not through the app's
# restricted database role, so this runs outside Tenant.with.
ChannelAccount.find_or_create_by!(phone_number_id: "sim-south-florida-av") do |a|
  a.business = business
  a.provider = "simulator"
  a.display_phone = "+1 305 555 0199"
end

Tenant.with(business) do
  [
    { name: "Sarah Johnson", phone: "+1 305 555 0142", need: "Conference room AV for 30 people, 45 days, $15-25k", source: "facebook", status: "qualified", score: 86 },
    { name: "Michael Reed", phone: "+1 305 555 0143", need: "Site estimate for a restaurant sound system", source: "website", status: "new" },
    { name: "Ana Torres", phone: "+1 305 555 0144", need: "Church livestream upgrade", source: "referral", status: "contacted" }
  ].each do |attrs|
    Lead.find_or_create_by!(phone: attrs[:phone]) { |l| l.assign_attributes(attrs) }
  end
end

puts "Seeded #{business.name}. Log in as owner@example.com / demo password 123; the owner's WhatsApp is +13055550100."
