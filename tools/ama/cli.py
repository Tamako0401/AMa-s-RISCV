"""在 EGO1 / 盘古 MES50HP 上开发 AMa-s-RISCV 的程序。

平时改了 C:  ama run <程序>   编译, 经串口下载到板子运行, 再显示串口输出 (几秒)

改了 rtl/、boards/、sw/boot/ 之后:  ama fpga build, 然后 ama fpga program (几分钟)

程序就是 sw/app/ 下的目录名。板子按插着的 USB 串口芯片自动识别 (FT2232 = EGO1, CP2102 = 盘古),
识别不了时用 --board 指定。本机工具路径写在 ama.local.toml (见 ama.local.toml.example), 没有也能用。
"""

import subprocess
import time
from typing import Optional

import typer


from . import load, fpga as projects
from .boards import ROOT, boards, gen_pins
from .firmware import build_firmware, check_app, firmware_dir, compile_app, elf_to_rom, run, write_hex, hwid
from .local import CONFIG, TOOLS, tool

BOARDS = boards()

cli = typer.Typer(
    help=__doc__, no_args_is_help=True, add_completion=False, context_settings={'help_option_names': ['-h', '--help']}
)
fpga = typer.Typer(help='位流: 只有改了 rtl/、boards/、sw/boot/ 才需要 (几分钟)', no_args_is_help=True)
cli.add_typer(fpga, name='fpga')



App = typer.Argument(..., help='sw/app/ 下的程序名')
BoardOpt = typer.Option(None, '--board', '-b', help='ego1 或 mes50hp; 不写就按插着的串口芯片识别')
PortOpt = typer.Option(None, '--port', '-p', help='串口; 不写就自动找')
ForceOpt = typer.Option(False, '--force', help='板上位流和本地源码版本不一致时也照样下载')


def step(what):
    typer.secho(f'==> {what}', fg='cyan', bold=True)


def fail(why):
    typer.secho(f'✗ {why}', fg='red', err=True)
    raise typer.Exit(1)


def detect():
    """插着的板子: [(串口, 板名)]。FT2232 有两个口, 串口是编号大的那个, 所以倒序后每块板只取第一个"""
    from serial.tools import list_ports

    found = {}
    for p in sorted(list_ports.comports(), key=lambda p: p.device, reverse=True):
        for name, board in BOARDS.items():
            if (p.vid, p.pid) == tuple(board['usb']) and name not in found:
                found[name] = p.device
    return [(port, name) for name, port in found.items()]


def pick_board(board, port=None):
    """返回 (板名, 串口或 None)"""
    if board and board not in BOARDS:
        fail(f'没有这块板: {board} (可选 {", ".join(BOARDS)})')
    plugged = [(p, b) for p, b in detect() if board in (None, b) and port in (None, p)]
    if board:
        return board, port or (plugged[0][0] if plugged else None)
    if len(plugged) == 1:
        return plugged[0][1], plugged[0][0]
    if CONFIG.get('board') in BOARDS:
        return CONFIG['board'], port
    fail('认不出是哪块板 (没插, 或插了两块), 用 --board ego1 或 --board mes50hp 指定')


def open_port(port, board):
    import serial

    if not port:
        fail(f'没找到 {board} 的串口: 检查 USB 线, 或用 --port 指定')
    return serial.Serial(port, 115200, timeout=0.3)


def terminal(ser):
    from serial.tools import miniterm

    typer.secho(f'--- {ser.port} 115200, Ctrl+] 退出 ---', fg='cyan')
    ser.timeout = None
    term = miniterm.Miniterm(ser, echo=False)
    term.set_rx_encoding('utf-8')
    term.set_tx_encoding('utf-8')
    term.start()
    term.join(True)
    term.close()


