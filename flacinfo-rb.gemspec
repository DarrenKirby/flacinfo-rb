Gem::Specification.new do |s|
  s.name                  = 'flacinfo-rb'
  s.required_ruby_version = '>= 2.7.0'
  s.version               = '1.1.0'
  s.author                = 'Darren Kirby'
  s.email                 = 'darren@dragonbyte.ca'
  s.homepage              = 'https://github.com/DarrenKirby/flacinfo-rb'
  s.platform              = Gem::Platform::RUBY
  s.summary               = 'Pure Ruby library for accessing metadata from Flac files'
  s.files                 = %w[README.md lib/flacinfo.rb]
  s.require_path          = 'lib'
  s.test_files            = %w[test/test-flacinfo.rb test/test.flac]
  s.extra_rdoc_files      = ['README.md']
  s.license               = 'GPL-2.0-only'
  s.description           = <<-DESCRIPTION
    flacinfo-rb is a pure Ruby library for low-level access to Flac files.
    You can use it to read, set, or delete 'id3' like data (Vorbis comments),
    delete, add, or resize padding blocks, and so on.
  DESCRIPTION
end
