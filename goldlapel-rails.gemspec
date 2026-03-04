Gem::Specification.new do |s|
  s.name        = "goldlapel-rails"
  s.version     = ENV.fetch("GEM_VERSION", "0.1.0")
  s.summary     = "Gold Lapel integration for Rails"
  s.description = "Auto-patches ActiveRecord's PostgreSQL adapter to route queries through the Gold Lapel proxy. Zero config — just add the gem."
  s.authors     = ["Stephen Gibson"]
  s.homepage    = "https://goldlapel.com"
  s.license     = "Proprietary"
  s.metadata    = {
    "homepage_uri"    => "https://goldlapel.com",
    "source_code_uri" => "https://github.com/Gold-Lapel/goldlapel-rails",
  }

  s.required_ruby_version = ">= 3.2.0"

  s.files = Dir["lib/**/*.rb"] + ["README.md"]
  s.require_paths = ["lib"]

  s.add_dependency "goldlapel"
  s.add_dependency "activerecord", ">= 7.0"
end
