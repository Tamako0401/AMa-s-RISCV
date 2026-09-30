"""Build local RV32 programs and test the imported CPU without a board or IP.

Requires Python 3, clang (RISC-V target), ld.lld, llvm-objcopy, iverilog, vvp.
This is a development regression, not the contest's GCC/CoreMark measurement.
"""
from pathlib import Path
import argparse
import random
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/cpu'

# 哈佛式存储器布局, 必须与 tests/cpu/link.ld 和 rtl/core/rib.v 保持一致:
#   ROM 0x0000_0000, 64 KiB, 只放指令(.text/.rodata)
#   RAM 0x1000_0000, 64 KiB, 放数据; 窗口第 0 个字保留为"运行结束"信箱
ROM_BYTES = 65536
RAM_BYTES = 65536
RESULT_RESERVE = 4


def run(*args, cwd=ROOT):
    subprocess.run([shutil.which(str(args[0])) or str(args[0]),
                    *[str(a) for a in args[1:]]], cwd=cwd, check=True)


def generate_alu():
    rng = random.Random(20260927)
    code = ['.section .text.init', '.globl _start', '_start:']
    mask = 0xffffffff
    signed = lambda x: x if x < 0x80000000 else x - 0x100000000
    ops = {
        'add': lambda a, b: a+b, 'sub': lambda a, b: a-b,
        'sll': lambda a, b: a << (b & 31),
        'srl': lambda a, b: a >> (b & 31),
        'sra': lambda a, b: signed(a) >> (b & 31),
        'slt': lambda a, b: int(signed(a) < signed(b)),
        'sltu': lambda a, b: int(a < b),
        'xor': lambda a, b: a ^ b, 'or': lambda a, b: a | b,
        'and': lambda a, b: a & b,
    }
    case = 2
    values = [0, 1, mask, 0x80000000, 0x7fffffff, 31, 32, 0xaaaaaaaa]
    for op, fn in ops.items():
        for n in range(32):
            a = values[n] if n < len(values) else rng.getrandbits(32)
            b = values[-n-1] if n < len(values) else rng.getrandbits(32)
            # rd==rs1 exercises dependent register updates as well.
            code += [f'li s11, {case}', f'li t0, 0x{a:08x}', f'li t1, 0x{b:08x}',
                     f'{op} t0, t0, t1', f'li t2, 0x{fn(a,b)&mask:08x}', 'bne t0, t2, fail']
            case += 1
    for op in ['addi','slti','sltiu','xori','ori','andi','slli','srli','srai']:
        for n in range(16):
            a = rng.getrandbits(32)
            imm = rng.randrange(32) if op in ['slli','srli','srai'] else rng.randrange(-2048,2048)
            base = {'addi':'add','slti':'slt','sltiu':'sltu','xori':'xor','ori':'or','andi':'and',
                    'slli':'sll','srli':'srl','srai':'sra'}[op]
            result = ops[base](a, imm & mask) & mask
            code += [f'li s11, {case}', f'li t0, 0x{a:08x}', f'{op} t0, t0, {imm}',
                     f'li t2, 0x{result:08x}', 'bne t0, t2, fail']
            case += 1
    # All branch conditions, including signed/unsigned boundary distinctions.
    conditions = {'beq': lambda a,b:a==b, 'bne':lambda a,b:a!=b,
                  'blt':lambda a,b:signed(a)<signed(b), 'bge':lambda a,b:signed(a)>=signed(b),
                  'bltu':lambda a,b:a<b, 'bgeu':lambda a,b:a>=b}
    for op, fn in conditions.items():
        for a,b in [(0,0),(0,1),(1,0),(mask,1),(0x80000000,0x7fffffff)]:
            code += [f'li s11, {case}', f'li t0, 0x{a:08x}', f'li t1, 0x{b:08x}']
            if fn(a,b):
                code += [f'{op} t0, t1, 1f', 'j fail', '1:']
            else:
                code += [f'{op} t0, t1, fail']
            case += 1
    code += ['li a0, 1', 'j finish', 'fail: mv a0, s11',
             'finish: li t0, 0x10000000', 'sw a0, 0(t0)', '1: j 1b']
    path = BUILD / 'alu.S'
    path.write_text('\n'.join(code)+'\n', encoding='utf-8')
    return path


