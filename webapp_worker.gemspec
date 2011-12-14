# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "webapp_worker/version"

Gem::Specification.new do |s|
  s.name        = "webapp_worker"
  s.version     = WebappWorker::VERSION
  s.authors     = ["Nick Willever"]
  s.email       = ["nickwillever@gmail.com"]
  s.homepage    = ""
  s.summary     = %q{Provides a worker for your webapp}
  s.description = %q{Allow the webapp to handle your workers, no need to use a job scheduler}

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_runtime_dependency 'trollop'
end
