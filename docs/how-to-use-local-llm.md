# 本项目模型调用方式分析

## 结论：直接加载权重，不调用任何 API 服务

本项目 **没有** 调用 LM Studio / Ollama / vLLM 等本地模型 API 服务。
所有模型推理均通过 HuggingFace `transformers` / `diffusers` 库 **直接加载权重到本地 GPU/CPU 内存** 后，调用 Python 对象方法完成。

README 第一行明确声明：**"No external APIs required (fully local)"**。

---

## 代码证据

### 1. MiniCPM 多模态聊天（minicpm.py, webcam_live_gradio.py）

```python
# 加载方式：HuggingFace AutoModel，INT4 量化，直接上 GPU
from transformers import AutoModel, AutoTokenizer

model = AutoModel.from_pretrained(
    "openbmb/MiniCPM-V-4_5-int4",
    trust_remote_code=True,
    torch_dtype=torch.float16,
    device_map="auto",
).eval()

tokenizer = AutoTokenizer.from_pretrained(
    "openbmb/MiniCPM-V-4_5-int4",
    trust_remote_code=True,
)

# 推理方式：直接调用模型对象的 .chat() 方法
response = model.chat(
    msgs=msgs,
    tokenizer=tokenizer,
    stream=True,           # 或 False
    max_new_tokens=240,
    ...
)
```

**调用链**：`Python 进程 → model.chat() → GPU 推理 → 返回文本`

没有任何 HTTP 请求参与。

### 2. Stable Diffusion 图像生成（sdxl.py, sdxl_safe.py, sdxl_safe_canny.py）

```python
from diffusers import AutoPipelineForText2Image

pipe = AutoPipelineForText2Image.from_pretrained(
    "stabilityai/sdxl-turbo",
    torch_dtype=torch.float16,
)
pipe.to("cuda")

with torch.inference_mode():
    img = pipe(prompt=prompt, ...).images[0]

pipe.to("cpu")
```

**调用链**：`Python 进程 → pipe() → GPU 推理 → 返回 PIL Image`

同样没有 HTTP 请求。

### 3. 语音识别（faster-whisper）

```python
from faster_whisper import WhisperModel
model = WhisperModel("small", device="cpu", compute_type="int8")
segments, info = model.transcribe(audio_path, ...)
```

CPU 本地推理，无 API。

### 4. 语音合成（Piper TTS）

```python
subprocess.run(["piper", "--model", voice_path, "--output_file", out_wav], input=text)
```

本地 CLI 调用 ONNX 模型，无 API。

---

## 不存在的东西（已验证）

| 检查项 | 结果 |
|--------|------|
| `import requests` | ❌ 不存在 |
| `import openai` | ❌ 不存在 |
| `import httpx` / `import aiohttp` | ❌ 不存在 |
| `http://127.0.0.1` 或任何 API URL | ❌ 不存在 |
| `/v1/chat/completions` 请求构建 | ❌ 不存在 |
| SSE streaming 解析 | ❌ 不存在 |
| `OPENAI_API_KEY` 等环境变量 | ❌ 不存在 |
| 任何 REST/gRPC 客户端调用 | ❌ 不存在 |

---

## `python minicpm.py` 默认加载的模型清单

| # | 模型名 / 路径 | HuggingFace ID | 用途 | 加载时机 | 设备 |
|---|--------------|----------------|------|----------|------|
| 1 | MiniCPM-V-4.5-int4 | `openbmb/MiniCPM-V-4_5-int4` | 多模态聊天（LLM + Vision） | **启动时立即加载**（构建 UI 时实例化 `MiniCPMAgent`） | GPU (INT4, fp16, device_map=auto) |
| 2 | Whisper small | `faster-whisper` `"small"` | 语音识别（STT） | 首次使用麦克风时懒加载 | CPU (int8) |
| 3 | Piper LibriTTS | `~/piper_voices/libritts_r_medium/en_US-libritts_r-medium.onnx` | 语音合成（TTS） | 每次 TTS 请求时 CLI 调用 | CPU (ONNX) |
| 4 | SD Turbo (Text2Image) | `stabilityai/sd-turbo` | 图像生成 Draft | 首次点击 "Generate image" 时懒加载 | CPU↔GPU 乒乓 |
| 5 | SD Turbo (Image2Image) | `stabilityai/sd-turbo` | 图像精炼 Refine | 首次勾选 "HD refine" 时懒加载 | CPU↔GPU 乒乓 |

