float g_fStartLoc[3];
float g_fStartAng[3];
float g_fLoc[3];
float g_fAng[3];
float g_fZoneBottom[32][3];
float g_fZoneTop[32][3];
float g_fZoneTimes[32][32];
float g_fRecordTime[9];
float g_fProcessingZoneTimes[32][32];

int g_iNextCheckPoint[32];
int g_iProcessingClass[32];
int g_iLastFrameInStartZone[32];
int g_iBeamSprite;
int g_iHaloSprite;
int g_iNumZones = 0;

bool g_bSkippedCheckPointMessage[32];
bool g_bWaitingForZoneSelection[MAXPLAYERS + 1];

enum {
  LISTING_RANKED, 
  LISTING_GENERAL, 
  LISTING_PLAYER
}

Handle g_hWeaponBlockTimer[MAXPLAYERS + 1];

// Initialize beam sprites on map start
void InitializeSpeedrunAssets() {
  g_iBeamSprite = PrecacheModel("materials/sprites/laser.vmt");
  g_iHaloSprite = PrecacheModel("materials/sprites/halo01.vmt");
}

// Add AreaSelector forward handlers
public void AreaSelector_OnAreaSelected(int client, AreaData area, float point1[3], float point2[3], float mins[3], float maxs[3], float center[3], float dimensions[3]) {
  // Only handle if this client was waiting for zone selection
  if (!g_bWaitingForZoneSelection[client]) {
    return;
  }

  g_bWaitingForZoneSelection[client] = false;

  // Stop blocking weapons
  if (g_hWeaponBlockTimer[client] != null) {
    delete g_hWeaponBlockTimer[client];
    g_hWeaponBlockTimer[client] = null;
  }

  // Convert AreaSelector data to the database format (x1,y1,z1,x2,y2,z2)
  // We'll use the original point1 and point2 to maintain compatibility
  char query[1024];
  Format(query, sizeof(query), 
    "INSERT INTO zones VALUES (null, '%d', '%s', '%f', '%f', '%f', '%f', '%f', '%f')", 
    g_iNumZones, 
    g_sCurrentMap, 
    point1[0], point1[1], point1[2],    // x1, y1, z1
    point2[0], point2[1], point2[2]     // x2, y2, z2
  );

  // Store the zone data in our arrays (convert to mins/maxs format for collision detection)
  g_fZoneBottom[g_iNumZones][0] = mins[0];
  g_fZoneBottom[g_iNumZones][1] = mins[1]; 
  g_fZoneBottom[g_iNumZones][2] = mins[2];
  
  g_fZoneTop[g_iNumZones][0] = maxs[0];
  g_fZoneTop[g_iNumZones][1] = maxs[1];
  g_fZoneTop[g_iNumZones][2] = maxs[2];

  // Save to database
  g_Database.Query(SQL_OnZoneAdded, query, client);

  // Show preview of the created zone
  ShowZone(client, g_iNumZones);

  // Provide feedback to the client
  PrintToChat(client, "\x01[\x03JA\x01] Zone %d created successfully!", g_iNumZones);
  
  if (g_iNumZones == 0) {
    PrintToChat(client, "\x01[\x03JA\x01] This is the \x05START\x01 zone");
  } else if (g_iNumZones == 1) {
    PrintToChat(client, "\x01[\x03JA\x01] This is the \x05FINISH\x01 zone");
  } else {
    PrintToChat(client, "\x01[\x03JA\x01] This is \x05checkpoint %d\x01", g_iNumZones - 1);
  }

  // Increment zone count after successful creation
  g_iNumZones++;
}

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

public void AreaSelector_OnDisplayUpdate(int client, int step, float currentPos[3], float heightOffset, float firstPoint[3], float dimensions[3], float volume) {
  if (!g_bWaitingForZoneSelection[client]) {
    return;
  }

  // Provide helpful hints during selection
  if (step == 1) {
    PrintHintText(client, "Step 1/2: Selecting first corner\nHeight offset: %.1f units", heightOffset);
  } else if (step == 2) {
    PrintHintText(client, "Step 2/2: Selecting second corner\nArea: %.1f x %.1f x %.1f\nVolume: %.0f units³", 
      dimensions[0], dimensions[1], dimensions[2], volume);
  }
}

void processSpeedrun(int client) {
  char query[1024];
  char steamid[32];
  char endtime[4];
  
  GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
  Format(endtime, sizeof(endtime), "c%d", g_iNumZones - 1);
  Format(query, sizeof(query), "SELECT %s FROM times WHERE SteamID='%s' AND class='%d' AND MapName='%s'", endtime, steamid, g_iProcessingClass[client], g_sCurrentMap);
  g_Database.Query(SQL_OnSpeedrunCheckLoad, query, client);
}

