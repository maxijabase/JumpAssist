// Zone data arrays
float g_fZoneBottom[32][3];
float g_fZoneTop[32][3];
int g_iZoneTypes[32]; // Store zone types
int g_iNumZones = 0;
int g_iStartZoneIndex = -1; // Track which zone is the start
int g_iEndZoneIndex = -1; // Track which zone is the end

// Client zone interaction state
bool g_bWaitingForZoneSelection[MAXPLAYERS + 1];
bool g_bWaitingForZoneType[MAXPLAYERS + 1];
int g_iClientSelectedZoneType[MAXPLAYERS + 1];
Handle g_hWeaponBlockTimer[MAXPLAYERS + 1];

// Zone display
bool g_bShowZones[MAXPLAYERS + 1];
Handle g_hZoneDisplayTimer[MAXPLAYERS + 1];

// Sprites for zone visualization
int g_iBeamSprite;
int g_iHaloSprite;

// Zone types enum
enum ZoneType {
  ZONE_START = 0,
  ZONE_CHECKPOINT = 1,
  ZONE_END = 2
}

// Initialize beam sprites on map start
void InitializeSpeedrunAssets() {
  g_iBeamSprite = PrecacheModel("materials/sprites/laser.vmt");
  g_iHaloSprite = PrecacheModel("materials/sprites/halo01.vmt");
}

// AreaSelector callback for zone creation
public void AreaSelector_OnAreaSelected(int client, AreaData area, float point1[3], float point2[3], float mins[3], float maxs[3], float center[3], float dimensions[3]) {
  // Only handle if this client was waiting for zone selection
  if (!g_bWaitingForZoneSelection[client] || !g_bWaitingForZoneType[client]) {
    return;
  }

  g_bWaitingForZoneSelection[client] = false;
  g_bWaitingForZoneType[client] = false;

  // Stop blocking weapons
  if (g_hWeaponBlockTimer[client] != null) {
    delete g_hWeaponBlockTimer[client];
    g_hWeaponBlockTimer[client] = null;
  }

  ZoneType selectedType = view_as<ZoneType>(g_iClientSelectedZoneType[client]);
  int zoneIndex = g_iNumZones;
  bool isReplacing = false;
  
  // Handle zone type-specific logic
  switch (selectedType) {
    case ZONE_START: {
      if (g_iStartZoneIndex != -1) {
        // Replace existing start zone
        zoneIndex = g_iStartZoneIndex;
        isReplacing = true;
        PrintToChat(client, "\x01[\x03JA\x01] Replacing existing start zone");
      } else {
        g_iStartZoneIndex = zoneIndex;
        g_iNumZones++;
      }
    }
    case ZONE_END: {
      if (g_iEndZoneIndex != -1) {
        // Replace existing end zone
        zoneIndex = g_iEndZoneIndex;
        isReplacing = true;
        PrintToChat(client, "\x01[\x03JA\x01] Replacing existing end zone");
      } else {
        g_iEndZoneIndex = zoneIndex;
        g_iNumZones++;
      }
    }
    case ZONE_CHECKPOINT: {
      // For checkpoints, always create new zone
      g_iNumZones++;
    }
  }

  // Store zone type
  g_iZoneTypes[zoneIndex] = view_as<int>(selectedType);

  // Store the zone data in our arrays
  g_fZoneBottom[zoneIndex][0] = mins[0];
  g_fZoneBottom[zoneIndex][1] = mins[1]; 
  g_fZoneBottom[zoneIndex][2] = mins[2];
  
  g_fZoneTop[zoneIndex][0] = maxs[0];
  g_fZoneTop[zoneIndex][1] = maxs[1];
  g_fZoneTop[zoneIndex][2] = maxs[2];

  // Create database query based on whether we're replacing or creating new
  char query[1024];
  
  if (isReplacing) {
    // Update existing zone
    Format(query, sizeof(query), 
      "UPDATE zones SET x1='%f', y1='%f', z1='%f', x2='%f', y2='%f', z2='%f', ZoneType='%d' WHERE MapName='%s' AND Number='%d'", 
      point1[0], point1[1], point1[2], 
      point2[0], point2[1], point2[2],
      view_as<int>(selectedType), 
      g_sCurrentMap, 
      zoneIndex);
  } else {
    // Insert new zone
    Format(query, sizeof(query), 
      "INSERT INTO zones (Number, MapName, ZoneType, x1, y1, z1, x2, y2, z2) VALUES ('%d', '%s', '%d', '%f', '%f', '%f', '%f', '%f', '%f')", 
      zoneIndex, 
      g_sCurrentMap, 
      view_as<int>(selectedType),
      point1[0], point1[1], point1[2], 
      point2[0], point2[1], point2[2]);
  }

  // Save to database
  g_Database.Query(SQL_OnZoneAdded, query, client);

  // Show preview of the created zone
  ShowZone(client, zoneIndex);

  // Provide feedback to the client
  char zoneTypeName[32];
  GetZoneTypeName(selectedType, zoneTypeName, sizeof(zoneTypeName));
  PrintToChat(client, "\x01[\x03JA\x01] %s zone %s successfully at index %d!", 
    zoneTypeName, 
    isReplacing ? "updated" : "created", 
    zoneIndex);
}

