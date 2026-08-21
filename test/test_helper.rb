ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Builds the records the tests work with. A Koppu is a row plus an Active Storage
# attachment, and the two are made together the same way DropController#create makes
# them, so what a test holds is what the app would have stored.
module RecordHelpers
  def create_koppurai(expires_at: Rails.configuration.FILE_EXPIRY_DAYS.days.from_now, session_id: SecureRandom.uuid, **attributes)
    Koppurai.create! expires_at: expires_at, session_id: session_id, **attributes
  end

  def create_koppu(koppurai: nil, filename: "hello.txt", content: "hello world", content_type: "text/plain")
    koppurai ||= create_koppurai
    blob = create_blob(filename: filename, content: content, content_type: content_type)

    koppu = koppurai.koppus.new byte_size: blob.byte_size, content_type: blob.content_type, checksum: blob.checksum
    koppu.koppu.attach blob
    koppu.save!

    koppu
  end

  def create_blob(filename: "hello.txt", content: "hello world", content_type: "text/plain")
    ActiveStorage::Blob.create_and_upload! io: StringIO.new(content), filename: filename,
      content_type: content_type, identify: content_type.nil?
  end

  # Both constants stand for sizes a test would rather not actually build -- a hundred
  # files, or five gigabytes -- so a test that needs to reach one of them borrows a
  # smaller value for the length of a block. Tests run in forked processes, so the
  # change is never seen by another test.
  def with_constant(owner, name, value)
    original = owner.const_get(name)
    owner.send :remove_const, name
    owner.const_set name, value

    yield
  ensure
    owner.send :remove_const, name
    owner.const_set name, original
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include RecordHelpers

    # Add more helper methods to be used by all tests here...
  end
end