public void SQL_OnSpeedrunCheckLoad(Database db, DBResultSet results, const char[] error, any data) {
  int client = data, datetime;
  float t;
  char query[1024];
  char steamid[32];
  
  GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
  datetime = GetTime();
  
  if (db == null) {
    LogError("OnSpeedrunCheckLoad() - Query failed! %s", error);
  }
  else if (results.RowCount) {
    results.FetchRow();
    float endTime = results.FetchFloat(0);
    
    if (endTime > g_fProcessingZoneTimes[client][g_iNumZones - 1] - g_fProcessingZoneTimes[client][0]) {
      Format(query, sizeof(query), "UPDATE times SET time='%d',", datetime);
      for (int i = 0; i < 32; i++) {
        if (i == 0) {
          Format(query, sizeof(query), "%s c%d='%f',", query, i, 0.0);
        }
        else {
          t = g_fProcessingZoneTimes[client][i] - g_fProcessingZoneTimes[client][0];
          if (t < 0.0) {
            t = 0.0;
          }
          Format(query, sizeof(query), "%s c%d='%f'", query, i, t);
          if (i != 31) {
            Format(query, sizeof(query), "%s,", query);
          }
        }
      }
      Format(query, sizeof(query), "%s WHERE SteamID='%s' AND MapName='%s' AND class='%d';", query, steamid, g_sCurrentMap, g_iProcessingClass[client]);
      g_Database.Query(SQL_OnSpeedrunSubmit, query, client);
    }
    else {
      char clientName[64];
      char message[256];
      float time = g_fProcessingZoneTimes[client][g_iNumZones - 1] - g_fProcessingZoneTimes[client][0];
      char className[32];
      GetClassName(view_as<TFClassType>(g_iProcessingClass[client]), className, sizeof(className));
      
      GetClientName(client, clientName, sizeof(clientName));
      Format(message, sizeof(message), "\x01[\x03JA\x01] \x03%s\x01: \x05%s\x01 map run: \x04%s\x01", clientName, className, TimeFormat(time));
      PrintToChatAll(message);
    }
  }
  else {
    Format(query, sizeof(query), "INSERT INTO times VALUES(null, '%s', '%d', '%s', '%d',", steamid, g_iProcessingClass[client], g_sCurrentMap, datetime);
    for (int i = 0; i < 32; i++) {
      if (i == 0) {
        Format(query, sizeof(query), "%s '%f',", query, 0.0);
      }
      else {
        t = g_fProcessingZoneTimes[client][i] - g_fProcessingZoneTimes[client][0];
        if (t < 0.0) {
          t = 0.0;
        }
        Format(query, sizeof(query), "%s '%f'", query, t);
        if (i != 31) {
          Format(query, sizeof(query), "%s,", query);
        }
      }
    }
    Format(query, sizeof(query), "%s);", query);
    g_Database.Query(SQL_OnSpeedrunSubmit, query, client);
  }
}

public void SQL_OnSpeedrunSubmit(Handle owner, Handle hndl, const char[] error, any data) {
  int client = data;
  if (hndl == null) {
    LogError("OnSpeedrunSubmit() - Query failed! %s", error);
  }
  else {
    char clientName[64];
    char message[256];
    float time = g_fProcessingZoneTimes[client][g_iNumZones - 1] - g_fProcessingZoneTimes[client][0];
    
    char className[32];
    GetClassName(view_as<TFClassType>(g_iProcessingClass[client]), className, sizeof(className));
    
    GetClientName(client, clientName, sizeof(clientName));
    if (time < g_fRecordTime[g_iProcessingClass[client]]) {
      float previousRecord = g_fRecordTime[g_iProcessingClass[client]];
      
      g_fRecordTime[g_iProcessingClass[client]] = time;
      if (previousRecord == 99999999.99) {
        Format(message, sizeof(message), "\x01[\x03JA\x01] \x03%s\x01 set the map record as \x05%s\x01 with time \x04%s\x01!", clientName, className, TimeFormat(time));
      }
      else {
        Format(message, sizeof(message), "\x01[\x03JA\x01] \x03%s\x01 broke the map record as \x05%s\x01 by \x04%s\x01 with time \x04%s\x01!", clientName, className, TimeFormat(previousRecord - time), TimeFormat(time));
      }
    }
    else {
      Format(message, sizeof(message), "\x01[\x03JA\x01] \x03%s\x01: \x05%s\x01 map run: \x04%s\x01", clientName, className, TimeFormat(time));
    }
    PrintToChatAll(message);
  }
}

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
  if (AreaSelector_IsSelecting(client)) {
    ReplyToCommand(client, "\x01[\x03JA\x01] You are already selecting an area");
    return Plugin_Handled;
  }

  // Start area selection
  if (AreaSelector_Start(client)) {
    g_bWaitingForZoneSelection[client] = true;
    // Start blocking weapons every 1 second
    g_hWeaponBlockTimer[client] = CreateTimer(1.0, Timer_BlockWeapons, client, TIMER_REPEAT);
    ReplyToCommand(client, "\x01[\x03JA\x01] Zone selection started. Double-click to select corners.");
    ReplyToCommand(client, "\x01[\x03JA\x01] Use mouse wheel or attack buttons to adjust height.");
  } else {
    ReplyToCommand(client, "\x01[\x03JA\x01] Failed to start zone selection");
  }

  return Plugin_Handled;
}

public Action Timer_BlockWeapons(Handle timer, int client) {
  if (!IsClientInGame(client) || !g_bWaitingForZoneSelection[client] || !AreaSelector_IsSelecting(client)) {
    g_hWeaponBlockTimer[client] = null;
    return Plugin_Stop;
  }
  
  BlockWeaponAttacks(client);
  return Plugin_Continue;
}

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

