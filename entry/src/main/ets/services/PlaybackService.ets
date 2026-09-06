import { BiliHttpClient } from './BiliHttpClient';
import { VideoItem } from '../models/VideoItem';
import { WbiService } from './WbiService';

export interface QualityOption {
  qn: number;
  label: string;
}

export interface PlaybackResolveResult {
  urls: string[];
  qualities: QualityOption[];
  grantedQn: number;
}

export class PlaybackService {
  static async resolve(item: VideoItem, cookie: string = ''): Promise<string> {
    const result: PlaybackResolveResult = await PlaybackService.resolveWithQuality(item, cookie, 0);
    if (result.urls.length === 0) throw new Error('没有可用的视频播放地址');
    return result.urls[0];
  }

  static async resolveCandidates(item: VideoItem, cookie: string = ''): Promise<string[]> {
    const result: PlaybackResolveResult = await PlaybackService.resolveWithQuality(item, cookie, 0);
    return result.urls;
  }

  /**
   * 按目标清晰度解析播放地址。preferredQn<=0 时走兼容流程（html5 优先）；
   * 指定 qn 时走 WBI playurl 请求该清晰度的 DURL 合流地址，失败回退兼容流程。
   * qualities 返回接口声明的可选清晰度（accept_quality/accept_description）。
   */
  static async resolveWithQuality(item: VideoItem, cookie: string = '',
    preferredQn: number = 0): Promise<PlaybackResolveResult> {
    if (item.cid <= 0) {
      throw new Error('视频 cid 缺失，无法获取播放地址');
    }
    const qualities: QualityOption[] = [];
    if (preferredQn > 0) {
      // 先走 WBI 通道按目标清晰度请求（登录态可授予 1080P）；
      // html5 通道在目标清晰度不可授予时会静默降级（如 80 请求返回 64），仅作兜底
      const preferred: PlaybackResolveResult =
        await PlaybackService.resolveWbiQuality(item, cookie, preferredQn, qualities);
      if (preferred.urls.length > 0 && preferred.grantedQn >= preferredQn) {
        return preferred;
      }
      const html5Candidates: string[] = [];
      const html5Granted: number =
        await PlaybackService.resolveHtml5Candidates(item, cookie, html5Candidates, qualities,
          [String(preferredQn), '80', '64', '32', '16']);
      if (html5Candidates.length > 0 && html5Granted >= preferred.grantedQn) {
        return { urls: html5Candidates, qualities: qualities, grantedQn: html5Granted };
      }
      if (preferred.urls.length > 0) {
        return preferred;
      }
      console.warn(`Pilihos playback preferred qn=${preferredQn} unavailable, falling back`);
    }
    const durlCandidates: string[] = [];
    let grantedQn: number = 0;
    let lastError: string = '';
    // 旧版 playurl 在部分视频上仍能返回音视频合并的 MP4，优先尝试它。
    await PlaybackService.resolveHtml5Candidates(item, cookie, durlCandidates, qualities);
    if (durlCandidates.length === 0) {
      for (const quality of ['16', '32']) {
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
          const result: Record<string, Object> =
            await BiliHttpClient.getJsonQuery('/x/player/wbi/playurl', query, cookie);
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
          PlaybackService.collectQualities(data, qualities);
          grantedQn = Math.max(grantedQn, Number(data['quality'] ?? 0));
          if (durl.length === 0 && videoList.length > 0) lastError = '播放接口仅返回 DASH 分离流';
          console.info(`Pilihos playback candidates: qn=${quality}, durl=${durl.length}, dash=${videoList.length}`);
        } catch (error) {
          lastError = String(error);
        }
      }
    }
    if (durlCandidates.length > 0) {
      console.info(`Pilihos playback stream: candidates=${durlCandidates.length}, url=${PlaybackService.describeUrl(durlCandidates[0])}`);
      return { urls: durlCandidates, qualities: qualities, grantedQn: grantedQn };
    }
    throw new Error(lastError === '' ? '没有可用的视频播放地址' : lastError);
  }

  private static async resolveWbiQuality(item: VideoItem, cookie: string, targetQn: number,
    qualities: QualityOption[]): Promise<PlaybackResolveResult> {
    const urls: string[] = [];
    let grantedQn: number = 0;
    try {
      const query: string = await WbiService.sign([
        item.bvid !== '' ? `bvid=${item.bvid}` : `avid=${item.aid}`,
        `cid=${item.cid}`,
        `qn=${targetQn}`,
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
      const result: Record<string, Object> =
        await BiliHttpClient.getJsonQuery('/x/player/wbi/playurl', query, cookie);
      if (Number(result['code'] ?? -1) !== 0) {
        return { urls: urls, qualities: qualities, grantedQn: 0 };
      }
      const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
      const durl: Object[] = (data['durl'] as Object[]) ?? [];
      PlaybackService.collectDurlCandidates(durl, urls);
      PlaybackService.collectQualities(data, qualities);
      grantedQn = Number(data['quality'] ?? 0);
      console.info(`Pilihos playback quality switch: target=${targetQn}, granted=${grantedQn}, durl=${durl.length}`);
    } catch (error) {
      console.warn(`Pilihos playback quality resolve failed: qn=${targetQn}, ${String(error)}`);
    }
    return { urls: urls, qualities: qualities, grantedQn: grantedQn };
  }

  static qualityLabel(qn: number, description: string = ''): string {
    // 统一使用B站现行清晰度命名，不采用接口 accept_description 的旧称
    if (qn === 127 || qn === 126) return '杜比';
    if (qn === 125) return 'HDR';
    if (qn === 120) return '4K';
    if (qn === 116) return '高清1080P60';
    if (qn === 112) return '高清1080P+';
    if (qn === 80) return '高清1080P';
    if (qn === 74) return '准高清720P60';
    if (qn === 64) return '准高清720P';
    if (qn === 32) return '标清480P';
    if (qn === 16) return '清晰360P';
    return qn > 0 ? `${qn}` : '自动';
  }

  private static collectQualities(data: Record<string, Object>, qualities: QualityOption[]): void {
    const qnList: Object[] = (data['accept_quality'] as Object[]) ?? [];
    const descList: Object[] = (data['accept_description'] as Object[]) ?? [];
    qnList.forEach((rawQn: Object, index: number): void => {
      const qn: number = Number(rawQn);
      if (qn <= 0) return;
      if (qualities.some((option: QualityOption): boolean => option.qn === qn)) return;
      const description: string = index < descList.length ? String(descList[index]) : '';
      qualities.push({ qn: qn, label: PlaybackService.qualityLabel(qn, description) });
    });
  }

  private static async resolveHtml5Candidates(item: VideoItem, cookie: string, candidates: string[],
    qualities: QualityOption[], qnList: string[] = ['16', '32', '64']): Promise<number> {
    let grantedQn: number = 0;
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
      for (const quality of qnList) {
        query['qn'] = quality;
        const result: Record<string, Object> = await BiliHttpClient.getJson('/x/player/playurl', query, cookie);
        if (Number(result['code'] ?? -1) !== 0) {
          console.warn(`Pilihos html5 playback fallback failed: qn=${quality}, ${String(result['message'] ?? '')}`);
          continue;
        }
        const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
        const durl: Object[] = (data['durl'] as Object[]) ?? [];
        PlaybackService.collectDurlCandidates(durl, candidates);
        PlaybackService.collectQualities(data, qualities);
        grantedQn = Number(data['quality'] ?? 0);
        console.info(`Pilihos html5 playback fallback: qn=${quality}, granted=${grantedQn}, durl=${durl.length}`);
        if (candidates.length > 0) break;
      }
    } catch (error) {
      console.warn(`Pilihos html5 playback fallback failed: ${String(error)}`);
    }
    return grantedQn;
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
