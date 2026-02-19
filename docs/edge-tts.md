# edge-tts 中文语音合成方案

## 背景

原项目使用 **Piper + LibriTTS** 作为 TTS 引擎，该方案为纯英文语音模型，完全不支持中文。
同时 `should_speak()` 断句函数只检测英文句末标点 `.!?`，中文标点 `。！？` 永远不会触发 TTS。

## 方案选型

| 方案 | 中文质量 | 离线 | 安装复杂度 | GPU 占用 |
|------|---------|------|-----------|---------|
| **edge-tts** (Microsoft) | ★★★★★ | ✗ 需联网 | pip install 即可 | 无 |
| Piper 中文模型 | ★★☆ | ✓ | 需下载 zh_CN 模型 | 无 |
| CosyVoice (阿里) | ★★★★ | ✓ | 复杂 (modelscope + torch) | 可选 |
| ChatTTS | ★★★★★ | ✓ | 复杂，需 GPU + 大模型权重 | 高 |

最终选择 **edge-tts**：质量最高、安装最简单、零 GPU 占用。唯一代价是需要联网。

## edge-tts 是什么

`edge-tts` 是一个开源 Python 库（[GitHub](https://github.com/rany2/edge-tts)），通过 WebSocket 协议直接调用 Microsoft Edge 浏览器内置的 TTS 后端 API（`speech.platform.bing.com`）。

### 关键事实

- **不需要安装 Edge 浏览器** — 它是独立的网络协议客户端，只需要能联网
- **免费，无需 API Key** — 使用的是 Edge 浏览器朗读功能的同一后端
- **支持 400+ 种语音**，覆盖中文、英文、日语等数十种语言
- 输出格式为 MP3，通过 ffmpeg 转码为 WAV PCM16 以兼容下游管线

## 当前配置

### 默认语音

```
zh-CN-XiaoxiaoNeural
```

- 女声，微软晓晓，自然度极高
- 通过环境变量 `EDGE_TTS_VOICE` 可切换

### 常用中文语音

| Voice ID | 性别 | 说明 |
|----------|------|------|
| `zh-CN-XiaoxiaoNeural` | 女 | 默认，自然亲切 |
| `zh-CN-XiaoyiNeural` | 女 | 温柔 |
| `zh-CN-YunxiNeural` | 男 | 标准男声 |
| `zh-CN-YunjianNeural` | 男 | 沉稳 |
| `zh-CN-liaoning-XiaobeiNeural` | 女 | 东北方言 |
| `zh-TW-HsiaoChenNeural` | 女 | 台湾腔 |

查看完整语音列表：

```bash
~/.venv/bin/edge-tts --list-voices | grep zh
```

### 切换语音

```bash
# 使用男声
EDGE_TTS_VOICE=zh-CN-YunxiNeural make run-gguf
```

## 技术实现

### 调用链

```
LLM streaming tokens
  → should_speak() 检测句末标点（。！？. ! ?）
    → TTSWavQueue.submit_text()
      → worker thread: tts_to_wav()
        → edge_tts.Communicate(text, voice).save(mp3)   # async, WebSocket
        → ffmpeg mp3 → wav PCM16 (24kHz mono)
        → wav_apply_volume_pcm16()
      → ready_q → Gradio audio output
```

### tts_to_wav() 实现

```python
def tts_to_wav(text: str) -> str:
    import edge_tts

    ts = int(time.time() * 1000)
    out_mp3 = os.path.join(tempfile.gettempdir(), f"minicpm_tts_{ts}.mp3")
    out_wav = os.path.join(tempfile.gettempdir(), f"minicpm_tts_{ts}.wav")

    async def _synthesize():
        comm = edge_tts.Communicate(text, EDGE_TTS_VOICE)
        await comm.save(out_mp3)

    # 新建 event loop — 线程安全（worker thread 中无全局 loop 冲突）
    loop = asyncio.new_event_loop()
    try:
        loop.run_until_complete(_synthesize())
    finally:
        loop.close()

    # mp3 → wav PCM16 (下游 wav_apply_volume_pcm16 要求)
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error",
         "-i", out_mp3,
         "-acodec", "pcm_s16le", "-ar", "24000", "-ac", "1",
         out_wav],
        check=True,
    )
    os.remove(out_mp3)
    return out_wav
```

### should_speak() 中文修复

```python
def should_speak(buf: str) -> bool:
    s = (buf or "").strip()
    if len(s) >= 180:
        return True
    # 同时支持英文和中文句末标点
    return s.endswith((".", "!", "?", "\u3002", "\uff01", "\uff1f"))
    #                                   。       ！       ？
```

## 安装

```bash
# 依赖
pip install edge-tts

# 系统依赖（ffmpeg 用于 mp3→wav 转码）
sudo apt install -y ffmpeg
```

已集成到项目 `requirements.txt` 和 `Makefile`：

```bash
make install      # 自动安装 edge-tts
make install-all  # 完整安装（含 PyTorch、GGUF 等）
```

## 与原 Piper 方案对比

| 维度 | Piper + LibriTTS | edge-tts |
|------|------------------|----------|
| 中文支持 | ✗ 不支持 | ✓ 原生中文 |
| 语音自然度 | 中等 | 极高（Neural TTS） |
| 离线运行 | ✓ | ✗ 需联网 |
| GPU 占用 | 无 | 无 |
| 本地模型文件 | ~60MB ONNX | 无 |
| 安装 | pip + 下载模型 | pip install 即可 |
| 延迟 | ~200ms | ~300-500ms（含网络） |

## 已知限制

1. **必须联网** — 断网时 TTS 会报错，LLM 推理不受影响
2. **延迟略高于本地方案** — 网络往返约增加 100-300ms
3. **微软可能调整后端策略** — 非官方 API，理论上存在被限流的可能（目前未观察到）
4. **英文内容也会用中文语音读** — 当前硬编码为中文语音，英文会以中式口音朗读

## 故障排查

### TTS 无声音

```bash
# 1. 检查网络连通性
curl -I https://speech.platform.bing.com

# 2. 手动测试
~/.venv/bin/edge-tts --voice zh-CN-XiaoxiaoNeural --text "测试" --write-media /tmp/test.mp3
ffplay /tmp/test.mp3

# 3. 检查 ffmpeg
ffmpeg -version
```

### 切换回英文语音（如需）

```bash
EDGE_TTS_VOICE=en-US-JennyNeural make run-gguf
```
