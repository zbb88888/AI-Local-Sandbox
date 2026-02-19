# TODO — 待支持的模型 & 功能

## GGUF 音频模型（MiniCPM-o 内置端到端音频管线）

### `MiniCPM-o-4_5-audio-F16.gguf` (~1.16GB)

- **来源**：`openbmb/MiniCPM-o-4_5-gguf` 仓库 `audio/` 目录
- **作用**：MiniCPM-o 内置的 Whisper-medium audio encoder，支持音频直接输入 LLM 进行端到端处理
- **能力**：
  - 音频理解（Audio Understanding）
  - 说话人分析（Speaker Analysis）
  - 端到端 ASR（LLM 直接从音频生成文本，无需外部 STT）
  - 音频场景标注（Sound Scene Tagging）
- **当前状态**：❌ 未集成
- **阻塞原因**：
  1. `llama.cpp` 对 MiniCPM-o audio pipeline 的支持仍处于实验阶段
  2. 当前使用 `faster-whisper` (CPU) + `Piper TTS` (CPU) 的独立方案更稳定
  3. 加载后额外占用 ~1.16GB VRAM
- **集成后的数据流变化**：
  ```
  当前:  麦克风 → faster-whisper (CPU) → 文本 → LLM (GGUF) → 文本 → Piper TTS → 音频
  未来:  麦克风 → 音频直接送入 LLM (audio encoder + GGUF LLM) → 文本/音频
  ```
- **前置条件**：等待 `llama-cpp-python` 支持 MiniCPM-o 的 `--audio-model` 参数

---

### `token2wav-gguf/` (TTS 相关)

- **来源**：`openbmb/MiniCPM-o-4_5-gguf` 仓库 `token2wav-gguf/` 目录
- **作用**：MiniCPM-o 内置的 CosyVoice2 TTS 模型（GGUF 格式），支持端到端语音生成
- **能力**：
  - Zero-shot 语音克隆
  - 角色扮演语音（Voice Roleplay）
  - 情感/语调控制
- **当前状态**：❌ 未集成
- **阻塞原因**：同上，需要 llama.cpp omni 推理框架支持
- **当前替代**：Piper TTS (ONNX, CPU) — 固定声音，不支持克隆

---

## 未来可选升级

| 模型 | 文件 | 大小 | 用途 | 优先级 |
|------|------|------|------|--------|
| Audio Encoder | `audio/MiniCPM-o-4_5-audio-F16.gguf` | ~1.16GB | 端到端音频理解 | 中 — 等 llama.cpp 稳定支持 |
| Token2Wav TTS | `token2wav-gguf/` | ~1.1GB | 端到端语音合成 + 声音克隆 | 中 — 同上 |
| Q4_K_S 变体 | `MiniCPM-o-4_5-Q4_K_S.gguf` | 4.80GB | VRAM 紧张时的 LLM 备选 | 低 — 已在代码中注释备用 |
| 更高精度变体 | Q5_K_M / Q6_K / Q8_0 | 5.85-8.71GB | 更高推理质量 | 低 — 按需切换 |

---

## 跟踪参考

- [MiniCPM-o 4.5 GGUF 仓库](https://huggingface.co/openbmb/MiniCPM-o-4_5-gguf)
- [llama.cpp-omni](https://github.com/tc-mb/llama.cpp-omni) — 支持全双工多模态实时推理的 fork
- [MiniCPM-V CookBook](https://github.com/OpenSQZ/MiniCPM-V-CookBook) — 官方部署指南