def build(name, sources, march='rv32i'):
    objects = []
    for index, src in enumerate(sources):
        obj = BUILD / f'{name}-{index}.o'
        run('clang', '--target=riscv32-unknown-elf', f'-march={march}', '-mabi=ilp32',
            '-O2', '-ffreestanding', '-fno-builtin', '-fno-stack-protector',
            '-msmall-data-limit=0', '-mno-relax', '-c', src, '-o', obj)
        objects.append(obj)
    elf = BUILD / f'{name}.elf'
    run('ld.lld', '-m', 'elf32lriscv', '--no-relax', '-T', 'tests/cpu/link.ld', *objects, '-o', elf)
    # 哈佛式: 指令镜像进 ROM, 数据初值进 RAM
    rom_bin = BUILD / f'{name}-rom.bin'
    ram_bin = BUILD / f'{name}-ram.bin'
    run('llvm-objcopy', '-O', 'binary', '--only-section=.text', elf, rom_bin)
    run('llvm-objcopy', '-O', 'binary', '--only-section=.data', elf, ram_bin)
    rom = rom_bin.read_bytes()
    if len(rom) > ROM_BYTES:
        raise ValueError(f'{name}: .text exceeds ROM ({len(rom)} > {ROM_BYTES})')
    # 未初始化的 ROM 填 0xa5(非法指令), 越界取指会立刻暴露
    rom += b'\xa5' * (ROM_BYTES - len(rom))
    data = ram_bin.read_bytes()
    if len(data) > RAM_BYTES - RESULT_RESERVE:
        raise ValueError(f'{name}: .data exceeds RAM ({len(data)})')
    # RAM 窗口第 0 个字留给结束信箱(与 link.ld 的 ORIGIN 对齐), 其后是数据;
    # 未初始化的部分填 0xa5: startup 必须真的把 BSS 清零。
    data = b'\x00' * RESULT_RESERVE + data
    data += b'\xa5' * (RAM_BYTES - len(data))
    hexfs = []
    for region, image in (('rom', rom), ('ram', data)):
        path = BUILD / f'{name}-{region}.hex'
        path.write_text(''.join(f'{int.from_bytes(image[i:i+4],"little"):08x}\n'
                                for i in range(0, RAM_BYTES, 4)), encoding='ascii')
        hexfs.append(path)
    return (hexfs[0], hexfs[1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--quick', action='store_true', help='Only fixed-latency smoke test')
    parser.add_argument('--vcd', action='store_true', help='Write a waveform per run')
    parser.add_argument('--modelsim', action='store_true', help='Use ModelSim instead of Icarus')
    args = parser.parse_args()
    simulator_tools = ['vlib','vmap','vlog','vsim'] if args.modelsim else ['iverilog','vvp']
    for tool in ['clang','ld.lld','llvm-objcopy', *simulator_tools]:
        if not shutil.which(tool):
            parser.error(f'Missing required tool: {tool}')
    BUILD.mkdir(parents=True, exist_ok=True)
    programs = [('smoke', build('smoke',['tests/cpu/smoke.S']), 3)]
    if not args.quick:
        programs += [('alu',build('alu',[generate_alu()]),0),
                     ('boot',build('boot',['tests/cpu/start.S','tests/cpu/boot.c']),-1),
                     ('memory',build('memory',['tests/cpu/memory.S'],'rv32i_zifencei'),8),
                     ('extensions',build('extensions',['tests/cpu/extensions.S'],'rv32im_zicsr'),0)]
    configs = [(0,0,1)] if args.quick else [(0,0,1),(4,7,12345),(11,13,987654321)]
    if args.modelsim:
        modeldir = BUILD / 'modelsim'
        modeldir.mkdir(exist_ok=True)
        if not (modeldir/'modelsim.ini').exists():
            run('vmap','-c',cwd=modeldir)
        if not (modeldir/'work').exists():
            run('vlib','work',cwd=modeldir)
        sources = [ROOT/p for p in (ROOT/'rtl/cpu.f').read_text().splitlines()
                   if p and not p.startswith('+')]
        run('vlog','-sv',f'+incdir+{(ROOT/"rtl/core").as_posix()}',
            '-work','work',*sources,ROOT/'tests/cpu/cpu_tb.sv',cwd=modeldir)
    for iwait,dwait,seed in configs:
        output = BUILD / f'cpu-{iwait}-{dwait}.vvp'
        if not args.modelsim:
            run('iverilog','-g2012','-s','cpu_tb',f'-Pcpu_tb.I_DELAY={iwait}',
                f'-Pcpu_tb.D_DELAY={dwait}',f'-Pcpu_tb.SEED={seed}',
                '-o',output,'-f','rtl/cpu.f','tests/cpu/cpu_tb.sv')
        for name,images,stores in programs:
            extra = [f'+vcd={BUILD.as_posix()}/{name}-{iwait}-{dwait}.vcd'] if args.vcd else []
            image_args = [f'+rom={images[0].as_posix()}', f'+ram={images[1].as_posix()}']
            if args.modelsim:
                run('vsim','-c','-onfinish','stop','-voptargs=+acc','work.cpu_tb',
                    f'-gI_DELAY={iwait}',f'-gD_DELAY={dwait}',f'-gSEED={seed}',
                    *image_args,f'+stores={stores}',*extra,
                    '-wlf',f'{name}-{iwait}-{dwait}.wlf',
                    '-l',f'{name}-{iwait}-{dwait}.log',
                    '-do',f'do {{{(ROOT/"tests/cpu/run.do").as_posix()}}}',cwd=modeldir)
            else:
                run('vvp',output,*image_args,f'+stores={stores}',*extra)
    print(f'PASS: {len(programs)*len(configs)} CPU program/configuration runs', flush=True)


if __name__ == '__main__':
    main()
