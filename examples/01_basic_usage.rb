#!/usr/bin/env ruby
# frozen_string_literal: true
#
# 01_basic_usage.rb — ZFP gem basic usage examples
#
# Covers:
#   1. compress / decompress  — raw bytes, all four scalar types, 1-D
#   2. Multi-dimensional shapes — 1-D through 4-D
#   3. Compression modes       — reversible, fixed_rate, fixed_precision, fixed_accuracy
#   4. pack / unpack           — self-describing bytes, no external metadata needed
#   5. Numo::NArray            — all four Numo types, auto-detect, numo: true output
#   6. Codec object            — reusable codec across many arrays

$LOAD_PATH.unshift File.join(__dir__, "..", "lib")

require "zfp"
require "numo/narray"

BYTES_PER = { float: 4, double: 8, int32: 4, int64: 8 }.freeze

# ─── Display helpers ─────────────────────────────────────────────────────────

def banner(title)
  puts
  puts "═" * 72
  puts "  #{title}"
  puts "═" * 72
end

def section(title)
  puts
  puts "  #{title}"
  puts "  " + ("─" * 62)
end

def fmt_bytes(n)
  n >= 1024 ? format("%.1f KB", n / 1024.0) : "#{n} B"
end

def result_line(label, n_elements, type, compressed_size, original, restored)
  raw   = n_elements * BYTES_PER[type]
  ratio = format("%.1fx", raw.to_f / compressed_size)

  orig_a = original.is_a?(Numo::NArray) ? original.to_a.flatten : Array(original).flatten
  rest_a = restored.is_a?(Numo::NArray) ? restored.to_a.flatten : Array(restored).flatten
  err    = orig_a.zip(rest_a).map { |a, b| (a.to_f - b.to_f).abs }.max || 0.0
  acc    = err == 0.0 ? "exact     " : format("max_err=%.2e", err)

  puts format("  %-36s  %8s → %7s  %5s  [%s]",
    label, fmt_bytes(raw), fmt_bytes(compressed_size), ratio, acc)
end

# ─────────────────────────────────────────────────────────────────────────────
banner "ZFP GEM — BASIC USAGE EXAMPLES"

# ═════════════════════════════════════════════════════════════════════════════
banner "1.  compress / decompress — raw bytes API, all scalar types"
# ═════════════════════════════════════════════════════════════════════════════
#
# Zfp.compress returns a plain String of compressed bytes.
# Zfp.decompress returns a Ruby Array.
# The caller is responsible for keeping track of type, shape, and mode.
#
# Syntax:
#   bytes  = Zfp.compress(data, type:, shape:, mode:, **params)
#   result = Zfp.decompress(bytes, type:, shape:, mode:, **params)

section "All four scalar types · shape=[128] · mode=:reversible"

FLOAT_DATA  = (1..128).map { |i| i * 1.5 }
INT_DATA_32 = (1..128).to_a
INT_DATA_64 = (1..128).map { |i| i * 1_000_000_000 }

{ float:  FLOAT_DATA,
  double: FLOAT_DATA,
  int32:  INT_DATA_32,
  int64:  INT_DATA_64 }.each do |type, data|
  bytes  = Zfp.compress(data, type: type, shape: [128], mode: :reversible)
  result = Zfp.decompress(bytes, type: type, shape: [128], mode: :reversible)
  result_line("type=:#{type}, shape=[128]", 128, type, bytes.bytesize, data, result)
end

# ═════════════════════════════════════════════════════════════════════════════
banner "2.  Multi-dimensional shapes — 1-D through 4-D"
# ═════════════════════════════════════════════════════════════════════════════
#
# ZFP natively understands array dimensionality up to 4-D.
# Passing the correct shape lets it exploit spatial correlations across all axes.

section "type=:double · mode=:reversible · 256 elements, four layouts"

[
  [256],
  [16, 16],
  [4, 8, 8],
  [4, 4, 4, 4],
].each do |shape|
  n     = shape.reduce(:*)
  data  = (1..n).map { |i| Math.sin(i * 0.05) * 100 }
  bytes = Zfp.compress(data, type: :double, shape: shape, mode: :reversible)
  back  = Zfp.decompress(bytes, type: :double, shape: shape, mode: :reversible)
  dims  = "#{shape.length}-D  #{shape.inspect}"
  result_line(dims, n, :double, bytes.bytesize, data, back)
end

# ═════════════════════════════════════════════════════════════════════════════
banner "3.  Compression modes — tradeoff between ratio and accuracy"
# ═════════════════════════════════════════════════════════════════════════════
#
# :reversible      — bit-exact lossless (all types)
# :fixed_rate      — fixed bits-per-value; rate: controls the ratio
# :fixed_precision — fixed significant bits; precision: controls accuracy
# :fixed_accuracy  — absolute error bound; tolerance: controls max error
#
# Note: :fixed_rate / :fixed_precision / :fixed_accuracy are for float/double only.
# Integer types (:int32, :int64) support :reversible only.

