# Quick Start

This page shows the three ways to use the gem. Pick whichever fits your architecture.

---

## 1. Module Methods — the easy path

### Raw bytes: `compress` / `decompress`

The caller manages metadata (type, shape, mode). Returns a plain `String` of compressed bytes.

```ruby
require "zfp"

prices = [174.21, 174.85, 173.40, 175.10, 176.33]

# Lossless round-trip — bit-exact
bytes    = Zfp.compress(prices, type: :double, shape: [prices.size], mode: :reversible)
restored = Zfp.decompress(bytes, type: :double, shape: [prices.size], mode: :reversible)

prices == restored  # => true

# Lossy — absolute error bounded to $0.001 per element
bytes    = Zfp.compress(prices, type: :double, shape: [prices.size],
                                mode: :fixed_accuracy, tolerance: 0.001)
restored = Zfp.decompress(bytes, type: :double, shape: [prices.size],
                                 mode: :fixed_accuracy, tolerance: 0.001)
```

### Self-describing bytes: `pack` / `unpack`

Metadata (type, shape, mode, params) is embedded in a 32-byte header prepended to the compressed bytes. Pass bytes anywhere — Redis, S3, a message queue — and unpack without needing a schema.

```ruby
# Pack: embed type/shape/mode/params in the bytes themselves
packed   = Zfp.pack(prices, type: :double, shape: [prices.size],
                            mode: :fixed_accuracy, tolerance: 0.001)

# Unpack: zero additional arguments needed
restored = Zfp.unpack(packed)
```

---

## 2. `Zfp::Codec` — when you compress many arrays with the same config

Build a codec once. Compress forever.

```ruby
codec = Zfp::Codec.new(type: :double, shape: [252], mode: :fixed_accuracy, tolerance: 0.001)

# Same codec compresses each security's yearly price history
store = {}
securities.each do |ticker|
  store[ticker] = codec.compress(daily_closes[ticker])
end

# Retrieve and decompress
prices = codec.decompress(store["AAPL"])

# Or get self-describing bytes via codec.pack (decode with Zfp.unpack)
packed = codec.pack(daily_closes["AAPL"])
```

---

## 3. Numo::NArray — auto-detect type and shape

If [numo-narray](https://github.com/ruby-numo/numo-narray) is loaded, `type:` and `shape:` are inferred automatically from the array.

```ruby
require "numo/narray"

closes = Numo::DFloat.cast(daily_prices).reshape(50, 252)

# No type: or shape: needed
bytes  = Zfp.compress(closes, mode: :fixed_accuracy, tolerance: 0.001)
packed = Zfp.pack(closes,     mode: :reversible)

# Get a Numo array back
result = Zfp.decompress(bytes, type: :double, shape: [50, 252],
                               mode: :fixed_accuracy, tolerance: 0.001, numo: true)
# => Numo::DFloat[50, 252]

# pack/unpack preserves the Numo type automatically
result = Zfp.unpack(packed)
# => Numo::DFloat[50, 252]
```

---

## Choosing a Compression Mode

| Mode | Parameter | When to use |
|---|---|---|
| `:reversible` | _(none)_ | Correctness is non-negotiable; bit-exact round-trip required |
| `:fixed_accuracy` | `tolerance: Float` | Financial or ML data; you know the acceptable absolute error |
| `:fixed_precision` | `precision: Integer` | Scientific data; you want to preserve N significant bits |
| `:fixed_rate` | `rate: Float` | Fixed-size storage slots; you need guaranteed bytes-per-value |

See [Compression Modes](compression-modes.md) for a detailed guide with benchmarks.

---

## Next Steps

- [Compression Modes](compression-modes.md) — mode-by-mode guide with benchmarks
- [Multi-Dimensional Arrays](multi-dimensional.md) — exploit 2-D through 4-D structure
- [Numo::NArray](numo-narray.md) — full Numo integration reference
- [API Reference](api/index.md) — complete method signatures
