import { BiliHttpClient } from './BiliHttpClient';

export class LiveRoom {
  roomId: number = 0;
  title: string = '';
  uname: string = '';
  face: string = '';
  cover: string = '';
  online: number = 0;
  areaName: string = '';
}

export class LiveRoomStatus {
  liveStatus: number = 0;
  online: number = 0;
  title: string = '';
  areaName: string = '';
  keyframe: string = '';
}

export class LiveService {
  private static readonly liveHost: string = 'api.live.bilibili.com';

  static async loadLiveList(page: number = 1): Promise<LiveRoom[]> {
    const query: Record<string, string> = {};
    query['parent_area_id'] = '0';
    query['area_id'] = '0';
    query['page'] = String(page);
    query['page_size'] = '20';
    query['sort_type'] = 'online';
    const result: Record<string, Object> =
      await BiliHttpClient.getJsonHost(LiveService.liveHost, '/room/v1/Area/getRoomList', query);
    if (Number(result['code'] ?? -1) !== 0) {
      throw new Error(String(result['message'] ?? '直播列表获取失败'));
    }
    const rawList: Object[] = (result['data'] as Object[]) ?? [];
    return rawList.map((raw: Object): LiveRoom => LiveService.parseRoom(raw as Record<string, Object>))
      .filter((room: LiveRoom): boolean => room.roomId > 0);
  }

  static async loadRoomStatus(roomId: number): Promise<LiveRoomStatus> {
    const query: Record<string, string> = {};
    query['room_id'] = String(roomId);
    const result: Record<string, Object> =
      await BiliHttpClient.getJsonHost(LiveService.liveHost, '/room/v1/Room/get_info', query);
    if (Number(result['code'] ?? -1) !== 0) {
      throw new Error(String(result['message'] ?? '直播间信息获取失败'));
    }
    const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
    const status: LiveRoomStatus = new LiveRoomStatus();
    status.liveStatus = Number(data['live_status'] ?? 0);
    status.online = Number(data['online'] ?? 0);
    status.title = String(data['title'] ?? '');
    status.areaName = String(data['area_name'] ?? '');
    status.keyframe = String(data['keyframe'] ?? '');
    return status;
  }

  static async loadPlayUrl(roomId: number): Promise<string> {
    const query: Record<string, string> = {};
    query['room_id'] = String(roomId);
    query['protocol'] = '1';
    query['format'] = '1,2';
    query['codec'] = '0';
    query['qn'] = '10000';
    query['platform'] = 'web';
    query['ptype'] = '8';
    const result: Record<string, Object> =
      await BiliHttpClient.getJsonHost(LiveService.liveHost, '/xlive/web-room/v2/index/getRoomPlayInfo', query);
    if (Number(result['code'] ?? -1) !== 0) {
      throw new Error(String(result['message'] ?? '直播流获取失败'));
    }
    const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
    const playurlInfo: Record<string, Object> = (data['playurl_info'] ?? {}) as Record<string, Object>;
    const playurl: Record<string, Object> = (playurlInfo['playurl'] ?? {}) as Record<string, Object>;
    const streams: Object[] = (playurl['stream'] as Object[]) ?? [];
    let fallback: string = '';
    for (const rawStream of streams) {
      const stream: Record<string, Object> = rawStream as Record<string, Object>;
      const isHls: boolean = String(stream['protocol_name'] ?? '') === 'http_hls';
      const formats: Object[] = (stream['format'] as Object[]) ?? [];
      for (const rawFormat of formats) {
        const format: Record<string, Object> = rawFormat as Record<string, Object>;
        const codecs: Object[] = (format['codec'] as Object[]) ?? [];
        if (codecs.length === 0) continue;
        const codec: Record<string, Object> = codecs[0] as Record<string, Object>;
        const url: string = LiveService.assembleUrl(codec);
        if (url === '') continue;
        if (isHls) return url;
        if (fallback === '') fallback = url;
      }
    }
    if (fallback !== '') return fallback;
    throw new Error('直播间暂未开播或没有可用线路');
  }

  private static assembleUrl(codec: Record<string, Object>): string {
    const baseUrl: string = String(codec['base_url'] ?? '');
    const urlInfos: Object[] = (codec['url_info'] as Object[]) ?? [];
    if (baseUrl === '' || urlInfos.length === 0) return '';
    const urlInfo: Record<string, Object> = urlInfos[0] as Record<string, Object>;
    const host: string = String(urlInfo['host'] ?? '');
    const extra: string = String(urlInfo['extra'] ?? '');
    if (host === '') return '';
    let url: string = host + baseUrl;
    if (url.indexOf('?') < 0) {
      url += '?';
    } else if (!url.endsWith('?')) {
      url += '&';
    }
    return url + extra;
  }

  private static parseRoom(raw: Record<string, Object>): LiveRoom {
    const room: LiveRoom = new LiveRoom();
    room.roomId = Number(raw['roomid'] ?? 0);
    room.title = String(raw['title'] ?? '');
    room.uname = String(raw['uname'] ?? '');
    room.face = String(raw['face'] ?? '');
    room.online = Number(raw['online'] ?? 0);
    room.areaName = String(raw['area_v2_name'] ?? '');
    const cover: string = String(raw['cover'] ?? raw['user_cover'] ?? raw['system_cover'] ?? '');
    room.cover = cover.trim();
    return room;
  }
}
