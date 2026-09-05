import { BiliHttpClient } from './BiliHttpClient';
import { VideoItem } from '../models/VideoItem';
import { WbiService } from './WbiService';

export class PlaybackService {
  static async resolve(item: VideoItem, cookie: string = ''): Promise<string> {
    const candidates: string[] = await PlaybackService.resolveCandidates(item, cookie);
    if (candidates.length === 0) throw new Error('没有可用的视频播放地址');
    return candidates[0];
  }

  static async resolveCandidates(item: VideoItem, cookie: string = ''): Promise<string[]> {
    if (item.cid <= 0) {
      throw new Error('视频 cid 缺失，无法获取播放地址');
    }
    const qualityLevels: string[] = ['16', '32'];
    const durlCandidates: string[] = [];
    let lastError: string = '';
    // 旧版 playurl 在部分视频上仍能返回音视频合并的 MP4，优先尝试它。
    await PlaybackService.resolveHtml5Candidates(item, cookie, durlCandidates);
    if (durlCandidates.length > 0) {
      console.info(`Pilihos playback stream: legacy candidates=${durlCandidates.length}, url=${PlaybackService.describeUrl(durlCandidates[0])}`);
      return durlCandidates;
    }
    for (const quality of qualityLevels) {
      try {
        const query: string = await WbiService.sign([
          item.bvid !== '' ? `bvid=${item.bvid}` : `avid=${item.aid}`,
          `cid=${item.cid}`,
          `qn=${quality}`,
          // durl is a single MP4 containing audio and video, which matches ArkUI/AVPlayer best.
          'fnval=0',
          'fnver=0',
          'fourk=0',
          'voice_balance=0',
          'gaia_source=pre-load',
          'isGaiaAvoided=true',
          'web_location=1315873',
          'try_look=1',
          'otype=json'
        ]);
        const result: Record<string, Object> = await BiliHttpClient.getJsonQuery('/x/player/wbi/playurl', query, cookie);
        const code: number = Number(result['code'] ?? -1);
        if (code !== 0) {
          lastError = `接口错误 ${code}: ${String(result['message'] ?? '播放地址不可用')}`;
          continue;
        }
        const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
        const dash: Record<string, Object> = (data['dash'] as Record<string, Object>) ?? {};
        const videoList: Object[] = (dash['video'] as Object[]) ?? [];
        const durl: Object[] = (data['durl'] as Object[]) ?? [];
        PlaybackService.collectDurlCandidates(durl, durlCandidates);
        if (durl.length === 0 && videoList.length > 0) lastError = '播放接口仅返回 DASH 分离流';
        console.info(`Pilihos playback candidates: qn=${quality}, durl=${durl.length}, dash=${videoList.length}`);
      } catch (error) {
        lastError = String(error);
      }
    }
    const candidates: string[] = durlCandidates;
    if (candidates.length > 0) {
      console.info(`Pilihos playback stream: candidates=${candidates.length}, url=${PlaybackService.describeUrl(candidates[0])}`);
      return candidates;
    }
    throw new Error(lastError === '' ? '没有可用的视频播放地址' : lastError);
  }

  private static async resolveHtml5Candidates(item: VideoItem, cookie: string, candidates: string[]): Promise<void> {
    try {
      const query: Record<string, string> = {};
      if (item.bvid !== '') {
        query['bvid'] = item.bvid;
      } else {
        query['avid'] = String(item.aid);
      }
      query['cid'] = String(item.cid);
      query['fnval'] = '0';
      query['fnver'] = '0';
      query['fourk'] = '0';
      query['platform'] = 'html5';
      query['high_quality'] = '1';
      for (const quality of ['16', '32', '64']) {
        query['qn'] = quality;
        const result: Record<string, Object> = await BiliHttpClient.getJson('/x/player/playurl', query, cookie);
        if (Number(result['code'] ?? -1) !== 0) {
          console.warn(`Pilihos html5 playback fallback failed: qn=${quality}, ${String(result['message'] ?? '')}`);
          continue;
        }
        const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
        const durl: Object[] = (data['durl'] as Object[]) ?? [];
        PlaybackService.collectDurlCandidates(durl, candidates);
        console.info(`Pilihos html5 playback fallback: qn=${quality}, durl=${durl.length}`);
        if (candidates.length > 0) break;
      }
    } catch (error) {
      console.warn(`Pilihos html5 playback fallback failed: ${String(error)}`);
    }
  }

  private static collectDurlCandidates(durl: Object[], candidates: string[]): void {
    durl.forEach((raw: Object): void => {
      const entry: Record<string, Object> = raw as Record<string, Object>;
      const url: string = String(entry['url'] ?? entry['base_url'] ?? entry['baseUrl'] ?? '');
      if (url !== '' && !candidates.includes(url)) candidates.push(url);
      const backups: Object[] = (entry['backup_url'] as Object[]) ??
        (entry['backupUrl'] as Object[]) ?? [];
      backups.forEach((backup: Object): void => {
        const backupUrl: string = String(backup);
        if (backupUrl !== '' && !candidates.includes(backupUrl)) {
          candidates.push(backupUrl);
        }
      });
    });
  }

  private static describeUrl(url: string): string {
    const queryIndex: number = url.indexOf('?');
    return queryIndex >= 0 ? url.substring(0, queryIndex) : url;
  }
}
