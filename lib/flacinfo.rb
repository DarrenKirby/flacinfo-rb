# Copyright and Disclaimer
#
# Copyright:: (C) 2006 - 2026 Darren Kirby
#
# FlacInfo is free software. No warranty is provided and the author
# cannot accept responsibility for lost or damaged files.
#
# * License:: GPL2
# * Author:: Darren Kirby (mailto:darren@dragonbyte.ca)
# * Website:: https://github.com/DarrenKirby/flacinfo-rb
#
# More information
#
# The Flac spec has been made an official RFC. This RFC, and a simplified (read: easier to understand) spec are at:
# * https://datatracker.ietf.org/doc/rfc9639/
# * https://xiph.org/flac/old_format.html
# The Vorbis Comment spec is at:
# *http://www.xiph.org/vorbis/doc/v-comment.html

# :markup: markdown

require 'tempfile'
require 'fileutils'

# FlacInfoError is raised for general user errors.
# It will print a string that describes the problem.
FlacInfoError = Class.new(StandardError)

# FlacInfoReadError is raised when an error occurs parsing the Flac file.
# It will print a string that describes in which block the error occurred.
FlacInfoReadError = Class.new(StandardError)

# FlacInfoWriteError is raised when an error occurs writing the Flac file.
# It will print a string that describes where the error occurred.
FlacInfoWriteError = Class.new(StandardError)

# Used for instantiating block object types that don't exist in the parsed file.
FakeHeader = Struct.new(:type, :block_size, :offset, :is_last, keyword_init: true)

# Used for tags['vendor_tag']
FLAC_INFO_VERSION = '1.1.0'.freeze

# The Stream class models the flac file as a whole. It contains an array of class objects that represent the
# METADATA_BLOCK_DATA blocks in order and a pointer to the actual FRAME audio data. A FLAC bitstream consists of the
# "fLaC" marker at the beginning of the stream, followed by a mandatory metadata block (called the STREAMINFO block),
# any number of other metadata blocks, then the audio frames.
class Stream
  attr_reader :blocks

  def initialize(path)
    @filename = path.freeze
    @blocks = []
    @frame_data_offset = nil
    @io = File.open(@filename)
    parse_file
  end

  # This block must be present at position 0.
  def streaminfo
    @blocks.find { |b| b.is_a?(Streaminfo) }
  end

  # These blocks can occur 0 or 1 time.
  def seektable
    @blocks.find { |b| b.is_a?(Seektable) }
  end

  def cuesheet
    @blocks.find { |b| b.is_a?(Cuesheet) }
  end

  def vorbis_comment
    @blocks.find { |b| b.is_a?(VorbisComment) }
  end

  # These blocks may occur 0 or more times.
  def applications
    @blocks.grep(Application)
  end

  def application
    applications.first
  end

  def pictures
    @blocks.grep(Picture)
  end

  def picture
    pictures.first
  end

  def paddings
    @blocks.grep(Padding)
  end

  def padding
    paddings.first
  end

  def create_comment_block
    @blocks.last.is_last = false
    new_block = VorbisComment.from_scratch
    @blocks << new_block
    # Return the instance so the UI wrapper can call .add_comment on it
    new_block
  end

  def write_file(filename)
    # TODO
    # We need to determine if we are writing in-place, or to a new file. In case of the former, we need to determine
    # whether our metadata fits in-place before the audio frames, or whether we need a complete rewrite.
  end

  private

  def read_header
    header = BlockHeader.read(@io)
    klass = BLOCK_TYPES.fetch(header.type, Unknown)
    @blocks << klass.new(@io, header)
    header.is_last
  end

  def parse_file
    stream_marker = @io.read(4)
    #  First 4 bytes must be 0x66, 0x4C, 0x61, and 0x43
    raise FlacInfoReadError, "#{@filename} does not appear to be a valid Flac file" if stream_marker != 'fLaC'

    last = 0
    last = read_header until last == 1

    # The rest of the file is FRAME audio data.
    # We don't need to keep this in memory
    @frame_data_offset = @io.tell
    @frame_data_offset.freeze
    @io.close
  end

  # If a complete re-write is necessary, using a tmpfile i the fastest/safest approach.
  def write_tmp_file(filename = nil)
    outfile = filename || @filename

    # The type-checker was complaining, so we'll be defensive.
    raise FlacInfoWriteError, 'Frame data offset is missing' if @frame_data_offset.nil?

    # Create a temporary file to safely stream the new data into.
    # This prevents us from corrupting the original file if the process crashes halfway through.
    Tempfile.create('FlacInfo') do |temp_file|
      temp_file.binmode

      # Write all the blocks to the temp file
      @blocks.each do |block|
        temp_file.write(block.serialize(@filename))
      end

      # Copy the audio frame data directly from the original file to the temp file.
      File.open(@filename, 'rb') do |original_file|
        IO.copy_stream(original_file, temp_file, nil, @frame_data_offset)
      end

      # Replace the target file with our newly built temp file
      FileUtils.mv(temp_file.path, outfile)
    end
  rescue StandardError => e
    raise FlacInfoWriteError, "error writing flac file: #{e.message}"
  end
end

# BlockHeader knows how to parse the METADATA_BLOCK_HEADER. Every header is eactly 4 bytes in length. The first byte
# contains a bit-flag which declares if it is the last block, and 7 bits which represent the type. The other 3 bytes
# contain the length of the block, not including the header.
class BlockHeader
  attr_reader :type, :block_size, :offset, :is_last

  def self.read(io)
    #  first bit = Last-metadata-block flag
    #  bits 2-8 = BLOCK_TYPE. See type_table above
    block_header = io.read(1).unpack1('C')
    is_last = (block_header >> 7) & 0xF
    type = block_header & 0x7F
    # 7-126 are reserved, and will be implemented as Unknown.
    # 127 is explicitly labelled as 'invalid' by the spec.
    raise FlacInfoReadError, 'Invalid block header type' if type == 127

    block_size = "\u0000#{io.read(3)}".unpack1('N')
    offset = io.tell
    new(type, block_size, offset, is_last)
  end

  def initialize(type, block_size, offset, is_last)
    @type       = type
    @block_size = block_size
    @offset     = offset
    @is_last    = is_last
  end
end

