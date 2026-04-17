// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// todo: direct upload instrad of using rails memory
import * as ActiveStorage from "@rails/activestorage"
ActiveStorage.start()

// Controller & Action Name
const controller = document.body.dataset.controller
const action = document.body.dataset.action
if (controller) {
  import(`pages/${controller}`)
}
