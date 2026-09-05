import { VideoItem } from '../models/VideoItem';
import { BiliHttpClient } from './BiliHttpClient';

export class VideoDetailService {
  static async load(item: VideoItem): Promise<VideoItem> {
    const query: Record<string, string> = {};
    if (item.bvid !== '') {
      query['bvid'] = item.bvid;
    } else {
      query['aid'] = String(item.aid);
    }
    const result: Record<string, Object> = await BiliHttpClient.getJson('/x/web-interface/view', query);
    if (Number(result['code'] ?? -1) !== 0) {
      throw new Error(String(result['message'] ?? '视频详情获取失败'));
    }
    const data: Record<string, Object> = (result['data'] ?? {}) as Record<string, Object>;
    const owner: Record<string, Object> = (data['owner'] ?? {}) as Record<string, Object>;
    const stat: Record<string, Object> = (data['stat'] ?? {}) as Record<string, Object>;
    const rawTags: Object[] = (data['tags'] as Object[]) ?? [];
    const tags: string[] = [];
    rawTags.forEach((raw: Object): void => {
      const tag: Record<string, Object> = raw as Record<string, Object>;
      const name: string = String(tag['tag_name'] ?? tag['name'] ?? '');
      if (name !== '' && !tags.includes(name)) tags.push(name);
    });
    if (tags.length === 0 && item.bvid !== '') {
      try {
        const tagQuery: Record<string, string> = {};
        tagQuery['bvid'] = item.bvid;
        const tagResult: Record<string, Object> = await BiliHttpClient.getJson(
          '/x/web-interface/view/detail/tag', tagQuery);
        if (Number(tagResult['code'] ?? -1) === 0) {
          const tagData: Object[] = ((tagResult['data'] ?? []) as Object[]);
          tagData.forEach((raw: Object): void => {
            const tag: Record<string, Object> = raw as Record<string, Object>;
            const name: string = String(tag['tag_name'] ?? tag['name'] ?? '');
            if (name !== '' && !tags.includes(name)) tags.push(name);
          });
        }
      } catch (error) {
        console.error('Pilihos video tags request failed: ' + String(error));
      }
    }
    return {
      id: item.id,
      aid: Number(data['aid'] ?? item.aid),
      bvid: String(data['bvid'] ?? item.bvid),
      cid: Number(data['cid'] ?? item.cid),
      title: String(data['title'] ?? item.title),
      author: String(owner['name'] ?? item.author),
      authorFace: String(owner['face'] ?? item.authorFace ?? ''),
      cover: String(data['pic'] ?? item.cover),
      viewCount: Number(stat['view'] ?? item.viewCount),
      danmuCount: Number(stat['danmaku'] ?? item.danmuCount),
      likeCount: Number(stat['like'] ?? item.likeCount),
      commentCount: Number(stat['reply'] ?? item.commentCount),
      followed: item.followed,
      duration: Number(data['duration'] ?? item.duration),
      playUrl: item.playUrl,
      placeholder: false,
      publishTime: Number(data['pubdate'] ?? item.publishTime),
      description: String(data['desc'] ?? ''),
      tags: tags,
      detailLoaded: true
    };
  }
}
