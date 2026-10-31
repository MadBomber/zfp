# frozen_string_literal: true

require "test_helper"
require "rbconfig"

# Numo is loaded in the test process, so the "numo-narray not installed" path
# is exercised in a child Ruby whose +require+ refuses to load it.
class NumoAvailabilityTest < Minitest::Test
  LIB = File.expand_path("../../lib", __dir__)

  STUB = <<~RUBY
    module NoNumo
      def require(name) = name.start_with?("numo") ? raise(LoadError, "cannot load such file -- \#{name}") : super
    end
    Kernel.prepend(NoNumo)
    require "zfp"
  RUBY

  def run_without_numo(code)
    out = IO.popen([RbConfig.ruby, "-I#{LIB}", "-e", STUB + code], err: [:child, :out], &:read)
    [out.strip, $?.success?]
  end

  def setup
    skip "libzfp not installed" unless LIBZFP_PRESENT
  end

  def test_decompress_numo_true_raises_numo_not_available
    out, = run_without_numo(<<~RUBY)
      b = Zfp.compress([1.0, 2.0, 3.0, 4.0], type: :double, shape: [4], mode: :reversible)
      begin
        Zfp.decompress(b, type: :double, shape: [4], mode: :reversible, numo: true)
        puts "NO RAISE"
      rescue Zfp::NumoNotAvailable => e
        puts e.class
      end
    RUBY
    assert_equal "Zfp::NumoNotAvailable", out
  end

  def test_unpack_of_numo_flagged_bytes_raises_numo_not_available
    out, = run_without_numo(<<~RUBY)
      packed = Zfp.pack([1.0, 2.0], type: :double, shape: [2], mode: :reversible, numo: true)
      begin
        Zfp.unpack(packed)
        puts "NO RAISE"
      rescue Zfp::NumoNotAvailable => e
        puts e.class
      end
    RUBY
    assert_equal "Zfp::NumoNotAvailable", out
  end

  def test_ruby_array_paths_work_without_numo
    out, ok = run_without_numo(<<~RUBY)
      packed = Zfp.pack([1.0, 2.0], type: :double, shape: [2], mode: :reversible)
      p packed.unpack
    RUBY
    assert ok, out
    assert_equal "[1.0, 2.0]", out
  end
end