section "Same 256-element sinusoidal dataset · type=:double · shape=[256]"

n    = 256
data = (1..n).map { |i| Math.sin(i * 0.05) * 1_000.0 }

[
  { label: "reversible  (lossless)",            mode: :reversible,      params: {}                  },
  { label: "fixed_rate      rate: 8.0",         mode: :fixed_rate,      params: { rate: 8.0 }       },
  { label: "fixed_rate      rate: 4.0",         mode: :fixed_rate,      params: { rate: 4.0 }       },
  { label: "fixed_rate      rate: 2.0",         mode: :fixed_rate,      params: { rate: 2.0 }       },
  { label: "fixed_precision precision: 24",     mode: :fixed_precision, params: { precision: 24 }   },
  { label: "fixed_precision precision: 12",     mode: :fixed_precision, params: { precision: 12 }   },
  { label: "fixed_accuracy  tolerance: 0.001",  mode: :fixed_accuracy,  params: { tolerance: 0.001 }},
  { label: "fixed_accuracy  tolerance: 0.1",    mode: :fixed_accuracy,  params: { tolerance: 0.1 }  },
  { label: "fixed_accuracy  tolerance: 1.0",    mode: :fixed_accuracy,  params: { tolerance: 1.0 }  },
].each do |spec|
  bytes = Zfp.compress(data, type: :double, shape: [n], mode: spec[:mode], **spec[:params])
  back  = Zfp.decompress(bytes, type: :double, shape: [n], mode: spec[:mode], **spec[:params])
  result_line(spec[:label], n, :double, bytes.bytesize, data, back)
end

# ═════════════════════════════════════════════════════════════════════════════
banner "4.  pack / unpack — self-describing bytes, no metadata bookkeeping"
# ═════════════════════════════════════════════════════════════════════════════
#
# Zfp.pack embeds type, shape, mode, and params into the byte string.
# Zfp.unpack reconstructs the array with no additional arguments.
# The return type mirrors the input: Ruby Array in → Ruby Array out,
# Numo::NArray in → Numo::NArray out.
#
# Syntax:
#   packed = Zfp.pack(data, type:, shape:, mode:, **params)  # or omit type/shape for Numo
#   result = Zfp.unpack(packed)

section "Ruby Array → pack → unpack (type/shape/mode stored in bytes)"

data   = (1..100).map { |i| Math.cos(i * 0.1) * 500 }
packed = Zfp.pack(data, type: :double, shape: [100], mode: :reversible)
result = Zfp.unpack(packed)

puts "  Input:  Ruby Array[100] of Float"
puts "  Packed: #{fmt_bytes(packed.bytesize)}  (includes 32-byte header with metadata)"
puts "  Output: #{result.class}[#{result.size}]"
result_line("Array[100] :double :reversible", 100, :double, packed.bytesize, data, result)

section "Ruby Array of integers → pack → unpack"

idata  = (1..100).map { |i| i * 7 }
packed = Zfp.pack(idata, type: :int32, shape: [100], mode: :reversible)
result = Zfp.unpack(packed)

puts "  Input:  Ruby Array[100] of Integer"
puts "  Output: #{result.class}[#{result.size}]  match=#{idata == result}"
result_line("Array[100] :int32  :reversible", 100, :int32, packed.bytesize, idata, result)

section "Numo::DFloat → pack → unpack (type and shape auto-detected)"

na     = Numo::DFloat.cast((1..200).map { |i| Math.log(i + 1) }).reshape(10, 20)
packed = Zfp.pack(na, mode: :reversible)
result = Zfp.unpack(packed)

puts "  Input:  Numo::DFloat#{na.shape}  (shape inferred — no shape: arg needed)"
puts "  Packed: #{fmt_bytes(packed.bytesize)}"
puts "  Output: #{result.class}#{result.shape}"
result_line("DFloat[10,20] :double :reversible", 200, :double, packed.bytesize, na, result)

section "Lossy pack — fixed_accuracy, self-describing tolerance stored in bytes"

data   = (1..256).map { |i| Math.sin(i * 0.1) * 100 }
packed = Zfp.pack(data, type: :double, shape: [256], mode: :fixed_accuracy, tolerance: 0.01)
result = Zfp.unpack(packed)

puts "  pack(tolerance: 0.01)  stored in header → unpack needs no args"
result_line("Array[256] :double :fixed_accuracy", 256, :double, packed.bytesize, data, result)

# ═════════════════════════════════════════════════════════════════════════════
banner "5.  Numo::NArray — all four types, auto-detect, numo: true output"
# ═════════════════════════════════════════════════════════════════════════════
#
# compress / decompress accept and return Numo arrays when:
#   - input is a Numo::NArray  → type and shape inferred automatically
#   - decompress(..., numo: true) → returns Numo::NArray instead of Ruby Array

