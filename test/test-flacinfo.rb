#!/usr/bin/ruby

$:.unshift File.join(File.dirname(__FILE__), "..", "lib")

require 'test/unit'
require 'flacinfo'

class TestFlacInfo < Test::Unit::TestCase

  def setup
    @flac = FlacInfo.new("test.flac")
  end

  def test_streaminfo
    assert_equal(34,     @flac.streaminfo['block_size'])
    assert_equal(8,      @flac.streaminfo['offset'])
    assert_equal(4096,   @flac.streaminfo['minimum_block'])
    assert_equal(4096,   @flac.streaminfo['maximum_block'])
    assert_equal(4454,   @flac.streaminfo['minimum_frame'])
    assert_equal(7491,   @flac.streaminfo['maximum_frame'])
    assert_equal(44100,  @flac.streaminfo['samplerate'])
    assert_equal(2,      @flac.streaminfo['channels'])
    assert_equal(16,     @flac.streaminfo['bits_per_sample'])
    assert_equal(663552, @flac.streaminfo['total_samples'])
    assert_equal("8cde6ba4d9b7458f1446215941ea5e1b", @flac.streaminfo['md5'])
  end

  def test_vorbis_comments
    assert_equal(294, @flac.tags['block_size'])
    assert_equal(46, @flac.tags['offset'])
    assert_equal("test.flac", @flac.tags['TITLE'])
    assert_equal("Darren Kirby", @flac.tags['ARTIST'])
    assert_equal("No Thanks", @flac.tags['COPYRIGHT'])
    assert_equal("Badcomputer Org.", @flac.tags['ORGANIZATION'])
    assert_equal("A simple reference flac for the unit tests", @flac.tags['DESCRIPTION'])
    assert_equal("Spoken Word", @flac.tags['GENRE'])
    assert_equal("Wed Aug 15 14:28:07 2007", @flac.tags['DATE'])
    assert_equal("IN UR COMPUTER READING UR FLACS", @flac.tags['LOCATION'])
    assert_equal("reference libFLAC 1.2.0 20070715", @flac.tags['vendor_tag'])
  end

  def test_picture_one
    assert_equal(2, @flac.picture["n"])
    assert_equal(15921, @flac.picture[1]['block_size'])
    assert_equal(344, @flac.picture[1]['offset'])
    assert_equal("image/png", @flac.picture[1]['mime_type'])
    assert_equal("Artist/performer", @flac.picture[1]['type_string'])
    assert_equal(8, @flac.picture[1]['type_int'])
    assert_equal("The author of flacinfo", @flac.picture[1]['description_string'])
    assert_equal(0, @flac.picture[1]['n_colours'])
    assert_equal(32, @flac.picture[1]['colour_depth'])
    assert_equal(99, @flac.picture[1]['height'])
    assert_equal(100, @flac.picture[1]['width'])
    assert_equal(407, @flac.picture[1]['raw_data_offset'])
    assert_equal(15858, @flac.picture[1]['raw_data_length'])
  end

  def test_picture_two
    assert_equal(2, @flac.picture["n"])
    assert_equal(22183, @flac.picture[2]['block_size'])
    assert_equal(16269, @flac.picture[2]['offset'])
    assert_equal("image/jpeg", @flac.picture[2]['mime_type'])
    assert_equal("Other", @flac.picture[2]['type_string'])
    assert_equal(0, @flac.picture[2]['type_int'])
    assert_equal("A silly picture for the unit test", @flac.picture[2]['description_string'])
    assert_equal(0, @flac.picture[2]['n_colours'])
    assert_equal(24, @flac.picture[2]['colour_depth'])
    assert_equal(353, @flac.picture[2]['height'])
    assert_equal(507, @flac.picture[2]['width'])
    assert_equal(16344, @flac.picture[2]['raw_data_offset'])
    assert_equal(22108, @flac.picture[2]['raw_data_length'])
  end

  def test_padding
    assert_equal(258,   @flac.padding['block_size'])
    assert_equal(38456, @flac.padding['offset'])
  end

end

