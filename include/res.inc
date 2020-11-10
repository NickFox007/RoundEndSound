#if defined _res_included
 #endinput
#endif
#define _res_included

enum RES_Status
{
	RES_InvalidClient = -1,
	RES_Hidden,
	RES_Visible,
	RES_NotExists
}

#if !defined REQUIRE_PLUGIN
public __pl_res_SetNTVOptional()
{
	MarkNativeAsOptional("RES_GetPlaylistStatus");
	MarkNativeAsOptional("RES_GetPlaylistStatusForClient");
	MarkNativeAsOptional("RES_SetPlaylistStatus");
	MarkNativeAsOptional("RES_GetPlaylistName");
	MarkNativeAsOptional("RES_ShowPlaylist");
}
#endif

/*
 * Вызывается, когда игрок нажимает кнопку назад.
 *
 * client - id игрока.
 *
 * sName - Идентификатор плейлиста.
*/
typedef RESBack = function void(int client, const char[] sName);

/*
 * Получает глобальный статус плейлиста.
 *
 * sName - Идентификатор плейлиста.
 *
 * Возвращает RES_Hidden/RES_Visible/RES_NotExists.
*/
native RES_Status RES_GetPlaylistStatus(const char[] sName);

/*
 * Получает статус плейлиста для конкретного игрока.
 *
 * client - id игрока.
 *
 * sName - Идентификатор плейлиста.
 *
 * Возвращает RES_InvalidClient/RES_Hidden/RES_Visible/RES_NotExists.
*/
native RES_Status RES_GetPlaylistStatusForClient(int client, const char[] sName);

/*
 * Изменяет статус плейлиста для конкретного игрока на сессию.
 *
 * client - id игрока.
 *
 * sName - Идентификатор плейлиста.
 *
 * bStatus - Если true, то плейлист будет отображаться у игрока.
 *
 * Возвращает RES_InvalidClient/RES_Hidden/RES_Visible/RES_NotExists.
*/
native RES_Status RES_SetPlaylistStatus(int client, const char[] sName, bool bStatus = true);

/*
 * Получает имя плейлиста.
 *
 * sName - Идентификатор плейлиста.
 *
 * sBuff - Буфер.
 *
 * maxsize - Максимальный размер буфера.
*/
native void RES_GetPlaylistName(const char[] sName, char[] sBuff, int maxsize);

/*
 * Изменяет статус плейлиста для конкретного игрока на сессию.
 *
 * client - id игрока.
 *
 * sName - Идентификатор плейлиста.
 *
 * OnClientGoBack - Вызывается, когда игрок нажимает кнопку назад.
*/
native bool RES_ShowPlaylist(int client, const char[] sName, RESBack OnClientGoBack = INVALID_FUNCTION);