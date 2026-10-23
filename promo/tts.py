# Hindi narration with Kokoro-82M (Apache-2.0). Every line in each Hindi voice; Whisper checks clarity.
import json, os, difflib, unicodedata
import numpy as np, soundfile as sf, torch
from kokoro import KPipeline
import whisper, librosa

torch.set_num_threads(os.cpu_count())
SR = 24000
VOICES = ["hm_omega", "hm_psi", "hf_alpha", "hf_beta"]
pipe = KPipeline(lang_code="h")
asr = whisper.load_model("small")
lines = json.load(open("lines.json"))

def norm(s):
    return "".join(c for c in unicodedata.normalize("NFC", s) if c.isalnum())

def heard(w):
    a = librosa.resample(w.astype(np.float32), orig_sr=SR, target_sr=16000)
    return asr.transcribe(a, language="hi", fp16=False)["text"]

report = {}
for v in VOICES:
    os.makedirs(f"out/{v}", exist_ok=True)
    tot = []
    for lid, sents in lines:
        parts = []
        for s in sents:
            audio = [a for _, _, a in pipe(s, voice=v, speed=1.08)]
            w = np.concatenate([np.asarray(a) for a in audio]).astype(np.float32)
            idx = np.where(np.abs(w) > 0.02 * np.abs(w).max())[0]
            w = w[max(0, idx[0] - 600): idx[-1] + 2000]
            h = heard(w)
            sc = difflib.SequenceMatcher(None, norm(h), norm(s)).ratio()
            tot.append(sc)
            print(v, lid, round(sc, 3), "|", s, "|", h, flush=True)
            parts += [w, np.zeros(int(0.24 * SR), np.float32)]
        out = np.concatenate(parts[:-1])
        sf.write(f"out/{v}/{lid}.wav", out / np.abs(out).max() * 0.9, SR)
    report[v] = round(float(np.mean(tot)), 3)
    print("VOICE", v, report[v], flush=True)
json.dump(report, open("out/report.json", "w"), indent=1)
