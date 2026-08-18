# Be sure to restart your server when you modify this file.

# Folder downloads store already-compressed uploads verbatim (see
# ShareController::STORED_CONTENT_TYPES), so deflate only ever runs on the
# text-ish leftovers. Trade a few percent of ratio for a much faster archive.
Zip.default_compression = Zlib::BEST_SPEED
