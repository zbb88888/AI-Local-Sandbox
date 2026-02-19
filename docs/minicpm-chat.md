# MiniCPM 多模态聊天模块设计

## 1. 模块入口

文件：[minicpm.py](../minicpm.py)

## 2. 核心组件

### 2.1 模型加载（单例）

```python
get_minicpm_model()   → AutoModel (INT4, device_map="auto", eval mode)
get_minicpm_tokenizer() → AutoTokenizer (trust_remote_code=True)
```

模型全局单例，首次调用时加载，后续复用。
使用 `torch.float16` + INT4 量化，通过 `device_map="auto"` 自动分配 GPU/CPU 层。

### 2.2 MiniCPMAgent 类

```
MiniCPMAgent
├── model: AutoModel (单例引用)
├── tok: AutoTokenizer (单例引用)
├── stream_chat(state, user_text, default_tokens, max_turns, user_image)
│   ├── 处理图像上传 → SHA1 去重 → image_store 缓存
│   ├── 构建 MiniCPM 消息格式: [PIL_image, text] 或 text
│   ├── 调用 model.chat(stream=True)
│   └── yield 累积文本
└── _compute_vision_embedding_if_possible(pil_img)
    └── 尝试调用模型内部视觉编码接口（best-effort 缓存）
```

### 2.3 会话状态管理

```
MMState
├── msgs: list[dict]           # 模型对话历史 [{role, content}, ...]
├── last_image_id: str|None    # 当前活跃图像 SHA1
├── image_store: dict          # image_id → PIL.Image (CPU)
└── vision_cache: LRUCache(16) # image_id → embedding (best-effort)
```

历史裁剪策略：保留最近 `MAX_TURNS`（默认 12）轮对话。

### 2.4 两种响应模式

| 模式 | 函数 | 特点 |
|------|------|------|
| `final` | `chat_step()` | 等待完整响应后返回 |
| `stream` | `chat_step_stream()` | 逐 token 流式输出 + 实时 TTS 分段合成 |

### 2.5 消息格式（MiniCPM 协议）

```python
# 纯文本
{"role": "user", "content": "hello"}

# 带图像（MiniCPM 专用格式）
{"role": "user", "content": [pil_image, "describe this"]}
```

UI 层只存储文本（不含 PIL），模型层存储完整 multimodal content。

## 3. 语音子系统

### 3.1 Speech-to-Text (STT)

```
Gradio mic (filepath) → faster-whisper (CPU, int8, "small")
                       → transcribed text → 注入 chat input
```

- 模型: `faster-whisper` "small"
- 设备: **CPU**（保持 GPU 给 MiniCPM）
- 特性: VAD 过滤 + beam_size=5

### 3.2 Text-to-Speech (TTS)

```
响应文本 → clean_for_tts() → Piper CLI (CPU, ONNX)
         → WAV (PCM16) → volume 调整 → 播放
```

TTS 流水线（流模式下）：

```
TTSWavQueue (后台线程)
├── job_q: Queue     ← 文本片段入队
├── ready_q: Queue   ← 合成完的 WAV 路径
├── worker Thread    ← 持续消费 job_q → piper → wav → ready_q
└── SENTINEL         ← "__END__" 标记本轮结束
```

流式 TTS 触发策略（`should_speak()`）：
- 文本 ≥ 180 字符，或
- 以 `.` `!` `?` 结尾

### 3.3 音频工具链

| 函数 | 用途 |
|------|------|
| `wav_apply_volume_pcm16()` | PCM16 音量缩放 |
| `wav_reverse()` | 音频时间反转（soundfile） |
| `concat_wavs_flexible()` | 多段 WAV 合并（自动重采样） |
| `wav_duration_s()` | 读取 WAV 时长 |

## 4. 图像生成子系统（minicpm.py 内嵌）

```
get_sd_pipeline()        → sd-turbo (Text2Image, fp16)
get_sd_refine_pipeline() → sd-turbo (Image2Image, fp16)
```

仅提供基础 turbo 生成 + 可选 img2img 精炼。
高级图像生成请使用独立的 sdxl*.py 脚本。

## 5. 错误处理

| 异常 | 处理 |
|------|------|
| `torch.OutOfMemoryError` | 清空 CUDA cache，回滚 user message，UI 提示 |
| `RuntimeError` (dtype mismatch) | 识别 "mat2 must have the same dtype"，提示图像格式问题 |
| 通用 `Exception` | 回滚 user message，UI 显示错误类型 + 消息 |

## 6. Gradio UI 布局

```
┌─────────────────────────────────────────────────┐
│  Chatbot (height=420)                           │
├─────────────────────────────────────────────────┤
│ [Text Input] [Mic (可选)]     [Image Upload]    │
├─────────────────────────────────────────────────┤
│ [Reverse] [Send] [Clear]                        │
├─────────────────────────────────────────────────┤
│ [Audio Player: file / streaming]                │
├─────────────────────────────────────────────────┤
│ Options: tokens | turns | volume | TTS | mode   │
│          | voice_enabled                        │
├─────────────────────────────────────────────────┤
│ Image Gen: prompt | steps | w×h | refine opts   │
└─────────────────────────────────────────────────┘
```

可见性由 `apply_visibility(mode, voice_enabled)` 统一管理：
- `stream` 模式 ↔ `final` 模式 切换对应 input/button/audio 组件
- `voice_enabled` 控制 mic 组件显示
