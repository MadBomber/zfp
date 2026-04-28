# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "zfp"
require "numo/narray"
require "minitest/autorun"

LIBZFP_PRESENT = system("pkg-config --exists zfp 2>/dev/null") ||
                 system("brew list zfp > /dev/null 2>&1") ||
                 ["/usr/local/lib", "/opt/homebrew/lib", "/usr/lib"].any? do |dir|
                   Dir.glob("#{dir}/libzfp*").any?
                 end
