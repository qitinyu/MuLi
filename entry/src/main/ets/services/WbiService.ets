import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import util from '@ohos.util';
import http from '@ohos.net.http';
import { BiliHttpClient } from './BiliHttpClient';

export class WbiService {
  private static mixinKey: string = '';
  private static readonly table: number[] = [46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13];

  private static async md5Hex(value: string): Promise<string> {
    const md = cryptoFramework.createMd('MD5');
    const encoder = new util.TextEncoder();
    await md.update({ data: encoder.encodeInto(value) });
    const output = await md.digest();
    let result: string = '';
    output.data.forEach((item: number): void => {
      result += item.toString(16).padStart(2, '0');
    });
    return result;
  }

  private static getFileKey(url: string): string {
    const name: string = url.split('/').pop() ?? '';
    return name.split('.')[0];
  }

  private static getMixinKey(origin: string): string {
    let result: string = '';
    WbiService.table.forEach((index: number): void => { result += origin[index]; });
    return result;
  }

  private static async fetchMixinKey(): Promise<string> {
    if (WbiService.mixinKey !== '') return WbiService.mixinKey;
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request('https://api.bilibili.com/x/web-interface/nav', {
        method: http.RequestMethod.GET,
        header: { 'User-Agent': BiliHttpClient.browserUserAgent, 'Referer': 'https://www.bilibili.com/' },
        connectTimeout: 10000,
        readTimeout: 10000
      });
      const body: Record<string, Object> = JSON.parse(response.result as string) as Record<string, Object>;
      const data: Record<string, Object> = body['data'] as Record<string, Object>;
      const wbi: Record<string, Object> = data['wbi_img'] as Record<string, Object>;
      const origin: string = WbiService.getFileKey(String(wbi['img_url'])) + WbiService.getFileKey(String(wbi['sub_url']));
      WbiService.mixinKey = WbiService.getMixinKey(origin);
      return WbiService.mixinKey;
    } finally {
      request.destroy();
    }
  }

  static async sign(pairs: string[]): Promise<string> {
    const mixinKey: string = await WbiService.fetchMixinKey();
    pairs.push(`wts=${Math.floor(Date.now() / 1000)}`);
    const encoded: string[] = pairs.map((pair: string): string => {
      const separator: number = pair.indexOf('=');
      const key: string = pair.substring(0, separator);
      const value: string = pair.substring(separator + 1).replace(/[!'()*]/g, '');
      return `${key}=${encodeURIComponent(value)}`;
    });
    encoded.sort();
    const query: string = encoded.join('&');
    const rid: string = await WbiService.md5Hex(query + mixinKey);
    return `${query}&w_rid=${rid}`;
  }

  static warmup(): void {
    WbiService.fetchMixinKey().catch((error: Error): void => {
      console.error(`Pilihos WBI warmup failed: ${error.message}`);
    });
  }
}
