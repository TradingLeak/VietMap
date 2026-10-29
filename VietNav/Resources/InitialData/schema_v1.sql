CREATE TABLE traffic_nodes (
  id INTEGER PRIMARY KEY AUTOINCREMENT, osm_id INTEGER UNIQUE, type TEXT NOT NULL,
  latitude REAL NOT NULL CHECK(latitude BETWEEN -90 AND 90),
  longitude REAL NOT NULL CHECK(longitude BETWEEN -180 AND 180),
  speed_limit INTEGER, bearing REAL, road_name TEXT, road_ref TEXT, province TEXT, district TEXT,
  verified INTEGER NOT NULL DEFAULT 0, source TEXT NOT NULL DEFAULT 'OSM', created_at INTEGER, updated_at INTEGER
);
CREATE VIRTUAL TABLE traffic_nodes_rtree USING rtree(id, min_lat, max_lat, min_lon, max_lon);
CREATE INDEX idx_type ON traffic_nodes(type);
CREATE INDEX idx_province ON traffic_nodes(province);
CREATE TRIGGER traffic_nodes_ai AFTER INSERT ON traffic_nodes BEGIN
  INSERT INTO traffic_nodes_rtree VALUES (new.id,new.latitude,new.latitude,new.longitude,new.longitude);
END;
CREATE TRIGGER traffic_nodes_au AFTER UPDATE OF id,latitude,longitude ON traffic_nodes BEGIN
  DELETE FROM traffic_nodes_rtree WHERE id=old.id;
  INSERT INTO traffic_nodes_rtree VALUES (new.id,new.latitude,new.latitude,new.longitude,new.longitude);
END;
CREATE TRIGGER traffic_nodes_ad AFTER DELETE ON traffic_nodes BEGIN
  DELETE FROM traffic_nodes_rtree WHERE id=old.id;
END;
CREATE TABLE road_segments (
  id INTEGER PRIMARY KEY, osm_way_id INTEGER, road_name TEXT, road_type TEXT, max_speed INTEGER,
  geometry TEXT NOT NULL, province TEXT,
  min_lat REAL NOT NULL, max_lat REAL NOT NULL, min_lon REAL NOT NULL, max_lon REAL NOT NULL
);
CREATE VIRTUAL TABLE road_segments_rtree USING rtree(id, min_lat, max_lat, min_lon, max_lon);
CREATE TRIGGER road_segments_ai AFTER INSERT ON road_segments BEGIN
  INSERT INTO road_segments_rtree VALUES(new.id,new.min_lat,new.max_lat,new.min_lon,new.max_lon);
END;
CREATE TRIGGER road_segments_au AFTER UPDATE OF id,min_lat,max_lat,min_lon,max_lon ON road_segments BEGIN
  DELETE FROM road_segments_rtree WHERE id=old.id;
  INSERT INTO road_segments_rtree VALUES(new.id,new.min_lat,new.max_lat,new.min_lon,new.max_lon);
END;
CREATE TRIGGER road_segments_ad AFTER DELETE ON road_segments BEGIN
  DELETE FROM road_segments_rtree WHERE id=old.id;
END;
CREATE TABLE user_reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL, latitude REAL, longitude REAL,
  description TEXT, photo_path TEXT, reported_at INTEGER, uploaded INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_reports_uploaded ON user_reports(uploaded);