public Action cmdShowPR(int client, int args) {
  if (!g_cvarSpeedrunEnabled.BoolValue) {
    return Plugin_Continue;
  }
  if (g_Database == null) {
    PrintToChat(client, "This feature is not supported without a database configuration");
    return Plugin_Handled;
  }
  if (!client) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Cannot use this command from rcon");
    return Plugin_Handled;
  }
  if (!IsSpeedrunMap()) {
    ReplyToCommand(client, "\x01[\x03JA\x01] This map does not currently have speedrunning configured");
    return Plugin_Handled;
  }
  char query[1024];
  char steamid[32];
  char endtime[4];
  int class;
  
  GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
  class = (IsClientObserver(client)) ? 3 : view_as<int>(TF2_GetPlayerClass(client));
  
  Format(endtime, sizeof(endtime), "c%d", g_iNumZones - 1);
  Format(query, sizeof(query), "SELECT MapName, SteamID, %s, class FROM times WHERE SteamID='%s' AND class='%d' AND MapName='%s'", endtime, steamid, class, g_sCurrentMap);
  g_Database.Query(SQL_OnSpeedrunListingSubmit, query, client);
  
  return Plugin_Continue;
}

public void SQL_OnSpeedrunListingSubmit(Database db, DBResultSet results, const char[] error, any data) {
  int client = data;
  if (db == null) {
    LogError("OnSpeedrunListingSubmit() - Query failed! %s", error);
  }
  else if (results.RowCount) {
    char mapName[32];
    char steamid[32];
    char class[128];
    char timeString[128];
    char query[1024];
    char playerName[64];
    char toPrint[128];
    float time;
    DBResultSet hQuery;
    
    results.FetchRow();
    results.FetchString(0, mapName, sizeof(mapName));
    results.FetchString(1, steamid, sizeof(steamid));
    time = results.FetchFloat(2);
    timeString = TimeFormat(time);
    GetClassName(view_as<TFClassType>(results.FetchInt(3)), class, sizeof(class));
    Format(query, sizeof(query), "SELECT name FROM steamids WHERE SteamID='%s'", steamid);
    SQL_LockDatabase(g_Database);
    if ((hQuery = SQL_Query(g_Database, query)) == null) {
      char err[256];
      SQL_GetError(hQuery, err, sizeof(err));
      Format(toPrint, sizeof(toPrint), "\x01[\x03JA\x01] An error occurred: %s", err);
    }
    else {
      hQuery.FetchRow();
      hQuery.FetchString(0, playerName, sizeof(playerName));
      Format(toPrint, sizeof(toPrint), "\x01[\x03JA\x01] \x03%s\x01: \x05%s\x01 - \x03%s\x01: \x04%s\x01", playerName, mapName, class, timeString);
    }
    SQL_UnlockDatabase(g_Database);
    PrintToChat(client, toPrint);
    delete hQuery;
  }
  else {
    PrintToChat(client, "\x01[\x03JA\x01] No record exists");
  }
}

public Action cmdShowPlayerInfo(int client, int args) {
  if (!g_cvarSpeedrunEnabled.BoolValue) {
    return Plugin_Continue;
  }
  if (g_Database == null) {
    PrintToChat(client, "This feature is not supported without a database configuration");
    return Plugin_Handled;
  }
  if (!IsSpeedrunMap()) {
    ReplyToCommand(client, "\x01[\x03JA\x01] This map does not currently have speedrunning configured");
    return Plugin_Handled;
  }
  if (!client) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Cannot use this command from rcon");
    return Plugin_Handled;
  }
  char query[1024];
  char steamid[32];
  ArrayList data = new ArrayList(64);
  
  GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
  if (args == 0 || args == 1) {
    Format(query, sizeof(query), "SELECT * FROM times WHERE SteamID='%s' LIMIT 50", steamid);
    data.Push(client);
    data.Push(LISTING_PLAYER);
    data.PushString(g_sCurrentMap);
    data.Push(0);
  }
  g_Database.Query(SQL_OnSpeedrunMultiListingSubmit, query, data);
  
  return Plugin_Continue;
}

