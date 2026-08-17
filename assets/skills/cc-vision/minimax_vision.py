#!/usr/bin/env python3
"""cc-vision helper: 用 MiniMax-M3 视觉接口分析一张图片,把描述写到 stdout。

用法:
    minimax_vision.py <图片路径> [要问的问题]

环境变量:
    MINIMAX_API_KEY            必填,MiniMax 平台 API key
    MINIMAX_VISION_BASE_URL    默认 https://api.minimaxi.com/v1/chat/completions
    MINIMAX_VISION_MODEL       默认 MiniMax-M3
    MINIMAX_VISION_MAX_TOKENS  默认 2000

退出码:0 = 成功(stdout 为模型回答);非 0 = 失败(stderr 为原因)。
依赖仅标准库(容器自带 python3),无第三方包。
"""
import base64
import json
import os
import sys
import urllib.error
import urllib.request

BASE_URL = os.environ.get(
    "MINIMAX_VISION_BASE_URL", "https://api.minimaxi.com/v1/chat/completions"
)
MODEL = os.environ.get("MINIMAX_VISION_MODEL", "MiniMax-M3")
MAX_TOKENS = int(os.environ.get("MINIMAX_VISION_MAX_TOKENS", "2000"))
# MiniMax 官方限制:单张图片不超过 10MB
MAX_IMAGE_BYTES = 10 * 1024 * 1024

# 魔数识别格式(MiniMax 仅支持 JPEG/PNG/GIF/WEBP),不依赖扩展名
MIME_BY_MAGIC = [
    (b"\xff\xd8\xff", "image/jpeg"),
    (b"\x89PNG\r\n\x1a\n", "image/png"),
    (b"GIF8", "image/gif"),
    (b"RIFF", "image/webp"),  # webp 头为 RIFF....WEBP,需再校验后 4 字节
]


def die(msg: str) -> None:
    print(f"cc-vision: {msg}", file=sys.stderr)
    sys.exit(1)


def detect_mime(path: str) -> str:
    with open(path, "rb") as f:
        head = f.read(16)
    for magic, mime in MIME_BY_MAGIC:
        if head.startswith(magic):
            if mime == "image/webp" and head[8:12] != b"WEBP":
                continue
            return mime
    return ""


def main() -> None:
    if len(sys.argv) < 2:
        die("缺少图片路径参数。用法:minimax_vision.py <图片路径> [问题]")
    path, *rest = sys.argv[1:]
    prompt = " ".join(rest).strip() or "请详细描述这张图片的内容。"

    if not os.path.isfile(path):
        die(f"图片不存在:{path}")

    size = os.path.getsize(path)
    if size > MAX_IMAGE_BYTES:
        die(f"图片 {size // 1024} KB 超过 MiniMax 单张 10MB 上限,请先压缩再试。")

    mime = detect_mime(path)
    if not mime:
        die("无法识别图片格式(MiniMax 仅支持 JPEG/PNG/GIF/WEBP)。")

    api_key = os.environ.get("MINIMAX_API_KEY", "").strip()
    if not api_key:
        die(
            "环境变量 MINIMAX_API_KEY 未设置。"
            "请在宿主机 ~/.config/cca/common.env 加一行 "
            "MINIMAX_API_KEY=<你的MiniMaxKey>(对所有 profile 生效),再重启 cca。"
        )

    with open(path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode("ascii")

    payload = {
        "model": MODEL,
        # 看图任务要的是结论,关闭 thinking 避免响应带 reasoning 块、降低延迟
        "thinking": {"type": "disabled"},
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    {"type": "image_url", "image_url": {"url": f"data:{mime};base64,{b64}"}},
                ],
            }
        ],
        "max_completion_tokens": MAX_TOKENS,
    }

    req = urllib.request.Request(
        BASE_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        die(f"MiniMax API 返回 {e.code}:{body[:500]}")
    except urllib.error.URLError as e:
        die(f"无法连接 MiniMax({BASE_URL}):{e.reason}")

    try:
        content = data["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        die(f"MiniMax 响应缺少预期字段:{json.dumps(data, ensure_ascii=False)[:500]}")

    # content 可能是纯字符串,也可能是 [{type:text, text:...}, ...] 数组
    if isinstance(content, str):
        text = content.strip()
    elif isinstance(content, list):
        text = "\n".join(
            b.get("text", "")
            for b in content
            if isinstance(b, dict) and b.get("type") == "text"
        ).strip()
    else:
        text = str(content).strip()

    if not text:
        die(f"MiniMax 返回空内容:{json.dumps(data, ensure_ascii=False)[:500]}")
    print(text)


if __name__ == "__main__":
    main()
