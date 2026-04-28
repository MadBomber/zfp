# frozen_string_literal: true

require "test_helper"

class FfiTest < Minitest::Test
  def setup
    skip "libzfp not installed" unless LIBZFP_PRESENT
  end

  def test_loads_the_zfp_library
    assert_kind_of Module, Zfp::FFI
  end

  %i[
    zfp_stream_open zfp_stream_close zfp_stream_set_bit_stream zfp_stream_rewind
    zfp_stream_set_rate zfp_stream_set_precision zfp_stream_set_accuracy
    zfp_stream_set_reversible zfp_stream_maximum_size
    zfp_compress zfp_decompress
    zfp_field_alloc zfp_field_free zfp_field_set_pointer zfp_field_set_type
    zfp_field_set_size_1d zfp_field_set_size_2d zfp_field_set_size_3d zfp_field_set_size_4d
    stream_open stream_close
  ].each do |fn|
    define_method("test_attaches_#{fn}") do
      assert_respond_to Zfp::FFI, fn
    end
  end
end
