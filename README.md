# goldlapel-rails

Rails integration for [Gold Lapel](https://goldlapel.com) — the self-optimizing Postgres proxy. Includes L1 native cache — an in-process cache that serves repeated reads in microseconds with no TCP round-trip.

Auto-patches ActiveRecord's PostgreSQL adapter to start the Gold Lapel proxy on first connection and route all queries through it, with L1 cache enabled automatically. Zero config — just add the gem.

## Installation

```ruby
# Gemfile
gem "goldlapel-rails"
```

That's it. Your existing `config/database.yml` works unchanged.

## How It Works

When ActiveRecord opens its first PostgreSQL connection, `goldlapel-rails`:

1. Reads your connection params (host, port, user, password, database)
2. Starts the Gold Lapel proxy pointing at your database
3. Returns a connection through the proxy (`127.0.0.1:7932`) with L1 native cache active

On reconnect, the proxy is already running — the adapter reuses the rewritten params. Repeated reads hit the L1 cache and return in microseconds without a TCP round-trip.

## Optional Configuration

You can pass Gold Lapel options in `config/database.yml`:

```yaml
production:
  adapter: postgresql
  host: db.example.com
  database: mydb
  username: user
  password: pass
  goldlapel:
    port: 9000                          # proxy listen port (default: 7932)
    config:                             # proxy configuration
      mode: waiter
      pool_size: 30
      disable_n1: true
    extra_args:
      - "--threshold-duration-ms"
      - "200"
```

The `config` hash maps directly to Gold Lapel's configuration options. Use snake_case keys:

```ruby
# config/environments/production.rb (programmatic alternative)
config.database_configuration["production"]["goldlapel"] = {
  config: { mode: "waiter", pool_size: 30, disable_n1: true }
}
```

## Multiple Databases

Each database needs a different proxy port:

```yaml
production:
  primary:
    adapter: postgresql
    host: primary-db.example.com
    database: myapp
    goldlapel:
      port: 7932

  analytics:
    adapter: postgresql
    host: analytics-db.example.com
    database: analytics
    goldlapel:
      port: 7933
```

## Requirements

- Ruby >= 3.2
- Rails >= 7.0
- The [`goldlapel`](https://rubygems.org/gems/goldlapel) gem (added automatically as a dependency)

## License

Proprietary. See [goldlapel.com](https://goldlapel.com) for licensing.
