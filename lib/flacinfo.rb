# = Description
#
# flacinfo-rb gives you access to low level information on Flac files.
# * It parses stream information (METADATA_BLOCK_STREAMINFO).
# * It parses Vorbis comments (METADATA_BLOCK_VORBIS_COMMENT).
# * It allows you to add/delete/edit Vorbis comments and write them to the Flac file.
# * It parses the seek table (METADATA_BLOCK_SEEKTABLE).
# * It parses the 'application metadata block' (METADATA_BLOCK_APPLICATION).
#   * If application is ID 0x41544348 (Flac File) then we can parse that too.
# * It recognizes (but does not yet parse) the cue sheet (METADATA_BLOCK_CUESHEET).
# * It parses zero or more picture blocks (METADATA_BLOCK_PICTURE)
#   * It allows you to write the embedded images to a file.
#
# My goals are to create a nice native Ruby library interface which will allow
# the user to mimic most functionality of the 'metaflac' binary programmatically.
#
# = Copyright and Disclaimer
#
# Copyright:: (c) 2006, 2007, 2014 Darren Kirby
#
# FlacInfo is free software. No warranty is provided and the author
# cannot accept responsibility for lost or damaged files.
#
# License:: Ruby
# Author:: Darren Kirby (mailto:bulliver@gmail.com)
# Website:: https://github.com/DarrenKirby/flacinfo-rb
#
# = More information
#
# * The Flac spec is at:
#   http://flac.sourceforge.net/format.html
# * The Vorbis Comment spec is at:
#   http://www.xiph.org/vorbis/doc/v-comment.html


# FlacInfoError is raised for general user errors.
# It will print a string that describes the problem.
class FlacInfoError < StandardError
end

# FlacInfoReadError is raised when an error occurs parsing the Flac file.
# It will print a string that describes in which block the error occured.
class FlacInfoReadError < StandardError
end

# FlacInfoWriteError is raised when an error occurs writing the Flac file.
# It will print a string that describes where the error occured.
class FlacInfoWriteError < StandardError
end

