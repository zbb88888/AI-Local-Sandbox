# llama-cpp-python 安装踩坑记录

本文档记录在安装 `llama-cpp-python` 过程中**失败的方式**，避免重复踩坑。

---

## ❌ 方式 1：源码编译 + CUDA（`CMAKE_ARGS="-DGGML_CUDA=on"`）

```bash
CMAKE_ARGS="-DGGML_CUDA=on" pip install llama-cpp-python
```

### 错误 1：CUDA Toolkit not found

```
CMake Error at vendor/llama.cpp/ggml/src/ggml-cuda/CMakeLists.txt:187 (message):
  CUDA Toolkit not found
```

**原因**：系统只有 NVIDIA driver（591.86, CUDA 13.1），没有安装 CUDA Toolkit（`nvcc` 编译器）。

PyTorch 自带的 CUDA runtime 不包含 `nvcc`，无法编译 CUDA kernel。

**解决**：先安装 CUDA Toolkit：

```bash
sudo apt install -y nvidia-cuda-toolkit
nvcc --version   # 验证
```

### 错误 2：C++ 编译失败（ninja: build stopped: subcommand failed）

安装 `nvidia-cuda-toolkit` 后重试，cmake 配置通过了，但编译阶段失败：

```
[32/183] /usr/bin/x86_64-linux-gnu-g++ ... -o .../ops.cpp.o -c .../ops.cpp
ninja: build stopped: subcommand failed.
*** CMake build failed
```

**原因**：可能是内存不足（编译 183 个 C++ 文件消耗大量 RAM）或 GCC 13.3.0 与 llama.cpp 的兼容性问题。

**结论**：源码编译路径在当前环境下不可行。

---

## ❌ 方式 2：pip 直接下载预编译 wheel（网络超时）

```bash
pip install llama-cpp-python \
    --extra-index-url https://abetlen.github.io/llama-cpp-python/whl/cu124
```

### 错误：下载 551MB wheel 超时

```
Downloading ... llama_cpp_python-0.3.16-cp312-cp312-linux_x86_64.whl (551.3 MB)
━━━━━━━━━                         127.2/551.3 MB 15.7 MB/s
ERROR: Wheel 'llama-cpp-python' located at ... is invalid.
```

或：

```
TimeoutError: The read operation timed out
```

**原因**：pip 默认超时太短（15s），551MB 大文件在网络波动时容易断连导致下载不完整。

**结论**：`pip install` 大 wheel 不可靠。

---

## ✅ 最终成功方式：wget 下载 + 本地安装

```bash
# 1. 用 wget 下载（支持断点续传，超时容错好）
wget -c --timeout=300 -O /tmp/llama_cpp_python-0.3.16-cp312-cp312-linux_x86_64.whl \
    "https://github.com/abetlen/llama-cpp-python/releases/download/v0.3.16-cu124/llama_cpp_python-0.3.16-cp312-cp312-linux_x86_64.whl"

# 2. 本地安装
pip install /tmp/llama_cpp_python-0.3.16-cp312-cp312-linux_x86_64.whl

# 3. 验证
python3 -c "import llama_cpp; print('OK')"
```

### 环境信息

| 项 | 值 |
|----|-----|
| OS | Ubuntu 24.04 (WSL2) |
| Python | 3.12.3 |
| GPU | NVIDIA RTX 5070 Ti (16GB) |
| Driver | 591.86 (CUDA 13.1) |
| PyTorch CUDA | 12.8 |
| llama-cpp-python | 0.3.16 (cu124 prebuilt wheel) |
| wheel 大小 | 551 MB |

---

## 注意事项

- `cu124` wheel 与 PyTorch `cu128` 共存没有问题，因为 llama-cpp-python 自带独立的 CUDA runtime
- 如果后续升级 llama-cpp-python 版本，优先检查 [releases 页面](https://github.com/abetlen/llama-cpp-python/releases) 是否有对应 Python 版本 + CUDA 版本的预编译 wheel
- 预编译 wheel URL 格式：`https://github.com/abetlen/llama-cpp-python/releases/download/v{VERSION}-cu{CUDA}/llama_cpp_python-{VERSION}-cp{PYVER}-cp{PYVER}-linux_x86_64.whl`
