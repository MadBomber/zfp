# frozen_string_literal: true

require "test_helper"
require "tempfile"

class PackedTest < Minitest::Test
  def setup
    skip "libzfp not installed" unless LIBZFP_PRESENT
    @data   = (1..20).map(&:to_f)
    @bytes  = Zfp.pack(@data, type: :double, shape: [20], mode: :reversible)
    @packed = Zfp::Packed.new(@bytes)
  end

  def test_to_str_returns_the_bytes
    assert_equal @bytes, @packed.to_str
  end

  def test_bytesize
    assert_equal @bytes.bytesize, @packed.bytesize
  end

  def test_unpack_returns_original_data
    assert_equal @data, @packed.unpack
  end

  def test_zfp_unpack_accepts_a_packed
    assert_equal @data, Zfp.unpack(@packed)
  end

  def test_save_and_load_roundtrip
    Tempfile.create(["zfp", ".bin"]) do |f|
      @packed.save(f.path)
      loaded = Zfp::Packed.load(f.path)
      assert_equal @packed, loaded
      assert_equal @data, loaded.unpack
    end
  end

  def test_bytes_are_frozen_and_independent_of_input
    original = @bytes.dup
    @bytes << "trailing"
    assert_equal original, @packed.to_str
    assert @packed.to_str.frozen?
  end

  def test_equality_with_plain_string
    assert_equal @packed, @packed.to_str
  end
end
