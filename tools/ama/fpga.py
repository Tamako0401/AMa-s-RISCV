"""生成 FPGA 工程并检查综合结果。"""

import os
import re
import unicodedata
import shutil
import subprocess
from pathlib import Path

from .boards import ROOT, read_board
from . import local
from .firmware import hwid, run


def project_dir(board, app):
    return ROOT / 'build/fpga' / (f'{board}-{app}' if app else board)


def backend(board):
    data = read_board(board)
    if data['tool'] not in BACKENDS:
        raise SystemExit(f'不支持 FPGA 工具: {data["tool"]} (只支持 vivado、pds)')
    return data, BACKENDS[data['tool']]


def generate(board, app, rom):
    data, (generate_project, _, _) = backend(board)
    out = project_dir(board, app)
    out.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(rom, out / 'firmware.hex')
    # 加速器的权重 ROM 用 $readmemh("rtl/nn/nn_w.mem") 载入, 路径相对于工具的工作目录
    # (build.tcl 第一行 cd 到这里), 所以按同样的相对路径放一份。
    for mem in (ROOT / 'rtl/nn').glob('*.mem'):
        (out / 'rtl/nn').mkdir(parents=True, exist_ok=True)
        shutil.copyfile(mem, out / 'rtl/nn' / mem.name)
    # soc.f 直接喂给 Verilator (-f), 注释行 (//、#) 按它的语义跳过
    sources = [
        ROOT / p for p in (ROOT / 'rtl/soc.f').read_text().splitlines()
        if p and not p.startswith(('+', '//', '#'))
    ]
    top = ROOT / 'boards' / board / data['top']
    generate_project(board, data, out, sources, top, hwid(board))
    return out


def build(board, out):
    data, (_, run_project, _) = backend(board)
    (out / data['bitstream']).unlink(missing_ok=True)
    run_project(data, out)
    report(board, out)


def report(board, out):
    """打印上次构建的资源 (每个模块 + 全片) 和时序。"""
    data, (_, _, print_report) = backend(board)
    print_report(data, out)


def execute(data, out, args):
    path = out / f'{data["tool"]}-build.log'
    with path.open('w') as log:
        if run(*args, cwd=out, stdout=log, stderr=subprocess.STDOUT, check=False).returncode:
            raise SystemExit(f'{data["tool"]} 失败, 看日志 {path}')
    return path, path.read_text(errors='replace')


def project_inputs(board, data, out, sources, top):
    sources = [*sources, top]
    paths = [os.path.relpath(p, out) for p in sources]
    constraints = [os.path.relpath(ROOT / 'boards' / board / p, out) for p in data['constraints']]
    include = ' '.join('{' + os.path.relpath(p, out) + '}' for p in [ROOT, ROOT / 'rtl/core', ROOT / 'rtl/nn'])
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
        'report_utilization -hierarchical -hierarchical_depth 3 -file utilization_modules.rpt',
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


