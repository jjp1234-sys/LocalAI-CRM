Rails.application.routes.draw do
  # Load balancers and uptime monitors check this. 200 if the app booted.
  get "up" => "rails/health#show", as: :rails_health_check

  # Quote and contract pages customers open from a link.
  get "q/:token", to: "public_documents#quote", as: :public_quote
  post "q/:token/accept", to: "public_documents#accept_quote"
  post "q/:token/decline", to: "public_documents#decline_quote"
  get "c/:token", to: "public_documents#contract", as: :public_contract
  post "c/:token/sign", to: "public_documents#sign_contract"

  # Meta's WhatsApp webhook.
  get "webhooks/whatsapp", to: "webhooks/whatsapp#verify"
  post "webhooks/whatsapp", to: "webhooks/whatsapp#receive"

  # A fake WhatsApp for trying the product locally. Development only.
  if Rails.env.development?
    get "dev/whatsapp", to: "dev/whatsapp_simulator#show"
    get "dev/whatsapp/feed", to: "dev/whatsapp_simulator#feed"
    post "dev/whatsapp/send", to: "dev/whatsapp_simulator#deliver"
    post "dev/whatsapp/tick", to: "dev/whatsapp_simulator#tick"
  end

  namespace :api do
    namespace :v1 do
      post "signup", to: "registrations#create"
      resource :session, only: [ :create, :destroy ]
      get "me", to: "me#show"
      resources :invitations, only: :index do
        member do
          post :accept
          post :decline
        end
      end

      namespace :intake do
        resources :leads, only: :create
      end

      resources :businesses, only: [ :show, :update ] do
        scope module: :businesses do
          resource :summary, only: :show
          resources :leads, only: [ :index, :show, :create, :update ] do
            member do
              post :archive
              post :unarchive
            end
            resources :activities, only: :index
            resources :notes, only: [ :index, :create ]
            resources :job_costs, only: [ :index, :create ]
          end
          resources :quotes, only: [ :index, :show, :create, :update ] do
            post :deliver, on: :member
          end
          resources :contracts, only: [ :index, :show, :create ] do
            member do
              post :deliver
              post :void
            end
          end
          resources :follow_ups, only: [ :index, :show, :create, :update ]
          resources :conversations, only: [ :index, :show, :create, :update ] do
            resources :messages, only: [ :index, :create ]
          end
          resources :appointments, only: [ :index, :show, :create, :update ]
          resources :memberships, only: [ :index, :update, :destroy ]
          resources :invitations, only: [ :index, :create, :destroy ]
          resources :intake_keys, only: [ :index, :create, :destroy ]
        end
      end
    end
  end
end
