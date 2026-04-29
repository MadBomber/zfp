# Basic Usage Example

**File:** `examples/01_basic_usage.rb`

This script covers every major feature of the gem. Run it to see real compression ratios and errors on your system.

```bash
bundle exec ruby examples/01_basic_usage.rb
```

---

## What It Demonstrates

### 1. All Four Scalar Types

```ruby
{ float:  float_data,
  double: float_data,
  int32:  int_data_32,
  int64:  int_data_64 }.each do |type, data|
  bytes  = Zfp.compress(data, type: type, shape: [128], mode: :reversible)
  result = Zfp.decompress(bytes, type: type, shape: [128], mode: :reversible)
  # result == data  (exact, lossless)
end
```

### 2. Multi-Dimensional Shapes (1-D through 4-D)

```ruby
[[256], [16, 16], [4, 8, 8], [4, 4, 4, 4]].each do |shape|
  n     = shape.reduce(:*)
  data  = (1..n).map { |i| Math.sin(i * 0.05) * 100 }
  bytes = Zfp.compress(data, type: :double, shape: shape, mode: :reversible)
  back  = Zfp.decompress(bytes, type: :double, shape: shape, mode: :reversible)
end
```

All four layouts contain 256 elements. ZFP exploits different spatial correlations depending on dimensionality.

### 3. All Four Compression Modes

The script compresses the same 256-element sinusoidal dataset with every mode and parameter combination, printing raw size, compressed size, ratio, and max error:

| Mode | Params | Expected ratio |
|---|---|---|
| `:reversible` | — | ~2.5× |
| `:fixed_rate` | `rate: 8.0` | 8× |
| `:fixed_rate` | `rate: 4.0` | 16× |
| `:fixed_rate` | `rate: 2.0` | 32× |
| `:fixed_precision` | `precision: 24` | ~5× |
| `:fixed_precision` | `precision: 12` | ~10× |
| `:fixed_accuracy` | `tolerance: 0.001` | ~7× |
| `:fixed_accuracy` | `tolerance: 0.1` | ~10× |
| `:fixed_accuracy` | `tolerance: 1.0` | ~13× |

### 4. Pack / Unpack

```ruby
# Self-describing bytes — metadata embedded in 32-byte header
packed = Zfp.pack(data, type: :double, shape: [100], mode: :reversible)
result = Zfp.unpack(packed)   # no additional args needed

# Lossy pack — tolerance stored in header
packed = Zfp.pack(data, type: :double, shape: [256],
                        mode: :fixed_accuracy, tolerance: 0.01)
result = Zfp.unpack(packed)   # unpack reads tolerance from header
```

### 5. Numo::NArray

```ruby
# All four Numo types round-trip correctly
{ Numo::SFloat => :float, Numo::DFloat => :double,
  Numo::Int32  => :int32, Numo::Int64  => :int64 }.each do |klass, type|
  na     = klass.cast(data)
  bytes  = Zfp.compress(na, mode: :reversible)   # auto-detect type/shape
  result = Zfp.decompress(bytes, type: type, shape: [64], mode: :reversible, numo: true)
  # result is a Numo array of the same class
end

# Ruby Array in → numo: true → Numo output
data   = (1..64).map { |i| i * Math::PI }
bytes  = Zfp.compress(data, type: :double, shape: [64], mode: :reversible)
result = Zfp.decompress(bytes, type: :double, shape: [64], mode: :reversible, numo: true)
# result: Numo::DFloat[64]
```

### 6. Zfp::Codec

```ruby
# Build once, compress many
codec = Zfp::Codec.new(type: :double, shape: [100],
                        mode: :fixed_accuracy, tolerance: 0.001)

3.times do |k|
  data   = (1..100).map { |i| Math.sin(i * 0.1 * (k + 1)) * 500 }
  bytes  = codec.compress(data)
  result = codec.decompress(bytes)
end

# Codec + pack → Zfp.unpack
codec  = Zfp::Codec.new(type: :double, shape: [50], mode: :reversible)
packed = codec.pack(data)
result = Zfp.unpack(packed)   # self-describing, no schema needed
```

---

## Sample Output

```
══════════════════════════════════════════════════════════════════════════
  ZFP GEM — BASIC USAGE EXAMPLES
══════════════════════════════════════════════════════════════════════════

══════════════════════════════════════════════════════════════════════════
  1.  compress / decompress — raw bytes API, all scalar types
══════════════════════════════════════════════════════════════════════════

  All four scalar types · shape=[128] · mode=:reversible
  ──────────────────────────────────────────────────────────────────
  type=:float, shape=[128]               512 B →     248 B    2.1x  [exact     ]
  type=:double, shape=[128]            1.0 KB →     488 B    2.1x  [exact     ]
  type=:int32, shape=[128]               512 B →     192 B    2.7x  [exact     ]
  type=:int64, shape=[128]             1.0 KB →     344 B    3.0x  [exact     ]
```
