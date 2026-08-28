// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
// import "@hotwired/turbo-rails"
import "components"

// Controller & Action Name
const controller = document.body.dataset.controller
const action = document.body.dataset.action
if (controller) {
  import(`pages/${controller}`).catch(error => {
    console.error(`Could not load pages/${controller}`, error)
  })
}
