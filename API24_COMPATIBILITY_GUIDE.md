# Pilihos API 24 适配指南

## 适配策略概述

将项目从 API 26 适配到 API 24，同时保留 API 26 特性的核心策略是：
1. **修改 SDK 版本配置**
2. **条件编译/运行时版本检查**
3. **提供 API 24 降级方案**

---

## 一、修改 SDK 版本配置

### 1.1 更新 build-profile.json5

```json5
// D:\HM\Harmony\Pilihos\build-profile.json5
{
  "app": {
    "products": [
      {
        "name": "default",
        "bundleName": "com.pilihos.player",
        "signingConfig": "default",
        "compatibleSdkVersion": "24.0.0",  // 改为 24.0.0
        "targetSdkVersion": "26.0.0",      // 保持 26.0.0 以使用新特性
        "runtimeOS": "HarmonyOS",
      }
    ]
  }
}
```

**说明**：
- `compatibleSdkVersion: "24.0.0"` - 允许在 API 24+ 设备上安装
- `targetSdkVersion: "26.0.0"` - 编译时仍可使用 API 26 特性

---

## 二、核心功能适配方案

### 2.1 沉浸式材质系统 (uiMaterial)

**问题**：`uiMaterial.ImmersiveMaterial` 是 API 26 全新功能

**解决方案**：修改 `ImmersiveMaterial.ets` 添加版本检查和降级

```typescript
// D:\HM\Harmony\Pilihos\entry\src\main\ets\utils\ImmersiveMaterial.ets
import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

/** 沉浸光感材质，支持 API 24+ 降级 */
export class ImmersiveMaterial {
  private static strength: number = 1;
  private static apiLevel: number = 0;

  /** 获取当前设备 API 版本 */
  private static getApiLevel(): number {
    if (ImmersiveMaterial.apiLevel === 0) {
      // deviceInfo.apiTargetVersion 返回设备支持的最高 API 版本
      ImmersiveMaterial.apiLevel = deviceInfo.apiTargetVersion;
    }
    return ImmersiveMaterial.apiLevel;
  }

  /** 检查是否支持 UI Material */
  static isSupported(): boolean {
    return ImmersiveMaterial.getApiLevel() >= 26;
  }

  static setStrength(value: number): void {
    ImmersiveMaterial.strength = Math.max(0, Math.min(2, value));
  }

  static thin(): uiMaterial.Material {
    // API 24/25 降级：返回空材质（透明背景）
    if (!ImmersiveMaterial.isSupported() || ImmersiveMaterial.strength === 0) {
      return uiMaterial.Material.empty;
    }
    return new uiMaterial.ImmersiveMaterial({
      style: ImmersiveMaterial.strength === 1
        ? uiMaterial.ImmersiveStyle.REGULAR
        : uiMaterial.ImmersiveStyle.THIN,
      colorInvert: true,
      applyShadow: true,
      interactive: true,
      lightEffect: { color: Color.White }
    });
  }

  static ultraThin(): uiMaterial.Material {
    if (!ImmersiveMaterial.isSupported() || ImmersiveMaterial.strength === 0) {
      return uiMaterial.Material.empty;
    }
    return new uiMaterial.ImmersiveMaterial({
      style: ImmersiveMaterial.strength === 1
        ? uiMaterial.ImmersiveStyle.REGULAR
        : uiMaterial.ImmersiveStyle.ULTRA_THIN,
      colorInvert: true,
      applyShadow: true,
      interactive: true,
      lightEffect: { color: Color.White }
    });
  }

  /** API 24/25 降级方案：返回半透明背景样式 */
  static fallbackBackground(opacity: number = 0.85): ResourceColor {
    if (ImmersiveMaterial.isSupported()) {
      return Color.Transparent;
    }
    // API 24/25 使用半透明白色背景模拟磨砂效果
    const alpha = Math.round(opacity * 255).toString(16).padStart(2, '0');
    return `#${alpha}FFFFFF`;
  }
}
```

### 2.2 视频播放器适配

**问题**：`media.createMediaSourceWithUrl()` 和 `player.setMediaSource()` 是 API 26 新增

**解决方案**：修改 `VideoPlayerService.ets` 添加版本分支

```typescript
// D:\HM\Harmony\Pilihos\entry\src\main\ets\services\VideoPlayerService.ets
import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BiliHttpClient } from './BiliHttpClient';
import { deviceInfo } from '@kit.BasicServicesKit';

