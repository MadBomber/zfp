# frozen_string_literal: true

module Zfp
  # Thin value object around a self-describing byte string produced by
  # Zfp.pack / Codec#pack. Anything that accepts a String (via #to_str)
  # also accepts a Packed, including Zfp.unpack and Packer.decode.
  class Packed
    def self.load(path)
      new(File.binread(path))
    end

    def initialize(bytes)
      @bytes = bytes.to_str.dup.freeze
    end

    def to_str
      @bytes
    end
    alias to_s to_str

    def bytesize
      @bytes.bytesize
    end

    def save(path)
      File.binwrite(path, @bytes)
    end

    def unpack
      Zfp.unpack(@bytes)
    end

    def ==(other)
      other.respond_to?(:to_str) && to_str == other.to_str
    end
  end
end