def do_upload(app, board, port, force):
    board, port = pick_board(board, port)
    image = load.app_image(build_firmware(app, board, [], [], firmware_dir(app, board)))
    ser = open_port(port, board)
    step(f'下载到 {board} ({port})')
    hw = load.enter_bootloader(ser)
    if hw != hwid(board) and not force:
        fail(
            f'板上位流的硬件版本 0x{hw:08x} 和本地源码 0x{hwid(board):08x} 不一致 (rtl/、boards/、sw/boot/ 改过):\n'
            f'  先 ama fpga build, ama fpga program; 或者加 --force 照样下载'
        )
    start = time.monotonic()
    load.download(ser, image)
    ser.write(b'G')
    typer.secho(f'✓ {len(image)} 字节, {time.monotonic() - start:.1f} 秒', fg='green')
    return ser


@cli.command('test')
def test_cmd(paths: Optional[list[str]] = typer.Argument(None, help='测试目录或测试台文件; 不写跑全部')):
    """编译并运行 tests/ 和 sw/app/*/test/ 下的测试。"""
    from .testing import test

    if not test(paths):
        raise typer.Exit(1)


@cli.command('lint')
def lint_cmd(fix: bool = typer.Option(False, '--fix', help='直接修复工具能自动修的问题')):
    """检查 Python、C 和 Verilog 的规范及明显问题。"""
    from .lint import lint

    if not lint(fix):
        raise typer.Exit(1)


@cli.command('fmt')
def fmt_cmd(fix: bool = typer.Option(False, '--fix', help='直接改写格式不对的文件')):
    """检查 Python、C 和 Verilog 格式; 不加 --fix 只列出格式不对的文件。"""
    from .lint import fmt

    if not fmt(fix):
        raise typer.Exit(1)


@cli.command('run')
def run_cmd(app: str = App, board: Optional[str] = BoardOpt, port: Optional[str] = PortOpt, force: bool = ForceOpt):
    """编译, 下载, 然后显示串口输出 (最常用)。"""
    terminal(do_upload(app, board, port, force))


@cli.command()
def build(app: str = App, board: Optional[str] = BoardOpt):
    """只编译程序 (几秒), 不碰板子。"""
    board, _ = pick_board(board)
    elf = build_firmware(app, board, [], [], firmware_dir(app, board))
    typer.secho(f'✓ {elf.relative_to(ROOT)}', fg='green')


@cli.command()
def upload(app: str = App, board: Optional[str] = BoardOpt, port: Optional[str] = PortOpt, force: bool = ForceOpt):
    """编译, 经串口 bootloader 下载到板子上运行, 不留在串口上。"""
    do_upload(app, board, port, force).close()


@cli.command()
def monitor(board: Optional[str] = BoardOpt, port: Optional[str] = PortOpt):
    """只打开串口终端, 不下载。"""
    board, port = pick_board(board, port)
    terminal(open_port(port, board))


def sim_binary(out):
    obj = out / 'obj'
    sources = ['tests/soc/st7789_model.sv', 'sim/uart_rx.sv', 'sim/sim_top.sv']
    inputs = [ROOT / p for p in sources + ['rtl/soc.f', 'boards/mes50hp/pins_top.vh']]
    inputs += [ROOT / p for p in (ROOT / 'rtl/soc.f').read_text().split() if not p.startswith('+')]
    inputs += list((ROOT / 'rtl').rglob('*.vh'))
    binary = obj / 'sim'
    if not binary.exists() or any(p.stat().st_mtime_ns > binary.stat().st_mtime_ns for p in inputs):
        step('编译仿真外壳')
        run(
            *tool('verilator'),
            '--binary',
            '--timing',
            '-Wno-fatal',
            '--top-module',
            'sim_top',
            '-f',
            'rtl/soc.f',
            *sources,
            '--Mdir',
            obj,
            '-o',
            'sim',
            cwd=ROOT,
            stdout=subprocess.DEVNULL,
        )
    return binary


