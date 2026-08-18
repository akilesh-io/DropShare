Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  mount MissionControl::Jobs::Engine, at: "/jobs"

  root "drop#index"
  resources :drop, only: [:index,  :create] do
    member do
      delete :destroy_koppurai
      delete :destroy_koppu
    end
  end
  post "/drop/new", to: "drop#new", as: :new_drop

  # Resumable uploads, over the tus protocol: https://tus.io
  post    "/tus"        => "tus_uploads#create",  as: :tus_uploads
  get     "/tus/:token" => "tus_uploads#show",    as: :tus_upload
  patch   "/tus/:token" => "tus_uploads#update"
  delete  "/tus/:token" => "tus_uploads#destroy"
  match   "/tus(/:token)" => "tus_uploads#protocol_options", via: :options
  share_key_format = /[A-Za-z0-9_-]{4,14}/
  get "/f/:share_key",        to: "share#download_koppu",    as: :download_koppu, constraints: { share_key: share_key_format }
  get "/t/:share_key",        to: "share#text_preview",     as: :text_preview,  constraints: { share_key: share_key_format }
  get "/d/:share_key",        to: "share#download_folder", as: :download_folder, constraints: { share_key: share_key_format }
  get "/:share_key",          to: "share#index",             as: :share,          constraints: { share_key: share_key_format }
end