// AreaSelector callback for cancelled zone selection
public void AreaSelector_OnAreaCancelled(int client) {
  if (g_bWaitingForZoneSelection[client]) {
    g_bWaitingForZoneSelection[client] = false;
    // Stop blocking weapons
    if (g_hWeaponBlockTimer[client] != null) {
      delete g_hWeaponBlockTimer[client];
      g_hWeaponBlockTimer[client] = null;
    }
    PrintToChat(client, "\x01[\x03JA\x01] Zone selection cancelled");
  }
}

// Zone creation command
public Action cmdAddZone(int client, int args) {
  if (!g_cvarSpeedrunEnabled.BoolValue) {
    return Plugin_Continue;
  }
  if (g_Database == null) {
    PrintToChat(client, "This feature is not supported without a database configuration");
    return Plugin_Handled;
  }
  if (!client) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Cannot setup zones from rcon");
    return Plugin_Handled;
  }
  if (IsClientObserver(client)) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Cannot setup zones as spectator");
    return Plugin_Handled;
  }
  if (g_iNumZones >= 32) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Maximum zone count reached");
    return Plugin_Handled;
  }

  // Check if AreaSelector is available
  if (!LibraryExists("areaselector")) {
    ReplyToCommand(client, "\x01[\x03JA\x01] AreaSelector library not available");
    return Plugin_Handled;
  }

  // Check if client is already selecting
  if (AreaSelector_IsSelecting(client) || g_bWaitingForZoneSelection[client]) {
    ReplyToCommand(client, "\x01[\x03JA\x01] You are already selecting an area");
    return Plugin_Handled;
  }

  // Show zone type selection menu
  ShowZoneTypeMenu(client);
  return Plugin_Handled;
}

// Show zone type selection menu
void ShowZoneTypeMenu(int client) {
  Menu menu = new Menu(MenuHandler_ZoneType);
  menu.SetTitle("Select Zone Type:");
  
  // Check if start zone already exists
  if (g_iStartZoneIndex == -1) {
    menu.AddItem("start", "Start Zone");
  } else {
    menu.AddItem("start", "Start Zone (Replace existing)", ITEMDRAW_DISABLED);
  }
  
  menu.AddItem("checkpoint", "Checkpoint");
  
  // Check if end zone already exists
  if (g_iEndZoneIndex == -1) {
    menu.AddItem("end", "End Zone");
  } else {
    menu.AddItem("end", "End Zone (Replace existing)", ITEMDRAW_DISABLED);
  }
  
  menu.AddItem("cancel", "Cancel");
  menu.ExitButton = true;
  menu.Display(client, MENU_TIME_FOREVER);
}

