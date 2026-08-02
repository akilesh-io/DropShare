# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_02_120000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "koppurais", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "downloads_count"
    t.datetime "expires_at"
    t.string "session_id"
    t.string "share_key", null: false
    t.string "title"
    t.bigint "total_size"
    t.datetime "updated_at", null: false
    t.index ["session_id"], name: "index_koppurais_on_session_id"
    t.index ["share_key"], name: "index_koppurais_on_share_key", unique: true
  end

  create_table "koppus", force: :cascade do |t|
    t.bigint "byte_size"
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.integer "downloads_count"
    t.integer "koppurai_id", null: false
    t.string "share_key", null: false
    t.datetime "updated_at", null: false
    t.index ["koppurai_id"], name: "index_koppus_on_koppurai_id"
    t.index ["share_key"], name: "index_koppus_on_share_key", unique: true
  end

  create_table "stats", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "current_size"
    t.integer "current_uploads"
    t.bigint "lifetime_size"
    t.integer "lifetime_uploads"
    t.integer "total_downloads"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "koppus", "koppurais"
end
