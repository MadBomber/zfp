# frozen_string_literal: true

module Zfp
  class Codec
    VALID_TYPES   = %i[float double int32 int64].freeze
    VALID_MODES   = %i[fixed_rate fixed_precision fixed_accuracy reversible].freeze
    INTEGER_TYPES = %i[int32 int64].freeze

    def initialize(type:, shape:, mode:, numo: false, **params)
      validate_type!(type)
      validate_mode!(mode)
      validate_type_mode!(type, mode)
      Field.validate_shape!(shape)
      validate_params!(mode, params)
      @type   = type
      @shape  = shape
      @mode   = mode
      @params = params
      @numo   = numo
    end

    def compress(data)
      buf   = TypeCoercion.to_buffer(data, @type, @shape)
      field = Field.new(@type, @shape, buf)
      Stream.new(@mode, @params).compress(field)
    ensure
      field&.free
    end

    def decompress(bytes)
      count     = @shape.reduce(:*)
      elem_size = TypeCoercion::ELEMENT_SIZE[@type]
      out_buf   = ::FFI::MemoryPointer.new(:uint8, count * elem_size)
      field     = Field.new(@type, @shape, out_buf)
      Stream.new(@mode, @params).decompress(field, bytes)
      TypeCoercion.from_buffer(out_buf, @type, @shape, @numo)
    ensure
      field&.free
    end

    # numo: overrides what Zfp.unpack will return later. By default a Numo
    # input (or a codec built with numo: true) unpacks to Numo.
    def pack(data, numo: nil)
      as_numo    = numo.nil? ? (@numo || TypeCoercion.numo?(data)) : numo
      compressed = compress(data)
      Packer.encode(compressed, type: @type, shape: @shape, mode: @mode,
                    params: @params, numo: as_numo)
    end

    private

    def validate_type!(type)
      raise Zfp::InvalidType, "Unknown type: #{type.inspect}. Valid: #{VALID_TYPES}" \
        unless VALID_TYPES.include?(type)
    end

    def validate_mode!(mode)
      raise Zfp::InvalidMode, "Unknown mode: #{mode.inspect}. Valid: #{VALID_MODES}" \
        unless VALID_MODES.include?(mode)
    end

    # Integer types are lossless by nature; the gem supports them in
    # :reversible mode only, as documented.
    def validate_type_mode!(type, mode)
      return unless INTEGER_TYPES.include?(type) && mode != :reversible
      raise Zfp::InvalidMode,
        "#{type} supports mode: :reversible only (got #{mode.inspect})"
    end

    def validate_params!(mode, params)
      case mode
      when :fixed_rate
        raise Zfp::InvalidParams, "fixed_rate requires rate: (Float > 0)" \
          unless params[:rate]&.to_f&.positive?
      when :fixed_precision
        raise Zfp::InvalidParams, "fixed_precision requires precision: (Integer > 0)" \
          unless params[:precision].is_a?(Integer) && params[:precision] > 0
      when :fixed_accuracy
        raise Zfp::InvalidParams, "fixed_accuracy requires tolerance: (Float > 0)" \
          unless params[:tolerance]&.to_f&.positive?
      end
    end
  end
end
