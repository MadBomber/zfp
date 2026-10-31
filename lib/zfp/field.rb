# frozen_string_literal: true

module Zfp
  class Field
    attr_reader :zfp_type_int, :shape

    # Validates that +shape+ is an Array of 1-4 positive Integers.
    # Shared by Codec (at construction) and Field (at allocation).
    def self.validate_shape!(shape)
      unless shape.is_a?(Array) && shape.length.between?(1, 4) &&
             shape.all? { |d| d.is_a?(Integer) && d > 0 }
        raise Zfp::InvalidShape,
          "shape must be an Array of 1–4 positive integers, got #{shape.inspect}"
      end
    end

    # Ruby Arrays and Numo::NArray are row-major: the LAST dimension varies
    # fastest in memory. libzfp's nx is the FASTEST-varying dimension (see
    # zfp FAQ #0), so the shape must be reversed before it is handed to zfp.
    # Callers always work in row-major `shape:`; this is the only place the
    # conversion happens.
    def self.zfp_dimensions(shape)
      shape.reverse
    end

    def initialize(type, shape, buffer)
      self.class.validate_shape!(shape)
      @type         = type
      @shape        = shape
      @buffer       = buffer  # hold reference — prevents GC while field is alive
      @zfp_type_int = Zfp::TypeCoercion::RUBY_TO_ZFP_TYPE[type]
      @ptr = Zfp::FFI.zfp_field_alloc
      raise Zfp::Error, "Failed to allocate zfp_field" if @ptr.null?

      Zfp::FFI.zfp_field_set_pointer(@ptr, buffer)
      Zfp::FFI.zfp_field_set_type(@ptr, @zfp_type_int)
      set_shape(shape)
    end

    def pointer
      @ptr
    end

    def dims
      @shape.length
    end

    def free
      return if @ptr.nil? || @ptr.null?
      Zfp::FFI.zfp_field_free(@ptr)
      @ptr = ::FFI::Pointer::NULL
    end

    private

    def set_shape(shape)
      nx, ny, nz, nw = self.class.zfp_dimensions(shape)
      case shape.length
      when 1 then Zfp::FFI.zfp_field_set_size_1d(@ptr, nx)
      when 2 then Zfp::FFI.zfp_field_set_size_2d(@ptr, nx, ny)
      when 3 then Zfp::FFI.zfp_field_set_size_3d(@ptr, nx, ny, nz)
      when 4 then Zfp::FFI.zfp_field_set_size_4d(@ptr, nx, ny, nz, nw)
      end
    end
  end
end
