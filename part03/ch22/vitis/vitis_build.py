#!/usr/bin/env python3
"""5-2 XSA로 MicroBlaze V standalone 플랫폼과 응용(ELF)을 빌드한다(Vitis 2024.2 Python API).

5-4: 응용 이름과 소스 파일 목록을 인자로 받는다. 같은 workspace의 플랫폼은 한 번만 만든다.
6-1: 플랫폼 이름을 환경 변수 P3_PLAT_NAME으로 바꿀 수 있다(기본 soc21_npu_plat, 5-3·5-4 동작 그대로).
사용: vitis -s vitis_build.py <workspace> <xsa> <app 이름> <소스 파일...>
"""
import os
import sys

import vitis

ws, xsa, app_name = sys.argv[1:4]
files = sys.argv[4:]
plat_name = os.environ.get("P3_PLAT_NAME", "soc21_npu_plat")
client = vitis.create_client()
client.set_workspace(ws)
if not os.path.isdir(os.path.join(ws, plat_name)):
    plat = client.create_platform_component(name=plat_name, hw_design=xsa, os="standalone",
                                            cpu="microblaze_riscv_0", domain_name="standalone_mbv")
    plat.build()
xpfm = client.find_platform_in_repos(plat_name)
app = client.create_app_component(name=app_name, platform=xpfm, domain="standalone_mbv",
                                  template="empty_application")
for f in files:
    app.import_files(from_loc=os.path.dirname(f), files=[os.path.basename(f)], dest_dir_in_cmp="src")
app.build()
print(f"VITIS_BUILD_DONE {app_name}")
vitis.dispose()
