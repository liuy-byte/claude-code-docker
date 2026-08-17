#!/bin/sh
# Claude Code status line — robbyrussell 风格
# 目标效果： ➜  yly  git:(dev)↑2 │ Opus 5 │ ctx 62% │ ⚡high │ 5h 34%→18:00 │ 7d 61%→明09:00 │ learning │ @loop
#   ➜         粗体绿箭头（robbyrussell 标志）
#   yly       当前目录 basename，青色粗体
#   git:(dev) 当前分支，工作区干净=绿，脏=红；不在 git 仓库中整段省略
#   ↑2        本地领先上游的未推送 commit 数；为 0 或无上游分支时省略（黄色提示）
#   Opus 5    模型名，淡灰；去掉 "Claude " 前缀取简短形式
#   ctx 62%   上下文剩余百分比，淡灰
#   ⚡high    推理强度 effort.level，淡灰
#   5h 34%    5 小时限额用量，分级着色：<50% 淡灰 / 50~79% 黄 / >=80% 红；
#             若拿到 resets_at 重置时间戳，追加 "→HH:MM"（跨天加"明"/"N日"前缀，本身不单独着色，随所在段颜色）
#   7d 61%    7 天限额用量，仅 >=50% 时显示，分级着色 + 重置时间追加规则同 5h
#   learning  输出风格 output_style.name，仅非 default 时显示（黄色，提醒当前非默认行为）
#   @loop     会话名 session_name，无则退回 agent.name；都没有则省略
#   各段之间用 │ 分隔（分隔符固定淡灰）；任一字段缺失时该段整体省略，
#   不打印 null、不产生多余或连续的 │
#
# ⚠️ 颜色码必须是**真实 ESC 字符**（见下方 ESC=$(printf '\033')），不能写成字面 "\033"。
#    printf 只解释 format string 里的反斜杠转义，%s **参数**里的 \033 会被原样打印成乱码。
#    本脚本所有片段都是以 %s 参数传入的，故必须用真实 ESC。
#
# ⚠️ 容器是 Linux(GNU date):epoch->本地时间用 `date -d @<epoch>`。
#    BSD/macOS 的 `date -r` / `date -j` 在容器里不可用(见 format_reset_time)。

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')
remaining_pct=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')
effort_level=$(echo "$input" | jq -r '.effort.level // empty')
rate_5h_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rate_7d_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
# 重置时间：官方字段是 resets_at（unix 秒）；同时兼容几个可能的别名，取不到就空（该子片段整体省略）
rate_5h_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // .rate_limits.five_hour.reset_at // .rate_limits.five_hour.resetAt // .rate_limits.five_hour.reset_time // empty')
rate_7d_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // .rate_limits.seven_day.reset_at // .rate_limits.seven_day.resetAt // .rate_limits.seven_day.reset_time // empty')
output_style=$(echo "$input" | jq -r '.output_style.name // empty')
session_label=$(echo "$input" | jq -r '.session_name // .agent.name // empty')

# 目录名：仅取最后一级（basename）
basename_dir=$(basename "$cwd")
[ -z "$basename_dir" ] && basename_dir="/"

# 模型名简短形式：去掉 "Claude " 前缀（如 "Claude Opus 5" -> "Opus 5"）
model_short=$(printf "%s" "$model" | sed -E 's/^Claude //')

# 输出风格：default（含大小写变体）不显示，只在切到非默认风格时提醒
case "$(printf "%s" "$output_style" | tr '[:upper:]' '[:lower:]')" in
    default|"") output_style="" ;;
esac

# git 分支 + 脏净 + 未推送数：跳过 optional locks 避免阻塞；不在 git 仓库时整段省略
git_branch=""
git_dirty=0
git_ahead=""
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
    if [ -n "$git_branch" ]; then
        if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain --untracked-files=normal 2>/dev/null)" ]; then
            git_dirty=1
        fi
        # 未推送 commit 数；无上游分支时 git 会报错，静默吞掉并省略该段
        ahead=$(git -C "$cwd" --no-optional-locks rev-list --count '@{u}..HEAD' 2>/dev/null)
        case "$ahead" in
            ''|0|*[!0-9]*) git_ahead="" ;;
            *) git_ahead="$ahead" ;;
        esac
    fi
fi

# ANSI 颜色（真实 ESC 字符，可安全作为 printf 的 %s 参数传递）
ESC=$(printf '\033')
RESET="${ESC}[0m"
ARROW="${ESC}[1;32m"    # 粗体绿箭头
DIR="${ESC}[1;36m"      # 粗体青色目录
GIT_CLEAN="${ESC}[32m"  # 绿：干净
GIT_DIRTY="${ESC}[31m"  # 红：有改动
DIM="${ESC}[2m"         # 淡灰：常规信息
WARN="${ESC}[33m"       # 黄：需留意（未推送 / 限额过半 / 非默认输出风格）
ALERT="${ESC}[31m"      # 红：告警（限额 >=80%）

