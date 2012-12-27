##
# Utility methods for tiler tests.
#
module TestCommon
  def setup_changeset_test(id)
    setup_db
    load_changeset(id)
    verify_changeset_data
    @tiler.generate(16, id, {:retile => true})
    @changes = get_changes
    @changes_h = Hash[@changes.collect {|row| [row['id'].to_i, row]}]
    @tiles = get_tiles
    verify_tiles
  end

  def setup_db
    $config = YAML.load_file('../../rails/config/database.yml')['test']
    @conn = PGconn.open(:host => $config['host'], :port => $config['port'], :dbname => $config['database'],
      :user => $config['username'], :password => $config['password'])
    exec_sql_file('../../sql/owl_schema.sql')
    exec_sql_file('../../sql/owl_constraints.sql')
    #exec_sql_file('../../sql/owl_functions.sql')
    @tiler = Tiler::Tiler.new(@conn)
  end

  def exec_sql_file(file)
    @conn.exec(File.open(file).read)
  end

  def load_changeset(id)
    @conn.exec("COPY changes FROM STDIN;")
    File.open("../../testdata/#{id}-changes.csv").read.each_line do |line|
      @conn.put_copy_data(line)
    end
    @conn.put_copy_end
  end

  def verify_changeset_data
    #data = @conn.exec("SELECT id, version,
    #    ST_NumPoints(geom) AS num_points_geom, array_length(nodes, 1) AS num_points_arr,
    #    ST_NumPoints(prev_geom) AS prev_num_points_geom, array_length(prev_nodes, 1) AS prev_num_points_arr
    #  FROM _changeset_data WHERE type = 'W'").to_a
    #for row in data
    #  assert_equal(row['num_points_arr'].to_i, row['num_points_geom'].to_i, "Wrong linestring for row: #{row.inspect}")
      #assert_equal(row['prev_num_points_arr'].to_i, row['prev_num_points_geom'].to_i, "Wrong prev linestring for row: #{row.inspect}")
    #end
  end

  def get_changes
    @conn.exec("SELECT * FROM changes").to_a
  end

  def get_tiles
    @conn.exec("SELECT *,
        array_length(geom, 1) AS geom_arr_len,
        array_length(prev_geom, 1) AS prev_geom_arr_len,
        array_length(changes, 1) AS change_arr_len
      FROM tiles WHERE zoom = 16").to_a
  end

  # Performs sanity checks on given tiles.
  def verify_tiles
    # Check if each change has a tile.
    change_ids = @changes_h.keys.sort.uniq
    change_ids_from_tiles = @tiles.collect {|tile| pg_parse_array(tile['changes'])}.flatten.sort.uniq
    assert_equal(change_ids, change_ids_from_tiles)

    for tile in @tiles
      # Every change should have an associated geom and prev_geom entry.
      assert_equal(tile['change_arr_len'].to_i, tile['geom_arr_len'].to_i)
      assert_equal(tile['change_arr_len'].to_i, tile['prev_geom_arr_len'].to_i)
      changes_arr = pg_parse_array(tile['changes'])

      for geom in pg_parse_geom_array(tile['geom'])
        assert !geom.nil?
      end

      pg_parse_geom_array(tile['prev_geom']).each_with_index do |geom, index|
        change = @changes_h[changes_arr[index]]
        if change['el_version'].to_i != 1 and change['geom_changed'] == 't'
          #assert(geom != 'NULL', "prev_geom should not be null for change: #{change} and tile: #{tile}")
        end
      end
    end
  end

  def find_changes(filters)
    a = []
    for change in @changes
      match = true
      for k, v in filters
        match = (match and (change[k].to_s == v.to_s))
      end
      a << change if match
    end
    a
  end
end