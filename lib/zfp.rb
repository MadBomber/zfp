# frozen_string_literal: true

require_relative "zfp/version"
require_relative "zfp/errors"
require_relative "zfp/ffi"
require_relative "zfp/type_coercion"
require_relative "zfp/field"
require_relative "zfp/stream"
require_relative "zfp/packer"
require_relative "zfp/packed"
require_relative "zfp/codec"

module Zfp
  def self.compress(data, type: nil, shape: nil, mode:, **params)
    type  ||= TypeCoercion.detect_type(data)  or raise InvalidType,  "type: required for Ruby Array input"
    shape ||= TypeCoercion.detect_shape(data) or raise InvalidShape, "shape: required for Ruby Array input"
    Codec.new(type: type, shape: shape, mode: mode, **params).compress(data)
  end

  def self.decompress(bytes, type:, shape:, mode:, numo: false, **params)
    Codec.new(type: type, shape: shape, mode: mode, numo: numo, **params).decompress(bytes)
  end

  # Returns a Zfp::Packed: self-describing bytes that #unpack, #save(path),
  # and convert to a String via #to_str. numo: controls what unpack returns
  # later; it defaults to true for Numo::NArray input and false for an Array.
  def self.pack(data, type: nil, shape: nil, mode:, numo: nil, **params)
    type  ||= TypeCoercion.detect_type(data)  or raise InvalidType,  "type: required for Ruby Array input"
    shape ||= TypeCoercion.detect_shape(data) or raise InvalidShape, "shape: required for Ruby Array input"
    as_numo = numo.nil? ? TypeCoercion.numo?(data) : numo
    Codec.new(type: type, shape: shape, mode: mode, numo: as_numo, **params).pack(data, numo: as_numo)
  end

  # Decompresses packed bytes (a String or a Zfp::Packed) back to data.
  def self.unpack(bytes)
    type, shape, mode, params, numo, compressed = Packer.decode(bytes)
    Codec.new(type: type, shape: shape, mode: mode, numo: numo, **params).decompress(compressed)
  end

  # Reads a file written with Zfp::Packed#save. Returns the Zfp::Packed with
  # its metadata intact; call #unpack on it for the data.
  def self.load(path)
    Packed.load(path)
  end
end