# Block is a superclass that contains the attributes common to all
# METADATA_BLOCK_DATA blocks, regardless of type.
class Block
  include Enumerable
  attr_reader :type, :block_size, :offset, :is_last

  def initialize(header)
    @type       = header.type
    @block_size = header.block_size
    @offset     = header.offset
    @is_last    = header.is_last
  end

  def block_name
    self.class::BLOCK_NAME
  end

  def fields
    self.class::FIELDS
  end

  def each
    self.class::FIELDS.each do |field|
      yield field, public_send(field)
    end
  end

  alias each_pair each

  def to_h
    each.to_h
  end

  def [](key)
    public_send(key.to_sym)
  rescue NoMethodError
    raise FlacInfoError, "No such key: #{key}"
  end

  def inspect
    attrs = self.class::FIELDS.map do |field|
      "#{field}=#{self[field].inspect}"
    end.join(', ')

    "#<#{self.class} #{attrs}>"
  end

  private

  def build_block_header(type, size, last)
    # Combine last (1 bit), type (7 bits), and size (24 bits) into a 32-bit integer
    header_int = ((last & 1) << 31) | ((type & 0x7f) << 24) | (size & 0xffffff)

    # Pack the 32-bit integer as a big-endian network byte order string
    [header_int].pack('N')
  rescue StandardError => e
    raise FlacInfoWriteError, "error building block header: #{e.message}"
  end
end

# This block has information about the whole stream, like sample rate, number of channels, total number of samples, etc.
# It must be present as the first metadata block in the stream. Other metadata blocks may follow, and ones that the
# decoder doesn't understand, it will skip.
class Streaminfo < Block
  attr_reader :minimum_block, :maximum_block, :minimum_frame, :maximum_frame, :samplerate, :channels, :bits_per_sample,
              :total_samples, :md5

  FIELDS = %w[offset block_size minimum_block maximum_block minimum_frame maximum_frame samplerate channels
              bits_per_sample total_samples md5].freeze
  BLOCK_NAME = 'STREAMINFO'.freeze

  def initialize(io, header)
    super(header)
    @io = io
    parse_streaminfo
  end

  private

  def parse_channels_and_samples
    #  64 bits in big-endian order
    value = @io.read(8).unpack1('Q>')
    #  20 bits :: Sample rate in Hz.
    @samplerate = (value >> 44) & 0xFFFFF
    #  3 bits :: (number of channels) - 1.
    @channels = ((value >> 41) & 0x7) + 1
    #  5 bits :: (bits per sample) - 1.
    @bits_per_sample = ((value >> 36) & 0x1F) + 1
    #  36 bits :: Total samples in stream.
    @total_samples = value & 0xFFFFFFFFF
  end

  def parse_blocks_and_frames
    @minimum_block = @io.read(2).unpack1('n*')
    @maximum_block = @io.read(2).unpack1('n*')
    bytes = @io.read(3).bytes
    @minimum_frame = (bytes[0] << 16) | (bytes[1] << 8) | bytes[2]
    bytes = @io.read(3).bytes
    @maximum_frame = (bytes[0] << 16) | (bytes[1] << 8) | bytes[2]
  end

  def parse_streaminfo
    parse_blocks_and_frames
    parse_channels_and_samples

    # 128 bits :: MD5 signature of the unencoded audio data.
    @md5 = @io.read(16).unpack1('H32')
  rescue StandardError => e
    raise FlacInfoReadError, "Could not parse METADATA_BLOCK_STREAMINFO: #{e.message}"
  end

  # Return a byte-representation of the stream marker, STREAMINFO header, and STREAMINFO block. The only thing that
  # could have possibly changed is whether it's the last block or not. Size and content is persistent no matter what
  # else in the Stream object may have changed, so we just read it from the original file.
  def serialize(filename)
    payload = ''.b
    payload << 'fLaC'
    payload << build_block_header(@type, @block_size, @is_last)
    payload << File.binread(filename, @block_size, @offset)
  end
end

# This block allows for an arbitrary amount of padding. The contents of a PADDING block have no meaning. This block is
# useful when it is known that metadata will be edited after encoding; the user can instruct the encoder to reserve a
# PADDING block of sufficient size so that when metadata is added, it will simply overwrite the padding (which is
# relatively quick) instead of having to insert it into the right place in the existing file (which would normally
# require rewriting the entire file).
class Padding < Block
  FIELDS = %w[offset block_size].freeze
  BLOCK_NAME = 'PADDING'.freeze

  def initialize(io, header)
    super(header)
    @io = io
    @new = false
    @dirty = false
    parse_padding
  end

  private

  def parse_padding
    # Padding is just zero-bytes * block_size, so there's nothing really to parse. We just need to fast-forward to the
    # end of the padding block.
    @io.seek(@block_size, IO::SEEK_CUR)
  rescue StandardError => e
    raise FlacInfoReadError, "Could not parse METADATA_BLOCK_PADDING: #{e.message}"
  end

  def serialize
    data = build_block_header(@type, @block_size, @is_last)
    data + "\0" * @block_size
  end
end

# This is an optional block for storing seek points. It is possible to seek to any given sample in a FLAC stream without
# a seek table, but the delay can be unpredictable since the bitrate may vary widely within a stream. By adding seek
# points to a stream, this delay can be significantly reduced. Each seek point takes 18 bytes, so 1% resolution within a
# stream adds less than 2k. There can be only one SEEKTABLE in a stream, but the table can have any number of seek
# points. There is also a special 'placeholder' seekpoint which will be ignored by decoders but which can be used to
# reserve space for future seek point insertion.
class Seektable < Block
  attr_reader :seek_points, :points

  FIELDS = %w[offset block_size seek_points points].freeze
  BLOCK_NAME = 'SEEKTABLE'.freeze

  def initialize(io, header)
    super(header)
    @io = io
    parse_seektable
  end

  private

  def parse_points
    n = 0
    @seek_points.times do
      pt_arr = []
      pt_arr << @io.read(8).unpack1('Q>')
      pt_arr << @io.read(8).unpack1('Q>')
      pt_arr << @io.read(2).unpack1('S>')
      @points[n] = pt_arr
      n += 1
    end
  end

  def parse_seektable
    @seek_points = @block_size / 18
    @points = {}
    parse_points
  rescue StandardError => e
    raise FlacInfoReadError, "Could not parse METADATA_BLOCK_SEEKTABLE: #{e.message}"
  end

  ###
  def serialize(filename)
    payload = ''.b
    payload << build_block_header(@type, @block_size, @is_last)
    payload << File.binread(filename, @block_size, @offset)
  end
