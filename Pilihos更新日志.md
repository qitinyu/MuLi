## Pilihos更新日志
1. 版本号位于 `AppScope/app.json5`（versionName/versionCode）
2. [沉浸光感参考](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-immersive-light-sense)
3. [加载参考](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ts-basic-components-loadingprogress)
4. [新事件标记](https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/badge-0000001929816016)
5. [分段按钮](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ohos-arkui-advanced-segmentbutton#%E7%A4%BA%E4%BE%8B1%E8%AE%BE%E7%BD%AE%E5%88%86%E6%AE%B5%E6%8C%89%E9%92%AE%E7%9A%84%E7%B1%BB%E5%9E%8B)
6. [指向型菜单](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ts-universal-attributes-menu#%E7%A4%BA%E4%BE%8B4%E5%8F%B3%E9%94%AE%E5%BC%B9%E5%87%BA%E6%8C%87%E5%90%91%E5%9E%8B%E8%8F%9C%E5%8D%95)
7. [setAVMetadata](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/avsession-access-scene)
8. [即时反馈气泡](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/arkts-apis-uicontext-promptaction#showtoast)
9. [文本框](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ts-basic-components-textinput)


### Pilihos V1.0.5（1.0.5.1 → 1.0.5.9 · 真机反馈迭代）
> 主线：播放体验补全 + 互动能力落地；并行：架构还债与稳定性

- [✅] 1.0.5.9 直播：清晰度/线路切换（accept_qn 清晰度列表 + url_info 多线路，切换即重取流），信息行关注主播并回显已关注 #1058
- [✅] 1.0.5.8 UP主空间页：card 资料（粉丝/获赞/等级/签名）+ WBI 投稿列表（分页），关注按钮，点投稿回 App 播放；搜索分类页签接入真实排序参数（播放多/新发布等，切换即时重搜） #1057 #10511
- [✅] 1.0.5.7 互动：详情页点赞/投币/收藏/再看接真实接口（cookie+csrf）并回显高亮与计数；评论发布 /x/v2/reply/add 与评论点赞 /x/v2/reply/action #1055 #1056
- [✅] 1.0.5.6 真机修复②：进二级页闪退（qualityMenuVisible 补 @Provide）、31 处材质改真机毛玻璃 backgroundBlurStyle、搜索历史 Grid 占满整列压没结果区修复
- [✅] 1.0.5.5 真机修复①：材质过薄卡片不可见（降 REGULAR + 白色底衬）、搜索回车链路加固（去右侧无效按钮、空词 toast）、进视频控制条 2 秒自动隐藏
- [✅] 1.0.5.4 播放手势体系：左右半屏上下滑调亮度/音量（返回还原）、水平滑快进快退（HUD 预览时间）、双击暂停/播放 #1053
- [✅] 1.0.5.3 弹幕：XML 拉流解析 + Canvas 时间轴渲染（弹道分配防重叠/seek 重定位/暂停冻结/倍速联动），过滤词接入，发送弹幕（csrf） #1054
- [✅] 1.0.5.2 播放器：清晰度切换菜单（切换续播）+ 默认质量设置生效；播放记忆续播（aid+进度落盘，重进提示恢复）；buvid3 持久化降低 -412/-352 风控 #1051 #1052 #1059
- [✅] 1.0.5.1 架构还债：Index.ets 组件化拆分 2554→741 行（HomeTab/底栏/侧边栏/登录/PlayerScreen/PlayerOverlay/DetailScreen + FormatUtils/CommonBuilders），清理 XComponent 时代死代码 #10510
> 子版本号止于 1.0.5.9，此后的真机反馈修复不单独升版，按迭代批次记录：

- [✅] 迭代① 播放页与互动大改版：简介区新增"设置"子页、简介/评论/设置左右滑动切换；点赞乐观高亮带计数、收藏单击进默认夹+长按收藏夹面板、再看静默、分享走系统面板；竖屏化黑区信息面板（UP主头像+关注气泡+弹幕输入+六图标带计数）；清晰度切换 html5 优先+失败回退；UP主粉丝/投稿数真实获取、气泡关注（只是关注/特别关注/设置分组）、点头像进空间页；续播乱跳修复、返回记忆推荐位置
- [✅] 迭代② 搜索与卡片：搜索两层改版（搜索栏+热搜榜+历史 / 排序筛选+推荐流样式结果卡）；UP主卡片改版（LV徽章后置/直播头像红框+开播标记/关注气泡三选项）；推荐/热门/搜索卡片 UP主名称旁"已关注"标志（登录拉取关注列表，mid 优先昵称兜底）；材质加厚厚毛玻璃
- [✅] 迭代③ 侧边栏与稳定性：侧边栏滑动过渡、头像单击登出（气泡提示"已成功登出"）/长按换封面、LV徽章点击弹等级成长详情、B币/硬币行；相关视频入口闪退修复（推荐流位置记忆越界守卫）；互动回显与作者信息必经化（loadVideoContext）；竖屏化照官方样式重做（底栏浮层/视频真居中/控制条贴底联动显隐）；横屏 qp 并入控制条；收藏 csrf 补全与面板兜底；直播中标记批量校准；底栏材质回退浅色毛玻璃
- [✅] 迭代④ 手势系统多轮重构：单击切换控制条（显式 TapGesture，修复 onClick/Pan 抢占）；全向 Pan 拆分为水平快进快退（HUD 目标时间/总时长）+垂直左右半屏亮度/音量；双击暂停/播放恢复（多计数互斥）；长按 2 倍速快进（SDK 无 onActionStart，改 repeat 连续触发+首帧加速/末帧恢复）；竖屏化默认无控制条、上滑切视频且连播保持竖屏化；播放模式设置（单集循环/随机连播）底部面板、我的收藏页（收藏夹切换+点击播放）、横屏 home 一键回首页
- [✅] 迭代⑤ 推荐流与竖屏化收尾：竖屏单击出控制条修复（竖屏面补 Tap 链/横屏去重复链）；快扫（≥600vp/s）切视频与慢拖亮度/音量并存、下滑回退上一个；详情页底部推荐改为当前视频的相似视频（archive/related，排除看过的含未看完、过滤词、去重）；竖屏化上滑/随机连播/播完推荐改"全网真随机"（推荐接口独立游标池，播一部补一批）；竖屏 UP名后 LV 等级徽章、面板设置图标、弹幕开关 dm/dmg 与详情页逻辑一致
- [✅] 迭代⑥ 侧边栏与清晰度终版：B币/硬币真实显示（nav wallet + myinfo coins，随会话持久化）；LV 等级弹窗重做（当前分段 + 分段内经验进度条与积分 + LV0-LV6 真实门槛 200/1500/4500/9000/28000/108000 + 当前段高亮）并修复不弹出；清晰度改 B站新命名（自动/清晰360P/标清480P/准高清720P/高清1080P）、弹窗加"自动"、每次播放前重读默认清晰度（设置修改即时同步）、1080P 静默降级修复（WBI 通道优先）+ 降级提示；长按倍速 HUD 仅提示一次
- [ ] 评估项：深色模式适配、直播间弹幕（WebSocket）、番剧追番 #10512


### Pilihos V1.0.4
- [✅] 搜索页独立化，支持历史记忆与分类搜索（视频/UP主/番剧/影视） #1041
- [✅] 热门/直播/番剧/动态页签接入真实数据，新增热门/直播/番剧详情页 #1042
- [✅] 动态页功能化：图文/转发/互动数据完整展示，评论图标直达视频评论区 #1043
- [✅] 评论区改版：LV徽章、楼中楼展开、回复入口 #1044
- [✅] 直播分区：我的关注（横滑卡片）/推荐直播/相关直播，支持 HLS 直播流播放 #1045
- [✅] 播放区比例自适应视频尺寸（含 9:16 竖屏） #1046
- [✅] 竖屏化：downput 单击切换、长按拖拽分界，16:9 上下黑边居中 + qp 横屏入口，横屏 qp 返回 #1047
- [✅] 播放控件默认隐藏、触摸唤起；播完黑屏居中推荐 #1048
- [✅] 横竖屏/竖屏化切换自动续播 #1049
- [✅] 视频卡片竖屏标记（设置-外观可开关） #10410
- [✅] 视频/弹幕过滤词（设置-播放器，多行编辑实时生效） #10411
- [✅] 底部栏常驻开关（滚动隐藏/回弹弹出）、计数规则优化、时间显示修复、版块内容缓存 #10412


### Pilihos V1.0.3
- [✅] 加入设置-系统特性-API26高级特性-沉浸光感强度 #1031
- [✅] 适配API24,自动降级材质 #1031
- [✅] 加入动态基础布局 #1031
- [✅] 加入二级播放页评论区基本样式 #1033
- [✅] 尝试修复视频无法播放的问题 #1036
- [✅] 添加顶部栏合并/独立样式及其设置功能项 #1034
- [✅] 添加二级播放页对视频的进度条、弹幕，选集，倍速，全屏。字幕基础样式 #1034
- [✅] 修复底部栏出现的模糊、被遮盖问题。 #1035
- [✅] 加入搜索页基础样式，设置内添加搜索记忆常驻功能 #1036（于 V1.0.4 完成）
- [✅] 添加视频播放完毕后自动推荐视频功能 #1036
  

### Pilihos V1.0.2
> 全局
- [✅] 关于页细化，添加脚注 #1021
- [✅] 登录状态存续，可持续化 #1021
- [✅] 首页视频推荐优化推荐流，加入即时刷新功能 #1022
- [✅] 加入滑动底部自动加载更多内容 #1022
- [✅] 尝试适配沉浸光感（现阶段已全部适配） #1024
- [✅] 加入直播/热门/动态/番剧页面的占位方便测试 #1025

> 设置
- [✅] 布局更改，增加详细子界面控制 #1023
- [✅] 播放器内添加首页刷新保留选项 #1023
- [✅] 外观添加迷你栏互换功能 #1023
- [✅] 设置卡片全部取消垂直居中 #1023

> 底部栏更改
- [✅] 布局改为 迷你（搜索）+页签（主控）+迷你（功能） #1024


### Pilihos V1.0.1
1. 首页顶部-整体样式：头像 直播-推荐-热门 消息，五个内容均采用气泡按钮，方便后期适配沉浸光感
- [✅] 将首页顶部的搜索栏暂行删除（会移动到其他位置而不是去除功能），把最右侧的头像图标水平移动到最左侧。 #1011
- [✅] 将下方的直播、推荐、热门上移至头像图标的右侧，和头像图标、消息图标水平一行，采用华为的气泡按钮，代码如下：#1011
```
  - @Entry
  @Component
  struct ButtonExample {
  build() {
  Flex({ direction: FlexDirection.Column, alignItems: ItemAlign.Start, justifyContent: FlexAlign.SpaceBetween }) {
  Text('Rounded rectangle button with rounded corners by default.').fontSize(9).fontColor(0xCCCCCC)
  Flex({ alignItems: ItemAlign.Center, justifyContent: FlexAlign.SpaceBetween }) {
  Button('Rounded rectangle')
  .type(ButtonType.ROUNDED_RECTANGLE) // 设置按钮类型为圆角矩形
  .backgroundColor(0x317aff)
  .controlSize(ControlSize.NORMAL)
  .width(180)
  }
  Text('Rounded rectangle button configured with a borderRadius of 5.').fontSize(9).fontColor(0xCCCCCC)
  Flex({ alignItems: ItemAlign.Center, justifyContent: FlexAlign.SpaceBetween }) {
  Button('Rounded rectangle')
  .type(ButtonType.ROUNDED_RECTANGLE)
  .backgroundColor(0x317aff)
  .controlSize(ControlSize.NORMAL)
  .width(180)
  .borderRadius(5)
  }
  Text('Rounded rectangle button configured extra long text.').fontSize(9).fontColor(0xCCCCCC)
  Flex({ alignItems: ItemAlign.Center, justifyContent: FlexAlign.SpaceBetween }) {
  Button('Rounded rectangle Rounded rectangle Rounded rectangle Rounded rectangle')
  .type(ButtonType.ROUNDED_RECTANGLE)
  .backgroundColor(0x317aff)
  .width(180)
  .labelStyle({overflow:TextOverflow.Ellipsis, maxLines:3, minFontSize: 0})
  }
  }.height(400).padding({ left: 35, right: 35, top: 35 })
  }
  }
```

2. 底部栏-整体样式：动态-首页-番剧 |搜索。
   参考文章https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-hds-tabs-bar-floating
- [✅] 采用页签栏+迷你栏的样式。页签栏：动态、首页、番剧。迷你栏：搜索 #1011
- [✅] 页签栏修改版块入口顺序 #1011
- [✅] 对应逻辑 #1012
- [✅] 用户点击迷你栏后自动向最上方移动并固定，下方键盘会自动弹出，被键盘与上方的搜索栏 遮盖的下方内容呈半透明化。#1013
- [✅] 改基础部件为气泡按钮 #1012

3. 顶部左侧头像图标：侧边栏-我的
- [✅] 点击首页-左上角的用户头像，自动向右展开全屏侧边栏 #1011
- [✅] 我的侧边栏添加顶部图片,添加点击调用系统文件选择器选取图片 #1012
- [✅] 改陈列式内容布局为3*2卡片式布局 #1012
- [✅] 个人信息区域整体上移,半遮盖顶部区域 #1013
- [✅] 个人信息区域完善,添加等级徽章/个性签名/UID/IP归属 #1013
- [✅] 解决进入我的侧边栏无法返回上一页的问题,并添加系统手势导航 #1015

4. 顶部右上角消息图标：侧边栏-消息
- [✅] 同”我的“侧边栏样式，点击`消息图标`后，侧边栏向左展开全屏悬浮窗 #1011
- [✅] 图标全部替换,文本大小统一 #1012
- [✅] 底部栏整体下移 #1013
- [✅] 解决进入我的侧边栏无法返回上一页的问题,并添加系统手势导航 #1015

5. 二级播放页
- [✅] 改返回图标为`left` #1012
- [✅] 简介/评论分布左侧,`down`图标居中,弹幕编辑框最右侧 #1013
- [✅] 加入传统简介区六大功能图标 #1013
- [✅] 加入过长简介自动收缩一键展开功能 #1014
- [✅] 解决展开简介BV号显示错误问题,添加视频发布日期显示 #1014
- [✅] 解决首页/二级播放页底部推荐视频不显示发布日期的问题 #1015

6. 我的-设置-关于
- [✅] 完成基础样式布局 #1016
- [✅] 完善基础布局,添加弹窗提示和外链打开(多行文本) #1016

### Pilihos V1.0.0
- [✅] 创建项目结构，请求调试证书，进行签名 #1001
- [✅] 对Piliplus基本布局样式进行模仿，用arkts进行重构 #1001
- [✅] 完成首页、动态、我的基础布局，采用底部独立悬浮窗 #1002
- [✅] 首页-推荐，两列卡片布局完成，点击后二级播放界面样式完成 #1002
- [✅] 推荐页卡片封面可显示，数据可获取，修复对应错误 #1003
- [✅] 主体已经延伸到系统区域，“沉浸背景”和“内容避让”分开，但二级播放页顶部不做改变 #1004
- [✅] 添加模块缺少的系统 `Home`启动声明，防止设备误启动`AppDetailAbility`，导致软件重启进入设置页 #1005
- [✅] 修改首页视频卡片加载和显示模式，解决因过量加载引起的软件崩溃 #1005

