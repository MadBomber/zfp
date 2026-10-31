# Zfp::Codec

`Zfp::Codec` is a reusable compression object with a fixed configuration. Build one codec and compress many arrays of the same type, shape, and mode without repeating the parameters on every call.

```ruby
codec = Zfp::Codec.new(type: :double, shape: [252], mode: :fixed_accuracy, tolerance: 0.001)
```

---

## Constructor

```ruby
Zfp::Codec.new(type:, shape:, mode:, numo: false, **params) → Zfp::Codec
```

**Arguments:**

| Argument | Type | Required | Notes |
|---|---|---|---|
| `type:` | Symbol | yes | `:float`, `:double`, `:int32`, `:int64` |
| `shape:` | Array of Integer | yes | 1–4 positive integers |
| `mode:` | Symbol | yes | `:reversible`, `:fixed_rate`, `:fixed_precision`, `:fixed_accuracy` |
| `numo:` | Boolean | no | When `true`, `decompress` returns a `Numo::NArray` |
| `rate:` | Float | if `:fixed_rate` | Bits per value |
| `precision:` | Integer | if `:fixed_precision` | Significant bits |
| `tolerance:` | Float | if `:fixed_accuracy` | Max absolute error per element |

**Raises:** `Zfp::InvalidType`, `Zfp::InvalidMode` (including a lossy mode with an integer type), `Zfp::InvalidShape`, `Zfp::InvalidParams` at construction time.

---

## `#compress`

```ruby
codec.compress(data) → String
```

Compresses `data` and returns a plain `String` of compressed bytes. The codec's type, shape, mode, and params are used. `data` may be a flat or nested Ruby `Array`, or a `Numo::NArray`; its element count must equal the product of the codec's shape.

**Returns:** Compressed bytes (no header).

**Raises:** `Zfp::InvalidShape` if the element count does not match the shape; `Zfp::InvalidType` for integer data out of range or non-Array input.

**Example:**

```ruby
codec = Zfp::Codec.new(type: :double, shape: [100], mode: :fixed_accuracy, tolerance: 0.001)

store = {}
securities.each do |ticker|
  store[ticker] = codec.compress(daily_closes[ticker])
end
```

---

## `#decompress`

```ruby
codec.decompress(bytes) → Array | Numo::NArray
```

Decompresses bytes produced by this codec (or any codec with the same configuration). Returns a Ruby `Array`, or a `Numo::NArray` if the codec was constructed with `numo: true`.

**Example:**

```ruby
prices = codec.decompress(store["AAPL"])
# => Array of 100 Floats

numo_codec = Zfp::Codec.new(type: :double, shape: [8, 8], mode: :reversible, numo: true)
result = numo_codec.decompress(bytes)
# => Numo::DFloat[8, 8]
```

---

## `#pack`

```ruby
codec.pack(data, numo: nil) → Zfp::Packed
```

Compresses `data` and prepends the 32-byte metadata header, just like `Zfp.pack`. The resulting [`Zfp::Packed`](packed.md) is self-describing: decode it with `#unpack` or `Zfp.unpack`, or write it to disk with `#save`. `numo:` sets whether `Zfp.unpack` returns a `Numo::NArray`; by default it does when the codec was built with `numo: true` or the input is a Numo array.

**Example:**

```ruby
codec  = Zfp::Codec.new(type: :double, shape: [50], mode: :reversible)
packed = codec.pack(data)
result = packed.unpack        # no additional args
packed.save("data.zfp")       # or persist it; Zfp.load("data.zfp").unpack later
```

---

## Use Cases

### Batch compression of same-shaped arrays

```ruby
codec = Zfp::Codec.new(type: :double, shape: [252], mode: :fixed_accuracy, tolerance: 0.001)
redis = Redis.new

TICKERS.each do |ticker|
  redis.set("close:#{ticker}", codec.compress(closes[ticker]))
end

# Later
prices = codec.decompress(redis.get("close:AAPL"))
```

### Codec with Numo round-trip

```ruby
codec = Zfp::Codec.new(type: :double, shape: [50, 252], mode: :reversible, numo: true)

matrix = Numo::DFloat.cast(all_prices).reshape(50, 252)
bytes  = codec.compress(matrix)
result = codec.decompress(bytes)
# result: Numo::DFloat[50, 252]
```

### Codec for pack/unpack workflow

```ruby
codec   = Zfp::Codec.new(type: :float, shape: [1536], mode: :fixed_accuracy, tolerance: 1e-4)
vectors = embedding_batch.map { |v| codec.pack(v) }

# Store and retrieve without keeping a schema
vectors.each { |v| queue.push(v.to_str) }
queue.each   { |bytes| process(Zfp.unpack(bytes)) }
```