end

# This block is for storing various information that can be used in a cue sheet. It supports track and index points,
# compatible with Red Book CD digital audio discs, as well as other CD-DA metadata such as media catalogue number and
# track ISRCs. The CUESHEET block is especially useful for backing up CD-DA discs, but it can be used as a general
# purpose cueing mechanism for playback.
class Cuesheet < Block
  attr_reader :media_catalog_number, :lead_in, :is_cd, :n_tracks, :cuesheet_tracks

  FIELDS = %w[offset block_size media_catalog_number lead_in is_cd n_tracks cuesheet_tracks].freeze
  BLOCK_NAME = 'CUESHEET'.freeze

  Track = Struct.new(
    :offset,
    :track_number,
    :isrc,
    :type,
    :preemphasis,
    :indices
  )

  def initialize(io, header)
    super(header)
    @io = io
    @cuesheet_tracks = []
    parse_cuesheet
  end

  private

  def parse_cuesheet_track
    track = Track.new
    track.offset = @io.read(8).unpack1('Q>')
    track.track_number = @io.read(1).unpack1('C')
    raw_isrc = @io.read(12)
    track.isrc = raw_isrc unless raw_isrc == "\0" * 12
    raw_byte = @io.read(1).unpack1('C')
    track.type = ((raw_byte >> 7) & 0x1).zero? ? 'AUDIO' : 'NON-AUDIO'
    track.preemphasis = ((raw_byte >> 6) & 0x1) == 1
    # 13 zero bytes.
    @io.read(13)
    n = @io.read(1).unpack1('C')
    track.indices = []

    n.times do
      offset = @io.read(8).unpack1('Q>')
      index = @io.read(1).unpack1('C')
      # 3 zero bytes
      @io.read(3)
      track.indices << [offset, index]
    end

    @cuesheet_tracks << track
  end

  def parse_cuesheet
    raw = @io.read(128)
    catalog = raw.partition("\0").first
    @media_catalog_number = catalog unless catalog.empty?
    @lead_in = @io.read(8).unpack1('Q>')
    # First bit of this next byte is the CD? flag.
    @is_cd = ((@io.read(1).unpack1('C') >> 7) & 0x1) == 1
    # 258 bytes reserved. All bits must be set to zero.
    @io.read(258)
    @n_tracks = @io.read(1).unpack1('C')

    @n_tracks.times do
      parse_cuesheet_track
    end
  rescue StandardError => e
    raise FlacInfoReadError, "Could not parse METADATA_BLOCK_CUESHEET: #{e.message}"
  end

  def serialize(filename)
    data = build_block_header(@type, @block_size, @is_last)
    data + File.binread(filename, @block_size, @offset)
  end
end

# This block is for storing pictures associated with the file, most commonly cover art from CDs. There may be more than
# one PICTURE block in a file. The picture format is similar to the APIC frame in ID3v2. The PICTURE block has a type,
# MIME type, and UTF-8 description like ID3v2, and supports external linking via URL (though this is discouraged). The
# differences are that there is no uniqueness constraint on the description field, and the MIME type is mandatory. The
# FLAC PICTURE block also includes the resolution, colour depth, and palette size so that the client can search for a
# suitable picture without having to scan them all.
class Picture < Block
  attr_reader :type_int, :type_string, :description_string, :mime_type, :colour_depth, :n_colours, :width, :height,
              :raw_data_offset, :raw_data_length

  PICTURE_TYPE = ['Other', '32x32 pixels file icon', 'Other file icon', 'Cover (front)', 'Cover (back)', 'Leaflet page',
                  'Media', 'Lead artist/lead performer/soloist', 'Artist/performer', 'Conductor', 'Band/Orchestra',
                  'Composer', 'Lyricist/text writer', 'Recording Location', 'During recording', 'During performance',
                  'Movie/video screen capture', 'A bright coloured fish', 'Illustration', 'Band/artist logotype',
                  'Publisher/Studio logotype'].freeze
  FIELDS = %w[offset block_size type_int type_string description_string mime_type colour_depth n_colours width height
              raw_data_offset raw_data_length].freeze
  BLOCK_NAME = 'PICTURE'.freeze

  def initialize(io, header)
    super(header)
    @io = io
    @new = false
    parse_picture
  end

  def to_h
    FIELDS.to_h { |field| [field, public_send(field)] }
  end

  private

  def parse_picture
    @type_int           = @io.read(4).unpack1('L>')
    @type_string        = PICTURE_TYPE[@type_int]
    mime_length         = @io.read(4).unpack1('L>')
    @mime_type          = @io.read(mime_length)
    description_length  = @io.read(4).unpack1('L>')
    @description_string = @io.read(description_length)
    @width              = @io.read(4).unpack1('L>')
    @height             = @io.read(4).unpack1('L>')
    @colour_depth       = @io.read(4).unpack1('L>')
    @n_colours          = @io.read(4).unpack1('L>')
    @raw_data_length    = @io.read(4).unpack1('L>')
    @raw_data_offset    = @io.tell
    # Fast-forward over the picture data to the next block header.
    @io.seek(@raw_data_length, IO::SEEK_CUR)
  rescue StandardError => e
    raise FlacInfoReadError, "Could not parse METADATA_BLOCK_PICTURE: #{e.message}"
  end

  def serialize(filename)
    data = build_block_header(@type, @block_size, @is_last)
    if @new
      # What we do?
    else
      data += File.binread(filename, @block_size, @offset)
    end
    data
  end
end

