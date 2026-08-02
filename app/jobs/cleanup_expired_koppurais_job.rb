class CleanupExpiredKoppuraisJob < ApplicationJob
  queue_as :default

  def perform
    Koppurai.where(expires_at: ..Time.current).find_each(&:destroy)
  end
end
