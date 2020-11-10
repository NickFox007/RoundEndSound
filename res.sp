#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <csgo_colors>
#include <multicolors>
#include <clientprefs>
#include <emitsoundany>
#include <soundlib>
#include <res>

#pragma newdecls required

enum
{
	uniq = 0,
	name,
	music,
	not_played,
	hidden
};

ArrayList g_hPlaylists[5], g_hNotPlayed[MAXPLAYERS + 1], g_hVisible[MAXPLAYERS + 1];
Handle g_hDisableCookie, g_hVolumeCookie, g_hPlaylistCookie, g_hDPrint;
char g_sPlaylists[512], g_sHiddenPlaylists[512], g_sPrefix[32];
bool g_bPrint, g_bStopMapMusic, g_bOwnPlaylist, g_bRandom, g_bRepeat, g_bDisabled[MAXPLAYERS + 1], g_bDPrint[MAXPLAYERS + 1], g_bCount;
int g_iSoundEnts[2048], g_iNumSounds, g_iVolume[MAXPLAYERS + 1], g_iPlaylist[MAXPLAYERS + 1], g_iDefVolume;
bool g_bCSGO, g_bHidden;

public Plugin myinfo = 
{
	name = "Round End Sound",
	author = "d4Ck & NF",
	version = "1.2.3.1",
	url = "https://vk.com/nf_dev/"
};

public void OnPluginStart()
{	
	g_bCSGO = (GetEngineVersion() == Engine_CSGO);
	
	char sPatch[256];
	BuildPath(Path_SM, sPatch, sizeof(sPatch), "configs/res/settings.ini"); 
	KeyValues hKV = CreateKeyValues("Settings");
	
	if(!hKV)
 		SetFailState("[RES] Failed to allocate memory to read config.");

	if(!FileToKeyValues(hKV, sPatch))
		SetFailState("[RES] Configuration file was not found.");
	
	g_bPrint = !!KvGetNum(hKV, "display", 1);
	g_bStopMapMusic = !!KvGetNum(hKV, "stop_map_music", 1);
	g_bOwnPlaylist = !!KvGetNum(hKV, "own_playlist", 0);
	g_bRandom = !!KvGetNum(hKV, "random", 1);
	g_bRepeat = !!KvGetNum(hKV, "repeat", 0);
	g_iDefVolume = KvGetNum(hKV, "def_volume", 0);
	g_bCount = !!KvGetNum(hKV, "show_count", 1);
	if(g_iDefVolume > 9 || g_iDefVolume < 0) g_iDefVolume = 0;
	
	KvGetString(hKV, "playlists", g_sPlaylists, sizeof(g_sPlaylists), "rus;en");
	KvGetString(hKV, "hidden_playlists", g_sHiddenPlaylists, sizeof(g_sHiddenPlaylists));
	KvGetString(hKV, "prefix", g_sPrefix, sizeof(g_sPrefix), "{green}[RES]{default}");

	CloseHandle(hKV);
	
	g_hPlaylists[uniq] = new ArrayList(ByteCountToCells(32));
	g_hPlaylists[name] = new ArrayList(ByteCountToCells(128));
	g_hPlaylists[music] = new ArrayList();
	g_hPlaylists[not_played] = new ArrayList();
	g_hPlaylists[hidden] = new ArrayList(ByteCountToCells(32));
	
	g_hDisableCookie = RegClientCookie("res_disable", NULL_STRING, CookieAccess_Private);
	g_hDPrint = RegClientCookie("res_disable_print", NULL_STRING, CookieAccess_Private);
	g_hVolumeCookie = RegClientCookie("res_volume", NULL_STRING, CookieAccess_Private);
	g_hPlaylistCookie = RegClientCookie("res_playlist", NULL_STRING, CookieAccess_Private);
	
	HookEvent("round_start", OnRoundStart, EventHookMode_PostNoCopy);
	if(g_bCSGO) HookEvent("round_end", OnRoundEnd, EventHookMode_Pre);
	
	RegConsoleCmd("sm_res", MainMenuCmd);
	
	char sBuff[32];
	
	ParseStrig(g_sPlaylists, false);
	
	if(!GetArraySize(g_hPlaylists[music]))
		SetFailState("[RES] Failed to load playlists.");
	
	ParseStrig(g_sHiddenPlaylists, true);
	
	GetArrayString(g_hPlaylists[uniq], 0, sBuff, sizeof(sBuff));
	
	int iid = FindStringInArray(g_hPlaylists[hidden], sBuff);
	if(iid != -1) RemoveFromArray(g_hPlaylists[hidden], iid);
	
	g_bHidden = (GetArraySize(g_hPlaylists[hidden]) > 0);
	
	LoadTranslations("res.phrases");
}

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int iErr_max) 
{
	CreateNative("RES_GetPlaylistStatus", Native_GetPlaylistStatus);  
	CreateNative("RES_GetPlaylistStatusForClient", Native_GetPlaylistStatusForClient);
	CreateNative("RES_SetPlaylistStatus", Native_SetPlaylistStatus);  
	CreateNative("RES_GetPlaylistName", Native_GetPlaylistName);  
	
	RegPluginLibrary("res");
	
	return APLRes_Success;
}