// Zone type menu handler
public int MenuHandler_ZoneType(Menu menu, MenuAction action, int param1, int param2) {
  if (action == MenuAction_Select) {
    int client = param1;
    char info[16];
    menu.GetItem(param2, info, sizeof(info));
    
    if (StrEqual(info, "cancel")) {
      PrintToChat(client, "\x01[\x03JA\x01] Zone creation cancelled");
      return 0;
    }
    
    ZoneType zoneType;
    if (StrEqual(info, "start")) {
      zoneType = ZONE_START;
    } else if (StrEqual(info, "checkpoint")) {
      zoneType = ZONE_CHECKPOINT;
    } else if (StrEqual(info, "end")) {
      zoneType = ZONE_END;
    }
    
    // Store the selected zone type for this client
    g_iClientSelectedZoneType[client] = view_as<int>(zoneType);
    
    // Start area selection
    if (AreaSelector_Start(client)) {
      g_bWaitingForZoneSelection[client] = true;
      g_bWaitingForZoneType[client] = true;
      
      // Start blocking weapons
      g_hWeaponBlockTimer[client] = CreateTimer(1.0, Timer_BlockWeapons, client, TIMER_REPEAT);
      
      char zoneTypeName[32];
      GetZoneTypeName(zoneType, zoneTypeName, sizeof(zoneTypeName));
      ReplyToCommand(client, "\x01[\x03JA\x01] Creating %s zone. Double-click to select corners.", zoneTypeName);
      ReplyToCommand(client, "\x01[\x03JA\x01] Use mouse wheel or attack buttons to adjust height.");
    } else {
      ReplyToCommand(client, "\x01[\x03JA\x01] Failed to start zone selection");
    }
  }
  else if (action == MenuAction_End) {
    delete menu;
  }
  return 0;
}

// Timer to block weapons during zone selection
public Action Timer_BlockWeapons(Handle timer, int client) {
  if (!IsClientInGame(client) || !g_bWaitingForZoneSelection[client] || !AreaSelector_IsSelecting(client)) {
    g_hWeaponBlockTimer[client] = null;
    return Plugin_Stop;
  }
  
  BlockWeaponAttacks(client);
  return Plugin_Continue;
}

// Cancel zone selection command
public Action cmdCancelZoneSelection(int client, int args) {
  if (!client) {
    return Plugin_Handled;
  }
  
  if (g_bWaitingForZoneSelection[client] && AreaSelector_IsSelecting(client)) {
    AreaSelector_Cancel(client);
    PrintToChat(client, "\x01[\x03JA\x01] Zone selection cancelled");
  } else {
    PrintToChat(client, "\x01[\x03JA\x01] You are not currently selecting a zone");
  }
  
  return Plugin_Handled;
}

// Database callback for zone addition
public void SQL_OnZoneAdded(Handle owner, Handle hndl, const char[] error, any data) {
  int client = data;
  if (hndl == null) {
    LogError("OnZoneAdded() - Query failed! %s", error);
    PrintToChat(client, "\x01[\x03JA\x01] Zone creation failed: Database error");
    
    // Revert the zone count since database save failed
    if (g_iNumZones > 0) {
      g_fZoneBottom[g_iNumZones] = NULL_VECTOR;
      g_fZoneTop[g_iNumZones] = NULL_VECTOR;
    }
  } else if (error[0]) {
    LogError("OnZoneAdded() - Database error: %s", error);
    PrintToChat(client, "\x01[\x03JA\x01] Zone creation failed: %s", error);
    
    // Revert the zone count since database save failed  
    if (g_iNumZones > 0) {
      g_fZoneBottom[g_iNumZones] = NULL_VECTOR;
      g_fZoneTop[g_iNumZones] = NULL_VECTOR;
    }
  } else {
    PrintToChat(client, "\x01[\x03JA\x01] Zone successfully saved to database");
  }
}