public Action cmdShowTop(int client, int args) {
  if (!g_cvarSpeedrunEnabled.BoolValue) {
    return Plugin_Continue;
  }
  if (g_Database == null) {
    PrintToChat(client, "This feature is not supported without a database configuration");
    return Plugin_Handled;
  }
  if (!IsSpeedrunMap()) {
    ReplyToCommand(client, "\x01[\x03JA\x01] This map does not currently have speedrunning configured");
    return Plugin_Handled;
  }
  if (!client) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Cannot use this command from rcon");
    return Plugin_Handled;
  }
  char query[1024];
  char endtime[4];
  int class;
  ArrayList data = new ArrayList(64);
  class = (IsClientObserver(client)) ? 3 : view_as<int>(TF2_GetPlayerClass(client));
  
  if (args == 0) {
    Format(endtime, sizeof(endtime), "c%d", g_iNumZones - 1);
    Format(query, sizeof(query), "SELECT * FROM times WHERE class='%d' AND MapName='%s' ORDER BY %s ASC LIMIT 50", class, g_sCurrentMap, endtime);
    data.Push(client);
    data.Push(LISTING_RANKED);
    data.PushString(g_sCurrentMap);
    data.Push(class);
  }
  else {
    char arg1[128];
    char endTime[4];
    char mapName[128];
    char err[128];
    DBResultSet results;
    
    GetCmdArg(1, arg1, sizeof(arg1));
    GetFullMapName(arg1, mapName, sizeof(mapName));
    Format(query, sizeof(query), "SELECT * FROM times WHERE MapName='%s' LIMIT 1", mapName);
    SQL_LockDatabase(g_Database);
    if ((results = SQL_Query(g_Database, query)) == null) {
      SQL_GetError(results, err, sizeof(err));
      char toPrint[128];
      Format(toPrint, sizeof(toPrint), "\x01[\x03JA\x01] An error occurred: %s", err);
      PrintToChat(client, toPrint);
      return Plugin_Handled;
    }
    else {
      if (results.RowCount) {
        results.FetchRow();
        int finish = GetFinishCheckpoint(results);
        Format(endTime, sizeof(endTime), "c%d", finish);
      }
      else {
        PrintToChat(client, "\x01[\x03JA\x01] No records exists");
        return Plugin_Handled;
      }
    }
    SQL_UnlockDatabase(g_Database);
    Format(query, sizeof(query), "SELECT * FROM times WHERE class='%d' AND MapName='%s' ORDER BY %s ASC LIMIT 50", class, mapName, endTime);
    data.Push(client);
    data.Push(LISTING_RANKED);
    data.PushString(mapName);
    data.Push(class);
  }
  g_Database.Query(SQL_OnSpeedrunMultiListingSubmit, query, data);
  
  return Plugin_Continue;
}

public void SQL_OnSpeedrunMultiListingSubmit(Database db, DBResultSet results, const char[] error, any data) {
  if (db == null) {
    LogError("OnSpeedrunMultiListingSubmit() - Query failed! %s", error);
    return;
  }
  ArrayList array = view_as<ArrayList>(data);
  int client = array.Get(0);
  int multiType = array.Get(1);
  int class = array.Get(3);
  char map[64];
  
  array.GetString(2, map, sizeof(map));
  
  if (results.RowCount) {
    Menu menu = BuildMultiListingMenu(results, multiType, class, map);
    menu.Display(client, MENU_TIME_FOREVER);
  }
  else {
    PrintToChat(client, "\x01[\x03JA\x01] No records exists");
  }
  delete array;
}

float GetFinishTime(DBResultSet results) {
  for (int i = 7; i < 38; i++) {
    if (results.FetchFloat(i) == 0.0) {
      return (results.FetchFloat(i - 1));
    }
  }
  return 0.0;
}

int GetFinishCheckpoint(DBResultSet results) {
  for (int i = 7; i < 38; i++) {
    if (results.FetchFloat(i) == 0.0) {
      return (i - 6);
    }
  }
  return 0;
}

Menu BuildMultiListingMenu(DBResultSet resultSet, int type, int class, char[] map) {
  char mapName[32];
  char steamid[32];
  char timeString[128];
  char query[1024];
  char playerName[64];
  char toPrint[128];
  char err[256];
  char classString[128];
  char idString[16];
  char title[256];
  float time;
  DBResultSet results;
  int id;
  int listingClass;
  Menu menu = new Menu(Menu_MultiListing);
  
  for (int i = 0; i < resultSet.RowCount; i++) {
    resultSet.FetchRow();
    resultSet.FetchString(3, mapName, sizeof(mapName));
    resultSet.FetchString(1, steamid, sizeof(steamid));
    
    time = GetFinishTime(resultSet);
    timeString = TimeFormat(time);
    id = resultSet.FetchInt(0);
    listingClass = resultSet.FetchInt(2);
    GetClassName(view_as<TFClassType>(listingClass), classString, sizeof(classString));
    
    Format(idString, sizeof(idString), "%d", id);
    Format(query, sizeof(query), "SELECT name FROM steamids WHERE SteamID='%s'", steamid);
    
    SQL_LockDatabase(g_Database);
    if ((results = SQL_Query(g_Database, query)) == null) {
      SQL_GetError(results, err, sizeof(err));
      Format(toPrint, sizeof(toPrint), "\x01[\x03JA\x01] An error occurred: %s", err);
    }
    else {
      results.FetchRow();
      results.FetchString(0, playerName, sizeof(playerName));
      if (type == LISTING_RANKED) {
        Format(toPrint, sizeof(toPrint), "(%d) %s: %s", i + 1, timeString, playerName);
      }
      else if (type == LISTING_GENERAL) {
        Format(toPrint, sizeof(toPrint), "%s: %s", timeString, mapName, playerName);
      }
      else if (type == LISTING_PLAYER) {
        Format(toPrint, sizeof(toPrint), "%s - [%s - %s]", timeString, mapName, classString);
      }
    }
    SQL_UnlockDatabase(g_Database);
    menu.AddItem(idString, toPrint);
  }
  delete results;
  
  switch (type) {
    case LISTING_RANKED: {
      GetClassName(view_as<TFClassType>(class), classString, sizeof(classString));
      Format(title, sizeof(title), "%s - %s", map, classString);
    }
    case LISTING_PLAYER: {
      Format(title, sizeof(title), "%s", playerName);
    }
  }
  menu.SetTitle(title);
  
  return menu;
}