public int Native_GetPlaylistStatus(Handle hPlugin, int iNumParams)
{
	char sBuff[32];
	GetNativeString(1, sBuff, sizeof(sBuff));
	if(FindStringInArray(g_hPlaylists[uniq], sBuff) == -1) return 2;
	if(FindStringInArray(g_hPlaylists[hidden], sBuff) == -1) return 1;
	return 0;
}

public int Native_GetPlaylistStatusForClient(Handle hPlugin, int iNumParams)
{
	char sBuff[32];
	int client = GetNativeCell(1);
	
	if(client && IsClientInGame(client) && !IsFakeClient(client))
	{
		GetNativeString(2, sBuff, sizeof(sBuff));
		if(FindStringInArray(g_hPlaylists[uniq], sBuff) == -1) return 2;
		if(FindStringInArray(g_hPlaylists[hidden], sBuff) == -1 || FindStringInArray(g_hVisible[client], sBuff) != -1) return 1;
		return 0;
	}
	
	return -1;
}

public int Native_SetPlaylistStatus(Handle hPlugin, int iNumParams)
{
	char sBuff[32];
	int client = GetNativeCell(1);
	
	if(client && IsClientInGame(client) && !IsFakeClient(client))
	{
		GetNativeString(2, sBuff, sizeof(sBuff));
		
		int pid = FindStringInArray(g_hPlaylists[uniq], sBuff);
		
		if(pid == -1) return 2;
		
		if(FindStringInArray(g_hPlaylists[hidden], sBuff) == -1) return 1;
		
		bool bStatus = GetNativeCell(3);
		
		if(bStatus && FindStringInArray(g_hVisible[client], sBuff) == -1)
		{
			char sCookie[32];
			PushArrayString(g_hVisible[client], sBuff);
			GetClientCookie(client, g_hPlaylistCookie, sCookie, sizeof(sCookie));
			if(strcmp(sCookie, sBuff) == 0)
			{
				g_iPlaylist[client] = pid;
				if(g_bOwnPlaylist) LoadPlaylist(g_hNotPlayed[client], pid);
			}
		}
		else if(!bStatus && FindStringInArray(g_hVisible[client], sBuff) != -1)
		{
			RemoveFromArray(g_hVisible[client], FindStringInArray(g_hVisible[client], sBuff));
			
			if(FindStringInArray(g_hPlaylists[uniq], sBuff) == g_iPlaylist[client])
			{
				GetArrayString(g_hPlaylists[uniq], 0, sBuff, sizeof(sBuff));
				g_iPlaylist[client] = 0;
				if(g_bOwnPlaylist) LoadPlaylist(g_hNotPlayed[client], 0);
			}
		}
			
		return bStatus;
	}
	
	return -1;
}

