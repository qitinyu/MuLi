export interface VideoItem {
  id: number;
  aid: number;
  bvid: string;
  cid: number;
  title: string;
  author: string;
  cover: string;
  viewCount: number;
  danmuCount: number;
  likeCount: number;
  commentCount: number;
  followed: boolean;
  duration: number;
  playUrl: string;
  placeholder: boolean;
  publishTime: number;
  description: string;
  tags: string[];
  detailLoaded: boolean;
}
