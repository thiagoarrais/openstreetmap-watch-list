-- Database creation script for the OWL schema.

DROP TABLE IF EXISTS nodes;
DROP TABLE IF EXISTS ways;
DROP TABLE IF EXISTS changes;
DROP TABLE IF EXISTS tiles;
DROP TABLE IF EXISTS changesets;
DROP TABLE IF EXISTS relation_members;
DROP TABLE IF EXISTS relations;
DROP TABLE IF EXISTS users;

DROP TYPE IF EXISTS element_type CASCADE;
CREATE TYPE element_type AS ENUM ('N', 'W', 'R');

DROP TYPE IF EXISTS action CASCADE;
CREATE TYPE action AS ENUM ('CREATE', 'MODIFY', 'DELETE', 'AFFECT');

DROP AGGREGATE IF EXISTS array_accum(anyarray);
CREATE AGGREGATE array_accum (anyarray) (
  sfunc = array_cat,
  stype = anyarray,
  initcond = '{}'
);

-- Create a table for changesets.
CREATE TABLE changesets (
  id bigint NOT NULL,
  user_id bigint,
  user_name varchar(255),
  created_at timestamp without time zone NOT NULL,
  closed_at timestamp without time zone, -- If NULL, changeset is still open for business.
  open boolean NOT NULL,
  tags hstore NOT NULL,
  entity_changes int[9], -- For each element type (N, W, R) holds number of actions (CREATE, MODIFY, DELETE) in this changeset.
  num_changes int, -- Comes from the official changeset metadata.
  bbox geometry -- Bounding box of all changes for this changeset.
);

-- Create a table for changes.
CREATE TABLE changes (
  id bigserial NOT NULL,
  changeset_id bigint NOT NULL,
  tstamp timestamp without time zone NOT NULL,
  el_changeset_id bigint NOT NULL,
  el_type element_type NOT NULL,
  el_id bigint NOT NULL,
  el_version int NOT NULL,
  el_action action NOT NULL,
  geom_changed boolean,
  tags_changed boolean,
  nodes_changed boolean,
  members_changed boolean,
  geom geometry(GEOMETRY, 4326),
  prev_geom geometry(GEOMETRY, 4326),
  tags hstore NOT NULL,
  prev_tags hstore,
  nodes bigint[],
  prev_nodes bigint[],
  origin_el_type element_type,
  origin_el_id bigint,
  origin_el_version int,
  origin_el_action action
);

-- Create a table for OWL tiles.
CREATE TABLE tiles (
  changeset_id bigint NOT NULL,
  tstamp timestamp without time zone NOT NULL,
  x int NOT NULL,
  y int NOT NULL,
  zoom int NOT NULL,
  changes bigint[] NOT NULL,
  geom geometry(GEOMETRY, 4326)[] NOT NULL,
  prev_geom geometry(GEOMETRY, 4326)[] NOT NULL
);

-- Create a table for nodes.
CREATE TABLE nodes (
  id bigint NOT NULL,
  version int NOT NULL,
  visible boolean NOT NULL,
  user_id int NOT NULL,
  tstamp timestamp without time zone NOT NULL,
  changeset_id bigint NOT NULL,
  tags hstore NOT NULL,
  geom geometry(POINT, 4326) NOT NULL
);

-- Create a table for ways.
CREATE TABLE ways (
  id bigint NOT NULL,
  version int NOT NULL,
  visible boolean NOT NULL,
  user_id int NOT NULL,
  tstamp timestamp without time zone NOT NULL,
  changeset_id bigint NOT NULL,
  tags hstore NOT NULL,
  nodes bigint[] NOT NULL
);

-- Create a table for relations.
CREATE TABLE relations (
  id bigint NOT NULL,
  version int NOT NULL,
  visible boolean NOT NULL,
  user_id int NOT NULL,
  tstamp timestamp without time zone NOT NULL,
  changeset_id bigint NOT NULL,
  tags hstore NOT NULL
);

-- Create a table for representing relation member relationships.
CREATE TABLE relation_members (
  relation_id bigint NOT NULL,
  version bigint NOT NULL,
  member_id bigint NOT NULL,
  member_type character(1) NOT NULL,
  member_role text NOT NULL,
  sequence_id int NOT NULL
);

-- Create a table for users.
CREATE TABLE users (
  id int NOT NULL,
  name text NOT NULL
);
