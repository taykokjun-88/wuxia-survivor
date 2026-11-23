"""把 Gemini 的 2 秒 SFX v2 裁尾、限长、按旧音效响度归一后覆盖 assets/sfx。
用法: python3 tools/process_sfx_v2.py <解压目录>"""
import wave, glob, os, sys, numpy as np
LONG = ('jingle', 'bell_ring')   # 允许保留较长尾音
def load(f):
    w = wave.open(f); ch = w.getnchannels()
    d = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).reshape(-1, ch).astype(float) / 32768
    return d, w.getframerate()
def active_rms(d):
    m = np.abs(d).max(axis=1); idx = np.where(m > 0.02)[0]
    seg = d[idx.min():idx.max() + 1] if len(idx) else d
    return float(np.sqrt((seg ** 2).mean())) + 1e-9
src = sys.argv[1]
for f in sorted(glob.glob(src + '/*.wav')):
    b = os.path.basename(f); name = b[:-4]; o = 'assets/sfx/' + b
    c, sr = load(f); a, _ = load(o)
    m = np.abs(c).max(axis=1)
    # 平滑包络，找最后一个高于 -50dB 的点
    k = int(sr * 0.02); env = np.convolve(m, np.ones(k) / k, 'same')
    idx = np.where(env > 0.003)[0]; end = (idx.max() if len(idx) else len(c)) + int(sr * 0.03)
    cap = 2.0 if any(s in name for s in LONG) else max(0.45, min(1.3, len(a) / sr * 3))
    end = min(end, int(cap * sr), len(c)); c = c[:end]
    fl = min(len(c), int(sr * (0.25 if end / sr > 0.8 else 0.06)))
    c[-fl:] *= np.linspace(1, 0, fl)[:, None]
    g = np.clip(active_rms(a) / active_rms(c), 0.4, 2.5); c = c * g
    p = np.abs(c).max()
    if p > 0.95: c *= 0.95 / p
    pcm = (np.clip(c, -1, 1) * 32767).astype('<i2')
    w = wave.open(o, 'wb'); w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr); w.writeframes(pcm.tobytes()); w.close()
    print(name, round(end / sr, 2), 's gain', round(g, 2))