# This block is for use by third-party applications. The only mandatory field is a 32-bit identifier. This ID is granted
# upon request to an application by the FLAC maintainers. The remainder is of the block is defined by the registered
# application. The registered applications are listed on the registration page:
# https://www.iana.org/assignments/flac/flac.xhtml
class Application < Block
  attr_reader :id, :name, :raw_data, :flac_file

  FIELDS = %w[block_size offset id name raw_data flac_file].freeze
  BLOCK_NAME = 'APPLICATION'.freeze

  APP_ID = {
    '41544348' => 'FlacFile',
    '42534F4C' => 'beSolo',
    '42554753' => 'Bugs Player',
    '43756573' => 'GoldWave cue points',
    '46696361' => 'CUE Splitter',
    '46746F6C' => 'flac-tools',
    '4D4F5442' => 'MOTB MetaCzar',
    '4D505345' => 'MP3 Stream Editor',
    '4D754D4C' => 'MusicML: Music Metadata Language',
    '52494646' => 'Sound Devices RIFF chunk storage',
    '5346464C' => 'Sound Font FLAC',
    '534F4E59' => 'Sony Creative Software',
    '5351455A' => 'flacsqueeze',
    '54745776' => 'TwistedWave',
    '55495453' => 'UITS Embedding tools',
    '61696666' => 'FLAC AIFF chunk storage',
    '696D6167' => 'flac-image',
    '7065656D' => 'Parseable Embedded Extensible Metadata',
    '71667374' => 'QFLAC Studio',
    '72696666' => 'FLAC RIFF chunk storage',
    '74756E65' => 'TagTuner',
    '77363420' => 'FLAC Wave64 chunk storage',
    '78626174' => 'XBAT',
    '786D6364' => 'xmcd'
  }.freeze

  def initialize(io, header)
    super(header)
    @io = io
    parse_application
  end

  private

  # See http://firestuff.org/flacfile/
  def parse_flac_file_contents(size)
    @flac_file = {}
    desc_length = @io.read(1).unpack1('C')
    @flac_file['description'] = @io.read(desc_length)
    mime_length = @io.read(1).reverse.unpack1('C')
    @flac_file['mime_type'] = @io.read(mime_length)
    size = size - 2 - desc_length - mime_length
    @flac_file['raw_data'] = @io.read(size)
  rescue StandardError => e
    raise FlacInfoReadError, "Could not parse Flac File data: #{e.message}"
  end

  def parse_application
    @id = @io.read(4).unpack1('H*')
    @name = APP_ID[@id].to_s

    #  We only know how to parse data from 'Flac File'...
    if @id == '41544348'
      parse_flac_file_contents(@block_size - 4)
    else
      @raw_data = @io.read(@block_size - 4)
    end
  rescue StandardError => e
    raise FlacInfoReadError, "Could not parse METADATA_BLOCK_APPLICATION: #{e.message}"
  end
end

# This block is for storing a list of human-readable name/value pairs. Values are encoded using UTF-8. It is an
# implementation of the Vorbis comment specification (without the framing bit). This is the only officially supported
# tagging mechanism in FLAC. There may be only one VORBIS_COMMENT block in a stream. In some external documentation,
# Vorbis comments are called FLAC tags to lessen confusion.
class VorbisComment < Block
  attr_reader :tags, :comment

  BLOCK_NAME = 'VORBIS_COMMENT'.freeze
  FIELDS = %w[offset block_size comment tags].freeze

  def initialize(io, header)
    super(header)
    @io = io
    @tags = {}
    @comment = []
    @tags['block_size'] = @block_size
    @tags['offset'] = @offset
    @new = false
    @dirty = false

    parse_vorbis_comments
  end

  def self.from_scratch
    # 2. Instantiate the Struct cleanly using keyword arguments
    header = FakeHeader.new(type: 4, block_size: 0, offset: nil, is_last: true)

    # 3. Call new with a nil IO and your fake header
    instance = new(nil, header)

    # 4. Customize the state
    instance.tags['vendor_tag'] = "FlacInfo version #{FLAC_INFO_VERSION}"
    instance.instance_variable_set(:@new, true)
    instance.instance_variable_set(:@dirty, true)

    instance
  end

  def add_comment(str)
    @comment << str
    split_comment(str) # Add to tags hash.
    @dirty = true
  end

  def delete_comment(key)
    # Remove all matching strings from the array (e.g. "Artist=...")
    @comment.reject! { |c| c.start_with?("#{key}=") }
    @tags.delete(key) # Remove it from the hash
    @dirty = true
  end

  def [](key)
    @tags[key]
  end

  def each_pair(&block)
    @tags.each_pair(&block)
  end

  def keys
    @tags.keys
  end

  def to_h
    @tags.dup
  end

  private

  def split_comment(str)
    k, v = str.split('=', 2)
    #  Vorbis spec says we can have more than one identical comment ie:
    #  comment[0]="Artist=Charlie Parker"
    #  comment[1]="Artist=Miles Davis"
    #  so we just append the second and subsequent values to the first
    @tags[k] = if @tags.key?(k)
                 "#{@tags[k]}, #{v}"
               else
                 v
               end
  end

  def split_comments
    @comment.each do |c|
      split_comment(c)
    end
  end

  def parse_vorbis_comments
    vendor_length = @io.read(4).unpack1('L<')
    @tags['vendor_tag'] = @io.read(vendor_length)

    user_comment_list_length = @io.read(4).unpack1('L<')
    n = 0
    user_comment_list_length.times do
      length = @io.read(4).unpack1('L<')
      @comment[n] = @io.read(length)
      n += 1
    end

    split_comments
  rescue StandardError => e
    raise FlacInfoReadError, "Could not parse METADATA_BLOCK_VORBIS_COMMENT: #{e.message}"
  end

  def build_vorbis_comment_block
    # Initialize an empty string, forced to binary encoding (.b)
    payload = ''.b

    vendor = @tags['vendor_tag'].to_s
    payload << [vendor.bytesize].pack('V')
    payload << vendor

    payload << [@comment.length].pack('V')

    @comment.each do |c|
      payload << [c.bytesize].pack('V')
      payload << c.to_s
    end

    payload
  rescue StandardError => e
    raise FlacInfoWriteError, "Could not build METADATA_BLOCK_VORBIS_COMMENT: #{e.message}"
  end

  def serialize(filename)
    packed_tags = if @new || @dirty
                    build_vorbis_comment_block
                  else
                    File.binread(filename, @block_size, @offset)
                  end
    data = build_block_header(@type, packed_tags.bytesize, @is_last)
    data + packed_tags
  end
end