export class VideoPlayerService {
  private player: media.AVPlayer | undefined;
  private currentState: media.AVPlayerState = 'idle';
  private lastError: string = '';
  private errorCallback: ((message: string) => void) | null = null;
  private generation: number = 0;

  /** 检查是否支持新的媒体源 API */
  private static isNewMediaApiSupported(): boolean {
    return deviceInfo.apiTargetVersion >= 26;
  }

  get state(): media.AVPlayerState {
    return this.currentState;
  }

  get errorMessage(): string {
    return this.lastError;
  }

  onError(callback: (message: string) => void): void {
    this.errorCallback = callback;
  }

  async prepare(url: string, surfaceId: string, referer: string, cookie: string = ''): Promise<void> {
    await this.release();
    const generation: number = this.generation;
    this.lastError = '';
    if (url === '' || surfaceId === '') {
      throw new Error('播放源或视频画布为空');
    }

    const player: media.AVPlayer = await media.createAVPlayer();
    this.player = player;

    // API 26+ 使用 reason 参数，API 24/25 不使用
    if (VideoPlayerService.isNewMediaApiSupported()) {
      player.on('stateChange', (state: media.AVPlayerState, reason: media.StateChangeReason): void => {
        if (generation !== this.generation || this.player !== player) return;
        this.currentState = state;
        console.info(`Pilihos AVPlayer state: ${state}, reason=${reason}`);
      });
    } else {
      player.on('stateChange', (state: media.AVPlayerState): void => {
        if (generation !== this.generation || this.player !== player) return;
        this.currentState = state;
        console.info(`Pilihos AVPlayer state: ${state}`);
      });
    }

    player.on('error', (error: BusinessError): void => {
      if (generation !== this.generation || this.player !== player) return;
      this.lastError = `${error.code} ${error.message}`;
      console.error(`Pilihos AVPlayer error: ${this.lastError}`);
      if (this.errorCallback !== null) {
        this.errorCallback(this.lastError);
      }
    });

    // API 26+ 使用 setMediaSource，API 24/25 使用 url 属性
    if (VideoPlayerService.isNewMediaApiSupported()) {
      const headers: Record<string, string> = {
        'User-Agent': BiliHttpClient.browserUserAgent,
        'Referer': referer === '' ? 'https://www.bilibili.com/' : referer,
        'Origin': 'https://www.bilibili.com'
      };
      if (cookie !== '') {
        headers['Cookie'] = cookie;
      }
      const source: media.MediaSource = media.createMediaSourceWithUrl(url, headers);
      await player.setMediaSource(source);
    } else {
      // API 24/25 降级方案：直接设置 URL（无法自定义 HTTP 头）
      player.url = url;
    }

    player.surfaceId = surfaceId;
    await player.prepare();

    try {
      const tracks: Array<media.MediaDescription> = await player.getTrackDescription();
      console.info(`Pilihos AVPlayer tracks: ${tracks.length}`);
    } catch (error) {
      console.warn(`Pilihos AVPlayer track inspection failed: ${String(error)}`);
    }
  }

  async play(): Promise<void> {
    if (this.player === undefined) {
      throw new Error('播放器尚未准备完成');
    }
    this.player.setVolume(1.0);
    await this.player.play();
  }

  async pause(): Promise<void> {
    if (this.player !== undefined && this.currentState === 'playing') {
      await this.player.pause();
    }
  }

  async release(): Promise<void> {
    this.generation += 1;
    const player: media.AVPlayer | undefined = this.player;
    this.player = undefined;
    this.currentState = 'idle';
    this.lastError = '';
    if (player !== undefined) {
      try {
        await player.release();
      } catch (error) {
        console.warn(`Pilihos AVPlayer release failed: ${String(error)}`);
      }
    }
  }
}
```

### 2.3 HUKS 会话式加解密适配

**问题**：`huks.initSession/updateSession/finishSession` 是 API 26 增强功能

**解决方案**：修改 `AuthService.ets` 添加版本检查

```typescript
// 在 AuthService.ets 中添加以下辅助方法

import { deviceInfo } from '@kit.BasicServicesKit';

export class AuthService {
  // ... 现有代码 ...