// Show zones toggle command
public Action cmdShowZones(int client, int args) {
  if (!g_cvarSpeedrunEnabled.BoolValue) {
    return Plugin_Continue;
  }
  if (g_Database == null) {
    PrintToChat(client, "This feature is not supported without a database configuration");
    return Plugin_Handled;
  }
  if (!client) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Cannot toggle zone display from rcon");
    return Plugin_Handled;
  }
  if (IsClientObserver(client)) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Cannot toggle zone display as spectator");
    return Plugin_Handled;
  }
  
  // Toggle zone display
  g_bShowZones[client] = !g_bShowZones[client];
  
  if (g_bShowZones[client]) {
    // Start showing zones
    StartZoneDisplay(client);
    ReplyToCommand(client, "\x01[\x03JA\x01] Zone display \x05enabled\x01. Showing %d zones", g_iNumZones);
  } else {
    // Stop showing zones
    StopZoneDisplay(client);
    ReplyToCommand(client, "\x01[\x03JA\x01] Zone display \x05disabled\x01");
  }
  
  return Plugin_Handled;
}

// Show current zone command
public Action cmdShowZone(int client, int args) {
  if (!g_cvarSpeedrunEnabled.BoolValue) {
    return Plugin_Continue;
  }
  if (g_Database == null) {
    PrintToChat(client, "This feature is not supported without a database configuration");
    return Plugin_Handled;
  }
  if (!client) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Cannot show zones from rcon");
    return Plugin_Handled;
  }
  if (IsClientObserver(client)) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Cannot show zones as spectator");
    return Plugin_Handled;
  }
  
  bool foundZone = false;
  for (int i = 0; i < g_iNumZones; i++) {
    if (IsInZone(client, i)) {
      ShowZoneToClient(client, i);
      
      char zoneTypeName[32];
      switch (g_iZoneTypes[i]) {
        case 0: strcopy(zoneTypeName, sizeof(zoneTypeName), "Start");
        case 1: Format(zoneTypeName, sizeof(zoneTypeName), "Checkpoint %d", GetCheckpointNumber(i));
        case 2: strcopy(zoneTypeName, sizeof(zoneTypeName), "Finish");
        default: strcopy(zoneTypeName, sizeof(zoneTypeName), "Unknown");
      }
      
      ReplyToCommand(client, "\x01[\x03JA\x01] Showing \x05%s\x01 zone", zoneTypeName);
      foundZone = true;
      break;
    }
  }
  
  if (!foundZone) {
    ReplyToCommand(client, "\x01[\x03JA\x01] You are not in a zone");
  }
  
  return Plugin_Handled;
}

// Clear all zones command
public Action cmdClearZones(int client, int args) {
  if (!g_cvarSpeedrunEnabled.BoolValue) {
    return Plugin_Continue;
  }
  if (g_Database == null) {
    PrintToChat(client, "This feature is not supported without a database configuration");
    return Plugin_Handled;
  }
  if (!client) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Cannot clear zones from rcon");
    return Plugin_Handled;
  }
  char query[1024];
  DBResultSet results;
  
  Format(query, sizeof(query), "DELETE FROM times WHERE MapName='%s'", g_sCurrentMap);
  SQL_LockDatabase(g_Database);
  if ((results = SQL_Query(g_Database, query)) == null) {
    char err[256];
    SQL_GetError(results, err, sizeof(err));
    PrintToChat(client, "\x01[\x03JA\x01] An error occurred: %s", err);
  }
  SQL_UnlockDatabase(g_Database);
  for (int i = 0; i < 9; i++) {
    g_fRecordTime[i] = 99999999.99;
  }
  if (g_iNumZones) {
    for (int i = 0; i < 32; i++) {
      if (g_fZoneTimes[i][g_iNumZones - 1] != 0.0) {
        for (int j = 0; j < 32; j++) {
          g_fZoneTimes[i][j] = 0.0;
        }
      }
    }
  }
  Format(query, sizeof(query), "DELETE FROM zones WHERE MapName='%s'", g_sCurrentMap);
  SQL_LockDatabase(g_Database);
  if ((results = SQL_Query(g_Database, query)) == null) {
    char err[256];
    SQL_GetError(results, err, sizeof(err));
    PrintToChat(client, "\x01[\x03JA\x01] An error occurred: %s", err);
  }
  SQL_UnlockDatabase(g_Database);
  ClearMapZoneInfo();
  PrintToChat(client, "\x01[\x03JA\x01] All zones cleared");
  
  return Plugin_Continue;
}

