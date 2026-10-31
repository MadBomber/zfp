# frozen_string_literal: true

module Zfp
  # A self-describing compressed array: the 32-byte pack header plus the
  # libzfp payload, as produced by Zfp.pack / Codec#pack. The natural unit
  # for persistence — a .zfp file is complete without a sidecar schema.
  #
  #   packed = Zfp.pack(data, type: :double, shape: [252], mode: :reversible)
  #   packed.save("prices.zfp")
  #   Zfp.load("prices.zfp").unpack   # => data
  #
  # Anything that accepts a String via #to_str (File.binwrite, Redis, Zfp.unpack)
  # accepts a Packed directly.
  class Packed
    EXTENSION = ".zfp"

    def self.load(path)
      new(File.binread(path))
    end

    def initialize(bytes)
      @bytes = bytes.to_str.dup.freeze
      Packer.decode_header(@bytes)   # fail fast on bytes that are not a pack
    end

    def to_str
      @bytes
    end
    alias to_s to_str

    def bytesize
      @bytes.bytesize
    end

    # Header fields, read without decompressing.
    def type   = header[:type]
    def shape  = header[:shape]
    def mode   = header[:mode]
    def params = header[:params]
    def numo?  = header[:numo]

    def save(path)
      File.binwrite(path, @bytes)
      path
    end

    def unpack
      Zfp.unpack(@bytes)
    end

    def ==(other)
      other.respond_to?(:to_str) && to_str == other.to_str
    end
    alias eql? ==

    def hash
      @bytes.hash
    end

    def inspect
      "#<Zfp::Packed type=#{type.inspect} shape=#{shape.inspect} mode=#{mode.inspect}" \
        "#{params.empty? ? "" : " #{params.map { |k, v| "#{k}=#{v}" }.join(" ")}"}" \
        "#{numo? ? " numo" : ""} bytesize=#{bytesize}>"
    end

    private

    def header
      @header ||= Packer.decode_header(@bytes)
    end
  end
end
