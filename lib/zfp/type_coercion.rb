# frozen_string_literal: true

module Zfp
  module TypeCoercion
    RUBY_TO_ZFP_TYPE = {
      int32:  Zfp::FFI::ZFP_TYPE_INT32,
      int64:  Zfp::FFI::ZFP_TYPE_INT64,
      float:  Zfp::FFI::ZFP_TYPE_FLOAT,
      double: Zfp::FFI::ZFP_TYPE_DOUBLE
    }.freeze

    PACK_FORMAT = {
      float:  "e*",
      double: "E*",
      int32:  "l<*",
      int64:  "q<*"
    }.freeze

    ELEMENT_SIZE = {
      float:  4,
      double: 8,
      int32:  4,
      int64:  8
    }.freeze

    INTEGER_RANGE = {
      int32: (-2**31)..(2**31 - 1),
      int64: (-2**63)..(2**63 - 1)
    }.freeze

    class << self
      def detect_type(data)
        return nil unless numo?(data)
        case data
        when Numo::SFloat then :float
        when Numo::DFloat then :double
        when Numo::Int32  then :int32
        when Numo::Int64  then :int64
        else raise Zfp::InvalidType, "Unsupported Numo type: #{data.class}"
        end
      end

      def detect_shape(data)
        return nil unless numo?(data)
        data.shape
      end

      def numo?(data)
        defined?(Numo::NArray) && data.is_a?(Numo::NArray)
      end

      # Loads numo-narray on demand. Raises Zfp::NumoNotAvailable if the gem
      # is not installed, so callers never see a bare NameError.
      def ensure_numo!
        return if defined?(Numo::NArray)
        begin
          require "numo/narray"
        rescue LoadError
          raise Zfp::NumoNotAvailable,
            "Numo output requested but the numo-narray gem is not installed (gem install numo-narray)"
        end
      end

      # Flattens +data+ (Array or Numo::NArray) into a packed FFI buffer.
      # When +shape+ is given, the element count must equal its product;
      # a mismatch would otherwise make libzfp read or write past the buffer.
      def to_buffer(data, type, shape = nil)
        values = flatten_values(data)
        validate_count!(values, shape) if shape
        validate_integers!(values, type) if INTEGER_RANGE.key?(type)
        fmt    = PACK_FORMAT.fetch(type) { raise Zfp::InvalidType, "Unknown type: #{type}" }
        packed = values.pack(fmt)
        ptr    = ::FFI::MemoryPointer.new(:uint8, packed.bytesize)
        ptr.put_bytes(0, packed)
        ptr
      end

      def from_buffer(ptr, type, shape, as_numo)
        as_numo ? buffer_to_numo(ptr, type, shape) : buffer_to_array(ptr, type, shape)
      end

      private

      def flatten_values(data)
        return data.to_a.flatten if numo?(data)
        return data.flatten      if data.is_a?(Array)
        raise Zfp::InvalidType, "data must be an Array or Numo::NArray, got #{data.class}"
      end

      def validate_count!(values, shape)
        expected = shape.reduce(:*)
        return if values.length == expected
        raise Zfp::InvalidShape,
          "shape #{shape.inspect} describes #{expected} elements but data has #{values.length}"
      end

      def validate_integers!(values, type)
        range = INTEGER_RANGE[type]
        bad   = values.find { |v| !v.is_a?(Integer) || !range.cover?(v) }
        return unless bad
        raise Zfp::InvalidType,
          "#{type} data must be Integers in #{range.min}..#{range.max}, got #{bad.inspect}"
      end

      def buffer_to_array(ptr, type, shape)
        count = shape.reduce(:*)
        bytes = ptr.read_bytes(count * ELEMENT_SIZE[type])
        bytes.unpack(PACK_FORMAT[type])
      end

      def buffer_to_numo(ptr, type, shape)
        ensure_numo!
        count = shape.reduce(:*)
        bytes = ptr.read_bytes(count * ELEMENT_SIZE[type])
        array = bytes.unpack(PACK_FORMAT[type])
        numo_class_for(type).cast(array).reshape(*shape)
      end

      def numo_class_for(type)
        case type
        when :float  then Numo::SFloat
        when :double then Numo::DFloat
        when :int32  then Numo::Int32
        when :int64  then Numo::Int64
        else raise Zfp::InvalidType, "Unknown type: #{type}"
        end
      end
    end
  end
end
