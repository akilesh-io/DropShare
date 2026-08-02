Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  mount MissionControl::Jobs::Engine, at: "/jobs"

  root "drop#index"
  resources :drop, only: [:index, :new, :create] do
    member do
      delete :destroy_koppurai
      delete :destroy_koppu
    end
  end
  share_key_format = /[A-Za-z0-9_-]{14}/
  get "/f/:share_key",        to: "share#download_koppu",    as: :download_koppu, constraints: { share_key: share_key_format }
  get "/:share_key",          to: "share#index",             as: :share,          constraints: { share_key: share_key_format }
  # todo: implement zip download for folder
  # get "/d/:share_key",        to: "share#download_koppurai", as: :download_koppurai
end
