## Pilihos更新日志
1. 版本号位于`setting.ets`499-410
2. [沉浸光感参考](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-immersive-light-sense)
3. [加载参考](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ts-basic-components-loadingprogress)
4. [新事件标记](https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/badge-0000001929816016)
5. [分段按钮](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ohos-arkui-advanced-segmentbutton#%E7%A4%BA%E4%BE%8B1%E8%AE%BE%E7%BD%AE%E5%88%86%E6%AE%B5%E6%8C%89%E9%92%AE%E7%9A%84%E7%B1%BB%E5%9E%8B)
6. [指向型菜单](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ts-universal-attributes-menu#%E7%A4%BA%E4%BE%8B4%E5%8F%B3%E9%94%AE%E5%BC%B9%E5%87%BA%E6%8C%87%E5%90%91%E5%9E%8B%E8%8F%9C%E5%8D%95)
7. [setAVMetadata](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/avsession-access-scene)
8. [即时反馈气泡](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/arkts-apis-uicontext-promptaction#showtoast)
9. [文本框](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ts-basic-components-textinput)


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


### Pilihos V1.0.5（当前版本号 1.0.5.5）

> 主线：播放体验补全 + 互动能力落地；并行：架构还债与稳定性

- [✅] 真机修复批次（1.0.5.5）
  - 沉浸材质：API26 上 THIN/ULTRA_THIN 过薄且 fallbackBackground 全透明，底部栏/设置卡片等只剩文本不可见——材质统一降为 REGULAR 模糊亚克力，并保留约 50%-72% 白色底衬保证可见 #真机反馈1
  - 搜索：移除右侧搜索图标（与回车同链路且在真机上无效）；回车链路加固——onSubmit 的 value 为空时回退到输入状态值，两者皆空时 toast"请输入搜索关键词"，失败 toast 保留错误详情，提交时输出日志 #真机反馈2
  - 播放器：进入视频后控制条 2 秒自动隐藏（原先打开后无隐藏定时器，常驻到手动点击）；用户点击唤起后仍走 4 秒周期 #真机反馈3
- [✅] 播放器：手势体系——左右半屏上下滑调亮度/音量、水平滑快进快退、双击暂停 #1053
  - 横竖屏播放画面统一挂载 PanGesture：水平滑按预览进度抬手 seek（HUD 显示目标/起点时间），左半屏上下滑调系统亮度（返回时还原），右半屏上下滑调媒体音量（0-15）
  - 双击暂停/播放；手势 HUD 居中提示，自动隐藏
- [✅] 弹幕：拉取弹幕流并按时间轴渲染，弹幕过滤词正式接入，支持发送弹幕（csrf） #1054
  - services/DanmakuService：comment.bilibili.com/{cid}.xml 拉流，正则解析 d 标签（时间/模式/颜色/文本），实体转义还原
  - components/DanmakuOverlay：Canvas 逐帧渲染（33ms tick），弹道分配防重叠，顶部/底部弹幕 4s 停留；seek 跳变清空重定位，暂停冻结，倍速联动
  - 1.0.4 已存弹幕过滤词在解析阶段生效；发送走 /x/v2/reply/dm（SESSDATA+bili_jct），详情页弹幕输入框回车即发，成功后清空并 toast
  - 横竖屏播放画面均已挂载弹幕层，随 dmg 开关显隐
- [✅] 播放器：清晰度切换（列出 accept_quality，切换续播），播放质量默认值设置生效 #1051
  - PlaybackService.resolveWithQuality：指定 qn 走 WBI playurl 请求对应 DURL，回传 accept_quality/accept_description 供菜单展示，失败回退原兼容流程
  - 播放控制条新增"清晰度"菜单（当前清晰度高亮），切换时记录进度，新流 prepared 后自动续播（复用 pendingResumeMs）
  - 设置-播放器"播放质量"改为真实选项：自动/1080P/720P/480P/360P 循环切换，存 pilihos_player/default_quality
- [✅] 播放器：播放记忆——退出视频记录 aid+进度，再次进入自动续播并提示 #1052
  - utils/PlaybackMemory：aid→进度表（上限 300 条，JSON 落盘 pilihos_player/playback_progress）
  - 返回退出、切换相关/推荐视频时保存（>5s 才记）；再次进入恢复进度并 toast 提示，已看完的视频从头播放
- [✅] 架构：Index.ets 拆分（播放器/详情页/侧边栏/信息流独立组件，目标 <800 行） #10510
  - Index.ets 2554 → 741 行；业务逻辑与全局状态（@Provide）仍集中于 Index，界面区块拆至 components/
  - 新增组件：HomeTab（首页头部+信息流+版块切换）、HomeBottomBar/HomeActionMenu（底部栏+悬浮球+操作菜单）、Sidebars（我的/消息侧边栏）、LoginViews（登录/官方网页登录）、PlayerScreen（横竖屏播放画面+Video 事件）、PlayerOverlay（播放控制条+播完推荐）、DetailScreen（简介/评论区详情页）
  - 新增工具：FormatUtils（计数/时间/等级色等纯函数）、CommonBuilders（全局 loadingIndicator）
  - 清理不可达的 XComponent 时代播放器服务代码（playerService 回调链、surface 占位状态），实际播放走 Video 组件事件
  - 行为统一：首页卡片点击改走 openVideoDetail，不再遗留上一视频的评论区页签状态
- [✅] 稳定性（部分）：buvid3 持久化——首次生成后落盘 pilihos_client/buvid3，后续启动复用，降低 -412/-352 风控概率 #1059
  - 搜索回车真机问题闭环仍待用户回报 toast 错误码后定位
- [ ] 互动：详情页点赞/投币/收藏/再看接真实接口并回显状态（cookie+csrf） #1055
- [ ] 互动：评论发布入口接 /x/v2/reply/add，评论点赞 #1056
- [ ] UP主空间页：搜索结果点 UP 主进入主页（投稿列表/粉丝信息/关注按钮） #1057
- [ ] 直播：清晰度/线路切换（accept_qn），关注主播按钮 #1058
- [ ] 搜索：分类页签接入真实排序参数（默认排序/播放多/新发布等） #10511
- [ ] 评估项：深色模式适配、直播间弹幕（WebSocket）、番剧追番 #10512


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