// Clear zone information from memory
void ClearMapZoneInfo() {
  for (int i = 0; i < 32; i++) {
    g_fZoneBottom[i] = NULL_VECTOR;
    g_fZoneTop[i] = NULL_VECTOR;
    g_iZoneTypes[i] = -1;
  }
  g_iNumZones = 0;
  g_iStartZoneIndex = -1;
  g_iEndZoneIndex = -1;
}

// Load zones from database
void LoadMapZones() {
  char query[1024];
  Format(query, sizeof(query), 
    "SELECT x1, y1, z1, x2, y2, z2, Number, COALESCE(ZoneType, 1) as ZoneType FROM zones WHERE MapName='%s' ORDER BY Number ASC", 
    g_sCurrentMap);
  g_Database.Query(SQL_OnMapZonesLoad, query, 0);
}

// Database callback for loading zones
public void SQL_OnMapZonesLoad(Database db, DBResultSet results, const char[] error, any data) {
  if (db == null) {
    LogError("OnMapZonesLoad() - Query failed! %s", error);
    return;
  }
  
  if (!results.RowCount) {
    return;
  }
  
  // Reset zone tracking
  ClearMapZoneInfo();
  
  int maxZoneIndex = -1;
  
  while (results.FetchRow()) {
    // Read zone coordinates (columns 0-5)
    float point1[3], point2[3];
    point1[0] = results.FetchFloat(0); // x1
    point1[1] = results.FetchFloat(1); // y1
    point1[2] = results.FetchFloat(2); // z1
    point2[0] = results.FetchFloat(3); // x2
    point2[1] = results.FetchFloat(4); // y2
    point2[2] = results.FetchFloat(5); // z2
    
    // Read zone metadata (columns 6-7)
    int zoneIndex = results.FetchInt(6); // Number field
    int zoneType = results.FetchInt(7); // ZoneType field
    
    // Safety check - prevent array overflow
    if (zoneIndex >= 32 || zoneIndex < 0) {
      LogError("Zone index %d out of range for map %s (max 31)", zoneIndex, g_sCurrentMap);
      continue;
    }
    
    // Track start and end zones
    if (zoneType == view_as<int>(ZONE_START)) {
      g_iStartZoneIndex = zoneIndex;
    } else if (zoneType == view_as<int>(ZONE_END)) {
      g_iEndZoneIndex = zoneIndex;
    }
    
    // Store zone type
    g_iZoneTypes[zoneIndex] = zoneType;
    
    // Calculate mins and maxs
    for (int i = 0; i < 3; i++) {
      g_fZoneBottom[zoneIndex][i] = (point1[i] < point2[i]) ? point1[i] : point2[i];
      g_fZoneTop[zoneIndex][i] = (point1[i] > point2[i]) ? point1[i] : point2[i];
    }
    
    if (zoneIndex > maxZoneIndex) {
      maxZoneIndex = zoneIndex;
    }
  }
  
  g_iNumZones = maxZoneIndex + 1;
}

// Check if client is in a specific zone
bool IsInZone(int client, int zone) {
  return IsInRegion(client, g_fZoneBottom[zone], g_fZoneTop[zone]);
}

// Check if client is in a region defined by bottom and upper coordinates
bool IsInRegion(int client, float bottom[3], float upper[3]) {
  float playerPos[3];
  float playerEye[3];
  
  GetEntPropVector(client, Prop_Data, "m_vecOrigin", playerPos);
  GetClientEyePosition(client, playerEye);
  
  // Calculate proper mins/maxs
  float mins[3], maxs[3];
  for (int i = 0; i < 3; i++) {
    mins[i] = (bottom[i] < upper[i]) ? bottom[i] : upper[i];
    maxs[i] = (bottom[i] > upper[i]) ? bottom[i] : upper[i];
  }
  
  // Check both player origin and eye position
  return (AreaSelector_IsPointInArea(playerPos, mins, maxs) || 
          AreaSelector_IsPointInArea(playerEye, mins, maxs));
}