int Menu_MultiListing(Menu menu, MenuAction action, int param1, int param2) {
  if (action == MenuAction_Select) {
    char info[32];
    menu.GetItem(param2, info, sizeof(info));
    PrintToChat(param1, "You selected run ID #%s", info);
  }
  return 0;
}

public Action cmdShowWR(int client, int args) {
  if (!g_cvarSpeedrunEnabled.BoolValue) {
    return Plugin_Continue;
  }
  if (g_Database == null) {
    PrintToChat(client, "This feature is not supported without a database configuration");
    return Plugin_Handled;
  }
  if (!IsSpeedrunMap()) {
    ReplyToCommand(client, "\x01[\x03JA\x01] This map does not currently have speedrunning configured");
    return Plugin_Handled;
  }
  if (!client) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Cannot use this command from rcon");
    return Plugin_Handled;
  }
  char query[1024];
  char steamid[32];
  char endtime[4];
  int class;
  
  GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
  class = (IsClientObserver(client)) ? 3 : view_as<int>(TF2_GetPlayerClass(client));
  
  Format(endtime, sizeof(endtime), "c%d", g_iNumZones - 1);
  Format(query, sizeof(query), "SELECT MapName, SteamID, %s, class FROM times WHERE class='%d' AND MapName='%s' ORDER BY %s ASC LIMIT 1", endtime, class, g_sCurrentMap, endtime);
  g_Database.Query(SQL_OnSpeedrunListingSubmit, query, client);
  
  return Plugin_Continue;
}

public Action cmdSpeedrunRestart(int client, int args) {
  if (!g_cvarSpeedrunEnabled.BoolValue) {
    return Plugin_Continue;
  }
  if (g_Database == null) {
    PrintToChat(client, "This feature is not supported without a database configuration");
    return Plugin_Handled;
  }
  if (!client) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Cannot speedrun from rcon");
    return Plugin_Handled;
  }
  if (IsClientObserver(client)) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Cannot speedrun as spectator");
    return Plugin_Handled;
  }
  if (!IsSpeedrunMap()) {
    ReplyToCommand(client, "\x01[\x03JA\x01] This map does not currently have speedrunning configured");
    return Plugin_Handled;
  }
  RestartSpeedrun(client);
  
  return Plugin_Continue;
}

public Action cmdDisableSpeedrun(int client, int args) {
  if (!g_cvarSpeedrunEnabled.BoolValue) {
    return Plugin_Continue;
  }
  if (g_Database == null) {
    PrintToChat(client, "This feature is not supported without a database configuration");
    return Plugin_Handled;
  }
  if (!client) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Cannot speedrun from rcon");
    return Plugin_Handled;
  }
  if (IsClientObserver(client)) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Cannot speedrun as spectator");
    return Plugin_Handled;
  }
  if (g_iSpeedrunStatus[client]) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Speedrunning disabled");
    g_iSpeedrunStatus[client] = 0;
  }
  return Plugin_Continue;
}

public Action cmdToggleSpeedrun(int client, int args) {
  if (!g_cvarSpeedrunEnabled.BoolValue) {
    return Plugin_Continue;
  }
  if (g_Database == null) {
    PrintToChat(client, "This feature is not supported without a database configuration");
    return Plugin_Handled;
  }
  if (!client) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Cannot speedrun from rcon");
    return Plugin_Handled;
  }
  if (IsClientObserver(client)) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Cannot speedrun as spectator");
    return Plugin_Handled;
  }
  if (!IsSpeedrunMap()) {
    ReplyToCommand(client, "\x01[\x03JA\x01] This map does not currently have speedrunning configured");
    return Plugin_Handled;
  }
  if (g_iSpeedrunStatus[client]) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Speedrunning disabled");
    g_iSpeedrunStatus[client] = 0;
  }
  else {
    ReplyToCommand(client, "\x01[\x03JA\x01] Speedrunning enabled");
    g_iSpeedrunStatus[client] = 1;
    RestartSpeedrun(client);
    g_bHPRegen[client] = false;
    g_bAmmoRegen[client] = false;
    g_bUnkillable[client] = false;
    SetEntProp(client, Prop_Data, "m_takedamage", 2, 1);
  }
  return Plugin_Continue;
}

public void RestartSpeedrun(int client) {
  float v[3];
  
  g_iSpeedrunStatus[client] = 2;
  for (int i = 0; i < 32; i++) {
    g_fZoneTimes[client][i] = 0.0;
  }
  g_iLastFrameInStartZone[client] = false;
  
  for (int i = 0; i < 3; i++) {
    ReSupply(client, g_iClientWeapons[client][i]);
  }
  
  int iMaxHealth = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, client);
  SetEntityHealth(client, iMaxHealth);
  TeleportEntity(client, g_fStartLoc, g_fStartAng, v);
}

public Action cmdSpeedrunForceReload(int client, int args) {
  if (!g_cvarSpeedrunEnabled.BoolValue) {
    return Plugin_Continue;
  }
  if (g_Database == null) {
    PrintToChat(client, "This feature is not supported without a database configuration");
    return Plugin_Handled;
  }
  ClearMapSpeedrunInfo();
  LoadMapSpeedrunInfo();
  
  return Plugin_Continue;
}

