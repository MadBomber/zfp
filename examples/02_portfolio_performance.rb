#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.join(__dir__, "..", "lib")

require "zfp"
require "numo/narray"

TRADING_DAYS = 252
TOLERANCE    = 0.001   # $0.001 per-element accuracy for lossy mode
SEED         = 42      # fixed seed → reproducible results

PORTFOLIO_NAMES = [
  "Aggressive Growth",
  "Blue Chip Value",
  "Tech Momentum",
  "Dividend Income",
  "Balanced Core"
].freeze

# t=ticker, p=starting price, s=annual volatility, m=annual drift
TICKERS = [
  { t: "AAPL",  p: 175.0, s: 0.25, m: 0.12 },
  { t: "MSFT",  p: 380.0, s: 0.22, m: 0.15 },
  { t: "GOOGL", p: 140.0, s: 0.28, m: 0.10 },
  { t: "AMZN",  p: 178.0, s: 0.30, m: 0.14 },
  { t: "NVDA",  p: 480.0, s: 0.55, m: 0.35 },
  { t: "META",  p: 350.0, s: 0.38, m: 0.20 },
  { t: "TSLA",  p: 250.0, s: 0.65, m: 0.15 },
  { t: "BRK",   p: 365.0, s: 0.12, m: 0.08 },
  { t: "JPM",   p: 195.0, s: 0.20, m: 0.09 },
  { t: "JNJ",   p: 155.0, s: 0.15, m: 0.06 },
  { t: "V",     p: 275.0, s: 0.18, m: 0.11 },
  { t: "PG",    p: 155.0, s: 0.14, m: 0.07 },
  { t: "MA",    p: 460.0, s: 0.20, m: 0.12 },
  { t: "HD",    p: 340.0, s: 0.22, m: 0.10 },
  { t: "CVX",   p: 155.0, s: 0.24, m: 0.08 },
  { t: "MRK",   p: 115.0, s: 0.17, m: 0.07 },
  { t: "ABBV",  p: 155.0, s: 0.19, m: 0.09 },
  { t: "PEP",   p: 170.0, s: 0.14, m: 0.07 },
  { t: "KO",    p:  60.0, s: 0.13, m: 0.05 },
  { t: "WMT",   p: 165.0, s: 0.16, m: 0.08 },
  { t: "DIS",   p:  95.0, s: 0.30, m: 0.05 },
  { t: "NFLX",  p: 500.0, s: 0.40, m: 0.20 },
  { t: "ADBE",  p: 550.0, s: 0.32, m: 0.12 },
  { t: "CRM",   p: 260.0, s: 0.30, m: 0.12 },
  { t: "INTC",  p:  35.0, s: 0.30, m: 0.02 },
  { t: "AMD",   p: 180.0, s: 0.50, m: 0.25 },
  { t: "QCOM",  p: 175.0, s: 0.28, m: 0.10 },
  { t: "TXN",   p: 175.0, s: 0.22, m: 0.09 },
  { t: "AVGO",  p: 900.0, s: 0.35, m: 0.20 },
  { t: "ORCL",  p: 120.0, s: 0.25, m: 0.10 },
  { t: "IBM",   p: 155.0, s: 0.18, m: 0.06 },
  { t: "GS",    p: 420.0, s: 0.25, m: 0.10 },
  { t: "BAC",   p:  35.0, s: 0.22, m: 0.08 },
  { t: "WFC",   p:  50.0, s: 0.22, m: 0.08 },
  { t: "C",     p:  55.0, s: 0.24, m: 0.07 },
  { t: "UNH",   p: 520.0, s: 0.20, m: 0.12 },
  { t: "LLY",   p: 650.0, s: 0.25, m: 0.20 },
  { t: "PFE",   p:  30.0, s: 0.20, m: 0.04 },
  { t: "ABT",   p: 105.0, s: 0.18, m: 0.08 },
  { t: "TMO",   p: 555.0, s: 0.22, m: 0.10 },
  { t: "NEE",   p:  60.0, s: 0.20, m: 0.07 },
  { t: "XOM",   p: 110.0, s: 0.22, m: 0.08 },
  { t: "SLB",   p:  50.0, s: 0.28, m: 0.06 },
  { t: "CAT",   p: 265.0, s: 0.25, m: 0.10 },
  { t: "DE",    p: 380.0, s: 0.25, m: 0.09 },
  { t: "BA",    p: 215.0, s: 0.35, m: 0.03 },
  { t: "RTX",   p:  92.0, s: 0.20, m: 0.08 },
  { t: "LMT",   p: 480.0, s: 0.17, m: 0.09 },
  { t: "COST",  p: 690.0, s: 0.20, m: 0.14 },
  { t: "TGT",   p: 150.0, s: 0.25, m: 0.07 },
].freeze

