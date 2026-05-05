// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "pages/uploads"

// Controller & Action Name
const controller = document.body.dataset.controller
const action = document.body.dataset.action
if (controller) {
  import(`pages/${controller}`)
}