public int Native_GetPlaylistName(Handle hPlugin, int iNumParams)
{	
	char sBuff[32];
	char sName[128];
	GetNativeString(1, sBuff, sizeof(sBuff));
	GetArrayString(g_hPlaylists[name], FindStringInArray(g_hPlaylists[uniq], sBuff), sName, sizeof(sName));
	SetNativeString(2, sName, GetNativeCell(3));
}

public void OnMapStart()
{
	char sFile[256];
	ArrayList hArray;
	int size, size2 = GetArraySize(g_hPlaylists[music]);
	for(int i; i < size2; ++i)
	{
		hArray = GetArrayCell(g_hPlaylists[music], i);
		size = GetArraySize(hArray);
		for(int b; b < size; ++b)
		{
			GetArrayString(hArray, b, sFile, sizeof(sFile));
			PrecacheSoundAny(sFile);
			Format(sFile, sizeof(sFile), "sound/%s", sFile);
			AddFileToDownloadsTable(sFile);
		}
	}
}

void ParseStrig(char[] sBuff, bool bHidden)
{
	int pos, pos2;
	char sBuf[32];
	
	TrimString(sBuff);
	
	while(sBuff[pos])
	{		
		if (sBuff[pos] == ';')
		{
			if(sBuf[0])
			{
				if(!bHidden) ReadPlaylist(sBuf);
				else ReadHiddenPlaylist(sBuf);
				
				if(!sBuff[pos+1]) break;
				
				while(pos2 > 0)
				{
					sBuf[pos2] = 0;
					--pos2;
				}
				++pos;
			}
		}
		
		if(sBuff[pos] == ' ') 
		{
			++pos;
			continue;
		}
		
		sBuf[pos2] = sBuff[pos];
		
		++pos2;
		++pos;
		
		if(!sBuff[pos]) 
		{
			if(!bHidden) ReadPlaylist(sBuf);
			else ReadHiddenPlaylist(sBuf);
			
			break;
		}
	}
}

void ReadPlaylist(char[] sBuff)
{
	char sFile[256], sName[128];
	
	BuildPath(Path_SM, sFile, sizeof(sFile), "configs/res/%s.ini", sBuff); 

	Handle hFile = OpenFile(sFile, "r");
	
	if(!hFile) 
		ThrowError("[RES] The file '%s.ini' was not found, but specified in the config.", sBuff);
	
	if(!ReadFileLine(hFile, sName, sizeof(sName))) 
	{
		CloseHandle(hFile);
		ThrowError("[RES] The file '%s.ini' is empty.", sBuff);
	}
	
	ArrayList hArray = new ArrayList(ByteCountToCells(256));
	
	while(!IsEndOfFile(hFile)) 
	{
		ReadFileLine(hFile, sFile, sizeof(sFile));
		TrimString(sFile);
		if(!sFile[0]) continue;
		
		if(strcmp(sFile[strlen(sFile)-3], "mp3") == 0)
		{
			PushArrayString(hArray, sFile);
			PrecacheSoundAny(sFile);
			Format(sFile, sizeof(sFile), "sound/%s", sFile);
			AddFileToDownloadsTable(sFile);
		}
		else LoadDir(sFile, hArray);
	}
	
	CloseHandle(hFile);
	
	if(GetArraySize(hArray))
	{
		int iid = PushArrayString(g_hPlaylists[uniq], sBuff);
		
		TrimString(sName);
		PushArrayString(g_hPlaylists[name], sName);
		PushArrayCell(g_hPlaylists[music], hArray);
		
		if(!g_bOwnPlaylist) 
		{
			ArrayList hRandomArray = new ArrayList(ByteCountToCells(256));
			LoadPlaylist(hRandomArray, iid);
			PushArrayCell(g_hPlaylists[not_played], hRandomArray);
		}
	}
	else CloseHandle(hArray);
}