# 按用量返回分级颜色：<50 淡灰 / 50~79 黄 / >=80 红
rate_color() {
    if [ "$1" -ge 80 ]; then
        printf "%s" "$ALERT"
    elif [ "$1" -ge 50 ]; then
        printf "%s" "$WARN"
    else
        printf "%s" "$DIM"
    fi
}

# 输出一个尾部片段：$1 = 颜色，$2 = 文本。分隔符固定淡灰并在片段前 reset
emit_segment() {
    printf ' %s│%s %s%s%s' "$DIM" "$RESET" "$1" "$2" "$RESET"
}

# 额度重置时间：epoch 秒 -> 本地 "HH:MM"；跨天加"明"（+1 天）/"N日"（+N 天）前缀。
# 字段缺失、非法或本机 date 解析失败时静默返回空，调用方据此整段省略；不单独着色，随所在段颜色。
# 容器是 Linux(GNU date)：`date -d @<epoch>` 转本地时间；跨天比较用"本地日历日"而非除以 86400，
# 避免夏令时/时区导致的偏差。
format_reset_time() {
    epoch="$1"
    case "$epoch" in
        ''|*[!0-9.]*) return ;;
    esac
    epoch_int=${epoch%%.*}
    case "$epoch_int" in
        ''|*[!0-9]*) return ;;
    esac
    reset_hm=$(date -d "@$epoch_int" +%H:%M 2>/dev/null)
    [ -z "$reset_hm" ] && return
    # 按本地日历日比较（而非直接除以 86400），避免夏令时/时区导致的偏差
    today_mid=$(date -d "$(date +%Y-%m-%d)" +%s 2>/dev/null)
    reset_mid=$(date -d "$(date -d "@$epoch_int" +%Y-%m-%d)" +%s 2>/dev/null)
    diff_days=0
    if [ -n "$today_mid" ] && [ -n "$reset_mid" ]; then
        diff_days=$(( (reset_mid - today_mid) / 86400 ))
    fi
    if [ "$diff_days" -ge 2 ]; then
        printf "%s日%s" "$diff_days" "$reset_hm"
    elif [ "$diff_days" -eq 1 ]; then
        printf "明%s" "$reset_hm"
    else
        printf "%s" "$reset_hm"
    fi
}

# ➜  目录
printf '%s➜%s  %s%s%s' "$ARROW" "$RESET" "$DIR" "$basename_dir" "$RESET"

# git:(branch)↑N
if [ -n "$git_branch" ]; then
    if [ "$git_dirty" -eq 1 ]; then
        printf '  %sgit:(%s)%s' "$GIT_DIRTY" "$git_branch" "$RESET"
    else
        printf '  %sgit:(%s)%s' "$GIT_CLEAN" "$git_branch" "$RESET"
    fi
    [ -n "$git_ahead" ] && printf '%s↑%s%s' "$WARN" "$git_ahead" "$RESET"
fi

# 模型名
[ -n "$model_short" ] && emit_segment "$DIM" "$model_short"

# 上下文剩余
if [ -n "$remaining_pct" ]; then
    remaining_int=$(printf "%.0f" "$remaining_pct" 2>/dev/null)
    [ -n "$remaining_int" ] && emit_segment "$DIM" "ctx ${remaining_int}%"
fi

# 推理强度
[ -n "$effort_level" ] && emit_segment "$DIM" "⚡${effort_level}"

# 5 小时限额：始终显示，分级着色；有重置时间就追加 "→HH:MM"
if [ -n "$rate_5h_pct" ]; then
    r5=$(printf "%.0f" "$rate_5h_pct" 2>/dev/null)
    if [ -n "$r5" ]; then
        r5_text="5h ${r5}%"
        r5_reset=$(format_reset_time "$rate_5h_reset")
        [ -n "$r5_reset" ] && r5_text="${r5_text}→${r5_reset}"
        emit_segment "$(rate_color "$r5")" "$r5_text"
    fi
fi

# 7 天限额：仅 >=50% 时显示，避免常态占位；有重置时间就追加 "→HH:MM"
if [ -n "$rate_7d_pct" ]; then
    r7=$(printf "%.0f" "$rate_7d_pct" 2>/dev/null)
    if [ -n "$r7" ] && [ "$r7" -ge 50 ]; then
        r7_text="7d ${r7}%"
        r7_reset=$(format_reset_time "$rate_7d_reset")
        [ -n "$r7_reset" ] && r7_text="${r7_text}→${r7_reset}"
        emit_segment "$(rate_color "$r7")" "$r7_text"
    fi
fi

# 非默认输出风格
[ -n "$output_style" ] && emit_segment "$WARN" "$output_style"

# 会话名 / agent 名
[ -n "$session_label" ] && emit_segment "$DIM" "@${session_label}"

printf '\n'
