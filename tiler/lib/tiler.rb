require 'logging'
require 'utils'

module Tiler

# Implements tiling logic.
class Tiler
  include ::Tiler::Logger

  attr_accessor :conn

  def initialize(conn)
    @conn = conn
  end

  def generate(zoom, changeset_id, options = {})
    #return -1 if options[:processing_tile_limit] and tiles.size > options[:processing_tile_limit]

    count = 0

    each_change(changeset_id) do |row|
      tile_geom(changeset_id, row['current_geom'], box2d_to_bbox(row['current_box']), zoom) if row['current_geom']
      tile_geom(changeset_id, row['new_geom'], box2d_to_bbox(row['new_box']), zoom) if row['new_geom']
      #puts row
    end

    count
  end

  ##
  # Retrieves a list of changeset ids according to given options.
  #
  def get_changeset_ids(options)
    sql = "SELECT id FROM changesets WHERE num_changes < #{options[:processing_change_limit]}"

    unless options[:retile]
      # We are NOT retiling so skip changesets that have been already tiled.
      sql += " AND last_tiled_at IS NULL"
    end

    sql += " ORDER BY created_at DESC"

    if options[:changesets] == ['all']
      ids = @conn.query(sql).collect {|row| row['id'].to_i}
    else
      # List of changeset ids must have been provided.
      ids = options[:changesets]
    end
    ids
  end

  def update_tiled_at(changeset_id)
    @conn.query("UPDATE changesets SET last_tiled_at = NOW() WHERE id = #{changeset_id}")
  end

  def generate_summary_tiles(summary_zoom)
    clear_summary_tiles(summary_zoom)
    subtiles_per_tile = 2**16 / 2**summary_zoom

    for x in (0..2**summary_zoom - 1)
      for y in (0..2**summary_zoom - 1)
        num_changesets = @conn.query("
          SELECT COUNT(DISTINCT changeset_id) AS num_changesets
          FROM changeset_tiles
          WHERE zoom = 16
            AND x >= #{x * subtiles_per_tile} AND x < #{(x + 1) * subtiles_per_tile}
            AND y >= #{y * subtiles_per_tile} AND y < #{(y + 1) * subtiles_per_tile}
          ").to_a[0]['num_changesets'].to_i

        @@log.debug "Tile (#{x}, #{y}), num_changesets = #{num_changesets}"

        @conn.query("INSERT INTO summary_tiles (num_changesets, zoom, x, y)
          VALUES (#{num_changesets}, #{summary_zoom}, #{x}, #{y})")
      end
    end
  end

  def clear_tiles(changeset_id, zoom)
    @conn.query("DELETE FROM changeset_tiles WHERE changeset_id = #{changeset_id} AND zoom = #{zoom}").cmd_tuples
  end

  protected

  def tile_geom(changeset_id, geom, bbox, zoom)
    tiles = bbox_to_tiles(zoom, bbox)
    #@@log.debug " Tiles to process: #{tiles.size}"

    tiles.each do |tile|
      x, y = tile[0], tile[1]
      lat1, lon1 = tile2latlon(x, y, zoom)
      lat2, lon2 = tile2latlon(x + 1, y + 1, zoom)

      geom = @conn.query("
        SELECT ST_Intersection(
          geom,
          ST_SetSRID(ST_MakeBox2D(ST_MakePoint(#{lon2}, #{lat1}), ST_MakePoint(#{lon1}, #{lat2})), 4326))
        FROM changesets WHERE id = #{changeset_id}").getvalue(0, 0)

      if geom != '0107000020E610000000000000' and geom
        @@log.debug "    Got geometry for tile (#{x}, #{y})"
        @conn.query("INSERT INTO changeset_tiles (changeset_id, zoom, x, y, geom)
          VALUES (#{changeset_id}, #{zoom}, #{x}, #{y}, '#{geom}')")
        count += 1
      end
    end
  end

  def each_change(changeset_id)
    @conn.exec("DECLARE change_cursor CURSOR FOR
        SELECT id,
          current_geom::geometry AS current_geom,
          new_geom::geometry AS new_geom,
          Box2D(current_geom::geometry) AS current_box,
          Box2D(new_geom::geometry) AS new_box
        FROM changes
        WHERE changeset_id = #{changeset_id} AND (NOT ST_IsEmpty(current_geom::geometry) OR
          NOT ST_IsEmpty(new_geom::geometry))")
    while (result = @conn.exec("FETCH NEXT IN change_cursor")).ntuples == 1 do
      yield result.to_a[0]
    end
  end

  def clear_summary_tiles(zoom)
    @conn.query("DELETE FROM summary_tiles WHERE zoom = #{zoom}").cmd_tuples
  end
end

end
