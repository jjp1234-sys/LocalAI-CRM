Rails.application.routes.draw do
  # Load balancers and uptime monitors check this. 200 if the app booted.
  get "up" => "rails/health#show", as: :rails_health_check

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
          end
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