section "All four Numo array types, compress / decompress roundtrip"

{
  Numo::SFloat => { type: :float,  n: 64,  data_fn: ->(n) { Numo::SFloat.cast((1..n).map { |i| i * 1.5 }) }  },
  Numo::DFloat => { type: :double, n: 64,  data_fn: ->(n) { Numo::DFloat.cast((1..n).map { |i| i * 1.5 }) }  },
  Numo::Int32  => { type: :int32,  n: 64,  data_fn: ->(n) { Numo::Int32.cast((1..n).to_a) }                   },
  Numo::Int64  => { type: :int64,  n: 64,  data_fn: ->(n) { Numo::Int64.cast((1..n).map { |i| i * 10_000 }) } },
}.each do |numo_class, spec|
  na     = spec[:data_fn].call(spec[:n])
  type   = spec[:type]
  bytes  = Zfp.compress(na, mode: :reversible)                                          # type/shape auto-detected
  result = Zfp.decompress(bytes, type: type, shape: [spec[:n]], mode: :reversible, numo: true)
  label  = "#{numo_class}[#{spec[:n]}]  →  #{result.class}"
  result_line(label, spec[:n], type, bytes.bytesize, na, result)
end

section "Multi-dimensional Numo arrays (2-D, 3-D)"

{
  "DFloat[16,16]  2-D" => Numo::DFloat.cast((1..256).map { |i| Math.sin(i * 0.05) * 50 }).reshape(16, 16),
  "DFloat[4,4,16] 3-D" => Numo::DFloat.cast((1..256).map { |i| Math.cos(i * 0.05) * 50 }).reshape(4, 4, 16),
}.each do |label, na|
  bytes  = Zfp.compress(na, mode: :reversible)
  result = Zfp.decompress(bytes, type: :double, shape: na.shape, mode: :reversible, numo: true)
  puts format("  %-28s  bytes=%s → %s  output: #{result.class}#{result.shape}",
    label, fmt_bytes(na.size * 8), fmt_bytes(bytes.bytesize))
end

section "Ruby Array input → numo: true → Numo output"

data   = (1..64).map { |i| i * Math::PI }
bytes  = Zfp.compress(data, type: :double, shape: [64], mode: :reversible)
result = Zfp.decompress(bytes, type: :double, shape: [64], mode: :reversible, numo: true)

puts "  Input:  Ruby Array[64]"
puts "  Output: #{result.class}#{result.shape}  (numo: true promotes output to Numo::DFloat)"

# ═════════════════════════════════════════════════════════════════════════════
banner "6.  Zfp::Codec object — reuse one codec across many arrays"
# ═════════════════════════════════════════════════════════════════════════════
#
# Construct a Codec once with fixed type/shape/mode/params.
# Call codec.compress / codec.decompress for raw bytes.
# Call codec.pack to get self-describing bytes (use Zfp.unpack to decode).

section "compress / decompress — three datasets through one codec"

codec = Zfp::Codec.new(type: :double, shape: [100], mode: :fixed_accuracy, tolerance: 0.001)
puts "  Codec: type=:double, shape=[100], mode=:fixed_accuracy, tolerance: 0.001\n\n"

3.times do |k|
  data   = (1..100).map { |i| Math.sin(i * 0.1 * (k + 1)) * 500 }
  bytes  = codec.compress(data)
  result = codec.decompress(bytes)
  err    = data.zip(result).map { |a, b| (a - b).abs }.max
  puts format("  dataset %-2d  raw=%s → %s  (%.1fx)  max_err=%.5f",
    k + 1, fmt_bytes(800), fmt_bytes(bytes.bytesize), 800.0 / bytes.bytesize, err)
end

section "pack via Codec — self-describing bytes, unpack via Zfp.unpack"

codec  = Zfp::Codec.new(type: :double, shape: [50], mode: :reversible)
data   = (1..50).map { |i| i * Math::PI }
packed = codec.pack(data)
result = Zfp.unpack(packed)     # Zfp.unpack: no args needed, metadata embedded

puts "  codec.pack(Array[50])  →  #{fmt_bytes(packed.bytesize)} self-describing bytes"
puts "  Zfp.unpack(packed)     →  #{result.class}[#{result.size}]  match=#{data == result}"

section "Codec with Numo input + numo: true output"

numo_codec = Zfp::Codec.new(type: :double, shape: [8, 8], mode: :reversible, numo: true)
na         = Numo::DFloat.cast((1..64).map { |i| Math.log(i + 1) }).reshape(8, 8)
bytes      = numo_codec.compress(na)
result     = numo_codec.decompress(bytes)

puts "  Input:  #{na.class}#{na.shape}"
puts "  Output: #{result.class}#{result.shape}  (numo: true in constructor → Numo out)"
result_line("DFloat[8,8] codec numo: true", 64, :double, bytes.bytesize, na, result)

puts
puts "═" * 72