public Action cmdRemoveTime(int client, int args) {
  if (!g_cvarSpeedrunEnabled.BoolValue) {
    return Plugin_Continue;
  }
  if (g_Database == null) {
    PrintToChat(client, "This feature is not supported without a database configuration");
    return Plugin_Handled;
  }
  if (!client) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Cannot remove times from rcon");
    return Plugin_Handled;
  }
  if (IsClientObserver(client)) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Cannot clear time as spectator");
    return Plugin_Handled;
  }
  char query[1024];
  char steamid[32];
  DBResultSet results;
  
  GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
  int class = view_as<int>(TF2_GetPlayerClass(client));
  Format(query, sizeof(query), "DELETE FROM times WHERE MapName='%s' AND SteamID='%s' AND class='%d'", g_sCurrentMap, steamid, class);
  SQL_LockDatabase(g_Database);
  if ((results = SQL_Query(g_Database, query)) == null) {
    char err[256];
    SQL_GetError(results, err, sizeof(err));
    PrintToChat(client, "\x01[\x03JA\x01] An error occurred: %s", err);
  }
  SQL_UnlockDatabase(g_Database);
  char classString[128];
  GetClassName(view_as<TFClassType>(class), classString, sizeof(classString));
  PrintToChat(client, "\x01[\x03JA\x01] %s time cleared", classString);
  
  return Plugin_Continue;
}

public Action cmdClearTimes(int client, int args) {
  if (!g_cvarSpeedrunEnabled.BoolValue) {
    return Plugin_Continue;
  }
  if (g_Database == null) {
    PrintToChat(client, "This feature is not supported without a database configuration");
    return Plugin_Handled;
  }
  if (!client) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Cannot clear times from rcon");
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
  for (int i = 0; i < 32; i++) {
    if (g_fZoneTimes[i][g_iNumZones - 1] != 0.0) {
      for (int j = 0; j < 32; j++) {
        g_fZoneTimes[i][j] = 0.0;
      }
    }
  }
  PrintToChat(client, "\x01[\x03JA\x01] All times cleared");
  
  return Plugin_Continue;
}

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
  for (int i = 0; i < 32; i++) {
    g_fZoneBottom[i] = NULL_VECTOR;
    g_fZoneTop[i] = NULL_VECTOR;
  }
  g_iNumZones = 0;
  PrintToChat(client, "\x01[\x03JA\x01] All zones cleared");
  
  return Plugin_Continue;
}

public Action cmdShowZones(int client, int args) {
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
  
  PrintToChat(client, "\x01[\x03JA\x01] Showing %d zones for 5 seconds", g_iNumZones);
  for (int i = 0; i < g_iNumZones; i++) {
    ShowZone(client, i);
  }
  
  return Plugin_Continue;
}

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
  bool foundZone;
  for (int i = 0; i < g_iNumZones; i++) {
    if (IsInZone(client, i)) {
      ShowZone(client, i);
      if (i == 0) {
        ReplyToCommand(client, "\x01[\x03JA\x01] Showing \x05Start\x01 zone");
      }
      else if (i == g_iNumZones - 1) {
        ReplyToCommand(client, "\x01[\x03JA\x01] Showing \x05Finish\x01 zone");
      }
      else {
        ReplyToCommand(client, "\x01[\x03JA\x01] Showing checkpoint \x05%d\x01", i);
      }
      foundZone = true;
      break;
    }
  }
  if (!foundZone) {
    ReplyToCommand(client, "\x01[\x03JA\x01] You are not in a zone");
  }
  
  return Plugin_Continue;
}

void SpeedrunOnGameFrame() {
  for (int i = 0; i < 32; i++) {
    if (g_iSpeedrunStatus[i] == 1) {
      for (int j = 0; j < g_iNumZones; j++) {
        if (IsInZone(i, j) && g_fZoneTimes[i][j] == 0.0 && j != 0 && j == g_iNextCheckPoint[i]) {
          g_fZoneTimes[i][j] = GetEngineTime();
          if (j != g_iNumZones - 1) {
            char timeString[128];
            timeString = TimeFormat(g_fZoneTimes[i][j] - g_fZoneTimes[i][0]);
            PrintToChat(i, "\x01[\x03JA\x01] \x01\x04Checkpoint %d\x01: %s", j, timeString);
            g_iNextCheckPoint[i]++;
          }
          else {
            char timeString[128];
            timeString = TimeFormat(g_fZoneTimes[i][j] - g_fZoneTimes[i][0]);
            PrintToChat(i, "\x01[\x03JA\x01] Finished in %s", timeString);
            g_iSpeedrunStatus[i] = 2;
            g_iProcessingClass[i] = view_as<int>(TF2_GetPlayerClass(i));
            g_fProcessingZoneTimes[i] = g_fZoneTimes[i];
            processSpeedrun(i);
          }
          g_bSkippedCheckPointMessage[i] = false;
        }
        else if (!g_bSkippedCheckPointMessage[i] && j > g_iNextCheckPoint[i] && IsInZone(i, j)) {
          PrintToChat(i, "\x01[\x03JA\x01] You skipped \x01\x04Checkpoint %d\x01!", g_iNextCheckPoint[i]);
          g_bSkippedCheckPointMessage[i] = true;
        }
        if (!IsInZone(i, 0) && g_iLastFrameInStartZone[i]) {
          for (int h = 0; h < 32; h++) {
            g_fZoneTimes[i][h] = 0.0;
          }
          PrintToChat(i, "\x01[\x03JA\x01] Speedrun started");
          g_iNextCheckPoint[i] = 1;
          g_bSkippedCheckPointMessage[i] = false;
          g_fZoneTimes[i][0] = GetEngineTime();
        }
        if (IsInZone(i, 0)) {
          g_iLastFrameInStartZone[i] = true;
        }
        else {
          g_iLastFrameInStartZone[i] = false;
        }
      }
    }
    else if (g_iSpeedrunStatus[i] == 2) {
      if (IsInZone(i, 0)) {
        g_iSpeedrunStatus[i] = 1;
        PrintToChat(i, "\x01[\x03JA\x01] Entered start zone");
      }
    }
  }
}