> 模型 4 和 5 是同一个 checkpoint，但分别加载为 Text2Image 和 Image2Image 两个独立 pipeline。

---

## 如果要改为调用本地 API 服务（如 LM Studio `http://127.0.0.1:1234`）

需要新增以下功能：

1. **添加 OpenAI 兼容 API 客户端**：通过 `requests` 库调用 `/v1/chat/completions`
2. **环境变量切换**：`MINICPM_API_URL` 控制走 API 还是走本地权重
3. **消息格式转换**：MiniCPM 的 `[PIL_image, text]` 格式 → OpenAI vision 的 `image_url` base64 格式
4. **SSE 流式解析**：处理 `data: {...}` 格式的 Server-Sent Events
5. **跳过本地模型加载**：API 模式下不加载 HF 权重，释放全部 GPU VRAM

这属于 **新功能开发**，当前代码库中不包含此能力。
---

## GGUF 入口：`python minicpm-o.py`

`minicpm-o.py` 已改造为使用 **GGUF 量化模型**，通过 `llama-cpp-python` 加载，替代原有的 HuggingFace AutoModel。

### GGUF 模型配置

| 配置项 | 值 |
|--------|------|
| HuggingFace 仓库 | `openbmb/MiniCPM-o-4_5-gguf` |
| **默认 LLM 文件** | `MiniCPM-o-4_5-Q4_K_M.gguf` (5.03GB) |
| 备选 LLM 文件 | `MiniCPM-o-4_5-Q4_K_S.gguf` (4.80GB) |
| Vision Projector | `vision/MiniCPM-o-4_5-vision-F16.gguf` (1.1GB) |
| 架构 | Qwen3 8B params |
| Context 长度 | 4096 tokens |
| GPU Offload | 全部层 (`n_gpu_layers=-1`) |

### Q4_K_M vs Q4_K_S

- **Q4_K_M (推荐)**：混合精度量化，attention 和 feed_forward 关键层使用 Q6_K，视觉理解质量更优。
- **Q4_K_S**：全部使用 Q4_K 量化，节省约 230MB VRAM，质量略低。仅在 VRAM 极度紧张时切换。

切换方式：编辑 `minicpm-o.py` 顶部配置常量即可：

```python
# 默认 Q4_K_M
GGUF_MODEL_FILE = "MiniCPM-o-4_5-Q4_K_M.gguf"
# 切换为 Q4_K_S：注释上面一行，取消下面一行的注释
# GGUF_MODEL_FILE = "MiniCPM-o-4_5-Q4_K_S.gguf"
```

### 额外依赖

```bash
# CUDA GPU 加速版
CMAKE_ARGS="-DGGML_CUDA=on" pip install llama-cpp-python
# 或 CPU-only 版
pip install llama-cpp-python
# huggingface_hub 用于自动下载 GGUF 文件
pip install huggingface_hub
```

### 调用链

```
python minicpm-o.py
  → get_minicpm_model()
    → hf_hub_download(Q4_K_M.gguf + vision-F16.gguf)
    → GGUFMiniCPMModel.__init__()
      → llama_cpp.Llama(model_path=..., clip_model_path=...)
  → GGUFMiniCPMModel.chat(msgs, stream=True)
    → _convert_msgs(): MiniCPM [PIL, text] → OpenAI vision base64 format
    → llm.create_chat_completion(messages=..., stream=True)
    → yield text delta chunks
```

### 与原 minicpm.py 的区别

| | `minicpm.py` | `minicpm-o.py` (GGUF) |
|---|---|---|
| 模型加载 | `AutoModel.from_pretrained()` | `llama_cpp.Llama()` |
| 量化方式 | AWQ INT4 (HF format) | GGUF Q4_K_M / Q4_K_S |
| 模型仓库 | `openbmb/MiniCPM-V-4_5-int4` | `openbmb/MiniCPM-o-4_5-gguf` |
| Tokenizer | `AutoTokenizer` | 内置 (llama.cpp 处理) |
| 依赖 | `transformers` | `llama-cpp-python` + `huggingface_hub` |
| 视觉输入 | PIL 直接传入 | PIL → base64 data URI 转换 |
| 其他组件 | STT/TTS/SD 不变 | STT/TTS/SD 不变 |