# frozen_string_literal: true

module Zfp
  module Packer
    # Header version 2 (zfp gem 0.2.0+): shape is row-major and the gem
    # reverses it for libzfp. Version 1 (0.1.0) passed shape[0] to libzfp as
    # nx, i.e. transposed, so multi-dimensional v1 streams cannot be decoded
    # with the corrected layout. 1-D v1 streams are identical and still load.
    MAGIC        = "ZFP\x02"
    LEGACY_MAGIC = "ZFP\x01"
    HEADER_LEN   = 32
    PACK_FMT     = "a4CCCCVVVVE"

    TYPE_TO_BYTE = { float: 0, double: 1, int32: 2, int64: 3 }.freeze
    BYTE_TO_TYPE = TYPE_TO_BYTE.invert.freeze

    MODE_TO_BYTE = { fixed_rate: 0, fixed_precision: 1, fixed_accuracy: 2, reversible: 3 }.freeze
    BYTE_TO_MODE = MODE_TO_BYTE.invert.freeze

    def self.encode(compressed_bytes, type:, shape:, mode:, params: {}, numo: false)
      flags  = numo ? 1 : 0
      dims   = shape.length
      dim0, dim1, dim2, dim3 = Array.new(4) { |i| shape[i].to_i }
      param  = extract_param(mode, params)
      header = [MAGIC, TYPE_TO_BYTE[type], MODE_TO_BYTE[mode], dims, flags,
                dim0, dim1, dim2, dim3, param].pack(PACK_FMT)
      header + compressed_bytes
    end

    # => [type, shape, mode, params, numo, compressed_data]
    def self.decode(bytes)
      bytes = bytes.to_str
      h = decode_header(bytes)
      [h[:type], h[:shape], h[:mode], h[:params], h[:numo], bytes[HEADER_LEN..]]
    end

    # Parses only the 32-byte header, without touching the payload.
    # Raises Zfp::PackerError if +bytes+ is not a pack this version can read.
    def self.decode_header(bytes)
      bytes = bytes.to_str
      if bytes.bytesize < HEADER_LEN
        raise Zfp::PackerError, "truncated header (#{bytes.bytesize} < #{HEADER_LEN} bytes)"
      end

      magic, type_b, mode_b, rank, flags, d0, d1, d2, d3, param =
        bytes[0, HEADER_LEN].unpack(PACK_FMT)

      validate_magic!(magic, rank)

      type = BYTE_TO_TYPE.fetch(type_b) { raise Zfp::PackerError, "unknown type byte #{type_b}" }
      mode = BYTE_TO_MODE.fetch(mode_b) { raise Zfp::PackerError, "unknown mode byte #{mode_b}" }
      {
        type:   type,
        shape:  [d0, d1, d2, d3].first(rank),
        mode:   mode,
        params: decode_params(mode, param),
        numo:   flags & 1 == 1
      }
    end

    private_class_method def self.validate_magic!(magic, rank)
      return if magic == MAGIC
      if magic == LEGACY_MAGIC
        return if rank == 1
        raise Zfp::PackerError,
          "#{rank}-D data packed by zfp gem 0.1.0 used a transposed dimension order " \
          "and cannot be unpacked by this version; unpack with 0.1.0 and re-pack"
      end
      raise Zfp::PackerError, "bad magic bytes (expected ZFP\\x02)"
    end

    private_class_method def self.extract_param(mode, params)
      case mode
      when :fixed_rate      then params[:rate].to_f
      when :fixed_precision then params[:precision].to_f
      when :fixed_accuracy  then params[:tolerance].to_f
      else 0.0
      end
    end

    private_class_method def self.decode_params(mode, param)
      case mode
      when :fixed_rate      then { rate: param }
      when :fixed_precision then { precision: param.round }
      when :fixed_accuracy  then { tolerance: param }
      else {}
      end
    end
  end
end
