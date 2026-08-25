import { BiliHttpClient } from './BiliHttpClient';
import { VideoItem } from '../models/VideoItem';
import { WbiService } from './WbiService';

export class PlaybackService {
  static async resolve(item: VideoItem): Promise<string> {
    const candidates: string[] = await PlaybackService.resolveCandidates(item);
    if (candidates.length === 0) throw new Error('没有可用的视频播放地址');
    return candidates[0];
  }

  static async resolveCandidates(item: VideoItem): Promise<string[]> {
    const qualityLevels: string[] = ['16', '32'];
    const durlCandidates: string[] = [];
    const dashCandidates: string[] = [];
    let lastError: string = '';
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
          'try_look=1'
        ]);
        const result: Record<string, Object> = await BiliHttpClient.getJsonQuery('/x/player/wbi/playurl', query);
        const code: number = Number(result['code'] ?? -1);
        if (code !== 0) {
          lastError = `接口错误 ${code}: ${String(result['message'] ?? '播放地址不可用')}`;
          continue;
        }
        const data: Record<string, Object> = result['data'] as Record<string, Object>;
        const dash: Record<string, Object> = (data['dash'] as Record<string, Object>) ?? {};
        const videoList: Object[] = (dash['video'] as Object[]) ?? [];
        const durl: Object[] = (data['durl'] as Object[]) ?? [];
        durl.forEach((raw: Object): void => {
          const entry: Record<string, Object> = raw as Record<string, Object>;
          let url: string = String(entry['url'] ?? '');
          if (url === '') {
            const backups: Object[] = (entry['backup_url'] as Object[]) ?? [];
            if (backups.length > 0) url = String(backups[0]);
          }
          if (url !== '' && !durlCandidates.includes(url)) durlCandidates.push(url);
        });
        videoList.forEach((raw: Object): void => {
          const entry: Record<string, Object> = raw as Record<string, Object>;
          const url: string = String(entry['baseUrl'] ?? entry['base_url'] ?? entry['url'] ?? '');
          if (url !== '' && !dashCandidates.includes(url)) dashCandidates.push(url);
        });
        console.info(`Pilihos playback candidates: qn=${quality}, durl=${durl.length}, dash=${videoList.length}`);
      } catch (error) {
        lastError = String(error);
      }
    }
    const candidates: string[] = durlCandidates.concat(dashCandidates);
    if (candidates.length > 0) {
      console.info(`Pilihos playback stream: candidates=${candidates.length}, url=${PlaybackService.describeUrl(candidates[0])}`);
      return candidates;
    }
    throw new Error(lastError === '' ? '没有可用的视频播放地址' : lastError);
  }

  private static describeUrl(url: string): string {
    const queryIndex: number = url.indexOf('?');
    return queryIndex >= 0 ? url.substring(0, queryIndex) : url;
  }
}
