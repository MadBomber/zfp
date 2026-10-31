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

  # numo: controls what Zfp.unpack returns later. It defaults to true for
  # Numo::NArray input and false for a Ruby Array.
  def self.pack(data, type: nil, shape: nil, mode:, numo: nil, **params)
    type  ||= TypeCoercion.detect_type(data)  or raise InvalidType,  "type: required for Ruby Array input"
    shape ||= TypeCoercion.detect_shape(data) or raise InvalidShape, "shape: required for Ruby Array input"
    as_numo = numo.nil? ? TypeCoercion.numo?(data) : numo
    Codec.new(type: type, shape: shape, mode: mode, numo: as_numo, **params).pack(data, numo: as_numo)
  end

  def self.unpack(bytes)
    type, shape, mode, params, numo, compressed = Packer.decode(bytes)
    Codec.new(type: type, shape: shape, mode: mode, numo: numo, **params).decompress(compressed)
  end
end
