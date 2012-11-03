#!/usr/bin/env ruby

$:.unshift File.absolute_path(File.dirname(__FILE__) + '/lib/')

require 'optparse'
require 'pg'
require 'yaml'

require 'logging'
require 'tiler'

$config = YAML.load_file('../rails/config/database.yml')['development']

options = {}

opt = OptionParser.new do |opts|
  opts.banner = "Usage: owl_tiler.rb [options]"

  opts.separator('')
  opts.separator('Geometry tiles')
  opts.separator('')

  opts.on("--geometry-tiles x,y,z", Array, "Comma-separated list of zoom levels for which to generate geometry tiles") do |list|
    options[:geometry_tiles] = list.map(&:to_i)
  end

  opts.separator('')

  opts.on("--changesets x,y,z", Array,
      "List of changesets; possible values for this option:",
      "all - all changesets from the database",
      "id1,id2,id3 - list of specific changeset ids to process",
      "Default is 'all'.") do |c|
    options[:changesets] = c
  end

  opts.separator('')

  opts.on("--retile", "Remove existing tiles and regenerate tiles from scratch (optional, default is false)") do |o|
    options[:retile] = o
  end

  opts.separator('')
  opts.separator('Summary tiles')
  opts.separator('')

  opts.on("--summary-tiles x,y,z", Array, "Comma-separated list of zoom levels for which to generate summary tiles") do |list|
    options[:summary_tiles] = list.map(&:to_i)
  end
end

opt.parse!

if !options[:geometry_tiles] and !options[:summary_tiles]
  puts opt.help
  exit 1
end

options[:changesets] ||= ['all']
options[:geometry_tiles] ||= []
options[:summary_tiles] ||= []

@conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['database'],
  :user => $config['username'], :password => $config['password'])

tiler = Tiler::Tiler.new(@conn)

for summary_zoom in options[:summary_tiles]
  before = Time.now

  @conn.transaction do |c|
    puts "Generating summary tiles for zoom level #{summary_zoom}..."
    tiler.generate_summary_tiles(summary_zoom)
  end

  puts "Took #{Time.now - before}s"
end

for zoom in options[:geometry_tiles]
  tiler.get_changeset_ids(options).each do |changeset_id|
    before = Time.now

    @conn.transaction do |c|
      puts "Generating tiles for changeset #{changeset_id} at zoom level #{zoom}..."
      tile_count = tiler.generate(zoom, changeset_id, options)
      puts "Done, tile count: #{tile_count}"
    end

    puts "Changeset #{changeset_id} took #{Time.now - before}s"
  end
end