

# Muli（沐哩） - Bilibili HarmonyOS 手机端

## 项目概述

<div align="center">
  <img src="entry/src/main/resources/base/media/app_logo.png" alt="MuLi Logo" width="200">
</div>

**MuLi** 是一个基于 HarmonyOS（鸿蒙）系统的 Bilibili（哔哩哔哩）第三方视频客户端，使用 ArkTS 语言开发，支持 API 24+ 设备。欢迎各位大佬给出建议和批评！

## 主要功能
- **首页推荐**：个性化推荐视频流，支持下拉刷新和上拉加载更多
- **视频播放**：竖屏详情页播放和横屏全屏播放，使用原生 XComponent 组件
- **用户系统**：通过 Bilibili 官方页面登录，支持 Cookie 认证和会话持久化
- **个人中心**：展示用户信息、动态、关注、粉丝等统计数据
- **消息中心**：显示回复、@我、点赞、系统通知等消息分类
- **搜索功能**：支持视频搜索
- **设置页面**：外观设置、播放器设置等

## 技术架构
- **开发语言**：ArkTS（HarmonyOS 原生语言）
- **UI 框架**：ArkUI（声明式 UI）
- **网络请求**：HarmonyOS HTTP 客户端
- **视频播放**：原生 XComponent + 自定义播放器服务
- **数据存储**：Preferences（轻量级存储）
- **安全机制**：HUKS 密钥管理、Wbi 签名算法

## 项目结构
```
MuLi/
├── entry/src/main/ets/
│   ├── pages/              # 页面组件
│   │   ├── Index.ets           # 首页（推荐、直播、热门）
│   │   ├── DynamicPage.ets     # 动态页面
│   │   ├── AnimePage.ets       # 番剧页面
│   │   ├── HotPage.ets         # 热门页面
│   │   ├── LivePage.ets        # 直播页面
│   │   └── Settings.ets        # 设置页面
│   ├── services/           # 业务服务
│   │   ├── AuthService.ets         # 认证服务
│   │   ├── BiliHttpClient.ets      # HTTP 客户端
│   │   ├── DynamicService.ets      # 动态服务
│   │   ├── PlaybackService.ets     # 播放服务
│   │   ├── RecommendationService.ets # 推荐服务
│   │   ├── ReplyService.ets        # 评论服务
│   │   ├── SearchService.ets       # 搜索服务
│   │   ├── VideoDetailService.ets  # 视频详情服务
│   │   ├── VideoPlayerService.ets  # 视频播放器服务
│   │   └── WbiService.ets         # Wbi 签名服务
│   ├── models/             # 数据模型
│   │   └── VideoItem.ets          # 视频数据模型
│   ├── utils/              # 工具类
│   │   ├── ImmersiveMaterial.ets  # 沉浸光感材质
│   │   └── AdvancedFeatures.ets   # 高级特性
│   └── entryability/       # 应用入口
├── resources/              # 资源文件
└── API24_COMPATIBILITY_GUIDE.md  # API 24 适配指南
```

## 当前版本
- **版本号**：V2.1.1
- **最低支持 API**：24（兼容旧设备，部分功能降级）
- **目标 API**：26（完整功能支持）

## 开发环境
- **开发工具**：DevEco Studio
- **HarmonyOS SDK**：API 24-26
- **签名配置**：debug 模式
- **真机测试环境**：HUAWEI MATE 70 PRO

## 快速开始

>[!warring]
> 由于暂时没有进行邀测打算，所以只能继续侧载，任选其一，侧载教程：

1. [Release](https://github.com/qitinyu/MuLi/releases)下载最新HAP包
2. [小白调试助手](https://yqamm.top/posts/harmony/20260118cz/)
3. [Hokit](https://yqamm.top/posts/harmony/260713hokit/)
4. 按照上述侧载教程进行侧载试用

## 注意事项
- API 24 设备部分功能会降级（如沉浸光感效果）
- 视频播放需要网络连接
- 首次使用需要登录 Bilibili 账号

## 相关文档
- [API 24 兼容性指南](API24_COMPATIBILITY_GUIDE.md)
- [MuLi日志及Wiki](https://github.com/qitinyu/MuLi/wiki)
