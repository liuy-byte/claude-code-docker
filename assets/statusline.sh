#!/usr/bin/env bash
# cca 默认 statusLine:随镜像分发,cc-entrypoint 每次启动把本文件
# 从 /opt/cc-assets/statusline.sh 同步到卷内 ~/.claude/statusline.sh。
# 自定义:改 settings.json 里 statusLine.command 指到自己脚本即可,
# 不要直接改本文件 —— 下次 `cca update` 拉新镜像会被覆盖(等同公共 skill 约定)。
#
# 渲染: model · cwd (branch [!N ?N]) · pct%
# 输入: stdin 是 Claude Code 注入的 JSON
# 设计: 缺字段就降级显示,不报错(避免偶发空数据炸渲染)

# 只 set -u(引用未定义变量报错);不用 -e/pipefail —— 本脚本目标是"某段取数失败就
# 降级为空、绝不炸渲染",-e/pipefail 会让任一管道段(jq/git/awk)非零退出就中止脚本、
# 状态栏变空白,与容错目标相悖。各段自身用 // 兜底或 if 保护即可。
set -u

input=$(cat)

# --- 一次 jq 取全部字段(statusLine 是热路径,合并成单个 jq 子进程),tab 分隔后 shell 侧 read 拆开 ---
#   model: display_name→id→"?";  cwd: current_dir→cwd→空(shell 侧 pwd 兜底)
#   pct:   percentage_used → 100-remaining_percentage → token 求和/window_size,同一 // 链三级降级容忍多版本 JSON
IFS=$'\t' read -r model cwd pct < <(printf '%s' "$input" | jq -r '
  [ (.model.display_name // .model.id // "?"),
    (.workspace.current_dir // .cwd // ""),
    ( .context_window.percentage_used
      // (if .context_window.remaining_percentage != null
            then ([100 - .context_window.remaining_percentage, 0] | max) else null end)
      // (if .context_window.context_window_size and .context_window.current_usage then
            ((.context_window.current_usage.input_tokens // 0)
             + (.context_window.current_usage.output_tokens // 0)
             + (.context_window.current_usage.cache_creation_input_tokens // 0)
             + (.context_window.current_usage.cache_read_input_tokens // 0)
            ) * 100 / .context_window.context_window_size | floor
          else null end)
      // "" )
  ] | @tsv')
[ -z "$cwd" ] && cwd=$(pwd)
# 只显示末段目录名(${cwd##*/} 省 basename 的 fork);根目录剥空兜底回 /
dir=${cwd##*/}
[ -z "$dir" ] && dir=/

# --- 上下文 %,按用量变色:绿 < 50 / 黄 50-80 / 红 > 80(段首自带分隔符,空则整段空)---
# 先剥小数、再校验是纯数字才染色:异常 JSON 让 pct 变成非数字(如 "abc"、空串)时,
# 直接进 [ -lt ] 会每次刷新向 stderr 喷 "integer expression expected",这里提前跳过。
pct_seg=''
pct_num=${pct%.*}
case "$pct_num" in
  ''|*[!0-9]*) ;;  # 非纯数字 ⇒ 不显示百分比(不染色、不喷错)
  *)
    if   [ "$pct_num" -lt 50 ]; then color='32'  # 绿
    elif [ "$pct_num" -lt 80 ]; then color='33'  # 黄
    else                            color='31'  # 红
    fi
    pct_seg=$(printf '\033[90m · \033[00m\033[%sm%s%%\033[00m' "$color" "$pct")
  ;;
esac

# --- git 分支 + starship 风格状态标记(非 git 目录跳过)---
# 约定:!N = 修改/暂存的文件数(staged + unstaged);?N = 未跟踪的文件数;干净则不显示
branch=''
if [ -d "$cwd" ] && cd "$cwd" && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  b=$(git symbolic-ref --short HEAD 2>/dev/null)
  [ -z "$b" ] && b=$(git describe --tags --exact-match HEAD 2>/dev/null)
  if [ -n "$b" ]; then
    changes=$(git status --porcelain 2>/dev/null)
    if [ -n "$changes" ]; then
      # 一遍 awk 同时算出 modified(staged+unstaged,非 ?? 开头)和 untracked(?? 开头)
      read modified untracked < <(printf '%s\n' "$changes" | awk '
        /^\?\?/ {u++; next}
        NF {m++}
        END {print m+0, u+0}
      ')
      marker=''
      [ "${modified:-0}" -gt 0 ] && marker="${marker}!${modified} "
      [ "${untracked:-0}" -gt 0 ] && marker="${marker}?${untracked} "
      [ -n "$marker" ] && b="$b ${marker% }"
    fi
    branch=$(printf ' \033[33m(%s)\033[00m' "$b")
  fi
fi

# --- 渲染:model · cwd (branch) · pct%(中间用灰色 · 分隔)---
# branch 与 pct_seg 都自带前导分隔符、空时整段为空,故单条 printf 即可,无孤立 · 残留。
# 两者内部的 ANSI 已是被 printf 展开的真实 ESC 字节,故用 %s 原样输出(不能用 %b,
# 否则 cwd/分支名里的字面反斜杠会被二次转义)。分隔符内联在格式串里
# (若写成 sep='\033[90m · \033[00m' 变量,单引号会把 \033 当字面字符原样打印)。
printf '\033[36m%s\033[00m\033[90m · \033[00m\033[01;34m%s\033[00m%s%s\n' \
  "$model" "$dir" "$branch" "$pct_seg"