# ─── Normal variate via Box-Muller ───────────────────────────────────────────
def rnorm(rng)
  u1 = [rng.rand, Float::EPSILON].max
  Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math::PI * rng.rand)
end

# ─── Geometric Brownian Motion ───────────────────────────────────────────────
def simulate_gbm(start_price, mu, sigma, days, rng)
  dt   = 1.0 / 252
  prev = start_price
  Numo::DFloat.zeros(days).tap do |arr|
    days.times do |i|
      arr[i] = prev = prev * Math.exp((mu - 0.5 * sigma**2) * dt + sigma * Math.sqrt(dt) * rnorm(rng))
    end
  end
end

# ─── Data structures ─────────────────────────────────────────────────────────
Portfolio = Struct.new(
  :name, :positions, :close_matrix,
  :packed_lossless, :packed_lossy,
  :start_value, :end_value,
  keyword_init: true
)
Position = Struct.new(:ticker, :shares, keyword_init: true)

def build_portfolio(name, rng)
  specs     = TICKERS.sample(rng.rand(10..30), random: rng)
  positions = specs.map do |spec|
    shares = (rng.rand(10_000.0..50_000.0) / spec[:p]).round
    shares = 1 if shares < 1
    Position.new(ticker: spec[:t], shares: shares)
  end

  matrix = Numo::DFloat.zeros(specs.size, TRADING_DAYS)
  specs.each_with_index do |spec, i|
    matrix[i, true] = simulate_gbm(spec[:p], spec[:m], spec[:s], TRADING_DAYS, rng)
  end

  Portfolio.new(
    name: name, positions: positions, close_matrix: matrix,
    packed_lossless: nil, packed_lossy: nil,
    start_value: nil, end_value: nil
  )
end

# ─── Formatters ──────────────────────────────────────────────────────────────
def fmt_bytes(n)
  n >= 1024 ? format("%.1f KB", n / 1024.0) : "#{n} B"
end

def fmt_money(n)
  s = n.abs.round.to_s.reverse.scan(/.{1,3}/).join(",").reverse
  n < 0 ? "-$#{s}" : "$#{s}"
end

def fmt_pct(n)
  format("%+.1f%%", n)
end

def portfolio_value(positions, matrix, day)
  positions.each_with_index.sum { |pos, i| matrix[i, day] * pos.shares }
end

# ─── Main ────────────────────────────────────────────────────────────────────
rng = Random.new(SEED)

puts
puts "=" * 74
puts "  ZFP GEM — PORTFOLIO COMPRESSION & PERFORMANCE DEMO"
puts "  #{PORTFOLIO_NAMES.size} portfolios · #{TRADING_DAYS} trading days (~1 year) · seed=#{SEED}"
puts "=" * 74

print "\nGenerating portfolios... "
portfolios = PORTFOLIO_NAMES.map { |name| build_portfolio(name, rng) }
puts "done."

print "Compressing with ZFP...  "
portfolios.each do |p|
  p.packed_lossless = Zfp.pack(p.close_matrix, mode: :reversible)
  p.packed_lossy    = Zfp.pack(p.close_matrix, mode: :fixed_accuracy, tolerance: TOLERANCE)
end
puts "done.\n"

