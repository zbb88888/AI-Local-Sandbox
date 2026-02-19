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

## 如果要改为调用本地 API 服务（如 LM Studio `http://127.0.0.1:1234`）

需要新增以下功能：

1. **添加 OpenAI 兼容 API 客户端**：通过 `requests` 库调用 `/v1/chat/completions`
2. **环境变量切换**：`MINICPM_API_URL` 控制走 API 还是走本地权重
3. **消息格式转换**：MiniCPM 的 `[PIL_image, text]` 格式 → OpenAI vision 的 `image_url` base64 格式
4. **SSE 流式解析**：处理 `data: {...}` 格式的 Server-Sent Events
5. **跳过本地模型加载**：API 模式下不加载 HF 权重，释放全部 GPU VRAM

这属于 **新功能开发**，当前代码库中不包含此能力。
