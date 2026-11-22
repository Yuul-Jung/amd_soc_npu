#!/usr/bin/env python3
"""31장: 보안 적재 시험용 '모델 B'(29장과 같은 6→3 구조, 다른 seed·학습 길이). PC 전용, PyTorch 필요.
29장 train_sensor_model.py를 seed·epoch만 바꿔 실행하고 결과를 이 폴더의 model_b_f32.json으로 저장한다."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
import part03.ch29.reference.train_sensor_model as t  # noqa: E402

out = Path(__file__).with_name("model_b_f32.json")
t.SEED, t.EPOCHS = 3131, 700
t.MODEL_JSON = out                     # 29장 파일은 건드리지 않는다
t.main()
doc = json.loads(out.read_text())
doc["model"] = "sensor_linear_6x3_f32_model_b"
out.write_text(json.dumps(doc) + "\n")
