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
    }
    return headers;
  }
}
