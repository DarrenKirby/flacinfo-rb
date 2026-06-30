#!/usr/bin/ruby

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..', 'lib')

require 'test/unit'
require 'flacinfo'

class TestFlacInfoFileOne < Test::Unit::TestCase

  def setup
    @flac = FlacInfo.new('test.flac')
  end

  def test_streaminfo
    assert_equal(34,      @flac.streaminfo.block_size)
    assert_equal(8,       @flac.streaminfo.offset)
    assert_equal(4096,    @flac.streaminfo.minimum_block)
    assert_equal(4096,    @flac.streaminfo.maximum_block)
    assert_equal(4454,    @flac.streaminfo.minimum_frame)
    assert_equal(7491,    @flac.streaminfo.maximum_frame)
    assert_equal(44_100,  @flac.streaminfo.samplerate)
    assert_equal(2,       @flac.streaminfo.channels)
    assert_equal(16,      @flac.streaminfo.bits_per_sample)
    assert_equal(663_552, @flac.streaminfo.total_samples)
    assert_equal('8cde6ba4d9b7458f1446215941ea5e1b', @flac.streaminfo.md5)
  end

  def test_vorbis_comments
    assert_equal(294, @flac.tags['block_size'])
    assert_equal(46, @flac.tags['offset'])
    assert_equal('test.flac', @flac.tags['TITLE'])
    assert_equal('Darren Kirby', @flac.tags['ARTIST'])
    assert_equal('No Thanks', @flac.tags['COPYRIGHT'])
    assert_equal('Badcomputer Org.', @flac.tags['ORGANIZATION'])
    assert_equal('A simple reference flac for the unit tests', @flac.tags['DESCRIPTION'])
    assert_equal('Spoken Word', @flac.tags['GENRE'])
    assert_equal('Wed Aug 15 14:28:07 2007', @flac.tags['DATE'])
    assert_equal('IN UR COMPUTER READING UR FLACS', @flac.tags['LOCATION'])
    assert_equal('reference libFLAC 1.2.0 20070715', @flac.tags['vendor_tag'])
  end

  def test_picture_one
    assert_equal(2, @flac.pictures.length)
    assert_equal(15_921, @flac.pictures[0].block_size)
    assert_equal(344, @flac.pictures[0].offset)
    assert_equal('image/png', @flac.pictures[0].mime_type)
    assert_equal('Artist/performer', @flac.pictures[0].type_string)
    assert_equal(8, @flac.pictures[0].type_int)
    assert_equal('The author of flacinfo', @flac.pictures[0].description_string)
    assert_equal(0, @flac.pictures[0].n_colours)
    assert_equal(32, @flac.pictures[0].colour_depth)
    assert_equal(99, @flac.pictures[0].height)
    assert_equal(100, @flac.pictures[0].width)
    assert_equal(407, @flac.pictures[0].raw_data_offset)
    assert_equal(15_858, @flac.pictures[0].raw_data_length)
  end

  def test_picture_two
    assert_equal(2, @flac.pictures.length)
    assert_equal(22_183, @flac.pictures[1].block_size)
    assert_equal(16_269, @flac.pictures[1].offset)
    assert_equal('image/jpeg', @flac.pictures[1].mime_type)
    assert_equal('Other', @flac.pictures[1].type_string)
    assert_equal(0, @flac.pictures[1].type_int)
    assert_equal('A silly picture for the unit test', @flac.pictures[1].description_string)
    assert_equal(0, @flac.pictures[1].n_colours)
    assert_equal(24, @flac.pictures[1].colour_depth)
    assert_equal(353, @flac.pictures[1].height)
    assert_equal(507, @flac.pictures[1].width)
    assert_equal(16_344, @flac.pictures[1].raw_data_offset)
    assert_equal(22_108, @flac.pictures[1].raw_data_length)
  end

  def test_padding
    assert_equal(258,    @flac.padding.block_size)
    assert_equal(38_456, @flac.padding.offset)
  end

end

