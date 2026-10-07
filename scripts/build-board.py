"""Build the MES50HP board firmware (bring-up app, or the SPI LCD demo with --lcd)
and generate an isolated PDS build script."""
from pathlib import Path
import argparse, shutil, subprocess, os, hashlib, json
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'build/mes50hp'

def run(*args):
    subprocess.run([shutil.which(str(args[0])) or str(args[0]), *map(str,args[1:])],
                   cwd=OUT, check=True)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--simulate',action='store_true',help='Also test UART and CPU-driven LEDs')
    parser.add_argument('--lcd',action='store_true',help='Build the SPI LCD demo firmware instead of the bring-up app')
    parser.add_argument('--pds',action='store_true',help='Run installed PDS in the isolated output directory')
    args=parser.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    cflags=['--target=riscv32-unknown-elf','-march=rv32i_zicsr','-mabi=ilp32',
            '-O2','-ffreestanding','-fno-builtin','-fno-stack-protector','-msmall-data-limit=0',
            '-mno-relax']
    inc=[f'-I{ROOT/d}' for d in ['sw/device','sw/drivers','sw/bsp','sw/components/lcd']] if args.lcd else []
    app=[ROOT/'sw/board/start.S']
    if args.lcd:
        app+=[ROOT/'sw/board/lcd_main.c',ROOT/'sw/drivers/spi.c',ROOT/'sw/bsp/bsp.c',
              ROOT/'sw/bsp/bsp_lcd.c',ROOT/'sw/components/lcd/lcd.c',
              ROOT/'sw/components/lcd/st7789.c']
    else:
        app+=[ROOT/'sw/board/main.c']
    objs=[]
    for source in app:
        obj=OUT/(source.name+'.o')
        run('clang',*cflags,*inc,'-c',source,'-o',obj)
        objs.append(obj)
    run('ld.lld','-m','elf32lriscv','--no-relax','-T',ROOT/'sw/board/link.ld',
        *objs,'-o',OUT/'firmware.elf')
    run('llvm-objcopy','-O','binary',OUT/'firmware.elf',OUT/'firmware.bin')
    data=(OUT/'firmware.bin').read_bytes()
    if len(data)>65536: raise ValueError('Firmware exceeds 64 KiB RAM')
    size=len(data)
    data+=b'\xa5'*(65536-size)
    (OUT/'firmware.hex').write_text(''.join(f'{int.from_bytes(data[i:i+4],"little"):08x}\n'
                                         for i in range(0,65536,4)),encoding='ascii')
    sources=[ROOT/p for p in (ROOT/'rtl/cpu.f').read_text().splitlines() if p and not p.startswith('+')]
    sources += [ROOT/p for p in ['rtl/utils/vld_rdy.v','rtl/perips/gpio.v','rtl/perips/uart.v',
                                'rtl/perips/spi.v',
                                'rtl/soc/minimal_soc.v','boards/mes50hp/mes50hp_top.v']]
    # Tcl paths are brace-quoted, so Windows spaces are preserved.
    tcl=['cd {'+OUT.as_posix()+'}',
         'set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484']
    tcl += ['add_design {'+p.as_posix()+'}' for p in sources]
    tcl += ['add_constraint {'+(ROOT/'boards/mes50hp/mes50hp.fdc').as_posix()+'}',
            'compile -top_module mes50hp_top -include_path {'+(ROOT/'rtl/core').as_posix()+'}',
            'synthesize -ads -selected_syn_tool_opt 2', 'dev_map', 'pnr', 'report_timing', 'gen_bit_stream']
    (OUT/'build.tcl').write_text('\n'.join(tcl)+'\n',encoding='utf8')
    print(f'Firmware: {size} bytes; output: {OUT}',flush=True)
    if args.simulate:
        # Keep the deliverable image unchanged; only shorten software waits
        # (LED heartbeat or LCD init delays) in a separate simulation image.
        # UART stays at real baud.
        sim_defines=['-DSIM_CYCLE_DIV=1000'] if args.lcd else ['-DHEARTBEAT_CYCLES=100000']
        sim_objs=[OUT/'start.S.o']
        for source in app[1:]:
            obj=OUT/('sim-'+source.name+'.o')
            run('clang',*cflags,*inc,*sim_defines,'-c',source,'-o',obj)
            sim_objs.append(obj)
        run('ld.lld','-m','elf32lriscv','--no-relax','-T',ROOT/'sw/board/link.ld',
            *sim_objs,'-o',OUT/'sim.elf')
        run('llvm-objcopy','-O','binary',OUT/'sim.elf',OUT/'sim.bin')
        simdata=(OUT/'sim.bin').read_bytes()
        simdata+=b'\xa5'*(65536-len(simdata))
        (OUT/'sim.hex').write_text(''.join(f'{int.from_bytes(simdata[i:i+4],"little"):08x}\n'
                                         for i in range(0,65536,4)),encoding='ascii')
        tb='board_lcd_tb' if args.lcd else 'board_tb'
        tb_sources=[*sources,ROOT/'tests/board'/(tb+'.sv')]
        if args.lcd: tb_sources.append(ROOT/'tests/soc/st7789_model.sv')
        # A full 240x320 frame is ~150k SPI bytes; Verilator is much faster
        # than Icarus for this, so prefer it when available.
        if shutil.which('verilator'):
            objdir=OUT/'obj'
            run('verilator','--binary','--timing','-Wno-fatal','--top-module',tb,
                '+incdir+'+(ROOT/'rtl/core').as_posix(),*tb_sources,
                '--Mdir',objdir.as_posix(),'-o',tb+'_sim')
            run(str(objdir/(tb+'_sim')))
        else:
            run('iverilog','-g2012','-s',tb,'-I',ROOT/'rtl/core','-o',OUT/'board.vvp',
                *tb_sources)
            run('vvp',OUT/'board.vvp')
    if args.pds:
        pds=os.environ.get('PDS_SHELL',r'C:\pango\PDS_2022.2-SP1-Lite\bin\pds_shell.exe')
        # PDS chooses its project directory at process launch. Tcl cd alone
        # does not relocate that directory or its readmemh search path.
        with (OUT/'pds-build.log').open('w',encoding='utf8') as log:
            result=subprocess.run([pds,'-file','build.tcl'],cwd=OUT,stdout=log,stderr=subprocess.STDOUT)
        if result.returncode: raise RuntimeError('PDS failed; inspect build/mes50hp/pds-build.log')
        log=(OUT/'pds-build.log').read_text(encoding='utf8',errors='replace')
        if 'Cannot open specified data file' in log:
            raise RuntimeError('PDS did not load firmware initialization')
        timing=OUT/'report_timing/mes50hp_top.rtr'
        bitstream=OUT/'generate_bitstream/mes50hp_top.sbit'
        if 'Executing : gen_bit_stream successfully.' not in log or not bitstream.exists():
            raise RuntimeError('PDS did not confirm bitstream generation')
        if not timing.exists() or 'All Constraints Met.' not in timing.read_text(errors='replace'):
            raise RuntimeError('Timing failed; do not use this bitstream as a validated build')
        files=sources+[ROOT/'rtl/core/defines.v',ROOT/'boards/mes50hp/mes50hp.fdc',
                       *app,ROOT/'sw/board/link.ld',
                       OUT/'firmware.elf',OUT/'firmware.hex',bitstream,timing]
        manifest={str(p.relative_to(ROOT)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
        (OUT/'build-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf8')
        print('PASS PDS: initialized firmware, bitstream generated, all timing constraints met.',flush=True)

if __name__=='__main__': main()
