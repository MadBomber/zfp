# frozen_string_literal: true

module Zfp
  class Stream
    def initialize(mode, params)
      @mode   = mode
      @params = params
    end

    def compress(field)
      zfp_ptr = bitstream = output_buf = nil
      zfp_ptr = open_zfp_stream
      apply_mode(zfp_ptr, field)
      bufsize    = Zfp::FFI.zfp_stream_maximum_size(zfp_ptr, field.pointer)
      output_buf = ::FFI::MemoryPointer.new(:uint8, bufsize)
      bitstream  = Zfp::FFI.stream_open(output_buf, bufsize)
      Zfp::FFI.zfp_stream_set_bit_stream(zfp_ptr, bitstream)
      Zfp::FFI.zfp_stream_rewind(zfp_ptr)
      written = Zfp::FFI.zfp_compress(zfp_ptr, field.pointer)
      raise Zfp::CompressionFailed, "zfp_compress returned 0" if written == 0
      output_buf.read_bytes(written)
    ensure
      Zfp::FFI.stream_close(bitstream) if bitstream && !bitstream.null?
      Zfp::FFI.zfp_stream_close(zfp_ptr) if zfp_ptr && !zfp_ptr.null?
    end

    # libzfp's bitstream has no bounds checking: it reads as many words as the
    # field requires, regardless of how many bytes the caller supplied. The
    # input is therefore copied into a zero-filled buffer at least as large as
    # the worst-case stream size, so a short or corrupt input can never read
    # past the end of the buffer.
    def decompress(field, compressed_bytes)
      zfp_ptr = bitstream = input_buf = nil
      raise Zfp::DecompressionFailed, "no compressed bytes given" if compressed_bytes.bytesize.zero?

      zfp_ptr = open_zfp_stream
      apply_mode(zfp_ptr, field)
      validate_input_size!(compressed_bytes.bytesize, field)
      max_size  = Zfp::FFI.zfp_stream_maximum_size(zfp_ptr, field.pointer)
      bufsize   = [max_size, compressed_bytes.bytesize].max
      input_buf = ::FFI::MemoryPointer.new(:uint8, bufsize)  # zero-filled
      input_buf.put_bytes(0, compressed_bytes)
      bitstream = Zfp::FFI.stream_open(input_buf, bufsize)
      Zfp::FFI.zfp_stream_set_bit_stream(zfp_ptr, bitstream)
      Zfp::FFI.zfp_stream_rewind(zfp_ptr)
      read = Zfp::FFI.zfp_decompress(zfp_ptr, field.pointer)
      raise Zfp::DecompressionFailed, "zfp_decompress returned 0" if read == 0
    ensure
      Zfp::FFI.stream_close(bitstream) if bitstream && !bitstream.null?
      Zfp::FFI.zfp_stream_close(zfp_ptr) if zfp_ptr && !zfp_ptr.null?
    end

    # The rate libzfp actually applied in the last fixed_rate call. libzfp
    # rounds the requested rate up to its per-block minimum, so this can be
    # higher than params[:rate]. nil for the other modes.
    attr_reader :actual_rate

    # Exact compressed size of a fixed_rate stream for +field+:
    # blocks * bits_per_block, rounded up to a 64-bit stream word.
    def fixed_rate_size(field)
      blocks         = field.shape.reduce(1) { |acc, d| acc * ((d + 3) / 4) }
      bits_per_block = (@actual_rate * (4**field.dims)).round
      words          = (blocks * bits_per_block + 63) / 64
      words * 8
    end

    private

    def open_zfp_stream
      ptr = Zfp::FFI.zfp_stream_open(nil)
      raise Zfp::Error, "Failed to allocate zfp_stream" if ptr.null?
      ptr
    end

    # In fixed-rate mode the compressed size is fully determined by the shape
    # and the applied rate, so a shorter input is provably truncated. The
    # variable-rate modes have no such invariant; for them the zero padding in
    # #decompress is the only protection.
    def validate_input_size!(actual, field)
      return unless @mode == :fixed_rate
      expected = fixed_rate_size(field)
      return if actual >= expected
      raise Zfp::DecompressionFailed,
        "fixed_rate stream is truncated: expected #{expected} bytes, got #{actual}"
    end

    def apply_mode(zfp_ptr, field)
      case @mode
      when :fixed_rate
        @actual_rate = Zfp::FFI.zfp_stream_set_rate(zfp_ptr, @params[:rate].to_f,
                                                    field.zfp_type_int, field.dims, 0)
      when :fixed_precision
        Zfp::FFI.zfp_stream_set_precision(zfp_ptr, @params[:precision])
      when :fixed_accuracy
        Zfp::FFI.zfp_stream_set_accuracy(zfp_ptr, @params[:tolerance].to_f)
      when :reversible
        Zfp::FFI.zfp_stream_set_reversible(zfp_ptr)
      else
        raise Zfp::InvalidMode, "Unknown mode: #{@mode}"
      end
    end
  end
end
