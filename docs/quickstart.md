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

`pack` returns a `Zfp::Packed`: the compressed payload behind a 32-byte header that records type, shape, mode, and params. It behaves like a `String` wherever one is expected (`to_str`), so it can go straight into Redis, S3, a message queue, or a file, and be unpacked later without a schema.

```ruby
# Pack: embed type/shape/mode/params in the bytes themselves
packed = Zfp.pack(prices, type: :double, shape: [prices.size],
                          mode: :fixed_accuracy, tolerance: 0.001)
packed.mode      # => :fixed_accuracy   (header fields, no decompression)
packed.shape     # => [10005]

# Unpack: zero additional arguments needed
restored = packed.unpack        # or Zfp.unpack(packed) / Zfp.unpack(raw_bytes)
```

The header is specific to this gem, and the raw `compress` output has no header at all, so neither can be read by the `zfp` command-line tool or other zfp bindings.

### Files on disk: `save` / `load`

A `.zfp` file is just the packed bytes, so it is complete on its own.

```ruby
packed.save("prices.zfp")              # returns the path

loaded = Zfp.load("prices.zfp")        # => Zfp::Packed, metadata intact
loaded.type, loaded.shape, loaded.mode # inspect before decompressing
prices_again = loaded.unpack
```

`Zfp.load` raises `Errno::ENOENT` for a missing file and `Zfp::PackerError` for a file that is not a zfp pack. The `.zfp` extension is a convention, not a requirement.

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

# Or get a self-describing Zfp::Packed via codec.pack, and save it
codec.pack(daily_closes["AAPL"]).save("aapl.zfp")
```

---

## 3. Numo::NArray — auto-detect type and shape

If you have required [numo-narray](https://github.com/ruby-numo/numo-narray), `type:` and `shape:` are inferred automatically from the array. Requesting Numo output without the gem installed raises `Zfp::NumoNotAvailable`.

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