// Show a zone to all clients
void ShowZone(int client, int zone) {
  ShowZoneToClient(client, zone);
}

// Start zone display for a client
void StartZoneDisplay(int client) {
  if (!IsValidClient(client) || !g_bShowZones[client]) {
    return;
  }
  
  // Stop any existing timer
  if (g_hZoneDisplayTimer[client] != null) {
    delete g_hZoneDisplayTimer[client];
    g_hZoneDisplayTimer[client] = null;
  }
  
  // Start repeating timer to show zones
  g_hZoneDisplayTimer[client] = CreateTimer(5.0, Timer_ShowZones, client, TIMER_REPEAT);
  
  // Show zones immediately
  ShowAllZonesToClient(client);
}

// Stop zone display for a client
void StopZoneDisplay(int client) {
  if (g_hZoneDisplayTimer[client] != null) {
    delete g_hZoneDisplayTimer[client];
    g_hZoneDisplayTimer[client] = null;
  }
  g_bShowZones[client] = false;
}

// Timer callback to continuously show zones
public Action Timer_ShowZones(Handle timer, int client) {
  if (!IsValidClient(client) || !g_bShowZones[client]) {
    g_hZoneDisplayTimer[client] = null;
    return Plugin_Stop;
  }
  
  ShowAllZonesToClient(client);
  return Plugin_Continue;
}

// Show all zones to a specific client
void ShowAllZonesToClient(int client) {
  if (!IsValidClient(client) || g_iNumZones == 0) {
    return;
  }
  
  for (int i = 0; i < g_iNumZones; i++) {
    if (g_iZoneTypes[i] != -1) { // Only show valid zones
      ShowZoneToClient(client, i);
    }
  }
}

// Show a specific zone to a client with color coding
void ShowZoneToClient(int client, int zone) {
  if (g_iBeamSprite <= 0 || g_iHaloSprite <= 0) {
    PrintToChat(client, "\x01[\x03JA\x01] Beam sprites not loaded");
    return;
  }
  
  // Color code zones based on type
  int color[4];
  switch (g_iZoneTypes[zone]) {
    case 0: { // ZONE_START - Green
      color[0] = 0;   // Red
      color[1] = 255; // Green
      color[2] = 0;   // Blue
      color[3] = 255; // Alpha
    }
    case 1: { // ZONE_CHECKPOINT - Yellow
      color[0] = 255; // Red
      color[1] = 255; // Green
      color[2] = 0;   // Blue
      color[3] = 255; // Alpha
    }
    case 2: { // ZONE_END - Red
      color[0] = 255; // Red
      color[1] = 0;   // Green
      color[2] = 0;   // Blue
      color[3] = 255; // Alpha
    }
    default: { // Unknown - White
      color[0] = 255; // Red
      color[1] = 255; // Green
      color[2] = 255; // Blue
      color[3] = 255; // Alpha
    }
  }
  
  Effect_DrawBeamBoxToClient(client, g_fZoneBottom[zone], g_fZoneTop[zone], 
    g_iBeamSprite, g_iHaloSprite, 0, 30, 5.0, 2.0, 2.0, 2, 1.0, color, 0);
}

// Block weapon attacks for a client
void BlockWeaponAttacks(int client) {
  if (!IsValidClient(client) || !IsPlayerAlive(client)) {
    return;
  }
  
  float engineTime = GetGameTime();
  
  // Block all weapon slots from attacking for 1.1 seconds
  for (int i = 0; i <= 2; i++) {
    int weapon = GetPlayerWeaponSlot(client, i);
    if (IsValidEntity(weapon)) {
      SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", engineTime + 1.1);
      SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", engineTime + 1.1);
    }
  }
}

// Get zone type name as string
void GetZoneTypeName(ZoneType zoneType, char[] buffer, int maxlen) {
  switch (zoneType) {
    case ZONE_START: strcopy(buffer, maxlen, "Start");
    case ZONE_CHECKPOINT: strcopy(buffer, maxlen, "Checkpoint");
    case ZONE_END: strcopy(buffer, maxlen, "End");
  }
}