  /** 检查是否支持 HUKS 会话式 API */
  private static isHuksSessionSupported(): boolean {
    return deviceInfo.apiTargetVersion >= 26;
  }

  /** 加密数据 - 支持 API 24+ */
  private static async encryptData(data: Uint8Array): Promise<Uint8Array> {
    const alias = AuthService.secureKeyAlias;

    if (AuthService.isHuksSessionSupported()) {
      // API 26+ 使用会话式 API
      const session = await huks.initSession(alias, {
        cipherPurpose: huks.CipherPurpose.ENCRYPT,
        algorithm: huks.Algorithm.AES,
        blockMode: huks.BlockMode.GCM,
        padding: huks.Padding.NONE,
        purpose: huks.HuksPurpose.ENCRYPT
      });
      await huks.updateSession(session.handle, { inData: data });
      const result = await huks.finishSession(session.handle, { inData: new Uint8Array(0) });
      return result.outData;
    } else {
      // API 24/25 使用传统 API
      const options: huks.HuksOptions = {
        purpose: huks.HuksPurpose.ENCRYPT,
        algorithm: huks.Algorithm.AES,
        blockMode: huks.BlockMode.GCM,
        padding: huks.Padding.NONE
      };
      const result = await huks.encrypt(alias, data, options);
      return result.outData;
    }
  }

  /** 解密数据 - 支持 API 24+ */
  private static async decryptData(ciphertext: Uint8Array): Promise<Uint8Array> {
    const alias = AuthService.secureKeyAlias;

    if (AuthService.isHuksSessionSupported()) {
      // API 26+ 使用会话式 API
      const session = await huks.initSession(alias, {
        cipherPurpose: huks.CipherPurpose.DECRYPT,
        algorithm: huks.Algorithm.AES,
        blockMode: huks.BlockMode.GCM,
        padding: huks.Padding.NONE,
        purpose: huks.HuksPurpose.DECRYPT
      });
      await huks.updateSession(session.handle, { inData: ciphertext });
      const result = await huks.finishSession(session.handle, { inData: new Uint8Array(0) });
      return result.outData;
    } else {
      // API 24/25 使用传统 API
      const options: huks.HuksOptions = {
        purpose: huks.HuksPurpose.DECRYPT,
        algorithm: huks.Algorithm.AES,
        blockMode: huks.BlockMode.GCM,
        padding: huks.Padding.NONE
      };
      const result = await huks.decrypt(alias, ciphertext, options);
      return result.outData;
    }
  }
}
```

### 2.4 WebView Cookie 管理适配

**问题**：`WebCookieManager.fetchCookie()` 是 API 26 新增

**解决方案**：修改 `Index.ets` 中的 `syncWebLoginCookie` 方法

```typescript
// 在 Index.ets 中修改 syncWebLoginCookie 方法

import { deviceInfo } from '@kit.BasicServicesKit';

private async syncWebLoginCookie(): Promise<void> {
  if (!this.webLoginVisible) return;

  try {
    let cookie: string = '';

    if (deviceInfo.apiTargetVersion >= 26) {
      // API 26+ 使用 WebCookieManager
      cookie = await web_webview.WebCookieManager.fetchCookie('https://www.bilibili.com');
    } else {
      // API 24/25 降级：从 WebView 控件获取 Cookie
      try {
        cookie = await this.webController.getCookie('https://www.bilibili.com');
      } catch (e) {
        console.warn('Pilihos: getCookie fallback failed, trying evaluateJS');
        // 备用方案：通过 JS 执行获取
        cookie = await this.webController.executeJavaScript('document.cookie') as string;
      }
    }

    if (cookie === '' || !cookie.includes('SESSDATA=')) return;

    const session: AuthSession = await AuthService.validateCookie(cookie, this.context);
    this.authSession = session;
    this.loginNotice = '登录成功，欢迎 ' + session.name;
    this.webLoginStatus = '登录成功';
    this.webLoginVisible = false;
    this.closeLoginPage();
  } catch (error) {
    this.webLoginStatus = '等待官方登录完成';
    console.error('Pilihos web login cookie sync failed: ' + String(error));
  }
}
```

### 2.5 其他 API 26 特性降级

#### SegmentButton 组件
```typescript
// Settings.ets 中的 SegmentButton 需要条件渲染
import { deviceInfo } from '@kit.BasicServicesKit';

