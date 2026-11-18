#!/usr/bin/env python3
"""(추가) 22장: 21장 XSA로 MicroBlaze V standalone 플랫폼과 NPU 드라이버 응용을 빌드한다(Vitis 2024.2 Python API).

사용: vitis -s vitis_build.py <workspace> <xsa> <sw 폴더> <model_data.h>
"""
import os
import sys

import vitis

ws, xsa, swdir, model_h = sys.argv[1:5]
client = vitis.create_client()
client.set_workspace(ws)
plat = client.create_platform_component(name="soc21_npu_plat", hw_design=xsa, os="standalone",
                                        cpu="microblaze_riscv_0", domain_name="standalone_mbv")
plat.build()
xpfm = client.find_platform_in_repos("soc21_npu_plat")
app = client.create_app_component(name="npu_app", platform=xpfm, domain="standalone_mbv",
                                  template="empty_application")
app.import_files(from_loc=swdir, dest_dir_in_cmp="src",
                 files=["npu_driver.h", "npu_driver.c", "app.h", "app.c", "npu_io_xil.c", "main.c"])
app.import_files(from_loc=os.path.dirname(model_h), files=[os.path.basename(model_h)], dest_dir_in_cmp="src")
app.build()
print("VITIS_BUILD_DONE")
vitis.dispose()
