float g_fStartLoc[3];
float g_fStartAng[3];
float g_fLoc[3];
float g_fAng[3];
float g_fZoneTimes[32][32];
float g_fRecordTime[9];
float g_fProcessingZoneTimes[32][32];

int g_iNextCheckPoint[32];
int g_iProcessingClass[32];
int g_iLastFrameInStartZone[32];

bool g_bSkippedCheckPointMessage[32];

enum {
  LISTING_RANKED, 
  LISTING_GENERAL, 
  LISTING_PLAYER
}

#include "zones.sp"

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

void SpeedrunOnGameFrame() {
  if (g_iStartZoneIndex == -1 || g_iEndZoneIndex == -1) {
    return; // Need both start and end zones
  }
  
  for (int i = 0; i < 32; i++) {
    if (g_iSpeedrunStatus[i] == 1) {
      // Check all zones
      for (int j = 0; j < g_iNumZones; j++) {
        if (g_iZoneTypes[j] == -1) continue; // Skip invalid zones
        
        if (IsInZone(i, j) && g_fZoneTimes[i][j] == 0.0) {
          ZoneType zoneType = view_as<ZoneType>(g_iZoneTypes[j]);
          
          switch (zoneType) {
            case ZONE_START: {
              // Handle start zone logic (this might be handled elsewhere)
            }
            case ZONE_CHECKPOINT: {
              if (j == g_iNextCheckPoint[i]) {
                g_fZoneTimes[i][j] = GetEngineTime();
                char timeString[128];
                timeString = TimeFormat(g_fZoneTimes[i][j] - g_fZoneTimes[i][g_iStartZoneIndex]);
                PrintToChat(i, "\x01[\x03JA\x01] \x04Checkpoint %d\x01: %s", GetCheckpointNumber(j), timeString);
                g_iNextCheckPoint[i] = GetNextCheckpoint(j);
                g_bSkippedCheckPointMessage[i] = false;
              }
            }
            case ZONE_END: {
              if (j == g_iEndZoneIndex) {
                g_fZoneTimes[i][j] = GetEngineTime();
                char timeString[128];
                timeString = TimeFormat(g_fZoneTimes[i][j] - g_fZoneTimes[i][g_iStartZoneIndex]);
                PrintToChat(i, "\x01[\x03JA\x01] Finished in %s", timeString);
                g_iSpeedrunStatus[i] = 2;
                g_iProcessingClass[i] = view_as<int>(TF2_GetPlayerClass(i));
                g_fProcessingZoneTimes[i] = g_fZoneTimes[i];
                processSpeedrun(i);
              }
            }
          }
        }
      }
      
      // Handle start zone exit (start timing)
      if (!IsInZone(i, g_iStartZoneIndex) && g_iLastFrameInStartZone[i]) {
        for (int h = 0; h < 32; h++) {
          g_fZoneTimes[i][h] = 0.0;
        }
        PrintToChat(i, "\x01[\x03JA\x01] Speedrun started");
        g_iNextCheckPoint[i] = GetFirstCheckpoint();
        g_bSkippedCheckPointMessage[i] = false;
        g_fZoneTimes[i][g_iStartZoneIndex] = GetEngineTime();
      }
      
      g_iLastFrameInStartZone[i] = IsInZone(i, g_iStartZoneIndex);
    }
    else if (g_iSpeedrunStatus[i] == 2) {
      if (IsInZone(i, g_iStartZoneIndex)) {
        g_iSpeedrunStatus[i] = 1;
        PrintToChat(i, "\x01[\x03JA\x01] Entered start zone");
      }
    }
  }
}

// Updated ClearMapSpeedrunInfo function - now calls zone clearing from zones.sp
void ClearMapSpeedrunInfo() {
  ClearMapZoneInfo(); // This function is now in zones.sp
  
  for (int i = 0; i < 32; i++) {
    for (int j = 0; j < 32; j++) {
      g_fZoneTimes[i][j] = 0.0;
      g_fProcessingZoneTimes[i][j] = 0.0;
    }
    g_iProcessingClass[i] = 0;
    g_iLastFrameInStartZone[i] = false;
    g_iSpeedrunStatus[i] = 0;
  }
  for (int j = 0; j < 9; j++) {
    g_fRecordTime[j] = 99999999.99;
  }
  g_fStartLoc = NULL_VECTOR;
  g_fStartAng = NULL_VECTOR;
}

// Updated LoadMapSpeedrunInfo function - now calls zone loading from zones.sp
void LoadMapSpeedrunInfo() {
  char query[1024] = "";
  
  ClearMapSpeedrunInfo();
  InitializeSpeedrunAssets(); // This function is now in zones.sp
  
  Format(query, sizeof(query), "SELECT x, y, z, xang, yang, zang FROM startlocs WHERE MapName='%s'", g_sCurrentMap);
  g_Database.Query(SQL_OnMapStartLocationLoad, query, 0);
  
  LoadMapZones(); // This function is now in zones.sp
}

// Updated SQL_OnRecordLoad function to work with zones.sp
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