void ClearMapSpeedrunInfo() {
  for (int i = 0; i < 32; i++) {
    g_fZoneBottom[i] = NULL_VECTOR;
    g_fZoneTop[i] = NULL_VECTOR;
    for (int j = 0; j < 32; j++) {
      g_fZoneTimes[i][j] = 0.0;
      g_fProcessingZoneTimes[i][j] = 0.0;
    }
    g_iProcessingClass[i] = 0;
    g_iLastFrameInStartZone[i] = false;
    g_iSpeedrunStatus[i] = 0;
    g_bWaitingForZoneSelection[i] = false;
    if (g_hWeaponBlockTimer[i] != null) {
      delete g_hWeaponBlockTimer[i];
      g_hWeaponBlockTimer[i] = null;
    }
  }
  for (int j = 0; j < 9; j++) {
    g_fRecordTime[j] = 99999999.99;
  }
  g_iNumZones = 0;
  g_fStartLoc = NULL_VECTOR;
  g_fStartAng = NULL_VECTOR;
}

void LoadMapSpeedrunInfo() {
  char query[1024] = "";
  
  ClearMapSpeedrunInfo();
  InitializeSpeedrunAssets(); // Initialize beam sprites
  
  Format(query, sizeof(query), "SELECT x, y, z, xang, yang, zang FROM startlocs WHERE MapName='%s'", g_sCurrentMap);
  g_Database.Query(SQL_OnMapStartLocationLoad, query, 0);
  Format(query, sizeof(query), "SELECT x1, y1, z1, x2, y2, z2 FROM zones WHERE MapName='%s' ORDER BY Number ASC", g_sCurrentMap);
  g_Database.Query(SQL_OnMapZonesLoad, query, 0);
}

public void SQL_OnMapZonesLoad(Database db, DBResultSet results, const char[] error, any data) {
  if (db == null) {
    LogError("OnMapZonesLoad() - Query failed! %s", error);
  }
  else if (results.RowCount) {
    int numRows = results.RowCount;
    g_iNumZones = 0;
    for (g_iNumZones = 0; g_iNumZones < numRows; g_iNumZones++) {
      results.FetchRow();
      
      // Read the two corner points from database
      float point1[3], point2[3];
      point1[0] = results.FetchFloat(0); // x1
      point1[1] = results.FetchFloat(1); // y1
      point1[2] = results.FetchFloat(2); // z1
      point2[0] = results.FetchFloat(3); // x2
      point2[1] = results.FetchFloat(4); // y2
      point2[2] = results.FetchFloat(5); // z2
      
      // Calculate mins and maxs for collision detection
      for (int i = 0; i < 3; i++) {
        g_fZoneBottom[g_iNumZones][i] = (point1[i] < point2[i]) ? point1[i] : point2[i];
        g_fZoneTop[g_iNumZones][i] = (point1[i] > point2[i]) ? point1[i] : point2[i];
      }
    }
    char query[1024] = "";
    for (int i = 0; i < 9; i++) {
      Format(query, sizeof(query), "SELECT c%d FROM times WHERE MapName='%s' AND class='%d' ORDER BY c%d ASC LIMIT 1", g_iNumZones - 1, g_sCurrentMap, i, g_iNumZones - 1);
      g_Database.Query(SQL_OnRecordLoad, query, i);
    }
  }
}

public void SQL_OnRecordLoad(Database db, DBResultSet results, const char[] error, any data) {
  int class = data;
  
  if (db == null) {
    LogError("OnRecordLoad() - Query failed! %s", error);
  }
  else if (results.RowCount) {
    results.FetchRow();
    float t = results.FetchFloat(0);
    if (t != 0.0) {
      g_fRecordTime[class] = t;
    }
  }
}

public void SQL_OnMapStartLocationLoad(Database db, DBResultSet results, const char[] error, any data) {
  if (db == null) {
    LogError("OnMapStartLocationLoad() - Query failed! %s", error);
  }
  else if (results.RowCount) {
    results.FetchRow();
    for (int i = 0; i < 3; i++) {
      g_fStartLoc[i] = results.FetchFloat(i);
      g_fStartAng[i] = results.FetchFloat(i + 3);
    }
  }
}

