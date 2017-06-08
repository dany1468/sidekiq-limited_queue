# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'sidekiq/limited_queue_size/version'

Gem::Specification.new do |spec|
  spec.name          = 'sidekiq-limited_queue_size'
  spec.version       = Sidekiq::LimitedQueueSize::VERSION
  spec.authors       = ['dany1468']
  spec.email         = ['dany1468@gmail.com']

  spec.summary       = %q{Sidekiq plugin for limiting queue size}
  spec.description   = %q{Sidekiq plugin for limiting queue size}
  spec.homepage      = 'https://github.com/dany1468/sidekiq-limited_queue_size'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.15'
  spec.add_development_dependency 'rake', '~> 10.0'
end
