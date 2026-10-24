"""上板前的静态检查, 不依赖 PDS: 管脚重复与参照库核对、GPLL 参数边界、软件 SYSCLK_HZ 一致性。

PDS 综合前的拦截网: 管脚写错位置、两个端口撞同一个焊盘、PLL 参数出 VCO 边界、
RTL 的 PLL 输出和 bsp.h 的 SYSCLK_HZ 对不上, 这些都能在秒级查出来。
管脚参照库 boards/<板>/padrefs.csv 由厂商例程 FDC 和硬件手册表格生成 (文件头有出处)。
"""

import csv
import re
import subprocess

from .boards import ROOT, read_board
from .firmware import compiler

# Logos2 GPLL 交流特性, DS04001 §4.4 (速度等级 -5/-6)
GPLL = {'fin': (10, 800), 'fpfd': (10, 450), 'vco': (600, 1200), 'fout': (4.69, 800)}
# 参数语义由厂商例程 2_5_pll_test 反推 (27MHz 进 54/81MHz 出, VCO=1053 验证):
#   VCO = fin × RATIOM × RATIOF / RATIOI,  clkout_i = VCO / RATIO_i


def fdc_locs(board):
    """约束文件里的 (管脚, 端口) 对。返回 {loc: [(文件名, 端口), ...]} 和原始对列表。"""
    data = read_board(board)
    by_loc, pairs = {}, []
    for name in data['constraints']:
        text = (ROOT / 'boards' / board / name).read_text(errors='replace')
        for port, loc in re.findall(r'define_attribute \{p:([^}]+)\} \{PAP_IO_LOC\} \{([^}]+)\}', text):
            loc, port = loc.strip(), port.strip()
            by_loc.setdefault(loc, []).append((name, port))
            pairs.append((name, port, loc))
    return by_loc, pairs


def pin_names(board):
    """pins.csv 的名字按行序 = io 下标, io[12] 能反查出 LED1 这样的功能名。"""
    path = ROOT / 'boards' / board / 'pins.csv'
    return [row['name'] for row in csv.DictReader(path.open())] if path.exists() else []


def load_padrefs(board):
    """boards/<板>/padrefs.csv -> {loc: [(net, source), ...]}; 没有就返回空 (检查降级)。"""
    path = ROOT / 'boards' / board / 'padrefs.csv'
    refs = {}
    if path.exists():
        for row in csv.reader(line for line in path.read_text().splitlines() if not line.startswith('#')):
            if len(row) == 3:
                refs.setdefault(row[0], []).append((row[1], row[2]))
    return refs


# 例程端口名的等价/展开规则: 厂商例程按颜色通道 (b_out/r_in) 和 pix_clk 命名 HDMI,
# 本仓库按总线 (hdmi_d) 命名; KEY0 手册叫 rst。展开后两边才谈得上 token 重叠。
ALIASES = {
    'pclk': {'p', 'clk'},
    'pixclk': {'pix', 'clk'},
    'key': {'rst'},
    'rst': {'key'},
}


