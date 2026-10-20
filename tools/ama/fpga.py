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


def backend(board):
    data = read_board(board)
    if data['tool'] not in BACKENDS:
        raise SystemExit(f'不支持 FPGA 工具: {data["tool"]} (只支持 vivado、pds)')
    return data, BACKENDS[data['tool']]


def generate(board, app, rom):
    data, (generate_project, _) = backend(board)
    out = project_dir(board, app)
    out.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(rom, out / 'firmware.hex')
    sources = [ROOT / p for p in (ROOT / 'rtl/soc.f').read_text().splitlines() if p and not p.startswith('+')]
    top = ROOT / 'boards' / board / data['top']
    generate_project(board, data, out, sources, top, hwid(board))
    return out


def build(board, out):
    data, (_, run_project) = backend(board)
    (out / data['bitstream']).unlink(missing_ok=True)
    run_project(data, out)


def execute(data, out, args):
    path = out / f'{data["tool"]}-build.log'
    with path.open('w') as log:
        run(*args, cwd=out, stdout=log, stderr=subprocess.STDOUT)
    return path, path.read_text(errors='replace')


def project_inputs(board, data, out, sources, top):
    sources = [*sources, top]
    paths = [os.path.relpath(p, out) for p in sources]
    constraints = [os.path.relpath(ROOT / 'boards' / board / p, out) for p in data['constraints']]
    include = ' '.join('{' + os.path.relpath(p, out) + '}' for p in [ROOT, ROOT / 'rtl/core'])
    name = top.stem
    return paths, constraints, include, name


def vivado_generate(board, data, out, sources, top, hardware_id):
    paths, constraints, include, name = project_inputs(board, data, out, sources, top)
    tcl = [f'read_verilog {{{p}}}' for p in paths]
    tcl += [f'read_xdc {{{p}}}' for p in constraints]
    tcl += [
        f"synth_design -top {name} -part {data['part']} -generic HW_ID=32'h{hardware_id:08x} -include_dirs {{{include}}}",
        'opt_design',
        'place_design',
        'route_design',
        'report_timing_summary -file timing_summary.rpt',
        'report_utilization -file utilization.rpt',
        'set wns [get_property SLACK [get_timing_paths -delay_type max]]',
        'if {$wns < 0} {error "Timing failed: WNS = $wns ns"}',
        f'write_bitstream -force {data["bitstream"]}',
    ]
    (out / 'build.tcl').write_text('\n'.join(tcl) + '\n')


def vivado_build(data, out):
    log_path, log = execute(data, out, [*local.tool('vivado'), '-mode', 'batch', '-source', 'build.tcl'])
    if "$readmem data file 'firmware.hex' is read successfully" not in log:
        raise SystemExit(f'Vivado 没有读取固件初始化文件，检查 {log_path}')
    if not (out / data['bitstream']).exists():
        raise SystemExit(f'Vivado 没有生成位流，检查 {log_path}')


def pds_generate(board, data, out, sources, top, hardware_id):
    # PDS 的参数覆盖依赖版本，复制顶层才能可靠固化 HW_ID。
    generated = out / top.name
    generated.write_text(
        top.read_text().replace('parameter [31:0] HW_ID = 0,', f"parameter [31:0] HW_ID = 32'h{hardware_id:08x},")
    )
    top = generated
    paths, constraints, include, name = project_inputs(board, data, out, sources, top)
    tcl = [
        f'set_arch -family {data["family"]} -device {data["device"]} -speedgrade {data["speedgrade"]} -package {data["package"]}'
    ]
    tcl += [f'add_design {{{p}}}' for p in paths]
    tcl += [f'add_constraint {{{p}}}' for p in constraints]
    tcl += [
        f'compile -top_module {name} -include_path {{{include}}}',
        'synthesize -ads -selected_syn_tool_opt 2',
        'dev_map',
        'pnr',
        'report_timing',
        'gen_bit_stream',
    ]
    (out / 'build.tcl').write_text('\n'.join(tcl) + '\n')


def pds_build(data, out):
    log_path, log = execute(data, out, [*local.tool('pds_shell'), '-file', 'build.tcl'])
    if 'Cannot open specified data file' in log:
        raise SystemExit(f'PDS 没有读取固件初始化文件，检查 {log_path}')
    if 'gen_bit_stream successfully' not in log or not (out / data['bitstream']).exists():
        raise SystemExit(f'PDS 没有生成位流，检查 {log_path}')
    timing = out / 'report_timing' / f'{Path(data["top"]).stem}.rtr'
    if 'All Constraints Met.' not in timing.read_text(errors='replace'):
        raise SystemExit(f'PDS 时序没有满足约束，检查 {timing}')


BACKENDS = {'vivado': (vivado_generate, vivado_build), 'pds': (pds_generate, pds_build)}
