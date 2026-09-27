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


def run(*args):
    subprocess.run([shutil.which(str(args[0])) or str(args[0]),
                    *[str(a) for a in args[1:]]], cwd=ROOT, check=True)


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
    elf, binary, hexf = [BUILD / (name+ext) for ext in ['.elf','.bin','.hex']]
    run('ld.lld', '-m', 'elf32lriscv', '--no-relax', '-T', 'tests/cpu/link.ld', *objects, '-o', elf)
    run('llvm-objcopy', '-O', 'binary', elf, binary)
    data = binary.read_bytes()
    if len(data) > 65536:
        raise ValueError(f'{name}: image exceeds RAM')
    # Poison uninitialized RAM: startup must actually clear the BSS.
    data += b'\xa5' * (65536-len(data))
    hexf.write_text(''.join(f'{int.from_bytes(data[i:i+4],"little"):08x}\n'
                           for i in range(0,65536,4)), encoding='ascii')
    return hexf


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--quick', action='store_true', help='Only fixed-latency smoke test')
    parser.add_argument('--vcd', action='store_true', help='Write a waveform per run')
    args = parser.parse_args()
    for tool in ['clang','ld.lld','llvm-objcopy','iverilog','vvp']:
        if not shutil.which(tool):
            parser.error(f'Missing required tool: {tool}')
    BUILD.mkdir(parents=True, exist_ok=True)
    programs = [('smoke', build('smoke',['tests/cpu/smoke.S']), 3)]
    if not args.quick:
        programs += [('alu',build('alu',[generate_alu()]),0),
                     ('boot',build('boot',['tests/cpu/start.S','tests/cpu/boot.c']),-1),
                     ('memory',build('memory',['tests/cpu/memory.S'],'rv32i_zifencei'),9),
                     ('extensions',build('extensions',['tests/cpu/extensions.S'],'rv32im_zicsr'),0)]
    configs = [(0,0,1)] if args.quick else [(0,0,1),(4,7,12345),(11,13,987654321)]
    for iwait,dwait,seed in configs:
        output = BUILD / f'cpu-{iwait}-{dwait}.vvp'
        run('iverilog','-g2012','-s','cpu_tb',f'-Pcpu_tb.I_DELAY={iwait}',
            f'-Pcpu_tb.D_DELAY={dwait}',f'-Pcpu_tb.SEED={seed}',
            '-o',output,'-f','rtl/cpu.f','tests/cpu/cpu_tb.sv')
        for name,hexf,stores in programs:
            extra = [f'+vcd={BUILD.as_posix()}/{name}-{iwait}-{dwait}.vcd'] if args.vcd else []
            run('vvp',output,f'+image={hexf.as_posix()}',f'+stores={stores}',*extra)
    print(f'PASS: {len(programs)*len(configs)} CPU program/configuration runs', flush=True)


if __name__ == '__main__':
    main()
