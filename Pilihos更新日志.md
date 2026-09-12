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
10. [状态按钮](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ts-basic-components-toggle)
11. [新事件标记](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/ts-container-badge#%E5%AD%90%E7%BB%84%E4%BB%B6)

### Pilihos V1.0.8
> 启动
- [✅] 开屏动画：Logo 卡片 + Pilihos 应用名 + 加载指示 + 底部"Pilihos By YuQi"署名，淡入停留后淡出进入主页 #1080
> 我的-侧边栏
- [✅] 观看记录页：/x/v2/history 分页加载，条目含封面/时长/UP主/观看时间与观看进度，点击进入详情播放 #1081
- [✅] 稍后再看页：/x/v2/history/watchlater 列表展示与点击播放 #1081
- [✅] 离线缓存入口点击提示待适配 #1081

### Pilihos V1.0.7
> 主线：底部导航沉浸光感重构 + 消息体系全链路 + UP主页改版 + 播放体验打磨
> 底部导航（沉浸光感）
- [✅] 底栏重构为 HdsTabs（IMMERSIVE/EXQUISITE 系统真材质），收起态 miniBar 搜索入口、展开态 动态/首页/热门 三页签，
贴底定位随滚动显隐，页签高亮与内容页联动
> 首页
- [✅] 顶栏三段式：我的头像 + 整条搜索栏 + 消息入口；首页背景改 #F5F7F9 纯色；移除左右迷你球与浮动菜单组件
- [✅] 视频卡片快捷操作悬浮菜单（自绘 overlay 锚点定位，可正常交互），入口图标 lista
- [✅] 搜索联想词（默认关）：键入关键词在搜索栏下方展开联想条目，点击直接搜索
> 消息
- [✅] 消息独立子页面：回复/@我/收到的赞/私信四通道真实数据，未读角标采用 Badge 新事件标记，私信头像昵称经 im_user_infos 补全
- [✅] 消息行重排版：用户名+动作后缀/正文黑体/原评论灰字/日期(MM/DD)+快捷点赞+快捷回复；回复与@我跳转自动展开目标楼层折叠回复；返回恢复消息页
- [✅] 私信聊天页：气泡消息流（超5分钟时间分隔、自动定位最新）、B站表情真实渲染、文本发送（web_im/send）、键盘动态避让、表情面板单击空白关闭
- [✅] 聊天设置视图：对方资料卡（点头像进主页）、置顶聊天/消息免打扰/加入黑名单占位开关、删除聊天（remove_session）、举报入口
> 侧边栏与收藏
- [✅] 我的/消息侧边栏贴屏边滑入；消息版块改独立子页，返回主页不再触发推荐流刷新（跳转快照/恢复机制）
- [✅] 观看记录页（/x/v2/history 分页）：封面/时长/UP主/观看进度（看到 xx:xx 或已看完），点击进入详情播放
- [✅] 稍后再看页（/x/v2/history/watchlater）：列表展示与点击播放；离线缓存入口提示待适配
- [✅] 收藏夹真实列表（WBI created/list 主路径 + rid favoured 合并 + 降级链），
加入/直接取消收藏（11010 水合重试）、新建收藏夹（folder/add）、删除模式勾选批量删除（folder/del）
> 视频区
- [✅] 沉浸材质策略管理器：API26+ 真材质/其余半透明降级双路径；快捷菜单弹层化修复挤压与交互
- [✅] 竖屏化重排：视频底部与弹幕输入行对齐、控制条随动、进度条蓝色、点赞白/红配色；普通区设置与竖屏化设置面板完全一致（Toggle 状态按钮）
- [✅] 横竖屏切换进度不重置（prepared 不清空续播位置）；打断接续（切后台回前台自动续播）；无UI进度条显示开关
- [✅] 分享重做：SharedData 改 uri 链接形态（QQ/WX 可达）+ 文本形态回退；分享入多级菜单（预览头+系统分享+复制链接，长按蒙层）
> UP 主页
- [✅] 按官方样式重做：横幅浮标、头像压横幅、粉丝/关注/获赞真实统计、私信+关注双按钮（自己的主页隐藏）、主页/动态/投稿三 tab 上滑吸顶
- [✅] 真实关注状态（attribute 2=已关注/6=互相关注 + /x/relation 确认）、大会员/年度大会员标识、主页内搜索 UP 投稿、更多菜单（分享主页/进入黑屋/举报用户）
- [✅] 动态 tab 展示该 UP 的动态（space_history，视频动态可跳详情），动态卡片点赞/分享接线
> 评论互动
- [✅] 表情面板与评论 [表情] 真实渲染；本地评论屏蔽；@用户蓝色超链接（content.members 映射）；
键入 @ 弹出联系人选择面板（mention/search）；楼中楼回复功能与"A 回复 @B"展示；评论区头像/昵称点击进空间
> 设置与架构
- [✅] 设置页修复（返回失效/悬浮窗子项展开）与样式统一（Toggle/关于页）；播放器设置：默认清晰度/长按倍速/偏好设置组
- [✅] 架构：VideoPreloader 预加载、Logger、PlayerSettingsService、viewmodels 分层、设置页组件化

### Pilihos V1.0.6
> 设置
- [✅] 引用开源设置页面并加以私有化样式改造 #1061
- [✅] 改变设置卡片布局，优化先关内容设置 #1061
- [✅] 取消LV点击明示弹窗，修复和设置交互的冲突 #1061
- [✅] 去除设置-外观-顶栏合并向 ￥1062
- [✅] 增加一键登出功能 #1063
> 主页
- [✅] 改变顶栏年内容为搜索栏 #1062
- [✅] 改左侧迷你栏为源顶部栏内容 #1062
> 视频区
- [✅]修复双击不可暂停 #1064
- [✅]修复上下滑动切换视频与音量/亮度加减的区域判定重复问题 #1064
- [✅]视频区-设置，增加弹幕设置 #1066
- [✅]评论区添加即时刷新功能 #1066
- [✅]修复底部区域推荐商品无法正常跳转播放
> 我的-侧边栏
- [✅]添加LV等级徽章等级明示弹窗 #1065
- [✅]添加一键跳转官网编辑个人资料 #1065
- [✅]内容区下移，避免与顶部图片区交互逻辑重复 #1065
- [✅]修改顶部图片更换入口，集成到LV等级详情页面 #1066
> 整改
- [✅]拆分index.sts,使其组件化，分别控制对应的组件 #1067
- [✅]优化视频播放、切换不同模式的使用体验，减少卡顿感 #1067
- [✅]加入视频预加载，减少视频播放等待时间 #1067



### Pilihos V1.0.5
> 主线：播放体验补全 + 互动能力落地；并行：架构还债与稳定性
- [✅] 1.0.5.9 直播：清晰度/线路切换（accept_qn 清晰度列表 + url_info 多线路，切换即重取流），信息行关注主播并回显已关注 #1058
- [✅] 1.0.5.8 UP主空间页：card 资料（粉丝/获赞/等级/签名）+ WBI 投稿列表（分页），关注按钮，
点投稿回 App 播放；搜索分类页签接入真实排序参数（播放多/新发布等，切换即时重搜） #1057 #10511
- [✅] 1.0.5.7 互动：详情页点赞/投币/收藏/再看接真实接口（cookie+csrf）并回显高亮与计数；
评论发布 /x/v2/reply/add 与评论点赞 /x/v2/reply/action #1055 #1056
- [✅] 1.0.5.6 进二级页闪退（qualityMenuVisible 补 @Provide）、31 处材质改真机毛玻璃 backgroundBlurStyle、搜索历史 Grid 占满整列压没结果区修复
- [✅] 1.0.5.5 材质过薄卡片不可见（降 REGULAR + 白色底衬）、搜索回车链路加固（去右侧无效按钮、空词 toast）、进视频控制条 2 秒自动隐藏
- [✅] 1.0.5.4 播放手势体系：左右半屏上下滑调亮度/音量（返回还原）、水平滑快进快退（HUD 预览时间）、双击暂停/播放 #1053
- [✅] 1.0.5.3 弹幕：XML 拉流解析 + Canvas 时间轴渲染（弹道分配防重叠/seek 重定位/暂停冻结/倍速联动），过滤词接入，发送弹幕（csrf） #1054
- [✅] 1.0.5.2 播放器：清晰度切换菜单（切换续播）+ 默认质量设置生效；播放记忆续播（aid+进度落盘，重进提示恢复）；
buvid3 持久化降低 -412/-352 风控 #1051 #1052 #1059
- [✅] 1.0.5.1 架构还债：Index.ets 组件化拆分，清理 XComponent 时代死代码 #10510



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