# ─── Compression statistics ───────────────────────────────────────────────────
puts
puts "COMPRESSION STATISTICS  (close-price matrix per portfolio)"
puts "-" * 74
puts format("  %-20s  %5s  %9s  %13s  %5s  %14s  %5s",
  "Portfolio", "Sec.", "Raw", "Lossless", "Ratio", "Lossy ±$#{TOLERANCE}", "Ratio")
puts "-" * 74

total_raw = total_ll = total_ls = 0
portfolios.each do |p|
  n   = p.positions.size
  raw = n * TRADING_DAYS * 8
  ll  = p.packed_lossless.bytesize
  ls  = p.packed_lossy.bytesize
  total_raw += raw; total_ll += ll; total_ls += ls
  puts format("  %-20s  %5d  %9s  %13s  %4.1fx  %14s  %4.1fx",
    p.name, n, fmt_bytes(raw), fmt_bytes(ll), raw.to_f / ll, fmt_bytes(ls), raw.to_f / ls)
end
puts "-" * 74
puts format("  %-20s  %5s  %9s  %13s  %4.1fx  %14s  %4.1fx",
  "TOTAL", "", fmt_bytes(total_raw), fmt_bytes(total_ll), total_raw.to_f / total_ll,
  fmt_bytes(total_ls), total_raw.to_f / total_ls)

# ─── Data integrity verification ─────────────────────────────────────────────
puts
puts "DATA INTEGRITY VERIFICATION"
puts "-" * 74

portfolios.each do |p|
  ll_restored = Zfp.unpack(p.packed_lossless)
  ls_restored = Zfp.unpack(p.packed_lossy)
  ll_delta    = (p.close_matrix - ll_restored).abs.max
  ls_delta    = (p.close_matrix - ls_restored).abs.max
  ll_label    = ll_delta == 0.0 ? "bit-exact" : format("max_err=%.2e", ll_delta)
  ls_label    = format("max_err=$%.5f", ls_delta)
  puts format("  %-20s  lossless: %-14s  lossy: %s", p.name, ll_label, ls_label)
end

# ─── Performance rankings ────────────────────────────────────────────────────
puts
puts "PORTFOLIO PERFORMANCE  (computed from decompressed lossless data)"
puts "-" * 74

portfolios.each do |p|
  closes        = Zfp.unpack(p.packed_lossless)
  p.start_value = portfolio_value(p.positions, closes, 0)
  p.end_value   = portfolio_value(p.positions, closes, TRADING_DAYS - 1)
end

ranked = portfolios.sort_by { |p| -(p.end_value - p.start_value) / p.start_value }

puts format("  %-4s  %-20s  %5s  %14s  %14s  %9s",
  "Rank", "Portfolio", "Sec.", "Start Value", "End Value", "Return")
puts "-" * 74

ranked.each_with_index do |p, i|
  ret = (p.end_value - p.start_value) / p.start_value * 100
  puts format("  %-4s  %-20s  %5d  %14s  %14s  %9s",
    "#{i + 1}.", p.name, p.positions.size,
    fmt_money(p.start_value), fmt_money(p.end_value), fmt_pct(ret))
end

# ─── Winner breakdown ─────────────────────────────────────────────────────────
winner = ranked.first
puts
puts "WINNER BREAKDOWN: #{winner.name}"
puts "-" * 74
closes = Zfp.unpack(winner.packed_lossless)

sec_rets = winner.positions.each_with_index.map do |pos, i|
  sv  = closes[i, 0] * pos.shares
  ev  = closes[i, TRADING_DAYS - 1] * pos.shares
  { ticker: pos.ticker, shares: pos.shares, sv: sv, ev: ev, ret: (ev - sv) / sv * 100 }
end.sort_by { |h| -h[:ret] }

puts format("  %-8s  %8s  %14s  %14s  %9s", "Ticker", "Shares", "Start Value", "End Value", "Return")
puts "  " + "-" * 58
sec_rets.each do |h|
  puts format("  %-8s  %8d  %14s  %14s  %9s",
    h[:ticker], h[:shares], fmt_money(h[:sv]), fmt_money(h[:ev]), fmt_pct(h[:ret]))
end

puts
puts "=" * 74
