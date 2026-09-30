# WhatsApp (Meta Cloud API) settings.
#
#   app_secret    Meta signs every webhook with this. Requests whose signature
#                 doesn't match are rejected, so nobody can fake a message.
#   verify_token  Meta sends this back once, when you register the webhook URL.
#
# Production must set WHATSAPP_APP_SECRET and WHATSAPP_VERIFY_TOKEN. Development
# and test use throwaway values, which the local simulator signs with too, so
# the same signature check runs everywhere.
Rails.application.configure do
  config.x.whatsapp.graph_api_version = ENV.fetch("WHATSAPP_GRAPH_API_VERSION", "v21.0")
  if Rails.env.production?
    config.x.whatsapp.app_secret = ENV.fetch("WHATSAPP_APP_SECRET")
    config.x.whatsapp.verify_token = ENV.fetch("WHATSAPP_VERIFY_TOKEN")
  else
    config.x.whatsapp.app_secret = ENV.fetch("WHATSAPP_APP_SECRET", "dev-whatsapp-app-secret")
    config.x.whatsapp.verify_token = ENV.fetch("WHATSAPP_VERIFY_TOKEN", "dev-whatsapp-verify-token")
  end
end
