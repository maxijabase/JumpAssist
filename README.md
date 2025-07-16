# JumpAssist
JumpAssist is a plugin designed to provide various utilities for Team Fortress 2 Jump servers.
This is a fork of JoinedSenses' TF2-ECJ-JumpAssist, which itself is a fork of arispoloway's JumpAssist.
In this version, I restored speedrunning functionalities, fixed some bugs and streamlined syntax and code style. The idea is to keep updating this version and updating functionality to meet today's requirements.

## Requirements
To run JumpAssist in your server, you will need to install the following dependencies beforehand:
- (Required) AreaSelector (https://github.com/maxijabase/sm-areaselector)
- (Optional) SaveLoc (https://github.com/JoinedSenses/SM-SaveLoc)

## Build Requirements:
https://github.com/JoinedSenses/SM-JSLib  
https://github.com/JoinedSenses/SM-SaveLoc  
https://github.com/JoinedSenses/SourceMod-IncludeLibrary/blob/master/include/color_literals.inc

## Commands

### Public (User) Commands

| Command(s)                | Functionality                                                                                  | Category         |
|---------------------------|-----------------------------------------------------------------------------------------------|------------------|
| `ja_help`                 | Shows JumpAssist's commands/help menu.                                                        | General/Help     |
| `sm_jumptf`               | Shows the jump.tf website.                                                                    | General/Help     |
| `sm_forums`               | Shows the jump.tf forums.                                                                     | General/Help     |
| `sm_jumpassist`           | Shows the forum page for JumpAssist.                                                          | General/Help     |
| `sm_s`, `sm_save`         | Saves your current position.                                                                  | Save/Teleport    |
| `sm_t`, `sm_tele`         | Teleports you to your current saved location.                                                 | Save/Teleport    |
| `sm_r`, `sm_reset`        | Sends you back to the beginning without deleting your save.                                   | Save/Teleport    |
| `sm_restart`              | Deletes your save and sends you back to the beginning.                                        | Save/Teleport    |
| `sm_undo`                 | Restores your last saved position.                                                            | Save/Teleport    |
| `sm_regen`, `sm_ammo`     | Regenerates weapon ammunition.                                                                | Misc             |
| `sm_superman`             | Makes you strong like superman.                                                               | Misc             |
| `sm_hardcore`             | Enables hardcore mode (No regen, no saves).                                                   | Misc             |
| `sm_hidemessage`          | Toggles display of JumpAssist messages (e.g., save/teleport notifications).                   | Misc             |
| `sm_explosions`           | Toggles displaying explosions.                                                                | Misc             |
| `sm_hide`                 | Show/Hide other players.                                                                      | Visual           |
| `sm_preview`              | Enables noclip, allowing preview of a map.                                                    | Visual           |
| `sm_skeys`                | Toggle showing a client's keys (HUD).                                                         | SKeys HUD        |
| `sm_skeyscolor`, `sm_skeyscolors` | Changes the color of the text for SKeys.                                             | SKeys HUD        |
| `sm_skeyspos`, `sm_skeysloc`     | Changes the location of the text for SKeys.                                           | SKeys HUD        |
| `sm_spec`                 | Spectate a player.                                                                            | Spectator        |
| `sm_spec_ex`, `sm_speclock` | Spectate a player, even through their death.                                               | Spectator        |
| `sm_race`                 | Initializes a new race.                                                                       | Race             |
| `sm_leaverace`, `sm_r_leave` | Leave the current race.                                                                   | Race             |
| `sm_specrace`             | Spectate a race.                                                                              | Race             |
| `sm_racelist`             | Display race list.                                                                            | Race             |
| `sm_raceinfo`             | Display information about the race you are in.                                                | Race             |
| `sm_showzones`            | Shows all zones of the map.                                                                   | Speedrun         |
| `sm_rmtime`               | Removes your time on the map.                                                                 | Speedrun         |
| `sm_showzone`, `sm_sz`    | Shows the current zone and says what zone it is.                                              | Speedrun         |
| `sm_speedrun`, `sm_sr`    | Enables/disables speedrunning.                                                                | Speedrun         |
| `sm_stopspeedrun`         | Disables speedrunning.                                                                        | Speedrun         |
| `sm_pr`                   | Shows your personal record.                                                                   | Speedrun         |
| `sm_wr`, `sm_top`         | Shows the map record.                                                                         | Speedrun         |
| `sm_pi`                   | Shows the player's runs.                                                                      | Speedrun         |

### Admin Commands

| Command(s)                | Functionality                                                                                  | Category         |
|---------------------------|-----------------------------------------------------------------------------------------------|------------------|
| `sm_bring`                | Bring a client or group to your position.                                                     | Teleport/Admin   |
| `sm_goto`                 | Go to a client's position.                                                                    | Teleport/Admin   |
| `sm_send`                 | Send target to another target.                                                                | Teleport/Admin   |
| `sm_fspec`                | Force a player to spectate another player.                                                    | Spectator/Admin  |
| `sm_serverrace`           | Invite everyone to a server-wide race.                                                        | Race/Admin       |
| `sm_setstart`             | Sets the map start location for speedrunning.                                                 | Speedrun/Admin   |
| `sm_addzone`              | Adds a checkpoint or end zone for speedrunning.                                               | Speedrun/Admin   |
| `sm_clearzones`           | Deletes all zones on the current map.                                                         | Speedrun/Admin   |
| `sm_cleartimes`           | Deletes all times on the current map.                                                         | Speedrun/Admin   |
| `sm_sr_force_reload`      | Forces reload of speedrun data/times.                                                         | Speedrun/Admin   |
| `sm_mapset`               | Change map settings (team/class/lockcps).                                                     | Admin            |

**Notes:**
- All commands prefixed with `sm_` can typically be used with or without the `!` (ex: `!save` or `/save`).
- Admin commands require appropriate SourceMod admin flags (e.g., `ADMFLAG_GENERIC`, `ADMFLAG_ROOT`, etc.).
- Some commands have aliases (e.g., `sm_save`/`sm_s`, `sm_tele`/`sm_t`, etc.).
- Some commands are only available if the relevant features (like speedrun or database) are enabled.