void ReadHiddenPlaylist(char[] sBuff)
{
	if(FindStringInArray(g_hPlaylists[uniq], sBuff) != -1)
		PushArrayString(g_hPlaylists[hidden], sBuff);
}

public void LoadDir(const char[] sDir, ArrayList hArray)
{
	char sFull[256], sBuff[256], sBuff2[256];

	FormatEx(sFull, sizeof(sFull), "sound/%s", sDir);
	DirectoryListing hDir = OpenDirectory(sFull);
	if(hDir)
	{
		FileType type;
		
		while(hDir.GetNext(sBuff, sizeof(sBuff), type))
		{
			if(type == FileType_File)
			{
				if(strcmp(sBuff[strlen(sBuff)-3], "mp3") == 0)
				{
					FormatEx(sBuff2, sizeof(sBuff2), "%s%s", sFull, sBuff);
					AddFileToDownloadsTable(sBuff2);
					PushArrayString(hArray, sBuff2[6]);
					PrecacheSoundAny(sBuff2[6]);
				}
			}
			else if(type == FileType_Directory && strcmp(sBuff, ".") && strcmp(sBuff, ".."))
			{
				FormatEx(sBuff2, sizeof(sBuff2), "%s%s/", sDir, sBuff);
				LoadDir(sBuff2, hArray);
			}
		}
		
		CloseHandle(hDir);
	}
	else ThrowError("[RES] Failed to open '%s'.", sDir);
}

public Action MainMenuCmd(int client, int args) 
{ 	
	if(client) OpenMainMenu(client);
	
	return Plugin_Handled; 
}