// 替换 SegmentButton 为普通按钮组（API 24/25 降级）
if (deviceInfo.apiTargetVersion >= 26) {
  // 使用 SegmentButton
  SegmentButton({ ... })
} else {
  // API 24/25 降级：使用 Row + Button 组合
  Row({ space: 8 }) {
    Button('弱')
      .type(ButtonType.ROUNDED_RECTANGLE)
      .backgroundColor(this.immersiveStrength === 0 ? '#1677A8' : '#F1F3F5')
      .onClick(() => { this.setImmersiveStrength(0); })
    Button('中')
      .type(ButtonType.ROUNDED_RECTANGLE)
      .backgroundColor(this.immersiveStrength === 1 ? '#1677A8' : '#F1F3F5')
      .onClick(() => { this.setImmersiveStrength(1); })
    Button('强')
      .type(ButtonType.ROUNDED_RECTANGLE)
      .backgroundColor(this.immersiveStrength === 2 ? '#1677A8' : '#F1F3F5')
      .onClick(() => { this.setImmersiveStrength(2); })
  }
}
```

#### ControlSize 枚举
```typescript
// API 24/25 不支持 ControlSize，直接移除该属性
if (deviceInfo.apiTargetVersion >= 26) {
  Button(label)
    .controlSize(ControlSize.NORMAL)
    // ...
} else {
  Button(label)
    // 不使用 controlSize
    // ...
}
```

#### expandSafeArea 数组语法
```typescript
// API 24/25 使用旧版语法
if (deviceInfo.apiTargetVersion >= 26) {
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
} else {
  .expandSafeArea(SafeAreaType.SYSTEM, SafeAreaEdge.TOP | SafeAreaEdge.BOTTOM)
}
```

#### Search.defaultFocus
```typescript
// API 24/25 不支持 defaultFocus，移除该属性
if (deviceInfo.apiTargetVersion >= 26) {
  Search({ ... })
    .defaultFocus(true)
} else {
  Search({ ... })
    // 不使用 defaultFocus
}
```

---

## 三、module.json5 配置调整

```json5
// D:\HM\Harmony\Pilihos\entry\src\main\module.json5
{
  "module": {
    // ... 其他配置保持不变 ...

    // 条件性元数据声明
    "metadata": [
      // API 26+ 才启用 UI Material
      // 注意：此处无法条件编译，需要在代码中动态检查
      {
        "name": "ohos.arkui.UIMaterial.state",
        "value": "enable"
      }
    ]
  }
}
```

**注意**：`module.json5` 不支持条件编译，但声明 `"value": "enable"` 不会影响 API 24/25 设备运行，只是该功能在低版本设备上不会生效。

---

## 四、构建配置

### 4.1 hvigorfile.ts 无需修改

现有的构建配置已支持多版本编译。

### 4.2 测试验证清单

1. **API 24 设备测试**：
   - [ ] 应用可正常安装
   - [ ] 首页推荐加载正常
   - [ ] 视频播放正常（无自定义 HTTP 头）
   - [ ] 登录功能正常（Cookie 存储/读取）
   - [ ] UI 显示正常（半透明背景替代磨砂效果）

2. **API 26 设备测试**：
   - [ ] 所有功能正常
   - [ ] 沉浸式光感效果正常
   - [ ] 视频播放支持自定义 HTTP 头
   - [ ] HUKS 会话式加解密正常

---

## 五、总结

### 适配优先级

| 功能 | 优先级 | 降级方案 |
|------|--------|----------|
| 沉浸式材质 | 高 | 半透明背景 |
| 视频播放 | 高 | 直接设置 URL |
| HUKS 加解密 | 中 | 传统 API |
| WebView Cookie | 中 | 从 WebView 获取 |
| SegmentButton | 低 | 按钮组替代 |
| 其他 UI 特性 | 低 | 移除或简化 |

### 注意事项

1. **API 24 设备将失去沉浸式光感效果**，但 UI 仍然可用
2. **视频播放可能受限**：API 24/25 无法设置自定义 HTTP 头，可能导致某些视频无法播放
3. **建议在真机上测试**：模拟器可能无法完全验证降级效果
4. **考虑放弃 API 24 支持**：如果沉浸式光感是核心特性，建议保持 API 26 最低版本