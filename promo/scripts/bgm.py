"""合成一段轻快的背景音乐（不依赖第三方库）：I–vi–IV–V 和弦琶音 + 贝斯 + 沙锤 + 一段五声音阶小旋律。
用法：python3 scripts/bgm.py public/sfx/bgm.wav [秒数]"""
import math, random, struct, sys, wave

SR = 22050
BPM = 112
BEAT = 60 / BPM
out = sys.argv[1]
seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 66
N = int(SR * seconds)
buf = [0.0] * N
rng = random.Random(7)

def note(freq, start, dur, vol, kind="pluck"):
    i0 = int(start * SR)
    n = int(dur * SR)
    for k in range(n):
        i = i0 + k
        if i >= N: break
        t = k / SR
        if kind == "pluck":     # 带一点泛音、快速衰减，像拨弦 / 八音盒
            env = math.exp(-t * 6) * min(1, t * 400)
            v = math.sin(2 * math.pi * freq * t) + 0.35 * math.sin(4 * math.pi * freq * t) + 0.1 * math.sin(6 * math.pi * freq * t)
        elif kind == "bass":
            env = math.exp(-t * 2.5) * min(1, t * 200)
            v = math.sin(2 * math.pi * freq * t)
        else:                   # bell：旋律，偏亮
            env = math.exp(-t * 3.5) * min(1, t * 300)
            v = math.sin(2 * math.pi * freq * t) + 0.5 * math.sin(2 * math.pi * freq * 2.01 * t) * math.exp(-t * 8)
        buf[i] += v * env * vol

def shaker(start, vol):
    i0 = int(start * SR)
    for k in range(int(0.06 * SR)):
        if i0 + k >= N: break
        t = k / SR
        buf[i0 + k] += (rng.random() * 2 - 1) * math.exp(-t * 70) * vol

hz = lambda m: 440 * 2 ** ((m - 69) / 12)
# C - Am - F - G，每个和弦一小节
chords = [[60, 64, 67], [57, 60, 64], [53, 57, 60], [55, 59, 62]]
bass = [36, 33, 29, 31]
# 四小节一句的小旋律（MIDI，None 是休止），八分音符
melody = [76, None, 79, 76, 74, None, 72, None, 74, 76, None, 72, 69, None, None, None,
          72, None, 74, 76, 79, None, 76, None, 74, 72, None, 74, 72, None, None, None]
bar = 4 * BEAT
t = 0.0
i = 0
while t < seconds:
    c = chords[i % 4]
    note(hz(bass[i % 4]), t, bar, 0.30, "bass")
    note(hz(bass[i % 4]), t + 2 * BEAT, bar / 2, 0.22, "bass")
    arp = c + [c[1] + 12, c[2], c[1], c[0] + 12, c[2]]
    for k in range(8):
        note(hz(arp[k]), t + k * BEAT / 2, BEAT, 0.13)
        shaker(t + k * BEAT / 2 + BEAT / 4, 0.05)
    if i >= 2:  # 前两小节只有伴奏，之后旋律进来
        phrase = melody[(i % 4) * 8:(i % 4) * 8 + 8]   # 四小节一句，每小节 8 个八分音符
        for k, m in enumerate(phrase):
            if m: note(hz(m), t + k * BEAT / 2, BEAT * 1.5, 0.16, "bell")
    t += bar
    i += 1

peak = max(abs(x) for x in buf) or 1
with wave.open(out, "w") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x / peak * 0.9)) * 32767)) for x in buf))
print("已生成", out)