public void OpenMainMenu(int client)
{
	char sBuff[256];
	Menu menu = new Menu(MainMenuCallback);
	
	SetMenuTitle(menu, "%T\n%T %i%%\n \n", "menu_title", client, "menu_volume", client, 100 - (g_iVolume[client]*10));
	
	FormatEx(sBuff, sizeof(sBuff), "%T [+10%]", "menu_increase", client);
	AddMenuItem(menu, "+", sBuff, g_iVolume[client] > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	FormatEx(sBuff, sizeof(sBuff), "%T [-10%]", "menu_decrease", client);
	AddMenuItem(menu, "-", sBuff, g_iVolume[client] < 9 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	
	FormatEx(sBuff, sizeof(sBuff), "%T [%s]", "menu_status", client, g_bDisabled[client] ? "✘" : "✔");
	AddMenuItem(menu, "r", sBuff);
	
	if(g_bPrint)
	{
		FormatEx(sBuff, sizeof(sBuff), "%T [%s]", "menu_print", client, g_bDPrint[client] ? "✘" : "✔");
		AddMenuItem(menu, "p", sBuff);
	}
	
	int size = GetArraySize(g_hPlaylists[music]);
	if(g_bHidden) size -= GetArraySize(g_hPlaylists[hidden]) - GetArraySize(g_hVisible[client]);
	if(size > 1)
	{
		if(g_bCount) FormatEx(sBuff, sizeof(sBuff), "%T (%i)", "menu_choose", client, size);
		else FormatEx(sBuff, sizeof(sBuff), "%T", "menu_choose", client);
		AddMenuItem(menu, NULL_STRING, sBuff);
	}
	
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MainMenuCallback(Menu hMenu, MenuAction action, int client, int param2)
{
	switch(action)
	{
		case MenuAction_Select:
		{             
			char sItem[2];
			GetMenuItem(hMenu, param2, sItem, sizeof(sItem)); 
			
			bool bPlus;
			if((bPlus = (sItem[0] == '+')) || sItem[0] == '-')
			{
				if(bPlus) --g_iVolume[client];
				else ++g_iVolume[client];
				
				IntToString(g_iVolume[client], sItem, sizeof(sItem));
				SetClientCookie(client, g_hVolumeCookie, sItem);
				OpenMainMenu(client);
				CCPrintToChat(client, "%s {default}%t", g_sPrefix, bPlus ? "chat_increase" : "chat_decrease", 100 - (g_iVolume[client]*10));
			}
			else if(strcmp(sItem, "r") == 0)
			{
				g_bDisabled[client] = !g_bDisabled[client];
				IntToString(view_as<int>(g_bDisabled[client]), sItem, sizeof(sItem));
				SetClientCookie(client, g_hDisableCookie, sItem);
				OpenMainMenu(client);
				CCPrintToChat(client, "%s {default}%t", g_sPrefix, g_bDisabled[client] ? "chat_status_off" : "chat_status_on");
			}
			else if(strcmp(sItem, "p") == 0)
			{
				g_bDPrint[client] = !g_bDPrint[client];
				IntToString(view_as<int>(g_bDPrint[client]), sItem, sizeof(sItem));
				SetClientCookie(client, g_hDPrint, sItem);
				OpenMainMenu(client);
				CCPrintToChat(client, "%s {default}%t", g_sPrefix, g_bDPrint[client] ? "chat_print_off" : "chat_print_on");
			}	
			else
			{
				OpenPlaylistsMenu(client);
			}
		}
		case MenuAction_End:
		{
			delete hMenu;
		}
	}
}

public void OpenPlaylistsMenu(int client)
{
	char sBuff[256];
	char sUniq[32];
	Menu menu = new Menu(PlaylistsCallback);
	
	SetMenuTitle(menu, "%T\n \n", "choose_menu_title", client);
	SetMenuExitBackButton(menu, true);
	
	int size = GetArraySize(g_hPlaylists[name]);
	for (int i = 0; i < size; ++i)
	{
		GetArrayString(g_hPlaylists[uniq], i, sUniq, sizeof(sUniq));
		if(FindStringInArray(g_hPlaylists[hidden], sUniq) == -1 || FindStringInArray(g_hVisible[client], sUniq) != -1)
		{
			GetArrayString(g_hPlaylists[name], i, sBuff, sizeof(sBuff));
			if(g_bCount) Format(sBuff, sizeof(sBuff), "[%s] %s (%i)", g_iPlaylist[client] == i ? "✔" : "✘", sBuff, GetArraySize(GetArrayCell(g_hPlaylists[music], i)));
			else Format(sBuff, sizeof(sBuff), "[%s] %s", g_iPlaylist[client] == i ? "✔" : "✘", sBuff);
			AddMenuItem(menu, sUniq, sBuff);
		}
	}
	
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int PlaylistsCallback(Menu hMenu, MenuAction action, int client, int param2)
{
	switch(action)
	{
		case MenuAction_Select:
		{             
			char sItem[32];
			char sName[64];
			GetMenuItem(hMenu, param2, sItem, sizeof(sItem)); 
			int iid = FindStringInArray(g_hPlaylists[uniq], sItem);
			
			if(g_iPlaylist[client] != iid)
			{
				g_iPlaylist[client] = iid;
				SetClientCookie(client, g_hPlaylistCookie, sItem);
				if(g_bOwnPlaylist) LoadPlaylist(g_hNotPlayed[client], iid);
			
				GetArrayString(g_hPlaylists[name], iid, sName, sizeof(sName));
				TrimString(sName);
				CCPrintToChat(client, "%s {default}%t", g_sPrefix, "chat_choose", sName);
			}
			
			OpenPlaylistsMenu(client);
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				OpenMainMenu(client);
		}
		case MenuAction_End:
		{
			delete hMenu;
		}
	}
	return;
}

public void OnClientCookiesCached(int client)
{
	if(!IsFakeClient(client))
	{		
		if(g_bHidden) 
			g_hVisible[client] = new ArrayList(ByteCountToCells(32));
		
		char sBuff[32];
		GetClientCookie(client, g_hDisableCookie, sBuff, sizeof(sBuff));
		g_bDisabled[client] = !!StringToInt(sBuff);
		
		GetClientCookie(client, g_hDPrint, sBuff, sizeof(sBuff));
		g_bDPrint[client] = !!StringToInt(sBuff);
		
		GetClientCookie(client, g_hVolumeCookie, sBuff, sizeof(sBuff));
		if(g_iDefVolume && !sBuff[0])
		{
			IntToString(10 - g_iDefVolume, sBuff, sizeof(sBuff));
			SetClientCookie(client, g_hVolumeCookie, sBuff);
		}
		g_iVolume[client] = StringToInt(sBuff);
		
		int iid;
		GetClientCookie(client, g_hPlaylistCookie, sBuff, sizeof(sBuff));
		if(!sBuff || (iid = FindStringInArray(g_hPlaylists[uniq], sBuff)) == -1)
		{
			GetArrayString(g_hPlaylists[uniq], 0, sBuff, sizeof(sBuff));
			SetClientCookie(client, g_hPlaylistCookie, sBuff);
			iid = 0;
		}
		else if(FindStringInArray(g_hPlaylists[hidden], sBuff) != -1) iid = 0;
		
		g_iPlaylist[client] = iid;
		
		if(g_bOwnPlaylist) 
		{
			g_hNotPlayed[client] = new ArrayList(ByteCountToCells(256));
			LoadPlaylist(g_hNotPlayed[client], iid);
		}	
	}
}

public void OnClientDisconnect(int client)
{
	if(g_hNotPlayed[client]) delete g_hNotPlayed[client];
	if(g_hVisible[client]) delete g_hVisible[client];
}


public void PrintSongInfo(int client, char filename[256])
{
	if(GetEngineVersion() == Engine_CSGO)
	{
		//ReplaceStringEx(filename,sizeof(filename),"ad","download");
		ReplaceStringEx(filename,sizeof(filename),"*","");
		ReplaceStringEx(filename,sizeof(filename),"//","/");
	}
	Format(filename,sizeof(filename),"%s.mp3",filename);
	Handle soundfile = OpenSoundFile(filename);
	//CPrintToChatAll(filename);    
	
	char szBuffer[255];
	char sArtist[64]; char sTitle[64];
	
	GetSoundArtist(soundfile,sArtist,sizeof(sArtist));
	GetSoundTitle(soundfile,sTitle,sizeof(sTitle));
		
	Format(szBuffer, sizeof(szBuffer),"{green}[RES] {default}Сейчас играет: {lime}%s {default}- {lime}%s",sArtist ,sTitle);

	CPrintToChat(client,szBuffer);

	CloseHandle(soundfile); 
}



public Action CS_OnTerminateRound(float &delay, CSRoundEndReason &reason)
{
	char sSound[256];
	int iid;
	ArrayList hArray, hBArray;
	
	if(!g_bOwnPlaylist) 
	{
		hArray = new ArrayList(ByteCountToCells(256));
		int size = GetArraySize(g_hPlaylists[music]);
		for (int i = 0; i < size; ++i)
		{
			hBArray = GetArrayCell(g_hPlaylists[not_played], i);
			
			if(GetArraySize(hBArray) == 0) LoadPlaylist(hBArray, i);
			
			if(g_bRandom) iid = GetRandomInt(0, GetArraySize(hBArray) - 1);
			GetArrayString(hBArray, iid, sSound, sizeof(sSound));
			PushArrayString(hArray, sSound);
			if(!g_bRepeat || (g_bRepeat && !g_bRandom)) 
				RemoveFromArray(hBArray, iid);
		}
	}
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i) && !g_bDisabled[i])
		{
			if(g_bOwnPlaylist) 
			{
				if(GetArraySize(g_hNotPlayed[i]) == 0) LoadPlaylist(g_hNotPlayed[i], g_iPlaylist[i]);
				
				if(g_bRandom) iid = GetRandomInt(0, GetArraySize(g_hNotPlayed[i]) - 1);
				else iid = 0;
				GetArrayString(g_hNotPlayed[i], iid, sSound, sizeof(sSound));
				if(!g_bRepeat || (g_bRepeat && !g_bRandom)) 
					RemoveFromArray(g_hNotPlayed[i], iid);
			}
			else GetArrayString(hArray, g_iPlaylist[i], sSound, sizeof(sSound));
			
			if(g_bCSGO) ClientCommand(i, "playgamesound Music.StopAllMusic");
			
			EmitSoundToClientAny(i, sSound, -2, 0, 0, 0, 1.0 - (float(g_iVolume[i])*0.1), 100, -1, NULL_VECTOR, NULL_VECTOR, true, 0.0);
			
			int slash = FindCharInString(sSound, '/', true) + 1;
			ReplaceString(sSound[slash], sizeof(sSound), ".mp3", NULL_STRING, false);
			TrimString(sSound[slash]);
			
			
			
			if(g_bPrint && !g_bDisabled[i] && !g_bDPrint[i]) PrintSongInfo(i,sSound);
				//CCPrintToChat(i, "%s {default}%t", g_sPrefix, "print_msg", sSound[slash]);
				
		}
	}

	if(hArray) CloseHandle(hArray);
	
	if(g_bStopMapMusic)
	{
		int entity = INVALID_ENT_REFERENCE;
		for(int i = 1; i <= MaxClients; ++i)
		{
			if(!IsClientInGame(i) || IsFakeClient(i)) continue;
			
			for (int u = 0; u < g_iNumSounds; ++u)
			{
				entity = EntRefToEntIndex(g_iSoundEnts[u]);
				
				if (entity != INVALID_ENT_REFERENCE){
					GetEntPropString(entity, Prop_Data, "m_iszSound", sSound, sizeof(sSound));
					EmitSoundToClient(i, sSound, entity, SNDCHAN_STATIC, SNDLEVEL_NONE, SND_STOP, 0.0, SNDPITCH_NORMAL, _, _, _, true);
				}
			}
		}
	}
	
	return Plugin_Continue;
}

public void OnRoundStart(Handle hEvent, const char[] sName, bool dontBroadcast)
{
	if(g_bStopMapMusic)
	{
		g_iNumSounds = 0;
		
		char sSound[PLATFORM_MAX_PATH];
		int entity = INVALID_ENT_REFERENCE;

		while((entity = FindEntityByClassname(entity, "ambient_generic")) != INVALID_ENT_REFERENCE)
		{
			GetEntPropString(entity, Prop_Data, "m_iszSound", sSound, sizeof(sSound));

			int len = strlen(sSound);
			if (len > 4 && (StrEqual(sSound[len-3], "mp3") || StrEqual(sSound[len-3], "wav")))
				g_iSoundEnts[g_iNumSounds++] = EntIndexToEntRef(entity);
		}
	}
}

public Action OnRoundEnd(Handle hEvent, const char[] sName, bool dontBroadcast)
{
	dontBroadcast = true;
	return Plugin_Changed;
}

public void LoadPlaylist(ArrayList hArray, int iid)
{
	char sSound[256];
	
	ClearArray(hArray);
	
	ArrayList hArray2 = GetArrayCell(g_hPlaylists[music], iid);
	
	int size = GetArraySize(hArray2) - 1;
	for (int i = 0; i <= size; ++i)
	{
		GetArrayString(hArray2, i, sSound, sizeof(sSound));
		PushArrayString(hArray, sSound);
	}
		
	if(g_bRandom)
		for (int i = size; i > 0 ; --i)
			SwapArrayItems(hArray, i, GetRandomInt(0, i));
}

public void CCPrintToChat(int client, const char[] message, any ...)
{
	char sBuff[256];
	VFormat(sBuff, sizeof(sBuff), message, 3);
	
	if(g_bCSGO) CGOPrintToChat(client, sBuff);
	else CPrintToChat(client, sBuff);
}