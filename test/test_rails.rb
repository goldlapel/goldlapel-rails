require "minitest/autorun"

# Stub goldlapel gem BEFORE requiring rails.rb (which does `require "goldlapel"`)
module GoldLapel
  @start_calls = []

  def self.start_calls
    @start_calls
  end

  def self.start(upstream, port: nil, extra_args: [])
    @start_calls << { upstream: upstream, port: port, extra_args: extra_args }
  end

  def self.reset!
    @start_calls = []
  end
end
$LOADED_FEATURES << "goldlapel.rb"

# Stub out Rails/ActiveRecord so we can load our code without a full Rails app.
module Rails
  class Railtie
    def self.initializer(name, &block); end
  end
end

module ActiveSupport
  def self.on_load(name, &block); end
end

module ActiveRecord
  module ConnectionAdapters
    class PostgreSQLAdapter; end
  end
end

require_relative "../lib/goldlapel/rails"

# ---------------------------------------------------------------------------
# URL construction tests
# ---------------------------------------------------------------------------
class TestBuildUpstreamUrl < Minitest::Test
  def test_standard_params
    url = GoldLapel::Rails.build_upstream_url(
      host: "db.example.com", port: "5432",
      user: "myuser", password: "mypass", dbname: "mydb"
    )
    assert_equal "postgresql://myuser:mypass@db.example.com:5432/mydb", url
  end

  def test_nil_host_defaults_to_localhost
    url = GoldLapel::Rails.build_upstream_url(
      host: nil, port: "5432", user: "u", password: "p", dbname: "db"
    )
    assert_equal "postgresql://u:p@localhost:5432/db", url
  end

  def test_empty_host_defaults_to_localhost
    url = GoldLapel::Rails.build_upstream_url(
      host: "", port: "5432", user: "u", password: "p", dbname: "db"
    )
    assert_equal "postgresql://u:p@localhost:5432/db", url
  end

  def test_nil_port_defaults_to_5432
    url = GoldLapel::Rails.build_upstream_url(
      host: "db.example.com", port: nil, user: "u", password: "p", dbname: "db"
    )
    assert_equal "postgresql://u:p@db.example.com:5432/db", url
  end

  def test_special_chars_percent_encoded
    url = GoldLapel::Rails.build_upstream_url(
      host: "db.example.com", port: "5432",
      user: "user@org", password: "p@ss:word/special", dbname: "my db"
    )
    assert_equal(
      "postgresql://user%40org:p%40ss%3Aword%2Fspecial@db.example.com:5432/my+db",
      url
    )
  end

  def test_no_user_or_password
    url = GoldLapel::Rails.build_upstream_url(
      host: "db.example.com", port: "5432", dbname: "mydb"
    )
    assert_equal "postgresql://db.example.com:5432/mydb", url
  end

  def test_user_without_password
    url = GoldLapel::Rails.build_upstream_url(
      host: "db.example.com", port: "5432", user: "myuser", dbname: "mydb"
    )
    assert_equal "postgresql://myuser@db.example.com:5432/mydb", url
  end

  def test_empty_user_treated_as_no_user
    url = GoldLapel::Rails.build_upstream_url(
      host: "db.example.com", port: "5432", user: "", password: "p", dbname: "mydb"
    )
    assert_equal "postgresql://db.example.com:5432/mydb", url
  end

  def test_unix_socket_raises
    assert_raises(ArgumentError) do
      GoldLapel::Rails.build_upstream_url(
        host: "/var/run/postgresql", port: "5432", dbname: "mydb"
      )
    end
  end
end

# ---------------------------------------------------------------------------
# Connect override tests
# ---------------------------------------------------------------------------

# Minimal adapter double that includes our extension
class FakeAdapter
  prepend GoldLapel::Rails::PostgreSQLExtension

  attr_accessor :connection_parameters, :config
  attr_reader :super_called

  def initialize(config:, connection_parameters:)
    @config = config
    @connection_parameters = connection_parameters
    @super_called = 0
  end

  private

  def connect
    @super_called += 1
  end
end

class TestConnect < Minitest::Test
  def setup
    GoldLapel.reset!
  end

  def test_starts_proxy_and_swaps_params
    adapter = FakeAdapter.new(
      config: {},
      connection_parameters: {
        host: "db.example.com", port: "5432",
        user: "u", password: "p", dbname: "mydb"
      }
    )

    adapter.send(:connect)

    assert_equal 1, GoldLapel.start_calls.length
    call = GoldLapel.start_calls.first
    assert_equal "postgresql://u:p@db.example.com:5432/mydb", call[:upstream]
    assert_nil call[:port]
    assert_equal [], call[:extra_args]

    assert_equal "127.0.0.1", adapter.connection_parameters[:host]
    assert_equal 7932, adapter.connection_parameters[:port]
    assert_equal 1, adapter.super_called
  end

  def test_custom_port_from_config
    adapter = FakeAdapter.new(
      config: { goldlapel: { port: 9000 } },
      connection_parameters: {
        host: "db.example.com", port: "5432",
        user: "u", password: "p", dbname: "mydb"
      }
    )

    adapter.send(:connect)

    assert_equal 9000, GoldLapel.start_calls.first[:port]
    assert_equal 9000, adapter.connection_parameters[:port]
  end

  def test_extra_args_from_config
    adapter = FakeAdapter.new(
      config: { goldlapel: { extra_args: ["--threshold-duration-ms", "200"] } },
      connection_parameters: {
        host: "db.example.com", port: "5432",
        user: "u", password: "p", dbname: "mydb"
      }
    )

    adapter.send(:connect)

    assert_equal ["--threshold-duration-ms", "200"], GoldLapel.start_calls.first[:extra_args]
  end

  def test_missing_goldlapel_config_uses_defaults
    adapter = FakeAdapter.new(
      config: {},
      connection_parameters: {
        host: "db.example.com", port: "5432",
        user: "u", password: "p", dbname: "mydb"
      }
    )

    adapter.send(:connect)

    call = GoldLapel.start_calls.first
    assert_nil call[:port]
    assert_equal [], call[:extra_args]
  end

  def test_reconnect_skips_proxy_setup
    adapter = FakeAdapter.new(
      config: {},
      connection_parameters: {
        host: "db.example.com", port: "5432",
        user: "u", password: "p", dbname: "mydb"
      }
    )

    adapter.send(:connect)
    adapter.send(:connect)

    # Proxy started only once
    assert_equal 1, GoldLapel.start_calls.length
    # But super called twice (both connects go through)
    assert_equal 2, adapter.super_called
    # Params still point at proxy
    assert_equal "127.0.0.1", adapter.connection_parameters[:host]
    assert_equal 7932, adapter.connection_parameters[:port]
  end
end