# 'Unknown' blocks are present when a METADATA_BLOCK has type 7-126, which are reserved for future use as per the spec.
# The presence of one of these types likely indicates an invalid block, but we present it as unknown to be future-proof,
# that is, the spec recommends ignoring blocks we don't understand.
class Unknown < Block
  def initialize(io, header)
    super(header)
    @io = io
    skip_unknown
  end

  # Just fast-forward over the block.
  def skip_unknown
    @io.seek(@block_size, IO::SEEK_CUR)
  end

  def serialize(filename)
    data = build_block_header(@type, @block_size, @is_last)
    data + File.binread(filename, @block_size, @offset)
  end
end

# Mapping from block types to the classes that represent them. Defined down here, as otherwise we get an undefined
# constant error because these classes must be instantiated. This table is used for the dynamic dispatch in the
# read_header method in the Stream class.
BLOCK_TYPES = {
  0 => Streaminfo,
  1 => Padding,
  2 => Application,
  3 => Seektable,
  4 => VorbisComment,
  5 => Cuesheet,
  6 => Picture
}.freeze

# This class formats the metadata blocks for use with 'meta_flac', as well as the individual 'print_<block type>'
# methods.
class MetaFlacPrinter
  attr_reader :flac, :io

  def initialize(flac, io, which = :all)
    @flac = flac
    @io = io
    @which = which
  end

  def print
    blocks =
      if @which == :all
        @flac.blocks
      else
        result = @flac.public_send(@which)
        result.is_a?(Array) ? result : [result]
      end

    blocks.each do |block|
      n = @flac.blocks.index(block)
      @block = block

      @io.puts "METADATA block ##{n}"
      @io.puts "  type: #{@block.type} (#{@block.block_name})"
      @io.puts "  is last: #{@block.is_last.zero? ? 'false' : 'true'}"

      case block.type
      when 0
        meta_stream
      when 1
        meta_pad
      when 2
        meta_app
      when 3
        meta_seek
      when 4
        meta_vorb
      when 5
        meta_cue
      when 6
        meta_pict
      else
        @io.puts "  length: #{@block.block_size}"
      end
    end
    nil
  end

  def meta_stream
    @io.puts "  length: #{@block.block_size}"
    @io.puts "  minimum blocksize: #{@block.minimum_block} samples"
    @io.puts "  maximum blocksize: #{@block.maximum_block} samples"
    @io.puts "  minimum framesize: #{@block.minimum_frame} bytes"
    @io.puts "  maximum framesize: #{@block.maximum_frame} bytes"
    @io.puts "  sample rate: #{@block.samplerate} Hz"
    @io.puts "  channels: #{@block.channels}"
    @io.puts "  bits-per-sample: #{@block.bits_per_sample}"
    @io.puts "  total samples: #{@block.total_samples}"
    @io.puts "  MD5 signature: #{@block.md5}"
  end

  def meta_pad
    @io.puts "  length: #{@block.block_size}"
  end

  def meta_app
    @io.puts "  length: #{@block.block_size}"
    @io.puts "  id: #{@block.id}"
    @io.puts "  application name: #{@block.name}"
    if @block.id == '41544348'
      @io.puts "    description: #{@block.flac_file['description']}"
      @io.puts "    mime type: #{@block.flac_file['mime_type']}"
      #  Don't want to dump binary data
      if @block.flac_file['mime_type'] =~ /text/
        @io.puts '    raw data:'
        @io.puts @block.flac_file['raw_data']
      else
        @io.puts "'Flac File' data may be binary. Use 'raw_data_dump' to see it"
      end
    else
      @io.puts '    raw data'
      @io.puts @block.raw_data
    end
  end

  def meta_seek
    @io.puts "  length: #{@block.block_size}"
    @io.puts "  seek points: #{@block.seek_points}"
    n = 0
    points = @block.points
    @block.seek_points.times do
      @io.print "    point #{n}: sample number: #{points[n][0]}, "
      @io.print "stream offset: #{points[n][1]}, "
      @io.print "frame samples: #{points[n][2]}\n"
      n += 1
    end
  end

  def meta_vorb
    @io.puts "  length: #{@block.block_size}"
    @io.puts "  vendor string: #{@block.tags['vendor_tag']}"
    @io.puts "  comments: #{@block.comment.size}"
    n = 0
    @block.comment.each do |v|
      @io.puts "    comment[#{n}]: #{v}"
      n += 1
    end
  end

  def meta_cue
    @io.puts "  length: #{@block.block_size}"
    @io.puts "  media catalog number: #{@block.media_catalog_number}"
    @io.puts "  lead in: #{@block.lead_in}"
    @io.puts "  is CD: #{@block.is_cd}"
    @io.puts "  number of tracks: #{@block.cuesheet_tracks.size}"
    @block.cuesheet_tracks.each_with_index do |ct, i|
      puts "    track[#{i}]"
      puts "      offset: #{ct.offset}"
      puts "      number: #{ct.track_number}"
      puts "      ISRC: #{ct.isrc}"
      puts "      type: #{ct.type}"
      puts "      pre-emphasis: #{ct.preemphasis}"
      puts "      number of index.points: #{ct.indices.size}"
      ct.indices.each_with_index do |idx, j|
        puts "        index[#{j}]"
        puts "          offset: #{idx[0]}"
        puts "          number: #{idx[1]}"
      end
    end
  end

  def meta_pict
    @io.puts "  length: #{@block.block_size}"
    @io.puts "  type: #{@block.type_int} => #{@block.type_string}"
    @io.puts "  mimetype: #{@block.mime_type}"
    @io.puts "  description: #{@block.description_string}"
    @io.puts "  image width: #{@block.width}"
    @io.puts "  image height: #{@block.height}"
    @io.puts "  colour depth: #{@block.colour_depth}"
    @io.puts "  number of colours: #{@block.n_colours}"
    @io.puts "  image size: #{@block.raw_data_length} bytes"
  end
end