def tokens(name):
    """网络名拆成小写字母段: HD_TX_D0 -> {hd, tx, d}, lcd_sck -> {lcd, sck}。
    HDMI 数据总线按位段补上颜色通道 token (D[7:0]=B, [15:8]=G, [23:16]=R)。"""
    result = {t for t in re.split(r'[^a-z]+', name.lower()) if t}
    m = re.fullmatch(r'(hdmi(?:_rx)?_d)\[(\d+)\]', name.lower())
    if m:
        result.add('bgr'[int(m[2]) // 8])
    return result | {a for t in result for a in ALIASES.get(t, ())}


def sysclk_hz(board):
    """预处理 sw/bsp/bsp.h 拿到本板的 SYSCLK_HZ, 和 RTL 的 PLL 输出对账。"""
    args = [
        *compiler(),
        '-E',
        '-dM',
        f'-DBOARD_{board.upper()}',
        *[f'-I{d}' for d in ('sw/device', 'sw/drivers', 'sw/bsp')],
        '-x',
        'c',
        '-',
    ]
    result = subprocess.run(args, check=False, input=b'#include "bsp.h"\n', capture_output=True, cwd=ROOT)
    found = re.search(rb'#define SYSCLK_HZ (\d+)UL', result.stdout)
    return int(found[1]) if found else None


def check_pll(board, problems):
    """顶层内联的 GTP_GPLL: 参数边界 + 输出频率和 SYSCLK_HZ 对账。返回算出的 MHz 数。"""
    data = read_board(board)
    top = (ROOT / 'boards' / board / data['top']).read_text(errors='replace')
    m = re.search(r'GTP_GPLL\s*#', top)
    if not m:
        return None

    def param(name):
        found = re.search(r'\.\s*' + name + r'\(\s*([0-9.]+)\s*\)', top[m.start() :])
        return float(found[1]) if found else None

    fin, ratioi = param('CLKIN_FREQ'), param('STATIC_RATIOI')
    ratiom, ratiof, ratio0 = param('STATIC_RATIOM'), param('STATIC_RATIOF'), param('STATIC_RATIO0')
    if None in (fin, ratioi, ratiom, ratiof, ratio0):
        problems.append(('ERROR', 'GTP_GPLL 参数没抓全 (写法变了?)', ''))
        return None
    fpfd = fin / ratioi
    vco = fin * ratiom * ratiof / ratioi
    out0 = vco / ratio0
    for value, name, limit in [
        (fin, '输入 MHz', GPLL['fin']),
        (fpfd, 'PFD MHz', GPLL['fpfd']),
        (vco, 'VCO MHz', GPLL['vco']),
        (out0, 'clkout0 MHz', GPLL['fout']),
    ]:
        if not limit[0] <= value <= limit[1]:
            problems.append(('ERROR', f'GTP_GPLL {name} = {value:g} 超出 datasheet 边界 {limit}', ''))
    hz = sysclk_hz(board)
    if hz and abs(out0 * 1e6 - hz) > hz * 0.001:
        problems.append(('ERROR', f'PLL clkout0 = {out0:g} MHz, bsp.h 的 SYSCLK_HZ = {hz / 1e6:g} MHz, 对不上', ''))
    # 晶振输入的 create_clock 周期要和 CLKIN_FREQ 一致
    for name in data['constraints']:
        text = (ROOT / 'boards' / board / name).read_text(errors='replace')
        for period, port in re.findall(r'create_clock -name \S+ -period ([\d.]+) \[get_ports \{(\w+)\}\]', text):
            if port == 'clk' and abs(1000 / float(period) - fin) > 0.01:
                problems.append(
                    ('ERROR', f'{name}: clk 约束 {1000 / float(period):g} MHz != PLL CLKIN_FREQ {fin:g} MHz', '')
                )
    return out0


def check(board):
    """跑全部检查, 返回 [(级别, 说明, 证据)]。ERROR 让 ama fpga build/check 失败, WARN 只提示。"""
    data = read_board(board)
    problems = []
    if data['tool'] != 'pds':
        return problems  # xdc 的物理约束写法不同, 先只查 pds 板
    by_loc, pairs = fdc_locs(board)
    for loc, uses in by_loc.items():
        if len(uses) > 1:
            problems.append(
                ('ERROR', f'管脚 {loc} 被约束了 {len(uses)} 次: ' + ', '.join(f'{f}:{p}' for f, p in uses), '')
            )
    refs = load_padrefs(board)
    names = pin_names(board)
    vindicated = 0
    for _, port, loc in pairs:
        m = re.fullmatch(r'io\[(\d+)\]', port)
        ours = names[int(m[1])] if m and int(m[1]) < len(names) else port
        if refs:
            if loc not in refs:
                problems.append(('ERROR', f'{ours} 的管脚 {loc} 不在参照库里 (padrefs.csv)', ''))
                continue
            demo_nets = [net for net, src in refs[loc] if src.startswith('demo:')]
            if demo_nets and not tokens(ours) & set().union(*map(tokens, demo_nets)):
                problems.append(
                    ('WARN', f'{ours} 在 {loc}, 例程同脚的端口是 {" ".join(demo_nets)}, 名字对不上 (人工确认)', '')
                )
            vindicated += 1
    pll_out = check_pll(board, problems)
    print(
        f'检查 {board}: {len(pairs)} 个管脚约束'
        + (f', {vindicated} 个在参照库里' if refs else ', 无参照库 (padrefs.csv), 只查了重复')
        + (f', PLL clkout0 = {pll_out:g} MHz' if pll_out else '')
    )
    for level, msg, _ in problems:
        print(f'{level}: {msg}')
    return problems


def fatal(board):
    """ama fpga build 的预检: 有 ERROR 就拦下。"""
    return any(level == 'ERROR' for level, _, _ in check(board))
