# 实时摄像头视觉分析模块设计

## 1. 模块入口

文件：[webcam_live_gradio.py](../webcam_live_gradio.py)

## 2. 架构概述

这不是传统的逐帧视频处理，而是 **"最新帧优先"** 的近实时分析：

```
┌──────────────┐     ┌─────────────────┐     ┌──────────────┐
│ Webcam Stream│────▶│ capture_latest  │────▶│ _latest_frame│
│ (Gradio)     │     │ _frame()        │     │ (global var) │
└──────────────┘     └─────────────────┘     └──────┬───────┘
                                                     │
                     ┌─────────────────┐             │
                     │  run_session()  │◀────────────┘
                     │  (generator)    │  每 1/fps 秒取最新帧
                     │                 │
                     │  ┌───────────┐  │
                     │  │ MiniCPM   │  │
                     │  │ stream_   │  │
                     │  │ chat()    │  │
                     │  └───────────┘  │
                     └────────┬────────┘
                              │ yield (text, status)
                              ▼
                     ┌─────────────────┐
                     │ Gradio UI       │
                     │ output textbox  │
                     └─────────────────┘
```

## 3. 并发模型

### 3.1 帧捕获（高频）

`webcam.stream()` → `capture_latest_frame()` 在每个浏览器帧到达时调用。
仅更新全局 `_latest_frame`（加锁），不做推理。

### 3.2 分析循环（低频）

`run_session()` 是 Gradio generator，按 `analyze_fps`（默认 2 FPS）节奏运行：

```python
while running:
    frame = _latest_frame          # 取最新帧
    if busy and drop_if_busy:      # 推理中 → 跳过
        continue
    pil = _to_pil(frame)           # numpy → PIL RGB
    pil_small = _resize_long_edge(pil, 640)  # 限制长边 640px
    model.stream_chat(image=pil_small, ...)  # 流式推理
    sleep(1/fps)
```

### 3.3 状态管理

```python
@dataclass
class LiveState:
    running: bool          # 会话是否运行中
    busy: bool             # 模型是否在推理
    last_text: str         # 最新输出文本
    frames_seen: int       # 捕获帧计数
    frames_analyzed: int   # 实际分析帧计数
```

线程安全通过 `_state_lock` (threading.Lock) 和 `_stop_event` (threading.Event) 保证。

## 4. 帧预处理

```
numpy (H,W,3) → np.fliplr() (镜像翻转) → PIL RGB
              → _resize_long_edge(640) → 送入模型
```

镜像翻转模拟自拍镜像效果。
长边限制到 640px 以平衡推理速度和 VRAM 占用。

## 5. 浏览器端控制

通过 JavaScript 注入自动点击 Gradio webcam 组件的开始/停止按钮：

- `JS_START_WEBCAM`: 自动点击 webcam 组件内的 button 启动摄像头
- `JS_STOP_WEBCAM`: 自动点击停止摄像头

## 6. 模型配置

| 参数 | 值 | 说明 |
|------|------|------|
| `max_slice_nums` | 1 | 限制图像切片数，减少 VRAM |
| `temperature` | 0.1 | 低温度，输出稳定 |
| `max_new_tokens` | 120 (默认) | 可调 10–500 |
| `sampling` | True | stream_chat 要求 |

## 7. Gradio Queue 配置

```python
demo.queue(default_concurrency_limit=1, max_size=1)
```

- `concurrency_limit=1`: 防止重叠推理
- `max_size=1`: 减少请求积压
