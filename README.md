# flacinfo-rb

- Author: Darren Kirby
- mailto:darren@dragonbyte.ca
- License: GPL2

[![Gem Version](https://badge.fury.io/rb/flacinfo-rb.svg)](https://badge.fury.io/rb/flacinfo-rb)

flacinfo.rb gives you access to metadata from Flac files.
* It parses stream information (METADATA_BLOCK_STREAMINFO).
* It parses Vorbis comments (METADATA_BLOCK_VORBIS_COMMENT), if present.
    * It allows you to add/delete/edit Vorbis comments and write them to the Flac file.
* It parses the seek table (METADATA_BLOCK_SEEKTABLE), if present.
* It parses the cuesheet (METADATA_BLOCK_CUESHEET), if present.
* It parses zero or more application metadata blocks (METADATA_BLOCK_APPLICATION).
    * If application is ID 0x41544348 (Flac File) then it parses that too.
* It parses zero or more picture blocks (METADATA_BLOCK_PICTURE)
    * It allows you to write the embedded images to a file.
* It parses zero or more padding blocks (METADATA_BLOCK_PADDING).

## Quick API docs

## Initializing

```
require 'flacinfo'
flac = FlacInfo.new("some_song.flac")
```

## Public data accessors

* `streaminfo`   - STREAMINFO block object.
* `seektable`    - SEEKTABLE block object.
* `cuesheet`     - CUESHEET block metadata
* `comment`      - Array of VORBIS_COMMENT block metadata.
* `tags`         - Hash of VORBIS_COMMENT metadata seperated into key=value pairs.
* `applications` - Array of APPLICATION block metadata objects.
* `application`  - The first APPLICATION block.
* `paddings`     - Array of PADDING block objects.
* `padding`      - The first PADDING block object.
* `pictures`     - Array of PICTURE block objects.
* `picture`      - The first PICTURE block object.
* `flac_file`    - APPLICATION Id 0x41544348 (FlacFile) metadata if present.

These accessors are always present, but will return `nil` if the flac file does not contain the associated metadata
block. STREAMINFO is the only block garanteed to be present. SEEKTABLE, VORBIS_COMMENT, and CUESHEET blocks may appear
zero or one time in the flac file. APPLICATION, PICTURE, and PADDING blocks may appear zero or more times (ie: there may
be more than one of these blocks present). These three block types have two accessors defined. The plural accessor
returns an array of objects, even if only one is present. The singular accessors return the first object of that type:

```
> flac.pictures
=> [#<Picture offset=344, block_size=15921, type_int=8, type_string="Artist/performer", description_string="The author of
  flacinfo", mime_type="image/png", colour_depth=32, n_colours=0, width=100, height=99, raw_data_offset=407, raw_data_length=15858>,
#<Picture offset=16269, block_size=22183, type_int=0, type_string="Other", description_string="A silly picture for the 
unit test", mime_type="image/jpeg", colour_depth=24, n_colours=0, width=507, height=353, raw_data_offset=16344, raw_data_length=22108>]
> flac.picture
=> #<Picture offset=344, block_size=15921, type_int=8, type_string="Artist/performer", description_string="The author of
flacinfo", mime_type="image/png", colour_depth=32, n_colours=0, width=100, height=99, raw_data_offset=407, raw_data_length=15858>
```
Except for `comment` and `tags` (which do not have fixed, known fields), all accessor fields can be accessed using
either 'dot' syntax, or hash syntax:

```
> flac.streaminfo.block_size
=> 34
> flac.streaminfo['block_size']
=> 34
```
The fixed fields for these objects are well documented in the source itself (and in the flac specification). You can run
`object.fields` for a quick vie of what is available, and run `object.block_name` to get the name of the object as a
string:

```
> flac.picture.fields
=> ["offset", "block_size", "type_int", "type_string", "description_string", "mime_type", "colour_depth", "n_colours",
"width", "height", "raw_data_offset", "raw_data_length"]
> flac.seektable.block_name
=> "SEEKTABLE"
```

Each block object implements `to_h` and includes the `Enumerable` class which allows for Ruby block structure:

```
> flac.streaminfo.each_pair do |k, v|
>   puts "The value of #{k} is: #{v}"
> end
The value of offset is: 8
The value of block_size is: 34
The value of minimum_block is: 4096
The value of maximum_block is: 4096
The value of minimum_frame is: 3627
The value of maximum_frame is: 17933
The value of samplerate is: 44100
The value of channels is: 2
The value of bits_per_sample is: 24
The value of total_samples is: 5440923
The value of md5 is: 4dd6616fecef46efa5aaa5a271fc131f
=> ["offset", "block_size", "minimum_block", "maximum_block", "minimum_frame", "maximum_frame", "samplerate", "channels",
"bits_per_sample", "total_samples", "md5"]
```


## Public methods

* `comment_add`       - adds a comment
* `comment_del`       - deletes a comment
* `hastag('str')`     - returns true if tags['str'] exists
* `meta_flac`         - prints all META BLOCKS. (Mostly) equivalent to 'metaflac --list'
* `padding_add!`      - adds a PADDING block of size 'b' or 4096 bytes
* `padding_del!`      - deletes the PADDING block
* `padding_resize!`   - resizes (grow or shrink) a padding block to size 'b' or 4096 bytes
* `print_seektable`   - pretty-print seektable hash
* `print_streaminfo`  - pretty-print streaminfo hash
* `print_tags`        - pretty-print tags hash
* `raw_data_dump(?)`  - if passed a filename it will dump flac_file['raw_data'] to that file,
                        otherwise it will dump it to the console (even if binary!)
* `update!`           - writes comment changes to disk
* `write_picture(?)`  - write image from PICTURE block(s) to optional file

The public methods and attributes are very well documented in the source itself. Please read
there if you don't understand any of this. You can also use Rdoc to generate HTML documentation.


