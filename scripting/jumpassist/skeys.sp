#define XPOS 0
#define YPOS 1
#define XPOSDEFAULT 0.54
#define YPOSDEFAULT 0.4
#define ALLKEYS 3615
#define DEFAULTSKEYSCOLOR {255, 255, 255}

#define DISPLAY 0
#define EDIT 1

#define RED 0
#define GREEN 1
#define BLUE 2

Handle
g_hHudDisplayForward, 
g_hHudDisplayASD, 
g_hHudDisplayJump, 
g_hHudDisplayAttack;
bool
g_bSKeysEnabled[MAXPLAYERS + 1];
int
g_iButtons[MAXPLAYERS + 1], 
g_iSKeysColor[MAXPLAYERS + 1][3], 
g_iSKeysMode[MAXPLAYERS + 1];
float
g_fSKeysPos[MAXPLAYERS + 1][2];

/* ======================================================================
   ------------------------------- Commands
*/

public Action cmdGetClientKeys(int client, int args) {
  g_bSKeysEnabled[client] = !g_bSKeysEnabled[client];
  PrintJAMessage(client, "HUD keys are"...cTheme2..." %s\x01.", g_bSKeysEnabled[client] ? "enabled":"disabled");
  return Plugin_Handled;
}

public Action cmdChangeSkeysColor(int client, int args) {
  if (client == 0) {
    return Plugin_Handled;
  }
  
  if (args < 3) {
    PrintJAMessage(client, cTheme2..."Usage\x01: sm_skeys_color <R> <G> <B>");
    return Plugin_Handled;
  }
  
  char red[4];
  GetCmdArg(1, red, sizeof(red));
  
  char green[4];
  GetCmdArg(2, green, sizeof(green));
  
  char blue[4];
  GetCmdArg(3, blue, sizeof(blue));
  
  if (!IsStringNumeric(red) || !IsStringNumeric(blue) || !IsStringNumeric(green)) {
    PrintJAMessage(client, "Invalid numeric value");
    return Plugin_Handled;
  }
  
  SaveKeyColor(client, red, green, blue);
  return Plugin_Handled;
}

public Action cmdChangeSkeysLoc(int client, int args) {
  if (client == 0) {
    return Plugin_Handled;
  }
  
  if (IsClientObserver(client)) {
    PrintJAMessage(client, "Cannot use this feature while in spectate");
    return Plugin_Handled;
  }
  
  g_bSKeysEnabled[client] = true;
  
  switch (g_iSKeysMode[client]) {
    case EDIT: {
      g_iSKeysMode[client] = DISPLAY;
      SetEntityFlags(client, GetEntityFlags(client) & ~(FL_ATCONTROLS | FL_FROZEN));
    }
    case DISPLAY: {
      g_iSKeysMode[client] = EDIT;
      SetEntityFlags(client, GetEntityFlags(client) | FL_ATCONTROLS | FL_FROZEN);
      
      #define TAG "["...cTheme1..."SKEYS\x01]"
      
      PrintColoredChat(
        client, 
        TAG..." Update position using"...cTheme2..." mouse movement\x01.\n"...
        TAG..." Save with"...cTheme2..." attack\x01.\n"...
        TAG..." Reset with"...cTheme2..." jump\x01."
        );
      
      #undef TAG
    }
  }
  return Plugin_Handled;
}

/* ======================================================================
   ---------------------------- Internal Functions 
*/

void SetAllSkeysDefaults() {
  for (int i = 1; i <= MaxClients; ++i) {
    SetSkeysDefaults(i);
  }
}

void SetSkeysDefaults(int client) {
  g_fSKeysPos[client][XPOS] = XPOSDEFAULT;
  g_fSKeysPos[client][YPOS] = YPOSDEFAULT;
  g_iSKeysColor[client] = DEFAULTSKEYSCOLOR;
}

int IsStringNumeric(const char[] MyString) {
  int n = 0;
  while (MyString[n] != '\0') {
    if (!IsCharNumeric(MyString[n])) {
      return false;
    }
    ++n;
  }
  
  return true;
} 