public Action cmdSetStart(int client, int args) {
  if (!g_cvarSpeedrunEnabled.BoolValue) {
    return Plugin_Continue;
  }
  if (g_Database == null) {
    PrintToChat(client, "This feature is not supported without a database configuration");
    return Plugin_Handled;
  }
  if (!client) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Cannot select start from rcon");
    return Plugin_Handled;
  }
  if (IsClientObserver(client)) {
    ReplyToCommand(client, "\x01[\x03JA\x01] Cannot select start as spectator");
    return Plugin_Handled;
  }
  float a[3];
  float l[3];
  char query[1024];
  
  GetEntPropVector(client, Prop_Data, "m_vecOrigin", l);
  GetClientEyeAngles(client, a);
  g_fStartLoc = l;
  g_fStartAng = a;
  g_fLoc = l;
  g_fAng = a;
  Format(query, sizeof(query), "SELECT * FROM startlocs WHERE MapName='%s'", g_sCurrentMap);
  g_Database.Query(SQL_OnStartLocationCheck, query, client);
  
  return Plugin_Continue;
}

public void SQL_OnStartLocationCheck(Database db, DBResultSet results, const char[] error, any data) {
  int client = data;
  char query[1024];
  
  if (db == null) {
    LogError("OnStartLocationCheck() - Query failed! %s", error);
  }
  else if (results.RowCount) {
    Format(query, sizeof(query), "UPDATE startlocs SET x='%f', y='%f', z='%f', xang='%f', yang='%f', zang='%f' WHERE MapName='%s'", g_fLoc[0], g_fLoc[1], g_fLoc[2], g_fAng[0], g_fAng[1], g_fAng[2], g_sCurrentMap);
    g_Database.Query(SQL_OnStartLocationSet, query, client);
  }
  else {
    Format(query, sizeof(query), "INSERT INTO startlocs VALUES(null,'%s', '%f','%f','%f','%f','%f','%f');", g_sCurrentMap, g_fLoc[0], g_fLoc[1], g_fLoc[2], g_fAng[0], g_fAng[1], g_fAng[2]);
    g_Database.Query(SQL_OnStartLocationSet, query, client);
  }
}

public void SQL_OnStartLocationSet(Database db, DBResultSet results, const char[] error, any data) {
  int client = data;
  
  if (db == null) {
    LogError("OnStartLocationSet() - Query failed! %s", error);
  }
  else if (!error[0]) {
    PrintToChat(client, "\x01[\x03JA\x01] Start location successfully set");
  }
  else {
    PrintToServer(error);
    PrintToChat(client, "\x01[\x03JA\x01] Start location failed to set");
    g_fLoc = NULL_VECTOR;
    g_fAng = NULL_VECTOR;
  }
}

void GetFullMapName(char[] inputMapName, char[] output, int outputLen) {
  char baseJump[6] = "jump_";
  char toReturn[6];

  strcopy(toReturn, 6, inputMapName);
  if (StrEqual(toReturn, baseJump, false)) {
    Format(output, outputLen, "%s", inputMapName);
  }
  else {
    Format(output, outputLen, "jump_%s", inputMapName);
  }
}

void UpdateSteamID(int client) {
  char query[1024];
  char steamid[32];
  
  GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
  Format(query, sizeof(query), "SELECT * FROM steamids WHERE SteamID='%s'", steamid);
  g_Database.Query(SQL_OnSteamIDCheck, query, client);
}

public void SQL_OnSteamIDCheck(Database db, DBResultSet results, const char[] error, any data) {
  int client = data;
  char query[1024];
  
  if (db == null) {
    LogError("OnSpeedrunSubmit() - Query failed! %s", error);
  }
  else if (results.RowCount) {
    char name[64], steamid[32], nameEscaped[128];
    
    GetClientName(client, name, sizeof(name));
    GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
    g_Database.Escape(name, nameEscaped, sizeof(nameEscaped));
    Format(query, sizeof(query), "UPDATE steamids SET name='%s' WHERE SteamID='%s'", nameEscaped, steamid);
    g_Database.Query(SQL_OnSteamIDUpdate, query, client);
  }
  else {
    char name[64];
    char steamid[32];
    char nameEscaped[128];
    
    GetClientName(client, name, sizeof(name));
    GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
    g_Database.Escape(name, nameEscaped, sizeof(nameEscaped));
    Format(query, sizeof(query), "INSERT INTO steamids VALUES(null,'%s', '%s');", steamid, nameEscaped);
    g_Database.Query(SQL_OnSteamIDUpdate, query, client);
  }
}

public void SQL_OnSteamIDUpdate(Database db, DBResultSet results, const char[] error, any data) {
  if (db == null) {
    LogError("OnSteamIDUpdate() - Query failed! %s", error);
  }
}

bool IsSpeedrunMap() {
  return (g_fZoneBottom[0][0] != 0.0 && g_fZoneBottom[1][0] != 0.0 && g_fStartLoc[0] != 0.0);
}

bool IsInZone(int client, int zone) {
  return IsInRegion(client, g_fZoneBottom[zone], g_fZoneTop[zone]);
}

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

void ShowZone(int client, int zone) {
  if (g_iBeamSprite <= 0 || g_iHaloSprite <= 0) {
    PrintToChat(client, "\x01[\x03JA\x01] Beam sprites not loaded");
    return;
  }
  
  Effect_DrawBeamBoxToClient(client, g_fZoneBottom[zone], g_fZoneTop[zone], g_iBeamSprite, g_iHaloSprite, 0, 30);
}

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