# FlacInfo presents the public interface.
#
# STREAMINFO is the only block guaranteed to be present in the Flac file.
# The following 11 accessors will be present but return `nil` if the associated block is not present in the Flac file.
# All except for `comment` and `tags` may be accessed using either the dot operator:
#
#    `FlacInfo.streaminfo.block_size => 34`
#
# Or using Hash syntax:
#
#    `FlacInfo.streaminfo['block_size'] => 34`
#
# All 'offset' and 'block_size' values do not include the block header regardless of the block type. All block headers
# are 4 bytes no matter the type, so if you need the offset including the header, subtract 4. If you need the size
# including the header, add 4.
class FlacInfo
  # Access to values extracted from the STREAMINFO block. The fields are:
  # * `offset` - The STREAMINFO block's offset from the beginning of the file (not including the block header).
  # * `block_size` - The size of the STREAMINFO block (not including the block header).
  # * `minimum_block` - The minimum block size (in samples) used in the stream.
  # * `maximum_block` - The maximum block size (in samples) used in the stream.
  # * `minimum_frame` - The minimum frame size (in bytes) used in the stream.
  # * `maximum_frame` - The maximum frame size (in bytes) used in the stream.
  # * `samplerate` - Sample rate in Hz.
  # * `channels` - The number of channels used in the stream.
  # * `bits_per_sample` - The number of bits per sample used in the stream.
  # * `total_samples` - The total number of samples in stream.
  # * `md5` - MD5 signature of the raw audio data frames.
  def streaminfo
    @flac.streaminfo
  end

  # Access to values extracted from the SEEKTABLE block. Fields are -
  # * `offset` - The SEEKTABLE block's offset from the beginning of the file (not including the block header).
  # * `block_size` - The size of the SEEKTABLE block (not including the block header).
  # * `seek_points` - The number of seek points in the block.
  # * `points` - A hash whose keys start at 0 and end at ('seek_points' - 1). Each `seektable.points[n]` hash key
  # contains an array whose (integer) values are -
  #     * `0` - Sample number of first sample in the target frame, or 0xFFFFFFFFFFFFFFFF for a placeholder point.
  #     * `1` - Offset (in bytes) from the first byte of the first frame header to the first byte of the target frame's
  # header.
  #      * `2` - Number of samples in the target frame.
  def seektable
    @flac.seektable
  end

  # Array of `name=value` strings extracted from the VORBIS_COMMENT block. This is just the contents, metadata is in
  # `tags`. You should not normally operate on this array directly. Rather, use the comment_add and comment_del methods
  # to make changes.
  def comment
    @flac.vorbis_comment.comment
  end

  # Hash of each `comment` value separated into `key => value` pairs as well as the keys:
  # * `offset` - The VORBIS_COMMENT block's offset from the beginning of the file (not including the block header).
  # * `block_size` - The size of the VORBIS_COMMENT block (not including the block header).
  # * `vendor_tag` - Typically, the name and version of the software that encoded the file.
  def tags
    @flac.vorbis_comment.tags
  end

  # Values extracted from the APPLICATION block. Keys are:
  # * `offset` - The APPLICATION block's offset from the beginning of the file (not including the block header).
  # * `block_size` - The size of the APPLICATION block (not including the block header).
  # * `id`- Registered application ID, as a hex string. See http://flac.sourceforge.net/id.html
  # * `name`- Name of the registered application ID.
  def application
    @flac.application
  end

  def applications
    @flac.applications
  end

  # Values extracted from the PADDING block. Keys are:
  # 'offset'- The PADDING block's offset from the beginning of the file (not including the block header).
  # 'block_size'- The size of the PADDING block (not including the block header).
  def padding
    @flac.padding
  end

  # Values extracted from the CUESHEET block. Keys are:
  # 'offset'- The CUESHEET block's offset from the beginning of the file (not including the block header).
  # 'block_size'- The size of the CUESHEET block (not including the block header).
  def cuesheet
    @flac.cuesheet
  end

  # Values extracted from one or more PICTURE blocks. This hash always includes the key 'n' which is the number
  # of PICTURE blocks found, else '0'. For each block found there will be an integer key starting from 1. Each of these
  # is a hash which contains the keys:
  # * 'offset' - The PICTURE block's offset from the beginning of the file (not including the block header).
  # * 'block_size' - The size of the PICTURE block (not including the block header).
  # * 'type_int' - The picture type according to the ID3v2 APIC frame.
  # * 'type_string' - A text value representing the picture type.
  # * 'description_string' - A text description of the picture.
  # * 'mime_type' - The MIME type string. May be ' -->' to signify that the data part is a URL of the picture.
  # * 'colour_depth' - The colour depth of the picture in bits-per-pixel.
  # * 'n_colours' - For indexed-colour pictures (e.g. GIF), the number of colours used, or 0 for non-indexed pictures.
  # * 'width' - The width of the picture in pixels.
  # * 'height' - The height of the picture in pixels.
  # * 'raw_data_offset' - The raw picture data's offset from the beginning of the file.
  # * 'raw_data_length' - The length of the picture data in bytes.
  #
  # 'picture' returns the first picture block found directly.
  def picture
    @flac.picture
  end

  # 'pictures' returns an array of all picture blocks found, possibly length 1.
  def pictures
    @flac.pictures
  end

  # Values extracted from an APPLICATION block if it is type 0x41544348 (FlacFile). Fields are:
  # * 'description'- A brief text description of the contents.
  # * 'mime_type'- The Mime type of the contents.
  # * 'raw_data'- The contents. May be binary.
  def flac_file
    @flac.flac_file
  end

  # FlacInfo is the class for parsing Flac files.
  #
  #   FlacInfo.new(file)   -> FlacInfo instance
  #
  def initialize(filename)
    @filename = filename
    parse_flac_meta_blocks
  end

  # Returns true if @tags[tag] has a value, false otherwise.
  #
  # :call-seq:
  #   FlacInfo.hastag?(tag)   -> bool
  #
  def hastag?(tag)
    return false if tags.nil?

    @flac.vorbis_comment[tag] ? true : false
  end

  # Pretty print tags hash.
  #
  # :call-seq:
  #   FlacInfo.print_tags   -> nil
  #
  # Raises FlacInfoError if METADATA_BLOCK_VORBIS_COMMENT is not present.
  #
  def print_tags
    raise FlacInfoError, 'METADATA_BLOCK_VORBIS_COMMENT not present' if tags.nil?

    @flac.vorbis_comment.each_pair { |key, val| puts "#{key}: #{val}" }
    nil
  end

  # Pretty print streaminfo hash.
  #
  # :call-seq:
  #   FlacInfo.print_streaminfo   -> nil
  #
  def print_streaminfo
    MetaFlacPrinter.new(@flac, $stdout, :streaminfo).print
    nil
  end

  # Pretty print the seektable.
  #
  # :call-seq:
  #   FlacInfo.print_seektable   -> nil
  #
  # Raises FlacInfoError if METADATA_BLOCK_SEEKTABLE is not present.
  #
  def print_seektable
    raise FlacInfoError, 'METADATA_BLOCK_SEEKTABLE not present' if seektable.nil?

    MetaFlacPrinter.new(@flac, $stdout, :seektable).print
    nil
  end

  # Pretty print the cuesheet.
  #
  # :call-seq:
  #   FlacInfo.print_cuesheet   -> nil
  #
  # Raises FlacInfoError if METADATA_BLOCK_CUESHEET is not present.
  #
  def print_cuesheet
    raise FlacInfoError, 'METADATA_BLOCK_CUESHEET not present' if cuesheet.nil?

    MetaFlacPrinter.new(@flac, $stdout, :cuesheet).print
    nil
  end

  # Pretty print the picture block(s).
  #
  # :call-seq:
  #   FlacInfo.print_picture   -> nil
  #
  # Raises FlacInfoError if METADATA_BLOCK_PICTURE is not present.
  #
  def print_picture
    raise FlacInfoError, 'METADATA_BLOCK_PICTURE not present' if pictures.nil?

    MetaFlacPrinter.new(@flac, $stdout, :pictures).print
    nil
  end

  # This method produces output similar to 'metaflac --list'.
  #
  # :call-seq:
  #   FlacInfo.meta_flac ->   nil
  def meta_flac(target = $stdout)
    if target.is_a?(String)
      File.open(target, 'w') do |f|
        MetaFlacPrinter.new(@flac, f).print
      end
    else
      MetaFlacPrinter.new(@flac, target).print
    end
  end

  # Dumps the contents of flac_file['raw_data']
  #
  # :call-seq:
  #   FlacInfo.raw_data_dump()          -> nil
  #   FlacInfo.raw_data_dump(outfile)   -> nil
  #
  # If passed with 'outfile', the data will be written to a file with that name
  # otherwise it is written to the console (even if binary!). Raises FlacInfoError
  # if there is no Flac File data present.
  #
  def raw_data_dump(outfile = nil)
    raise FlacInfoError, 'Flac File data not present' if flac_file == {}

    if outfile.nil?
      puts @flac_file['raw_data']
    else
      f = if @flac_file['mime_type'] =~ /text/
            File.new(outfile, 'w')
          else
            File.new(outfile, 'wb')
          end
      f.write(@flac_file['raw_data'])
      f.close
    end
  end

  # Writes embedded images to a file
  #
  # :call-seq:
  #   FlacInfo.write_picture()                           -> nil
  #   FlacInfo.write_picture(:outfile=>"str")            -> nil
  #   FlacInfo.write_picture(:n=>int)                    -> nil
  #   FlacInfo.write_picture(:outfile=>"str", :n=>int)   -> nil
  #
  # If passed with ':outfile', the image will be written to a file with that name
  # otherwise it is written to the value of the 'album' tag if it exists, otherwise it
  # is written to 'flacimage'. All three of these will have a dot plus the relevant file
  # extension appended. The argument to ':n' is which image to write in case of multiples.
  #
  def write_picture(args = {})
    raise FlacInfoError, 'There is no METADATA_BLOCK_PICTURE' if pictures.nil?

    n = if args.key?(:n)
          args[:n]
        else
          0
        end

    #  "image/jpeg" => "jpeg"
    extension = @picture[n]['mime_type'].split('/')[1]

    outfile = if !args.key?(:outfile)
                if [nil, ''].include?(@tags['album'])
                  "flac_image#{n}.#{extension}"
                else
                  #  Try to use contents of "album" tag for the filename
                  "#{@tags['album']}#{n}.#{extension}"
                end
              else
                "#{args[:outfile]}.#{extension}"
              end

    in_p  = File.new(@filename, 'rb')
    out_p = File.new(outfile, 'wb')

    out_p.binmode #  For Windows folks...

    in_p.seek(@picture[n]['raw_data_offset'], IO::SEEK_SET)
    raw_data = in_p.read(@picture[n]['raw_data_length'])
    out_p.write(raw_data)

    in_p.close
    out_p.close

    nil
  end

  # Writes any changes to disk
  #
  # :call-seq:
  #   FlacInfo.write_file!             -> bool
  #   FlacInfo.write_file(filename)!   -> bool
  #
  # Returns true if write was successful, false otherwise. If the optional 'filename' is passed to the method, then the
  # flac will be written to that file. Otherwise, the original input file will be overwritten in-place.
  #
  def write_file!(filename = nil)
    @flac.write_file(filename)
  end

  # Adds a new comment to the comment array
  #
  # :call-seq:
  #   FlacInfo.comment_add(str)   -> bool
  #
  # 'str' must be in the form 'name=value', or 'name=' if you want to
  # set an empty value for a particular tag. Returns 'true' if successful,
  # false otherwise.
  #
  def comment_add(str)
    if str !~ /\w=/ #  We accept 'name=' in case you want to leave the value empty
      raise FlacInfoError, "comments must be in the form 'name=value'"
    end

    # Find the existing block, or tell Stream to create one and return it
    block = @flac.vorbis_comment || @flac.create_comment_block

    # Tell the block to update itself
    block.add_comment(str)

    true
  end

  # Deletes a comment from the comment array
  #
  # :call-seq:
  #   FlacInfo.comment_del(str)   -> bool
  #
  # If 'str' is in the form 'name=value' only exact matches
  # will be deleted. If 'str' is in the form 'name' any and all
  # comments named 'name' will be deleted. Returns 'true' if a
  # comment was deleted, false otherwise. Remember to call
  # 'update!' to write changes to the file.
  #
  def comment_del(key)
    block = @flac.vorbis_comment

    # If there is no Vorbis block, there's nothing to delete!
    return false if block.nil?

    block.delete_comment(key)
    true
  end

  # Adds a padding block
  #
  # :call-seq:
  #   FlacInfo.padding_add!(size)   --> Boolean
  #
  # 'size' is an optional integer argument for the
  # size of the padding block. It defaults to 4096 bytes.
  # Returns true if successful, else false.
  #
  def padding_add!(size = 4096)
    @metadata_blocks.each do |type|
      raise FlacInfoError, "PADDING block exists. Use 'padding_resize!'" if type[0] == 'padding'
    end
    build_padding_block(size) ? true : false
  end

  # Removes a padding block
  #
  # :call-seq:
  #   FlacInfo.padding_del!()   --> Boolean
  #
  # Returns true if the padding block is
  # successfully removed else false.
  #
  def padding_del!
    remove_padding_block ? true : false
  end

  # Resizes a padding block
  #
  # :call-seq:
  #   FlacInfo.padding_resize!(size)   --> Boolean
  #
  # 'size' is an optional integer argument for the
  # size of the new padding block. It defaults to 4096 bytes.
  # Returns true if successful, else false.
  #
  def padding_resize!(size = 4096)
    remove_padding_block
    build_padding_block(size)
  end

  #--
  #  This cleans up the output when using FlacInfo in irb
  def inspect # :nodoc:
    blocks = @flac.blocks.map do |blk|
      "(#{blk.class::BLOCK_NAME} size=#{blk.block_size} offset=#{blk.offset})"
    end.join(' ')

    "#<#{self.class}:0x#{(object_id * 2).to_s(16)} #{blocks}>"
  end
  #++

  private

  #  This is where the 'real' parsing starts
  def parse_flac_meta_blocks
    @flac = Stream.new(@filename)
  end

  def write_to_disk
    raise FlacInfoWriteError, 'No changes to write' if @comments_changed.nil?

    #  Build the VORBIS_COMMENT data
    vcd = build_vorbis_comment_block
    #  Build the VORBIS_COMMENT header
    vch = build_block_header(4, vcd.length, 0)

    #  Determine if we can shuffle the data or if a rewrite is necessary
    begin
      if !@padding.key?('block_size') || (vcd.length > @padding['block_size'])
        rewrite(vcd, vch)  # Rewriting is simpler but more expensive
      else
        shuffle(vcd, vch)  # Shuffling is more complicated but cheaper
      end
      parse_flac_meta_blocks #  Parse the file again to update new values
      true
    rescue StandardError => e
      raise FlacInfoWriteError, "error writing new data to #{@filename}: #{e.message}"
    end
  end

  #  Shuffle the data and update the PADDING block
  def shuffle(vcd, vch)
    flac = File.new(@filename, 'r+b')
    flac.binmode #  For Windows folks...

    #  Position ourselves at end of current Vorbis block
    flac.seek(@tags['offset'] + @tags['block_size'], IO::SEEK_SET)
    #  The data we need to shuffle starts at current position and ends at
    #  the beginning of the padding block, so the size we need to read is:
    #
    #  (offset of padding minus 4 bytes for the padding header) minus our current position
    #
    size_to_read = (@padding['offset'] - 4) - flac.tell
    data_to_shuffle = flac.read(size_to_read)

    flac.seek(@tags['offset'] - 4, IO::SEEK_SET)
    flac.write(vch)              #  Write the VORBIS_COMMENT header
    flac.write(vcd)              #  Write the VORBIS_COMMENT data
    flac.write(data_to_shuffle)  #  Write the shuffled data

    new_padding_size = @padding['block_size'] - (vcd.length - @tags['block_size'])
    ph = build_block_header(1, new_padding_size, 1) #  Build the new PADDING header

    flac.write(ph)  #  Write the new PADDING header
    flac.close      #  ...and we're done
  end

  #  Rewrite the entire file
  def rewrite(vcd, vch)
    flac = File.new(@filename, 'r+b')
    flac.binmode #  For Windows folks...

    flac.seek(@tags['offset'] + @tags['block_size'], IO::SEEK_SET)
    rest_of_file = flac.read
    flac.seek(@tags['offset'] - 4, IO::SEEK_SET)

    flac.write(vch)           #  Write the VORBIS_COMMENT header
    flac.write(vcd)           #  Write the VORBIS_COMMENT data
    flac.write(rest_of_file)  #  Write the rest of the file

    flac.close
  end

  # remove the padding block
  def remove_padding_block
    new_last_block = @metadata_blocks[-2]

    flac = File.new(@filename, 'r+b')
    flac.binmode

    flac.seek(@padding['offset'] + @padding['block_size'], IO::SEEK_SET)
    rest_of_file = flac.read

    flac.seek(@padding['offset'] - 4, IO::SEEK_SET)
    flac.write(rest_of_file)
    # Truncate the file at the 'new' end of file.
    flac.truncate(flac.tell)

    nbh = build_block_header(new_last_block[1], new_last_block[4], 1)

    flac.seek(new_last_block[3] - 4, IO::SEEK_SET)
    flac.write(nbh)
    flac.close

    parse_flac_meta_blocks  #  Parse the file again to update new values
    true
  rescue StandardError => e
    raise FlacInfoWriteError, "Could not update padding block: #{e.message}"
  end

  def build_padding_block(size)
    old_last_block = @metadata_blocks[-1]

    a = Array.new(size / 2, 0)
    pbd = a.pack('v*')
    pbh = build_block_header(1, size, 1)

    flac = File.new(@filename, 'r+b')
    flac.binmode

    flac.seek(old_last_block[4] + old_last_block[3], IO::SEEK_SET)
    co = flac.tell
    rest_of_file = flac.read
    flac.seek(co, IO::SEEK_SET)

    flac.write(pbh)
    flac.write(pbd)
    flac.write(rest_of_file)
    nbh = build_block_header(old_last_block[1], old_last_block[4], 0)

    flac.seek(old_last_block[3] - 4, IO::SEEK_SET)
    flac.write(nbh)

    flac.close
    parse_flac_meta_blocks  #  Parse the file again to update new values
    true
  rescue StandardError => e
    raise FlacInfoWriteError, "Could not update padding block: #{e.message}"
  end
end

# If called directly from the command line, run meta_flac on each argument
if __FILE__ == $PROGRAM_NAME
  ARGV.each do |filename|
    FlacInfo.new(filename).meta_flac
    puts
  end
end