@cli.command()
def sim(app: str = App):
    """在仿真里运行 sw/app/ 下的程序, 窗口显示屏幕, 终端显示串口。"""
    from sim.view import W, H, show, save_png

    check_app(app)
    out = ROOT / 'build/sim'
    elf = compile_app(app, 'mes50hp', ['-DSIM_CYCLE_DIV=1000'], out / app)
    rom = out / f'{app}.hex'
    write_hex(elf_to_rom(elf), rom)
    binary = sim_binary(out)
    frame = out / f'{app}.frame'
    frame.write_bytes(bytes(W * H * 2))
    step(f'仿真 {app}, 关窗口或 Ctrl+C 结束')
    process = subprocess.Popen([str(binary), f'+rom={rom}', f'+frame={frame}'], cwd=ROOT, start_new_session=True)
    try:
        show(frame, process)
    except KeyboardInterrupt:
        pass
    finally:
        if process.poll() is None:
            process.terminate()
        process.wait()
        png = out / f'{app}.png'
        save_png(frame, png)
        print(f'屏幕截图: {png.relative_to(ROOT)}')


def fpga_bit(board, app):
    return projects.project_dir(board, app) / BOARDS[board]['bitstream']


@fpga.command('build')
def fpga_build(app: str = App, board: Optional[str] = BoardOpt):
    """编译固件并综合出位流。"""
    board, _ = pick_board(board)
    elf = build_firmware(app, board, [], [], firmware_dir(app, board))
    out = projects.generate(board, app, elf.parent / 'rom.hex')
    projects.build(board, out)
    bit = out / BOARDS[board]['bitstream']
    bit.with_suffix('.hwid').write_text(f'0x{hwid(board):08x}\n')
    typer.secho(f'✓ {bit.relative_to(ROOT)}; 下一步 ama fpga program {app}', fg='green')


@fpga.command('program')
def fpga_program(app: str = App, board: Optional[str] = BoardOpt):
    """把固化了 <程序> 的位流烧进 FPGA (断电会丢, 重新上电要再烧)。"""
    board, _ = pick_board(board)
    bit = fpga_bit(board, app)
    if not bit.exists():
        fail(f'还没有位流, 先 ama fpga build {app} --board {board}')
    stamp = bit.with_suffix('.hwid')
    if not stamp.exists() or int(stamp.read_text(), 0) != hwid(board):
        fail(
            f'{bit.relative_to(ROOT)} 不是用当前源码构建的 (rtl/、boards/、sw/boot/ 改过), 先 ama fpga build {app} --board {board}'
        )
    if BOARDS[board]['tool'] == 'pds':
        # 紫光的下载器没有命令行入口, 只能在 PDS 图形界面里下载
        print(f'打开 PDS → Tools → Fabric Configuration → 选择位流:\n  {bit}')
        return
    step(f'烧写 {bit.relative_to(ROOT)}')
    result = subprocess.run(
        [
            *tool('vivado'),
            '-mode',
            'batch',
            '-nojournal',
            '-nolog',
            '-source',
            str(ROOT / 'boards/ego1/program.tcl'),
            '-tclargs',
            str(bit),
        ],
        cwd=bit.parent,
        capture_output=True,
        text=True,
    )
    # 返回码不可靠 (Vivado 没真正启动时也是 0), 以 program.tcl 打印的 DONE 位为准
    if result.returncode or 'DONE PROGRAMMED: 1' not in result.stdout:
        print(result.stdout[-2000:] + result.stderr[-2000:])
        fail('烧写失败: 检查 USB 线、板子电源, 以及有没有别的 Vivado 占着下载器')
    typer.secho('✓ 已烧写; 之后改 C 用 ama run 就行', fg='green')


@cli.command()
def doctor():
    """列出 ama 用到的工具: 实际调用的命令和版本。三台机器对一下版本就知道结果该不该一样。"""
    # pds_shell 没有查版本的参数, 只显示命令
    flag = {'vivado': '-version', 'pds_shell': None}
    for name in TOOLS:
        cmd = tool(name)
        version = '-'
        if flag.get(name, '--version'):
            try:
                result = subprocess.run([*cmd, flag.get(name, '--version')], capture_output=True, text=True)
                version = (result.stdout or result.stderr).strip().splitlines()[0]
            except FileNotFoundError:
                version = '找不到'
        print(f'{name:24} {" ".join(cmd)}\n{"":24} {version}')


gen = typer.Typer(help='生成板级文件', no_args_is_help=True)
cli.add_typer(gen, name='gen')


@gen.command('pins')
def pins(board: str):
    """从 pins.csv 生成引脚约束和头文件。"""
    gen_pins(board)
