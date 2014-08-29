require 'rubygems'
SPEC = Gem::Specification.new do |s|
  s.name              = "flacinfo-rb"
  s.version           = "1.0"
  s.author            = "Darren Kirby"
  s.email             = "bulliver@gmail.com"
  s.homepage          = "https://github.com/DarrenKirby/flacinfo-rb"
  s.platform          = Gem::Platform::RUBY
  s.summary           = "Pure Ruby library for accessing metadata from Flac files"
  s.files             = ["README", "lib/flacinfo.rb"]
  s.require_path      = "lib"
  s.has_rdoc          = true
  s.test_files        = ['test/test-flacinfo.rb', 'test/test.flac']
  s.extra_rdoc_files  = ["README"]
  s.license           = "GPL-3.0"
  s.description       = <<-EOF
    flacinfo-rb is a pure Ruby library for low-level access to Flac files.
    You can use it to read, set, or delete 'id3' like data (Vorbis comments),
    delete, add, or resize padding blocks, and so on.
EOF
end