# Note: STREAMINFO is the only block guaranteed to be present in the Flac file.
# All attributes will be present but empty if the associated block is not present in the Flac file,
# except for 'picture' which will have the key 'n' with the value '0'.
# All 'offset' and 'block_size' values do not include the block header. All block headers are 4 bytes
# no matter the type, so if you need the offset including the header, subtract 4. If you need the size
# including the header, add 4.
class FlacInfo
  # A list of 'standard field names' according to the Vorbis Comment specification. It is certainly
  # possible to use a non-standard name, but the spec recommends against it.
  # See: http://www.xiph.org/vorbis/doc/v-comment.html
  STANDARD_FIELD_NAMES= %w/TITLE VERSION ALBUM TRACKNUMBER ARTIST PERFORMER COPYRIGHT LICENSE
                           ORGANIZATION DESCRIPTION GENRE DATE LOCATION CONTACT ISRC/

  # Hash of values extracted from the STREAMINFO block. Keys are:
  # 'offset':: The STREAMINFO block's offset from the beginning of the file (not including the block header).
  # 'block_size':: The size of the STREAMINFO block (not including the block header).
  # 'minimum_block':: The minimum block size (in samples) used in the stream.
  # 'maximum_block':: The maximum block size (in samples) used in the stream.
  # 'minimum_frame':: The minimum frame size (in bytes) used in the stream.
  # 'maximum_frame':: The maximum frame size (in bytes) used in the stream.
  # 'samplerate':: Sample rate in Hz.
  # 'channels':: The number of channels used in the stream.
  # 'bits_per_sample':: The number of bits per sample used in the stream.
  # 'total_samples':: The total number of samples in stream.
  # 'md5':: MD5 signature of the unencoded audio data.
  attr_reader :streaminfo

  # Hash of values extracted from the SEEKTABLE block. Keys are:
  # 'offset':: The SEEKTABLE block's offset from the beginning of the file (not including the block header).
  # 'block_size':: The size of the SEEKTABLE block (not including the block header).
  # 'seek_points':: The number of seek points in the block.
  # 'points':: Another hash whose keys start at 0 and end at ('seek_points' - 1). Each "seektable['points'][n]" hash
  #            contains an array whose (integer) values are:
  #            '0':: Sample number of first sample in the target frame, or 0xFFFFFFFFFFFFFFFF for a placeholder point.
  #            '1':: Offset (in bytes) from the first byte of the first frame header to the first byte of the target frame's header.
  #            '2':: Number of samples in the target frame.
  attr_reader :seektable

  # Array of "name=value" strings extracted from the VORBIS_COMMENT block. This is just the contents, metadata is in 'tags'.
  # You should not normally operate on this array directly. Rather, use the comment_add and comment_del methods to make changes.
  attr_accessor :comment

  # Hash of the 'comment' values separated into "key => value" pairs as well as the keys:
  # 'offset':: The VORBIS_COMMENT block's offset from the beginning of the file (not including the block header).
  # 'block_size':: The size of the VORBIS_COMMENT block (not including the block header).
  # 'vendor_tag':: Typically, the name and version of the software that encoded the file.
  attr_reader :tags

  # Hash of values extracted from the APPLICATION block. Keys are:
  # 'offset':: The APPLICATION block's offset from the beginning of the file (not including the block header).
  # 'block_size':: The size of the APPLICATION block (not including the block header).
  # 'ID':: Registered application ID. See http://flac.sourceforge.net/id.html
  # 'name':: Name of the registered application ID.
  attr_reader :application

  # Hash of values extracted from the PADDING block. Keys are:
  # 'offset':: The PADDING block's offset from the beginning of the file (not including the block header).
  # 'block_size':: The size of the PADDING block (not including the block header).
  attr_reader :padding

  # Hash of values extracted from the CUESHEET block. Keys are:
  # 'offset':: The CUESHEET block's offset from the beginning of the file (not including the block header).
  # 'block_size':: The size of the CUESHEET block (not including the block header).
  attr_reader :cuesheet

  # Hash of values extracted from one or more PICTURE blocks. This hash always includes the key 'n' which is the number of
  # PICTURE blocks found, else '0'. For each block found there will be an integer key starting from 1. Each of these is a
  # hash which contains the keys:
  # 'offset':: The PICTURE block's offset from the beginning of the file (not including the block header).
  # 'block_size':: The size of the PICTURE block (not including the block header).
  # 'type_int':: The picture type according to the ID3v2 APIC frame.
  # 'type_string':: A text value representing the picture type.
  # 'description_string':: A text description of the picture.
  # 'mime_type':: The MIME type string. May be '-->' to signify that the data part is a URL of the picture.
  # 'colour_depth':: The color depth of the picture in bits-per-pixel.
  # 'n_colours':: For indexed-color pictures (e.g. GIF), the number of colors used, or 0 for non-indexed pictures.
  # 'width':: The width of the picture in pixels.
  # 'height':: The height of the picture in pixels.
  # 'raw_data_offset':: The raw picture data's offset from the beginning of the file.
  # 'raw_data_length':: The length of the picture data in bytes.
  attr_reader :picture

  # Hash of values extracted from an APPLICATION block if it is type 0x41544348 (Flac File).
  # Keys are:
  # 'description':: A brief text description of the contents.
  # 'mime_type':: The Mime type of the contents.
  # 'raw_data':: The contents. May be binary.
  attr_reader :flac_file

  # FlacInfo is the class for parsing Flac files.
  #
  # :call-seq:
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
    @tags["#{tag}"] ? true : false
  end

  # Pretty print tags hash.
  #
  # :call-seq:
  #   FlacInfo.print_tags   -> nil
  #
  # Raises FlacInfoError if METADATA_BLOCK_VORBIS_COMMENT is not present.
  #
  def print_tags
    if @tags == {}
      raise FlacInfoError, "METADATA_BLOCK_VORBIS_COMMENT not present"
    end
    @tags.each_pair { |key,val| puts "#{key}: #{val}" }
    nil
  end

  # Pretty print streaminfo hash.
  #
  # :call-seq:
  #   FlacInfo.print_streaminfo   -> nil
  #
  def print_streaminfo
    #  No test: METADATA_BLOCK_STREAMINFO must be present in valid Flac file
    @streaminfo.each_pair { |key,val| puts "#{key}: #{val}" }
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
    if @seektable == {}
      raise FlacInfoError, "METADATA_BLOCK_SEEKTABLE not present"
    end
    puts "  seek points: #{@seektable['seek_points']}"
    n = 0
    @seektable['seek_points'].times do
      print "    point #{n}: sample number: #{@seektable['points'][n][0]}, "
      print "stream offset: #{@seektable['points'][n][1]}, "
      print "frame samples: #{@seektable['points'][n][2]}\n"
      n += 1
    end
    nil
  end

  # This method produces output similar to 'metaflac --list'.
  #
  # :call-seq:
  #   FlacInfo.meta_flac ->   nil
  #
  def meta_flac
    n = 0
    pictures_seen = 0
    @metadata_blocks.each do |block|
      puts "METADATA block ##{n}"
      puts "  type: #{block[1]} (#{block[0].upcase})"
      puts "  is last: #{block[2] == 0 ? "false" : "true"}"
      case block[1]
        when 0
          meta_stream
        when 1
          meta_padd
        when 2
          meta_app
        when 3
          meta_seek
        when 4
          meta_vorb
        when 5
          meta_cue
        when 6
          pictures_seen += 1
          meta_pict(pictures_seen)
      end
      n += 1
    end
    nil
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
    if @flac_file == {}
      raise FlacInfoError, "Flac File data not present"
    end
    if outfile == nil
      puts @flac_file['raw_data']
    else
      if @flac_file['mime_type'] =~ /text/
        f = File.new(outfile, "w")
        f.write(@flac_file['raw_data'])
        f.close
      else
        f = File.new(outfile, "wb")
        f.write(@flac_file['raw_data'])
        f.close
      end
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
    if @picture["n"] == 0
      raise FlacInfoError, "There is no METADATA_BLOCK_PICTURE"
    end

    if args.has_key?(:n)
      n = args[:n]
    else
      n = 1
    end

    #  "image/jpeg" => "jpeg"
    extension = @picture[n]["mime_type"].split("/")[1]

    if not args.has_key?(:outfile)
      if @tags["album"] == nil or @tags["album"] == ""
        outfile = "flacimage#{n}.#{extension}"
      else
        #  Try to use contents of "album" tag for the filename
        outfile = "#{@tags["album"]}#{n}.#{extension}"
      end
    else
      outfile = "#{args[:outfile]}.#{extension}"
    end

    in_p  = File.new(@filename, "rb")
    out_p = File.new(outfile, "wb")

    out_p.binmode #  For Windows folks...

    in_p.seek(@picture[n]['raw_data_offset'], IO::SEEK_CUR)
    raw_data = in_p.read(@picture[n]['raw_data_length'])
    out_p.write(raw_data)

    in_p.close
    out_p.close

    nil
  end

  # Writes Vorbis tag changes to disk
  #
  # :call-seq:
  #   FlacInfo.update!   -> bool
  #
  # Returns true if write was successful, false otherwise.
  #
  def update!
    write_to_disk ? true : false
  end

  # Adds a new comment to the comment array
  #
  # :call-seq:
  #   FlacInfo.comment_add(str)   -> bool
  #
  # 'str' must be in the form 'name=value', or 'name=' if you want to
  # set an empty value for a particular tag. Returns 'true' if successful,
  # false otherwise. Remember to call 'update!' to write changes to the file.
  #
  def comment_add(name)
    if name !~ /\w=/  #  We accept 'name=' in case you want to leave the value empty
      raise FlacInfoError, "comments must be in the form 'name=value'"
    end
    begin
      @comment << name
      @comments_changed = 1
    rescue
      return false
    end
    return true
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
  def comment_del(name)
    bc = Array.new(@comment)  #  We need a copy
    if name.include? "="
      nc = @comment.delete_if { |x| x == name }
    else
      nc = @comment.delete_if { |x| x.split("=")[0] == name }
    end

    if nc == bc
      return false
    else
      @comments_changed = 1
      return true
    end
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
  def padding_add!(size=4096)
    @metadata_blocks.each do |type|
      if type[0] == "padding"
        raise FlacInfoError, "PADDING block exists. Use 'padding_resize!'"
      end
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
  def padding_resize!(size=4096)
    begin
      remove_padding_block
      build_padding_block(size)
      true
    rescue
      false
    end
  end

  #--
  #  This cleans up the output when using FlacInfo in irb
  def inspect #:nodoc:
    s = "#<#{self.class}:0x#{(self.object_id*2).to_s(16)} "
    @metadata_blocks.each do |blk|
      s += "(#{blk[0].upcase} size=#{blk[4]} offset=#{blk[3]}) "
    end
    s += "\b>"
  end
  #++

  private

  #  The following six methods are just helpers for meta_flac
  def meta_stream
    puts "  length: #{@streaminfo['block_size']}"
    puts "  minumum blocksize: #{@streaminfo['minimum_block']} samples"
    puts "  maximum blocksize: #{@streaminfo['maximum_block']} samples"
    puts "  minimum framesize: #{@streaminfo['minimum_frame']} bytes"
    puts "  maximum framesize: #{@streaminfo['maximum_frame']} bytes"
    puts "  sample rate: #{@streaminfo['samplerate']} Hz"
    puts "  channels: #{@streaminfo['channels']}"
    puts "  bits-per-sample: #{@streaminfo['bits_per_sample']}"
    puts "  total samples: #{@streaminfo['total_samples']}"
    puts "  MD5 signature: #{@streaminfo['md5']}"
  end

  def meta_padd
    puts "  length: #{@padding['block_size']}"
  end

  def meta_app
    puts "  length: #{@application['block_size']}"
    puts "  id: #{@application['ID']}"
    puts "  application name: #{@application['name']}"
    if @application['ID'] == "41544348"
      puts "    description: #{@flac_file['description']}"
      puts "    mime type: #{@flac_file['mime_type']}"
      #  Don't want to dump binary data
      if @flac_file['mime_type'] =~ /text/
        puts "    raw data:"
        puts @flac_file['raw_data']
      else
        puts "'Flac File' data may be binary. Use 'raw_data_dump' to see it"
      end
    else
      puts "    raw data"
      puts @application['raw_data']
    end
  end

  def meta_seek
    puts "  length: #{@seektable['block_size']}"
    print_seektable
  end

  def meta_vorb
    puts "  length: #{@tags['block_size']}"
    puts "  vendor string: #{@tags['vendor_tag']}"
    puts "  comments: #{@comment.size}"
    n = 0
    @comment.each do |c|
      puts "    comment[#{n}]: #{c}"
      n += 1
    end
  end

  def meta_cue
    puts "  length: #{@cuesheet['block_size']}"
  end

  def meta_pict(n)
    puts "  length: #{@picture[n]['block_size']}"
    puts "  type: #{@picture[n]['type_int']} => #{@picture[n]['type_string']}"
    puts "  mimetype: #{@picture[n]['mime_type']}"
    puts "  description: #{@picture[n]['description_string']}"
    puts "  image width: #{@picture[n]['width']}"
    puts "  image height: #{@picture[n]['height']}"
    puts "  colour depth: #{@picture[n]['colour_depth']}"
    puts "  number of colours: #{@picture[n]['n_colours']}"
    puts "  image size: #{@picture[n]['raw_data_length']} bytes"
  end


  #  This is where the 'real' parsing starts
  def parse_flac_meta_blocks
    @fp = File.new(@filename, "rb")  #  Our file pointer
    @comments_changed = nil          #  Do we need to write a new VORBIS_BLOCK?

    #  These next 8 lines initialize our public data structures.
    @streaminfo  = {}
    @comment     = []
    @tags        = {}
    @seektable   = {}
    @padding     = {}
    @application = {}
    @cuesheet    = {}
    @picture     = {"n" => 0}

    header = @fp.read(4)
    #  First 4 bytes must be 0x66, 0x4C, 0x61, and 0x43
    if header != 'fLaC'
      raise FlacInfoReadError, "#{@filename} does not appear to be a valid Flac file"
    end

    typetable = { 0 => "streaminfo", 1 => "padding", 2 => "application",
                  3 => "seektable", 4 => "vorbis_comment", 5 => "cuesheet",
                  6 => "picture" }

    @metadata_blocks = []
    lastheader = 0

    until lastheader == 1
      #  first bit = Last-metadata-block flag
      #  bits 2-8 = BLOCK_TYPE. See typetable above
      block_header = @fp.read(1).unpack("B*")[0]
      lastheader = block_header[0].to_i & 1
      type = sprintf("%u", "0b#{block_header[1..7]}").to_i
      @metadata_blocks << [typetable[type], type, lastheader]

      if type >= typetable.size
        raise FlacInfoReadError, "Invalid block header type"
      end

      self.send "parse_#{typetable[type]}"
    end

    @fp.close
  end

  def parse_seektable
    begin
      @seektable['block_size']  = @fp.read(3).unpack("B*")[0].to_i(2)
      @seektable['offset']      = @fp.tell
      @seektable['seek_points'] = @seektable['block_size'] / 18

      @metadata_blocks[-1] << @seektable['offset']
      @metadata_blocks[-1] << @seektable['block_size']

      n = 0
      @seektable['points'] = {}

      @seektable['seek_points'].times do
        pt_arr = []
        pt_arr << @fp.read(8).reverse.unpack("V*")[0]
        pt_arr << @fp.read(8).reverse.unpack("V*")[0]
        pt_arr << @fp.read(2).reverse.unpack("v*")[0]
        @seektable['points'][n] = pt_arr
        n += 1
      end

    rescue
      raise FlacInfoReadError, "Could not parse METADATA_BLOCK_SEEKTABLE"
    end
  end

  #  Not parsed yet, I have no flacs with a cuesheet!
  def parse_cuesheet
    begin
      @cuesheet['block_size'] = @fp.read(3).unpack("B*")[0].to_i(2)
      @cuesheet['offset']     = @fp.tell

      @metadata_blocks[-1] << @cuesheet['offset']
      @metadata_blocks[-1] << @cuesheet['block_size']

      @fp.seek(@cuesheet['block_size'], IO::SEEK_CUR)
    rescue
      raise FlacInfoReadError, "Could not parse METADATA_BLOCK_CUESHEET"
    end
  end

  def parse_picture
    n = @picture["n"] + 1
    @picture["n"] = n
    @picture[n]   = {}

    picture_type = ["Other", "32x32 pixels file icon", "Other file icon", "Cover (front)", "Cover (back)",
                    "Leaflet page", "Media", "Lead artist/lead performer/soloist", "Artist/performer",
                    "Conductor", "Band/Orchestra", "Composer", "Lyricist/text writer", "Recording Location",
                    "During recording", "During performance", "Movie/video screen capture", "A bright 
                     coloured fish", "Illustration", "Band/artist logotype", "Publisher/Studio logotype"]

    begin
      @picture[n]['block_size'] = @fp.read(3).unpack("B*")[0].to_i(2)
      @picture[n]['offset']     = @fp.tell

      @metadata_blocks[-1] << @picture[n]['offset']

      @picture[n]['type_int']           = @fp.read(4).reverse.unpack("v*")[0]
      @picture[n]['type_string']        = picture_type[@picture[n]['type_int']]
      mime_length                       = @fp.read(4).reverse.unpack("v*")[0]
      @picture[n]['mime_type']          = @fp.read(mime_length).unpack("a*")[0]
      description_length                = @fp.read(4).reverse.unpack("v*")[0]
      @picture[n]['description_string'] = @fp.read(description_length).unpack("M*")[0]
      @picture[n]['width']              = @fp.read(4).reverse.unpack("v*")[0]
      @picture[n]['height']             = @fp.read(4).reverse.unpack("v*")[0]
      @picture[n]['colour_depth']       = @fp.read(4).reverse.unpack("v*")[0]
      @picture[n]['n_colours']          = @fp.read(4).reverse.unpack("v*")[0]
      @picture[n]['raw_data_length']    = @fp.read(4).reverse.unpack("V*")[0]
      @picture[n]['raw_data_offset']    = @fp.tell

      @metadata_blocks[-1] << @picture[n]['block_size']

      @fp.seek((@picture[n]['raw_data_length']), IO::SEEK_CUR)
    rescue
      raise FlacInfoReadError, "Could not parse METADATA_BLOCK_PICTURE"
    end
  end

  def parse_application
    begin
      @application['block_size'] = @fp.read(3).unpack("B*")[0].to_i(2)
      @application['offset']     = @fp.tell

      @metadata_blocks[-1] << @application['offset']
      @metadata_blocks[-1] << @application['block_size']

      @application['ID'] = @fp.read(4).unpack("H*")[0]

      app_id = {"41544348" => "Flac File", "43756573" => "GoldWave Cue Points",
                "4D754D4C" => "MusicML", "46696361" => "CUE Splitter",
                "46746F6C" => "flac-tools", "5346464C" => "Sound Font FLAC",
                "7065656D" => "Parseable Embedded Extensible Metadata", "74756E65" => "TagTuner",
                "786D6364" => "xmcd"}

      @application['name'] = "#{app_id[@application['ID']]}"

      #  We only know how to parse data from 'Flac File'...
      if @application['ID'] = "41544348"
        parse_flac_file_contents(@application['block_size'] - 4)
      else
        @application['raw_data'] = @fp.read(@application['block_size'] - 4)
      end
    rescue
      raise FlacInfoReadError, "Could not parse METADATA_BLOCK_APPLICATION" 
    end
  end

  #  Unlike most values in the Flac header
  #  the Vorbis comments are in LSB order
  #
  #  @comment is an array of values according to the official spec implementation
  #  @tags is a more user-friendly data structure with the values
  #  separated into key=value pairs
  def parse_vorbis_comment
    begin
      @tags['block_size'] = @fp.read(3).unpack("B*")[0].to_i(2)
      @tags['offset']     = @fp.tell

      @metadata_blocks[-1] << @tags['offset']
      @metadata_blocks[-1] << @tags['block_size']

      vendor_length = @fp.read(4).reverse.unpack("B*")[0].to_i(2)

      @tags['vendor_tag']      = @fp.read(vendor_length)
      user_comment_list_length = @fp.read(4).reverse.unpack("B*")[0].to_i(2)

      n = 0
      user_comment_list_length.times do
        length = @fp.read(4).reverse.unpack("B*")[0].to_i(2)
        @comment[n] = @fp.read(length)
        n += 1
      end

      @comment.each do |c|
        k,v = c.split("=")
        #  Vorbis spec says we can have more than one identical comment ie:
        #  comment[0]="Artist=Charlie Parker"
        #  comment[1]="Artist=Miles Davis"
        #  so we just append the second and subsequent values to the first
        if @tags.has_key?(k)
          @tags[k] = "#{@tags[k]}, #{v}"
        else
          @tags[k] = v
        end
      end

    rescue
      raise FlacInfoReadError, "Could not parse METADATA_BLOCK_VORBIS_COMMENT"
    end
  end

  # padding is just a bunch of '0' bytes
  def parse_padding
    begin
      @padding['block_size'] = @fp.read(3).unpack("B*")[0].to_i(2)
      @padding['offset']     = @fp.tell

      @metadata_blocks[-1] << @padding['offset']
      @metadata_blocks[-1] << @padding['block_size']

      @fp.seek(@padding['block_size'], IO::SEEK_CUR)
    rescue
      raise FlacInfoReadError, "Could not parse METADATA_BLOCK_PADDING"
    end
  end

  def parse_streaminfo
    begin
      @streaminfo['block_size']    = @fp.read(3).unpack("B*")[0].to_i(2)
      @streaminfo['offset']        = @fp.tell

      @metadata_blocks[-1] << @streaminfo['offset']
      @metadata_blocks[-1] << @streaminfo['block_size']

      @streaminfo['minimum_block'] = @fp.read(2).reverse.unpack("v*")[0]
      @streaminfo['maximum_block'] = @fp.read(2).reverse.unpack("v*")[0]
      @streaminfo['minimum_frame'] = @fp.read(3).reverse.unpack("v*")[0]
      @streaminfo['maximum_frame'] = @fp.read(3).reverse.unpack("v*")[0]

      #  64 bits in MSB order
      bitstring = @fp.read(8).unpack("B*")[0]
      #  20 bits :: Sample rate in Hz.
      @streaminfo['samplerate']      = sprintf("%u", "0b#{bitstring[0..19]}").to_i
      #  3 bits :: (number of channels)-1
      @streaminfo['channels']        = sprintf("%u", "0b#{bitstring[20..22]}").to_i + 1
      #  5 bits :: (bits per sample)-1
      @streaminfo['bits_per_sample'] = sprintf("%u", "0b#{bitstring[23..27]}").to_i + 1
      #  36 bits :: Total samples in stream.
      @streaminfo['total_samples']   = sprintf("%u", "0b#{bitstring[28..63]}").to_i

      #  128 bits :: MD5 signature of the unencoded audio data.
      @streaminfo['md5'] = @fp.read(16).unpack("H32")[0]
    rescue
      raise FlacInfoReadError, "Could not parse METADATA_BLOCK_STREAMINFO"
    end
  end

  #  See http://firestuff.org/flacfile/
  def parse_flac_file_contents(size)
    begin
      @flac_file = {}
      desc_length = @fp.read(1).unpack("C")[0]
      @flac_file['description'] = @fp.read(desc_length)
      mime_length = @fp.read(1).reverse.unpack("C")[0]
      @flac_file['mime_type'] = @fp.read(mime_length)
      size = size - 2 - desc_length - mime_length
      @flac_file['raw_data'] = @fp.read(size)
    rescue
      raise FlacInfoReadError, "Could not parse Flac File data"
    end
  end

  #  Here we begin the FlacInfo write methods


  #  Build a block header given a type, a size, and whether it is last
  def build_block_header(type, size, last)
    begin
      bit_string = sprintf("%b%7b", last, type).gsub(" ","0")
      block_header_s = [bit_string].pack("B*")
      block_header_s += [size].pack("VX").reverse  # size is 3 bytes
    rescue
      raise FlacInfoWriteError, "error building block header"
    end
  end

  #  Build a string of packed data for the Vorbis comments
  def build_vorbis_comment_block
    begin
      vorbis_comm_s  = [@tags["vendor_tag"].length].pack("V")
      vorbis_comm_s += [@tags["vendor_tag"]].pack("A*")
      vorbis_comm_s += [@comment.length].pack("V")
      @comment.each do |c|
        vorbis_comm_s += [c.length].pack("V")
        vorbis_comm_s += [c].pack("A*")
      end
      vorbis_comm_s
    rescue
      raise FlacInfoWriteError, "error building vorbis comment block"
    end
  end

  def write_to_disk
    if @comments_changed == nil
      raise FlacInfoWriteError, "No changes to write"
    else
      vcd = build_vorbis_comment_block            #  Build the VORBIS_COMMENT data
      vch = build_block_header(4, vcd.length, 0)  #  Build the VORBIS_COMMENT header
    end

    #  Determine if we can shuffle the data or if a rewrite is necessary
    begin
      if not @padding.has_key?("block_size") or vcd.length > @padding['block_size']
        rewrite(vcd, vch)  # Rewriting is simpler but more expensive
      else
        shuffle(vcd, vch)  # Shuffling is more complicated but cheaper
      end
      parse_flac_meta_blocks  #  Parse the file again to update new values
      return true
    rescue
      raise FlacInfoWriteError, "error writing new data to #{@filename}"
    end
  end

  #  Shuffle the data and update the PADDING block
  def shuffle(vcd, vch)
    flac = File.new(@filename, "r+b")
    flac.binmode #  For Windows folks...

    #  Position ourselves at end of current Vorbis block
    flac.seek((@tags['offset'] + @tags['block_size']), IO::SEEK_CUR)
    #  The data we need to shuffle starts at current position and ends at
    #  the beginning of the padding block, so the size we need to read is:
    #
    #  (offset of padding minus 4 bytes for the padding header) minus our current position
    #
    size_to_read = (@padding['offset'] - 4) - flac.tell
    data_to_shuffle = flac.read(size_to_read)

    flac.seek((@tags['offset'] - 4), IO::SEEK_SET)
    flac.write(vch)              #  Write the VORBIS_COMMENT header
    flac.write(vcd)              #  Write the VORBIS_COMMENT data
    flac.write(data_to_shuffle)  #  Write the shuffled data

    new_padding_size = @padding['block_size'] - (vcd.length - @tags['block_size'])
    ph = build_block_header(1, new_padding_size, 1)  #  Build the new PADDING header

    flac.write(ph)  #  Write the new PADDING header
    flac.close      #  ...and we're done
  end

  #  Rewrite the entire file
  def rewrite(vcd, vch)
    flac = File.new(@filename, "r+b")
    flac.binmode #  For Windows folks...

    flac.seek((@tags['offset'] + @tags['block_size']), IO::SEEK_CUR)
    rest_of_file = flac.read()
    flac.seek((@tags['offset'] - 4), IO::SEEK_SET)

    flac.write(vch)           #  Write the VORBIS_COMMENT header
    flac.write(vcd)           #  Write the VORBIS_COMMENT data
    flac.write(rest_of_file)  #  Write the rest of the file

    flac.close
  end

  # remove the padding block
  def remove_padding_block
    begin
      new_last_block = @metadata_blocks[-2]

      flac = File.new(@filename, "r+b")
      flac.binmode

      flac.seek((@padding['offset'] + @padding['block_size']), IO::SEEK_CUR)
      rest_of_file = flac.read()

      flac.seek((@padding['offset'] - 4), IO::SEEK_SET)
      flac.write(rest_of_file)

      nbh = build_block_header(new_last_block[1], new_last_block[4], 1)

      flac.seek((new_last_block[3] - 4), IO::SEEK_SET)
      flac.write(nbh)
      flac.close()

      parse_flac_meta_blocks  #  Parse the file again to update new values
      true
    rescue
      false
    end
  end

  def build_padding_block(size)
    begin
      old_last_block = @metadata_blocks[-1]

      a = Array.new(size / 2, 0)
      pbd = a.pack("v*")
      pbh = build_block_header(1, size, 1)

      flac = File.new(@filename, "r+b")
      flac.binmode

      flac.seek((old_last_block[4] + old_last_block[3]), IO::SEEK_CUR)
      co = flac.tell
      rest_of_file = flac.read()
      flac.seek(co, IO::SEEK_SET)

      flac.write(pbh)
      flac.write(pbd)
      flac.write(rest_of_file)
      nbh = build_block_header(old_last_block[1], old_last_block[4], 0)

      flac.seek((old_last_block[3] - 4), IO::SEEK_SET)
      flac.write(nbh)

      flac.close()
      parse_flac_meta_blocks  #  Parse the file again to update new values
      true
    rescue
      false
    end
  end
end

# If called directly from the command line, run meta_flac on each argument
if __FILE__ == $0
  ARGV.each do |filename|
    FlacInfo.new(filename).meta_flac
    puts
  end
end