def vivado_report(data, out):
    # 表格: | 实例 (每层缩进两格) | 模块 | Total LUTs | Logic LUTs | LUTRAMs | SRLs | FFs | RAMB36 | RAMB18 | DSP |
    rows = []
    for line in (out / 'utilization_modules.rpt').read_text().splitlines():
        cells = [c.strip() for c in line.split('|')[1:-1]]
        if len(cells) > 9 and cells[2].isdigit():
            name = line.split('|')[1].rstrip()
            ram = float(cells[7]) * 36 + float(cells[8]) * 18
            rows.append(((len(name) - len(name.lstrip())) // 2 - 1, cells[0], cells[2], cells[6], ram, cells[9]))
    print_modules(rows)
    # 全片: | Site Type | Used | Fixed | Prohibited | Available | Util% |, 同名行取第一次出现的
    names = {'Slice LUTs': 'LUT', 'Slice Registers': 'FF', 'Block RAM Tile': 'RAM', 'DSPs': 'DSP', 'Bonded IOB': 'IO'}
    used = {}
    for line in (out / 'utilization.rpt').read_text().splitlines():
        cells = [c.strip() for c in line.split('|')[1:-1]]
        if len(cells) == 6 and cells[0] in names and names[cells[0]] not in used:
            used[names[cells[0]]] = (float(cells[1]), float(cells[4]))
    # 时序: 时钟表给周期, 时钟内路径表给 WNS / WHS; 能跑到的频率 = 1 / (周期 - WNS)
    timing = (out / 'timing_summary.rpt').read_text()
    periods = dict(re.findall(r'^\s*(\S+)\s+\{[^}]*\}\s+([\d.]+)', timing.split('| Clock Summary')[1], re.M))
    clocks = []
    for name, wns, whs in re.findall(
        r'^\s*(\S+)\s+(-?[\d.]+)\s+-?[\d.]+\s+\d+\s+\d+\s+(-?[\d.]+)', timing.split('| Intra Clock Table')[1], re.M
    ):
        period = float(periods[name])
        clocks.append((name, 1000 / period, 1000 / (period - float(wns)), float(wns), float(whs)))
    print_summary(used, '每块 36 Kb', clocks)


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
        pds_report(data, out)
        raise SystemExit(f'PDS 时序没有满足约束，检查 {timing}')


def pds_report(data, out):
    timing = out / 'report_timing' / f'{Path(data["top"]).stem}.rtr'
    # 综合报告里的 "Device Utilization Summary Of Each Module": | 实例 (每层缩进两格, 带 +) | LUT | FF | ...
    report = out / 'synthesize' / f'{Path(data["top"]).stem}.snr'
    text = report.read_text(encoding='gbk', errors='replace')
    # Logos2 的 DRM 列按 36 Kb 块计 (18 Kb 块算 0.5), Logos 全是 18 Kb 块
    block_kb = 36 if data.get('family') == 'Logos2' else 18
    # 列: 实例 | LUT | FF | Distributed RAM | APM | DRM | ...
    rows = []
    for line in text.split('Summary Of Each Module')[1].split('\n\n')[0].splitlines():
        cells = line.split('|')[1:-1]
        if len(cells) > 5 and cells[1].strip().isdigit():
            name = cells[0].rstrip()
            depth = (len(name) - len(name.lstrip(' +'))) // 2
            ram = float(cells[5]) * block_kb
            rows.append((depth, name.strip(' +'), cells[1].strip(), cells[2].strip(), ram, cells[4].strip()))
    print_modules(rows)
    # 全片, 如 "Total LUTs: 5198 of 42800 (12.14%)"、"Total DRM18K = 71.0 of 134 (52.99%)";
    # Logos2 的行名不带 18K ("Total DRM = 106.0 of 155"), 块也是 36 Kb 的
    names = {'LUTs': 'LUT', 'Registers': 'FF', 'DRM18K': 'RAM', 'DRM': 'RAM', 'APMs': 'DSP', 'I/O ports': 'IO'}
    found = re.findall(r'^Total (LUTs|Registers|DRM18K|DRM|APMs|I/O ports)\s*[:=]\s*([\d.]+) of (\d+)', text, re.M)
    used = {names[name]: (float(n), float(total)) for name, n, total in found}
    # 时序: Performance Summary 给每个时钟的要求频率、能跑到的频率和建立余量; Hold Summary 给保持余量
    rtr = timing.read_text(errors='replace')
    perf = rtr.split('Performance Summary')[1].split('====')[0]
    hold = rtr.split('Hold Summary(Slow Corner)')[1].split('====')[0]
    whs = {a: float(w) for a, b, w in re.findall(r'^\s*(\S+)\s+(\S+)\s+(-?[\d.]+)\s', hold, re.M) if a == b}
    clocks = [
        (name, float(want), float(fmax), float(wns), whs.get(name, float('nan')))
        for name, want, fmax, wns in re.findall(
            r'^\s*(\S+)\s+([\d.]+) MHz\s+([\d.]+) MHz\s+[\d.]+\s+[\d.]+\s+(-?[\d.]+)', perf, re.M
        )
    ]
    print_summary(used, f'每块 {block_kb} Kb', clocks)


def cells(*columns):
    """按 (文字, 宽度) 排一行, 宽度为负表示左对齐; 中文按两格宽算。"""
    out = ''
    for text, width in columns:
        text = str(text)
        pad = ' ' * max(abs(width) - len(text) - sum(unicodedata.east_asian_width(c) == 'W' for c in text), 0)
        out += (text + pad if width < 0 else pad + text) + ' '
    return out.rstrip()


def print_summary(used, ram_unit, clocks):
    """全片用量和每个时钟的时序。clocks: (时钟, 要求 MHz, 能跑到 MHz, 建立余量 WNS, 保持余量 WHS)。"""
    print('\n' + cells(('全片', -6), ('用了', 8), ('共有', 8), ('占比', 7)))
    for name in ['LUT', 'FF', 'RAM', 'DSP', 'IO']:
        if name in used:
            n, total = used[name]
            note = f'  ({ram_unit})' if name == 'RAM' else ''
            print(f'{name:6} {n:>8g} {total:>8g} {n / total:>7.1%}{note}')
    print('\n' + cells(('时钟', -16), ('要求', 9), ('能跑到', 9), ('WNS(ns)', 8), ('WHS(ns)', 8)))
    for name, want, fmax, wns, whs in clocks:
        print(f'{name:16} {want:>5.1f} MHz {fmax:>5.1f} MHz {wns:>+8.3f} {whs:>+8.3f}')


def print_modules(rows):
    """按模块的资源表, 只显示前三层 (顶层 / soc / soc 里的模块和核里的模块)。RAM 是块 RAM 的 Kbit, DSP 是乘法器块。"""
    print(cells(('模块', -28), ('LUT', 6), ('FF', 6), ('RAM(Kb)', 8), ('DSP', 4)))
    for depth, name, lut, ff, ram, dsp in rows:
        if depth <= 3:
            print(f'{"  " * depth + name:28} {lut:>6} {ff:>6} {ram:>8g} {dsp:>4}')


BACKENDS = {'vivado': (vivado_generate, vivado_build, vivado_report), 'pds': (pds_generate, pds_build, pds_report)}
