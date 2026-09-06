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


### Pilihos V1.0.5（当前版本号 1.0.6.4 · 真机反馈迭代）

> 主线：播放体验补全 + 互动能力落地；并行：架构还债与稳定性

- [✅] 真机反馈批次 5（1.0.6.4）
  - 共同根因修复：互动回显/作者信息挂在 loadVideoDetail，而它对已带详情的视频（搜索/相关跳转）直接短路——新增 loadVideoContext 走 openVideoDetail 必经路径，点赞/收藏回显、作者关注态、粉丝数、投稿数全部生效；patchCurrentVideo 改不可变替换，乐观高亮与计数立即刷新
  - 竖屏化底栏照官方样式重做：半透明圆角浮层贴视频底部（头像+UP名+粉丝数+粉色关注胶囊+收起按钮、简介一行、弹幕输入+点赞/投币/收藏/评论四图标带计数），点收起按钮折叠为紧凑条
  - 简介/面板点 UP主头像可进空间页（authorMid 缺失时自动补详情解析）
  - 收藏夹面板：去掉右上角 X（与新建图标重叠），空列表时提示重新登录；收藏 deal 补 csrf_token
  - 搜索：首层内容从顶部排列（取消居中）；"清空"紧邻"搜索历史"右侧；直播中标记改用 get_status_info_by_uids 批量校验真实开播状态（room_id 有值≠开播）
  - 侧边栏：头像加大至 104 并撑满右侧四行高度；LV 徽章与头像长按改用手势实现（此前点击冲突导致弹窗不出现）
  - 首页底栏/顶栏页签材质改深色毛玻璃（参考点赞提示气泡），文字改浅色

- [✅] 真机反馈批次 4（1.0.6.3）
  - 闪退修复：详情页点相关视频必崩——推荐流位置记忆在首页 Grid 已卸载时仍读取 currentOffset()（undefined.yOffset），加可见性守卫与容错
  - 竖屏化布局：视频按自身比例居中，播放控制条覆盖视频最底部（不再悬在黑区），弹幕输入/图标提亮可辨
  - 横屏：右下角独立 qp 圆钮移除，qp 并入底部控制条（横屏时即为返回竖屏入口）
  - 简介区：UP主粉丝数走 card 接口、投稿数走 WBI 投稿列表 total（此前 card 无投稿数字段导致一直占位）
  - 收藏：deal 接口补 csrf_token；收藏夹面板拉取失败也会打开（内显空列表），长按不再无响应
  - 分享改用系统分享面板（ShareKit SharedData+show），不再拉起浏览器
  - 弹幕发送：非 JSON 响应容错解析并回显片段；简介区弹幕输入回车即发（原有）
  - 侧边栏：改为头像本体单击（未登录→登录/已登录→登出）与长按（换头像），修复点 LV 徽章误触发登出导致弹窗看不到的问题；过渡动画加强（320ms 左滑+淡入）；新增 B币/硬币行（硬币走 coin/log 接口）

- [✅] 真机反馈批次 3（1.0.6.0 → 1.0.6.2）
  - 播放页重点：简介区顶栏新增"设置"子页（空白页），评论不显示数字；简介/评论/设置支持左右滑动切换；进入视频"乱跳位置"修复（清掉上一支视频遗留的续播位置）
  - 六图标交互：点赞乐观更新（即时高亮，点赞/收藏显示统计数，接口失败回滚）；投币暂缓（提示即将接入）；收藏单击进默认夹、长按弹出收藏夹面板（3列宫格+右上新建图标）；再看静默添加；分享走系统
  - 竖屏化：取消常驻横屏图标，黑区默认显示 UP主头像+关注气泡+弹幕输入+六图标，点击视频区唤起播放控制；横屏：底部qp返回竖屏修复（此前无响应）、选集菜单横屏可用、隐藏重复qp工具
  - 清晰度切换：优先走 html5 DURL 通道（更稳定），切换失败自动回退默认清晰度重试
  - 简介区：UP主粉丝数/投稿数真实显示（card 接口），点击进入 UP主空间页；关注按钮改气泡样式（lista图标），首次关注弹出"只是关注/特别关注/设置分组"
  - 搜索大改：两层结构——第一层搜索栏+热搜榜+历史记录，回车进入第二层（排序筛选+结果）；结果视频卡片照搬推荐流样式（双列）；UP主卡片改版（LV徽章后置、直播头像红框+直播中标记、关注气泡+三选项弹窗）
  - 综合：推荐/热门/搜索卡片 UP主名称旁"已关注"标志（登录后拉取关注列表，mid优先/昵称兜底）；返回推荐页记忆滚动位置；材质加厚为 COMPONENT_THICK 厚毛玻璃（参考系统弹窗）
  - 侧边栏：展开/收起滑动+淡入过渡；去除右上角 jinxin_right 图标；头像单击未登录进登录页、已登录直接登出（气泡提示"已成功登出"），长按头像换封面（试行）；点击 LV 徽章弹出 LV0-LV6 等级成长详情弹窗（当前升级进度+各级所需经验+获取方式）
