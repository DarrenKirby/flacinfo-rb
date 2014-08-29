require 'rubygems'
SPEC = Gem::Specification.new do |s|
  s.name              = "flacinfo-rb"
  s.version           = "0.4"
  s.author            = "Darren Kirby"
  s.email             = "bulliver@gmail.com"
  s.homepage          = "https://github.com/DarrenKirby/flacinfo-rb"
  s.rubyforge_project = 'flacinfo-rb'
  s.platform          = Gem::Platform::RUBY
  s.summary           = "Pure Ruby library for accessing metadata from Flac files"
  s.files             = ["README", "lib/flacinfo.rb"]
  s.require_path      = "lib"
  s.autorequire       = "flacinfo"
  s.has_rdoc          = true
  s.test_files        = ['test/test-flacinfo.rb', 'test/test.flac']
  s.extra_rdoc_files  = ["README"]
end

