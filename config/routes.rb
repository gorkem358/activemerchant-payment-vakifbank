Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
  get  '/payment',to: 'payment#payment'
  post  '/purchase',to: 'payment#purchase'
  post  '/purchase-step-two',to: 'payment#purchase_step_two'
  get  '/purchase-result',to: 'payment#purchase_result'
  get  '/acs-service',to: 'payment#acs_service'
  #some routes to let user enter order_id to cancel and cancelling the order
  get '/cancel', to: 'payment#cancel'
end