class TestFlacInfoFileTwo < Test::Unit::TestCase

  def setup
    @flac = FlacInfo.new('test2.flac')
  end

  def test_streaminfo
    assert_equal(0,         @flac.streaminfo.is_last)
    assert_equal(34,        @flac.streaminfo.block_size)
    assert_equal(8,         @flac.streaminfo.offset)
    assert_equal(4096,      @flac.streaminfo.minimum_block)
    assert_equal(4096,      @flac.streaminfo.maximum_block)
    assert_equal(3627,      @flac.streaminfo.minimum_frame)
    assert_equal(17_933,    @flac.streaminfo.maximum_frame)
    assert_equal(44_100,    @flac.streaminfo.samplerate)
    assert_equal(2,         @flac.streaminfo.channels)
    assert_equal(24,        @flac.streaminfo.bits_per_sample)
    assert_equal(5_440_923, @flac.streaminfo.total_samples)
    assert_equal('4dd6616fecef46efa5aaa5a271fc131f', @flac.streaminfo.md5)
  end

  def test_seektable
    assert_equal(0,            @flac.seektable.is_last)
    assert_equal(648,          @flac.seektable.block_size)
    assert_equal(46,           @flac.seektable.offset)
    assert_equal(36,           @flac.seektable.seek_points)
    assert_equal([0, 0, 4096], @flac.seektable.points[0])
    assert_equal(151_552,      @flac.seektable.points[1][0])
    assert_equal(473_295,      @flac.seektable.points[1][1])
    assert_equal(4096,         @flac.seektable.points[1][2])

    expected = { 0 => [0, 0, 4096],
                 1 => [151_552, 473_295, 4096],
                 2 => [307_200, 937_238, 4096],
                 3 => [462_848, 1_481_586, 4096],
                 4 => [614_400, 2_057_468, 4096],
                 5 => [770_048, 2_629_070, 4096],
                 6 => [925_696, 3_193_589, 4096],
                 7 => [1_077_248, 3_748_233, 4096],
                 8 => [1_232_896, 4_326_683, 4096],
                 9 => [1_388_544, 4_838_892, 4096],
                 10 => [1_540_096, 5_361_811, 4096],
                 11 => [1_695_744, 5_955_921, 4096],
                 12 => [1_851_392, 6_507_012, 4096],
                 13 => [2_002_944, 7_005_433, 4096],
                 14 => [2_158_592, 7_607_035, 4096],
                 15 => [2_314_240, 8_186_470, 4096],
                 16 => [2_465_792, 8_744_611, 4096],
                 17 => [2_621_440, 9_326_616, 4096],
                 18 => [2_777_088, 9_885_412, 4096],
                 19 => [2_928_640, 10_447_695, 4096],
                 20 => [3_084_288, 10_985_464, 4096],
                 21 => [3_239_936, 11_543_877, 4096],
                 22 => [3_395_584, 12_066_854, 4096],
                 23 => [3_547_136, 12_616_186, 4096],
                 24 => [3_702_784, 13_151_076, 4096],
                 25 => [3_858_432, 13_747_535, 4096],
                 26 => [4_009_984, 14_317_119, 4096],
                 27 => [4_165_632, 14_878_074, 4096],
                 28 => [4_321_280, 15_463_165, 4096],
                 29 => [4_472_832, 16_036_096, 4096],
                 30 => [4_628_480, 16_581_406, 4096],
                 31 => [4_784_128, 17_161_957, 4096],
                 32 => [4_935_680, 17_709_685, 4096],
                 33 => [5_091_328, 18_238_518, 4096],
                 34 => [5_246_976, 18_791_132, 4096],
                 35 => [5_398_528, 19_205_050, 4096] }

    assert_equal(expected, @flac.seektable.points)
  end

  # def test_vorbis_comments
  #   assert_equal(294, @flac.tags['block_size'])
  #   assert_equal(46, @flac.tags['offset'])
  #   assert_equal('test.flac', @flac.tags['TITLE'])
  #   assert_equal('Darren Kirby', @flac.tags['ARTIST'])
  #   assert_equal('No Thanks', @flac.tags['COPYRIGHT'])
  #   assert_equal('Badcomputer Org.', @flac.tags['ORGANIZATION'])
  #   assert_equal('A simple reference flac for the unit tests', @flac.tags['DESCRIPTION'])
  #   assert_equal('Spoken Word', @flac.tags['GENRE'])
  #   assert_equal('Wed Aug 15 14:28:07 2007', @flac.tags['DATE'])
  #   assert_equal('IN UR COMPUTER READING UR FLACS', @flac.tags['LOCATION'])
  #   assert_equal('reference libFLAC 1.2.0 20070715', @flac.tags['vendor_tag'])
  # end
  #
  # def test_padding
  #   assert_equal(258,    @flac.padding.block_size)
  #   assert_equal(38_456, @flac.padding.offset)
  # end
end
