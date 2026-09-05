import http from '@ohos.net.http';

export class BiliHttpClient {
  private static readonly apiBase: string = 'https://api.bilibili.com';
  private static readonly appBase: string = 'https://app.bilibili.com';
  static readonly browserUserAgent: string =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static async getJson(path: string, query: Record<string, string>, cookie: string = ''): Promise<Record<string, Object>> {
    const request: http.HttpRequest = http.createHttp();
    const queryText: string = Object.keys(query)
      .map((key: string) => `${encodeURIComponent(key)}=${encodeURIComponent(query[key])}`)
      .join('&');
    const url: string = `${BiliHttpClient.apiBase}${path}?${queryText}`;
    const headers: Record<string, string> = BiliHttpClient.buildHeaders(cookie);
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 10000,
        readTimeout: 15000
      });
      return JSON.parse(response.result as string) as Record<string, Object>;
    } finally {
      request.destroy();
    }
  }

  static async getJsonHost(host: string, path: string, query: Record<string, string>, cookie: string = ''): Promise<Record<string, Object>> {
    const request: http.HttpRequest = http.createHttp();
    const queryText: string = Object.keys(query)
      .map((key: string) => `${encodeURIComponent(key)}=${encodeURIComponent(query[key])}`)
      .join('&');
    const url: string = `https://${host}${path}?${queryText}`;
    const headers: Record<string, string> = BiliHttpClient.buildHeaders(cookie);
    try {
      const response: http.HttpResponse = await request.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 10000,
        readTimeout: 15000
      });
      return JSON.parse(response.result as string) as Record<string, Object>;
    } finally {
      request.destroy();
    }
  }

  static async getJsonQuery(path: string, queryText: string, cookie: string = ''): Promise<Record<string, Object>> {
    const request: http.HttpRequest = http.createHttp();
    const headers: Record<string, string> = BiliHttpClient.buildHeaders(cookie);
    try {
      const response: http.HttpResponse = await request.request(`${BiliHttpClient.apiBase}${path}?${queryText}`, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: 10000,
        readTimeout: 15000
      });
      return JSON.parse(response.result as string) as Record<string, Object>;
    } finally {
      request.destroy();
    }
  }

  static async getAppJson(path: string, queryText: string): Promise<Record<string, Object>> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(`${BiliHttpClient.appBase}${path}?${queryText}`, {
        method: http.RequestMethod.GET,
        header: { 'User-Agent': BiliHttpClient.browserUserAgent },
        connectTimeout: 10000,
        readTimeout: 15000
      });
      return JSON.parse(response.result as string) as Record<string, Object>;
    } finally {
      request.destroy();
    }
  }

  private static buildHeaders(cookie: string): Record<string, string> {
    const headers: Record<string, string> = {
      'User-Agent': BiliHttpClient.browserUserAgent,
      'Referer': 'https://www.bilibili.com/',
      'Origin': 'https://www.bilibili.com'
    };
    if (cookie !== '') {
      headers['Cookie'] = cookie;
    } else {
      // 匿名请求携带随机 buvid3，避免风控接口（如直播 API）返回 -352
      headers['Cookie'] = 'buvid3=' + BiliHttpClient.randomBuvid();
    }
    return headers;
  }

  private static randomBuvid(): string {
    if (BiliHttpClient.cachedBuvid !== '') return BiliHttpClient.cachedBuvid;
    const hex: string = '0123456789ABCDEF';
    let uuid: string = '';
    for (let i = 0; i < 36; i++) {
      if (i === 8 || i === 13 || i === 18 || i === 23) {
        uuid += '-';
        continue;
      }
      uuid += hex[Math.floor(Math.random() * 16)];
    }
    BiliHttpClient.cachedBuvid = uuid + 'infoc';
    return BiliHttpClient.cachedBuvid;
  }

  private static cachedBuvid: string = '';
}
