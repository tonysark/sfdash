# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'sfdash/version'

Gem::Specification.new do |spec|
  spec.name          = "sfdash"
  spec.version       = Sfdash::VERSION
  spec.authors       = ["J"]
  spec.email         = ["j"]
  spec.description   = %q{A stripped down version of a ruby client for the Salesforce SOAP API based on Savon.}
  spec.summary       = %q{I do not suggest using this, it has been edited by an amateur.}
  spec.homepage      = "https://github.com/tonysark/sfdash"
  spec.license       = 'MIT'

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "savon", "~> 2.3.0"

  spec.add_development_dependency 'rspec', '>= 2.14.0', '< 4.0.0'
  spec.add_development_dependency 'webmock', '>= 1.17.0', '< 2.0.0'
  spec.add_development_dependency 'simplecov', '>= 0.9.0', '< 1.0.0'
end
