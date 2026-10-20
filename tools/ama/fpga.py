"""生成 FPGA 工程并检查综合结果。"""
import os
import shutil
import subprocess
from pathlib import Path

from .boards import ROOT, read_board
from . import local
from .firmware import hwid, run


def project_dir(board, app):
    return ROOT / 'build/fpga' / f'{board}-{app}'


def generate(board, app, rom):
    data = read_board(board)
    out = project_dir(board, app)
    out.mkdir(parents=True, exist_ok=True)
    # 两种工具都从工程目录读取顶层默认的初始化文件。
    shutil.copyfile(rom, out / 'firmware.hex')
    sources = [ROOT / p for p in (ROOT / 'rtl/soc.f').read_text().splitlines() if p and not p.startswith('+')]
    top = ROOT / 'boards' / board / data['top']
    hardware_id = hwid(board)
    if data['tool'] == 'pds':
        # PDS 的参数覆盖依赖版本，复制顶层才能可靠固化 HW_ID。
        generated = out / top.name
        generated.write_text(top.read_text().replace('parameter [31:0] HW_ID = 0,',
                             f"parameter [31:0] HW_ID = 32'h{hardware_id:08x},"))
        top = generated
    sources.append(top)
    paths = [os.path.relpath(p, out) for p in sources]
    constraints = [os.path.relpath(ROOT / 'boards' / board / p, out) for p in data['constraints']]
    include = ' '.join('{' + os.path.relpath(p, out) + '}' for p in [ROOT, ROOT / 'rtl/core'])
    name = top.stem
    if data['tool'] == 'vivado':
        tcl = [f'read_verilog {{{p}}}' for p in paths]
        tcl += [f'read_xdc {{{p}}}' for p in constraints]
        tcl += [f"synth_design -top {name} -part {data['part']} -generic HW_ID=32'h{hardware_id:08x} -include_dirs {{{include}}}",
                'opt_design', 'place_design', 'route_design',
                'report_timing_summary -file timing_summary.rpt',
                'report_utilization -file utilization.rpt',
                'set wns [get_property SLACK [get_timing_paths -delay_type max]]',
                'if {$wns < 0} {error "Timing failed: WNS = $wns ns"}',
                f"write_bitstream -force {data['bitstream']}"]
    else:
        tcl = [f"set_arch -family {data['family']} -device {data['device']} -speedgrade {data['speedgrade']} -package {data['package']}"]
        tcl += [f'add_design {{{p}}}' for p in paths]
        tcl += [f'add_constraint {{{p}}}' for p in constraints]
        tcl += [f'compile -top_module {name} -include_path {{{include}}}',
                'synthesize -ads -selected_syn_tool_opt 2', 'dev_map', 'pnr', 'report_timing', 'gen_bit_stream']
    (out / 'build.tcl').write_text('\n'.join(tcl) + '\n')
    return out


def build(board, out):
    data = read_board(board)
    tool = data['tool']
    bit = out / data['bitstream']
    bit.unlink(missing_ok=True)
    if tool == 'vivado':
        cmd = [*local.tool('vivado'), '-mode', 'batch', '-source', 'build.tcl']
    else:
        cmd = [*local.tool('pds_shell'), '-file', 'build.tcl']
    log_path = out / f'{tool}-build.log'
    with log_path.open('w') as log:
        run(*cmd, cwd=out, stdout=log, stderr=subprocess.STDOUT)
    log = log_path.read_text(errors='replace')
    if tool == 'vivado':
        if "$readmem data file 'firmware.hex' is read successfully" not in log:
            raise SystemExit(f'Vivado 没有读取固件初始化文件，检查 {log_path}')
        if not bit.exists():
            raise SystemExit(f'Vivado 没有生成位流，检查 {log_path}')
    else:
        if 'Cannot open specified data file' in log:
            raise SystemExit(f'PDS 没有读取固件初始化文件，检查 {log_path}')
        if 'gen_bit_stream successfully' not in log or not bit.exists():
            raise SystemExit(f'PDS 没有生成位流，检查 {log_path}')
        timing = out / 'report_timing' / f"{Path(data['top']).stem}.rtr"
        if 'All Constraints Met.' not in timing.read_text(errors='replace'):
            raise SystemExit(f'PDS 时序没有满足约束，检查 {timing}')
