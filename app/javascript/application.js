// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// todo: direct upload instrad of using rails memory
import * as ActiveStorage from "@rails/activestorage"
ActiveStorage.start()