- [✅] 直播：清晰度/线路切换（accept_qn），关注主播按钮 #1058
  - LiveService.loadPlayUrlEx：按 qn 请求直播流，回传 g_qn_desc 清晰度列表、url_info 线路数与主播 mid
  - 播放区右下角"清晰度/线路"菜单（当前项高亮），切换即重取流；信息行新增关注按钮（/x/relation/modify，attribute 回显已关注状态）
- [✅] UP主空间页：搜索结果点 UP 主进入主页（投稿列表/粉丝信息/关注按钮） #1057
  - 新增 pages/UserSpace：/x/web-interface/card 资料（粉丝/获赞/等级/签名）+ WBI 签名 /x/space/wbi/arc/search 投稿列表（分页 25 条）
  - 关注按钮 /x/relation/modify；点投稿带 pilihosPlayback 参数返回 Index 播放（与搜索回跳同链路）
- [✅] 搜索：分类页签接入真实排序参数（默认排序/播放多/新发布等） #10511
  - SearchService.search 增 order 参数（click/pubdate/dm，仅 video 类生效，WBI 与旧接口同透传）
  - 搜索结果上方排序条（当前项高亮），切换即时重搜
- [✅] 互动：详情页点赞/投币/收藏/再看接真实接口并回显状态（cookie+csrf） #1055
  - 新增 services/InteractionService：like/coin_add/fav resource deal（默认收藏夹）/toview add；BiliHttpClient 增通用 postForm
  - VideoItem 增 liked/coined/favored；详情加载后经 archive/detail req_user 回显，按钮高亮（点赞红/收藏橙），计数联动；未登录操作 toast 引导
- [✅] 互动：评论发布入口接 /x/v2/reply/add，评论点赞 #1056
  - 评论输入栏"发送"为真实发布，成功后清空并刷新评论区；评论点赞 /x/v2/reply/action，红心高亮与计数联动（登录后加载时按 action 字段回显）
- [✅] 真机修复批次 2（1.0.5.6）
  - 闪退：点击视频进入二级页即闪退——qualityMenuVisible 在宿主仍是 @State 而播放器组件用 @Consume 引用，找不到 @Provide 祖先导致组件树创建即崩溃；改为 @Provide，并重跑全量 Consume/Provide 配对审计通过 #真机反馈4
  - 材质：真机 uiMaterial 系统材质渲染不出"光感"只剩半透明——31 处 systemMaterial 统一替换为 backgroundBlurStyle(COMPONENT_THIN + LIGHT) 真毛玻璃，白色底衬降为 32%-45% 仅轻度提亮 #真机反馈4
  - 搜索：键入关键词"不显示结果"的根因是历史面板的 Grid 未设高度、按可滚动容器默认占满整列，把结果区压成 0 高度（搜索实际成功、关键词进历史）；Grid 改为按内容高度的 Flex 流式布局，结果正常显示在历史下方 #真机反馈4
- [✅] 真机修复批次 1（1.0.5.5）
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

