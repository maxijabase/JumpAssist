void RunMigrations() {
  if (g_Database == null) {
    LogError("[JumpAssist] Cannot run migrations: Database not connected");
    return;
  }
  
  LogMessage("[JumpAssist] Running database migrations...");
  
  // Run all migrations in order
  Migration_AddZoneTypeColumn();
  Migration_CreateIndexes();
  Migration_SetDefaultZoneTypes();
  
  LogMessage("[JumpAssist] Database migrations completed");
}

// Migration 1: Add ZoneType column to zones table
void Migration_AddZoneTypeColumn() {
  char dbType[32];
  DBDriver driverType = g_Database.Driver;
  driverType.GetProduct(dbType, sizeof(dbType));
  
  if (StrEqual(dbType, "mysql", false)) {
    // MySQL syntax
    ExecuteSQL("ALTER TABLE zones ADD COLUMN ZoneType INT NOT NULL DEFAULT 1", 
               "Add ZoneType column (MySQL)", 
               true); // ignore errors
  } else {
    // SQLite syntax
    ExecuteSQL("ALTER TABLE zones ADD COLUMN ZoneType INTEGER NOT NULL DEFAULT 1", 
               "Add ZoneType column (SQLite)", 
               true); // ignore errors
  }
}

// Migration 2: Create useful indexes
void Migration_CreateIndexes() {
  // Index for zone lookups by map
  ExecuteSQL("CREATE INDEX IF NOT EXISTS idx_zones_map ON zones(MapName)", 
             "Create zones map index", 
             true);
  
  // Index for times lookups
  ExecuteSQL("CREATE INDEX IF NOT EXISTS idx_times_map_class ON times(MapName, class)", 
             "Create times map/class index", 
             true);
  
  // Index for player saves
  ExecuteSQL("CREATE INDEX IF NOT EXISTS idx_saves_lookup ON player_saves(steamID, playerMap, playerClass, playerTeam)", 
             "Create player saves lookup index", 
             true);
}

// Migration 3: Set default zone types for existing zones
void Migration_SetDefaultZoneTypes() {
  char query[1024];
  
  // Get all maps that have zones but no proper zone types set
  Format(query, sizeof(query), 
    "SELECT DISTINCT MapName FROM zones WHERE ZoneType IS NULL OR ZoneType = 1");
  g_Database.Query(SQL_OnMigrateZoneTypes, query);
}

/**
 * Callback to migrate zone types for maps
 */
public void SQL_OnMigrateZoneTypes(Database db, DBResultSet results, const char[] error, any data) {
  if (db == null || error[0]) {
    return; // Ignore errors, table might not exist yet
  }
  
  // Process each map
  while (results.FetchRow()) {
    char mapName[64];
    results.FetchString(0, mapName, sizeof(mapName));
    
    // Update zone types for this map
    MigrateMapZoneTypes(mapName);
  }
}

/**
 * Migrate zone types for a specific map
 */
void MigrateMapZoneTypes(const char[] mapName) {
  char query[512];
  
  // Set first zone (Number = 0) as start zone
  Format(query, sizeof(query), 
    "UPDATE zones SET ZoneType = 0 WHERE MapName = '%s' AND Number = 0", 
    mapName);
  ExecuteSQL(query, "Set start zone type", true);
  
  // Set last zone as end zone (find max Number first)
  Format(query, sizeof(query), 
    "UPDATE zones SET ZoneType = 2 WHERE MapName = '%s' AND Number = (SELECT MAX(Number) FROM zones WHERE MapName = '%s') AND Number > 0", 
    mapName, mapName);
  ExecuteSQL(query, "Set end zone type", true);
  
  // Set middle zones as checkpoints
  Format(query, sizeof(query), 
    "UPDATE zones SET ZoneType = 1 WHERE MapName = '%s' AND Number > 0 AND Number < (SELECT MAX(Number) FROM zones WHERE MapName = '%s')", 
    mapName, mapName);
  ExecuteSQL(query, "Set checkpoint zone types", true);
}

/**
 * Execute SQL with error handling
 */
bool ExecuteSQL(const char[] query, const char[] description, bool ignoreErrors = false) {
  char error[255];
  bool success = false;
  
  SQL_LockDatabase(g_Database);
  
  if (SQL_FastQuery(g_Database, query)) {
    success = true;
    LogMessage("[JumpAssist] Migration: %s - SUCCESS", description);
  } else {
    SQL_GetError(g_Database, error, sizeof(error));
    
    if (ignoreErrors) {
      // Check if it's a "already exists" type error
      if (StrContains(error, "already exists", false) != -1 || 
          StrContains(error, "duplicate", false) != -1 ||
          StrContains(error, "Duplicate column", false) != -1) {
        LogMessage("[JumpAssist] Migration: %s - SKIPPED (already exists)", description);
        success = true; // Treat as success
      } else {
        LogMessage("[JumpAssist] Migration: %s - IGNORED ERROR: %s", description, error);
        success = true; // Ignore the error
      }
    } else {
      LogError("[JumpAssist] Migration: %s - ERROR: %s", description, error);
    }
  }
  
  SQL_UnlockDatabase(g_Database);
  return success;
}

/**
 * Add future migrations here as needed
 */

// Example future migration:
// void Migration_AddNewFeature() {
//   ExecuteSQL("ALTER TABLE player_profiles ADD COLUMN new_setting INT DEFAULT 0", 
//              "Add new setting to profiles", 
//              true);
// }

// Another example:
// void Migration_CleanupOldData() {
//   ExecuteSQL("DELETE FROM old_table WHERE created_date < DATE('now', '-30 days')", 
//              "Clean up old data", 
//              true);
// }