// Helper functions for checkpoint management
int GetCheckpointNumber(int zoneIndex) {
  int checkpointNum = 1;
  for (int i = 0; i < zoneIndex; i++) {
    if (g_iZoneTypes[i] == view_as<int>(ZONE_CHECKPOINT)) {
      checkpointNum++;
    }
  }
  return checkpointNum;
}

int GetNextCheckpoint(int currentZone) {
  for (int i = currentZone + 1; i < g_iNumZones; i++) {
    if (g_iZoneTypes[i] == view_as<int>(ZONE_CHECKPOINT)) {
      return i;
    }
  }
  return g_iEndZoneIndex; // Next target is end zone
}

int GetFirstCheckpoint() {
  for (int i = 0; i < g_iNumZones; i++) {
    if (g_iZoneTypes[i] == view_as<int>(ZONE_CHECKPOINT)) {
      return i;
    }
  }
  return g_iEndZoneIndex; // No checkpoints, go straight to end
}

// Beam effect drawing functions
void Effect_DrawBeamBoxToClient(
  int client, 
  const float bottomCorner[3], 
  const float upperCorner[3], 
  int modelIndex, 
  int haloIndex, 
  int startFrame = 0, 
  int frameRate = 30, 
  float life = 5.0, 
  float width = 5.0, 
  float endWidth = 5.0, 
  int fadeLength = 2, 
  float amplitude = 1.0, 
  const int color[4] = { 255, 0, 0, 255 }, 
  int speed = 0
  ) {
  int clients[1];
  clients[0] = client;
  Effect_DrawBeamBox(clients, 1, bottomCorner, upperCorner, modelIndex, haloIndex, startFrame, frameRate, life, width, endWidth, fadeLength, amplitude, color, speed);
}

void Effect_DrawBeamBox(
  int[] clients, 
  int numClients, 
  const float bottomCorner[3], 
  const float upperCorner[3], 
  int modelIndex, 
  int haloIndex, 
  int startFrame = 0, 
  int frameRate = 30, 
  float life = 5.0, 
  float width = 5.0, 
  float endWidth = 5.0, 
  int fadeLength = 2, 
  float amplitude = 1.0, 
  const int color[4] = { 255, 0, 0, 255 }, 
  int speed = 0
  ) {
  // Create the additional corners of the box
  float corners[8][3];
  
  for (int i = 0; i < 4; i++) {
    Array_Copy(bottomCorner, corners[i], 3);
    Array_Copy(upperCorner, corners[i + 4], 3);
  }
  corners[1][0] = upperCorner[0];
  corners[2][0] = upperCorner[0];
  corners[2][1] = upperCorner[1];
  corners[3][1] = upperCorner[1];
  corners[4][0] = bottomCorner[0];
  corners[4][1] = bottomCorner[1];
  corners[5][1] = bottomCorner[1];
  corners[7][0] = bottomCorner[0];
  // Draw all the edges
  // Horizontal Lines
  // Bottom
  for (int i = 0; i < 4; i++) {
    int j = (i == 3 ? 0 : i + 1);
    TE_SetupBeamPoints(corners[i], corners[j], modelIndex, haloIndex, startFrame, frameRate, life, width, endWidth, fadeLength, amplitude, color, speed);
    TE_Send(clients, numClients);
  }
  // Top
  for (int i = 4; i < 8; i++) {
    int j = (i == 7 ? 4 : i + 1);
    TE_SetupBeamPoints(corners[i], corners[j], modelIndex, haloIndex, startFrame, frameRate, life, width, endWidth, fadeLength, amplitude, color, speed);
    TE_Send(clients, numClients);
  }
  // All Vertical Lines
  for (int i = 0; i < 4; i++) {
    TE_SetupBeamPoints(corners[i], corners[i + 4], modelIndex, haloIndex, startFrame, frameRate, life, width, endWidth, fadeLength, amplitude, color, speed);
    TE_Send(clients, numClients);
  }
}

void Array_Copy(const any[] array, any[] newArray, int size) {
  for (int i = 0; i < size; i++) {
    newArray[i] = array[i];
  }
}