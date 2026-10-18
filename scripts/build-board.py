"""Build board firmware (bring-up app, or the SPI LCD demo with --lcd)
and generate an isolated PDS (MES50HP) or Vivado (EGO1) build script.

--harvard builds the Harvard soc_top instead of minimal_soc: firmware comes from
sw/ (sw/startup.S, sw/link.ld; app sw/app/board_check or sw/app/lcd_demo, or
--app coremark) and the ROM image from scripts/elf2hex.py. RAM is not preloaded;
startup.S copies .data."""
from pathlib import Path
import argparse
import shutil
import subprocess
import os
import hashlib
import json
import shlex
import sys
import zlib
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'build/mes50hp'
sys.path.insert(0, str(ROOT/'scripts'))
from elf2hex import elf_to_rom, write_hex  # noqa: E402
import coremark  # noqa: E402
from hwid import hwid  # noqa: E402
from elf2hex import load_segments  # noqa: E402

# sw/ layered sources for the Harvard soc_top (keep in step with justfile sw_lib)
SW_LIB = ['sw/startup.S','sw/drivers/spi.c','sw/drivers/uart.c','sw/bsp/bsp.c','sw/components/lcd/lcd_io.c',
          'sw/components/lcd/lcd.c','sw/components/lcd/st7789.c','sw/components/lcd/st7735.c']
SW_INC = ['sw/device','sw/drivers','sw/bsp','sw/components/lcd']

def run(*args):
    subprocess.run([shutil.which(str(args[0])) or str(args[0]), *map(str,args[1:])],
                   cwd=OUT, check=True)

def main():
    global OUT
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--board',choices=['mes50hp','ego1'],default='mes50hp')
    parser.add_argument('--cc',choices=['clang','gcc'],default='clang',help='Compiler (default clang; gcc needs --harvard)')
    parser.add_argument('--simulate',action='store_true',help='Also test UART and CPU-driven LEDs')
    parser.add_argument('--lcd',action='store_true',help='Build the SPI LCD demo firmware instead of the bring-up app')
    parser.add_argument('--pds',action='store_true',help='Run installed PDS in the isolated output directory')
    parser.add_argument('--vivado',action='store_true',help='Run Vivado batch for EGO1')
    parser.add_argument('--harvard',action='store_true',
                        help='Use the Harvard soc_top (ROM 0x0 + RAM 0x10000000) and sw/ firmware')
    parser.add_argument('--app',
                        help='With --harvard: build sw/app/<APP>/*.c instead of board_check (coremark: '
                             'ITERATIONS=0, CoreMark picks a count that runs >= 10 s; simulate with scripts/coremark.py)')
    args=parser.parse_args()
    if args.cc=='gcc' and not args.harvard:
        parser.error('--cc gcc needs --harvard')
    if args.board=='ego1' and (not args.harvard or args.lcd or args.pds):
        parser.error('ego1 needs --harvard and does not support --lcd or --pds')
    if args.vivado and args.board!='ego1':
        parser.error('--vivado needs --board ego1')
    if args.app and not args.harvard:
        parser.error('--app needs --harvard')
    if args.app and args.lcd:
        parser.error('--app and --lcd are exclusive')
    if args.app=='coremark' and args.simulate:
        parser.error('simulate CoreMark with: python3 scripts/coremark.py'
                     +(' --cc gcc' if args.cc=='gcc' else ''))
    if args.app and args.simulate:
        parser.error('simulate apps with: python3 scripts/test-lcd.py <app> --tb <testbench>')
    if args.app and not (ROOT/'sw/app'/args.app).is_dir():
        parser.error(f'no such app: sw/app/{args.app}')
    # Keep every variant in its own directory so each becomes its own PDS
    # project (PDS picks the project directory at process launch).
    OUT=ROOT/('build/'+args.board+('-harvard' if args.harvard else '')+('-lcd' if args.lcd else '')
              +(f'-{args.app}' if args.app else '')+('-gcc' if args.cc=='gcc' else ''))
    OUT.mkdir(parents=True,exist_ok=True)
    if args.harvard:
        return harvard(args)
    cflags=['--target=riscv32-unknown-elf','-march=rv32i_zicsr','-mabi=ilp32',
            '-O2','-ffreestanding','-fno-builtin','-fno-stack-protector','-msmall-data-limit=0',
            '-mno-relax']
    inc=[f'-I{ROOT/d}' for d in ['sw/device','sw/drivers','sw/bsp','sw/components/lcd']] if args.lcd else []
    app=[ROOT/'sw/board/start.S']
    if args.lcd:
        app+=[ROOT/'sw/board/lcd_main.c',ROOT/'sw/drivers/spi.c',ROOT/'sw/bsp/bsp.c',
              ROOT/'sw/board/lcd_io.c',ROOT/'sw/components/lcd/lcd.c',
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
    if len(data)>65536:
        raise ValueError('Firmware exceeds 64 KiB RAM')
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
        if args.lcd:
            tb_sources.append(ROOT/'tests/soc/st7789_model.sv')
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
        if result.returncode:
            raise RuntimeError(f'PDS failed; inspect {OUT}/pds-build.log')
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

def harvard(args):
    """soc_top on the board: sw/ firmware -> ROM image, soc.f + matrix board top."""
    cflags=['--target=riscv32-unknown-elf','-march=rv32i_zicsr','-mabi=ilp32','-O2',
            '-nostdlib','-ffreestanding','-fno-builtin','-Wall','-Wextra',
            '-msmall-data-limit=0','-mno-relax','-fuse-ld=lld']
    libs=[]
    if args.cc=='gcc':
        cflags=[f'-march={coremark.MARCH}','-mabi=ilp32','-O2',
                '-nostdlib','-ffreestanding','-fno-builtin','-Wall','-Wextra',
                '-msmall-data-limit=0','-mno-relax']
        libs=['-lgcc']
    app=ROOT/'sw/app'/(args.app or ('lcd_demo' if args.lcd else 'board_check'))
    board=['-DBOARD_EGO1' if args.board=='ego1' else '-DBOARD_MES50HP']
    sources_c=[ROOT/p for p in SW_LIB]+sorted(app.glob('*.c'))
    inc=[f'-I{ROOT/d}' for d in SW_INC]
    boot_flags=[f for f in cflags if f != '-O2' and not f.startswith('-march=')]
    boot_flags+=['-march=rv32i_zicsr','-Os','-fno-delete-null-pointer-checks']
    def build_boot(name, defines):
        boot=OUT/(name+'.elf')
        run(coremark.compiler(args.cc),*boot_flags,*inc,*defines,
            '-T',ROOT/'sw/boot/link.ld',ROOT/'sw/boot/startup.S',ROOT/'sw/boot/main.c','-o',boot)
        segments=load_segments(boot.read_bytes())
        size=max(addr+len(data)-0xf800 for addr,data in segments if addr < 0x10000)
        if size > 2048:
            raise SystemExit(f'bootloader too large: {size} bytes')
        print(f'Bootloader {name}: {size} bytes',flush=True)
        return elf_to_rom(boot,base=0xf800,size=2048)
    boot_image=build_boot('boot',[])
    def combined(elf, name, boot):
        write_hex(elf_to_rom(elf,size=0xf800)+boot, OUT/(name+'.hex'))
    def build(name, defines):
        elf=OUT/(name+'.elf')
        # 共用板级测试台使用盘古接线, EGO1 引脚由独立屏幕仿真验证。
        run(coremark.compiler(args.cc),*cflags,*inc,
            *(['-DBOARD_MES50HP'] if name=='sim' else board),*defines,'-T',ROOT/'sw/link.ld',*sources_c,*libs,'-o',elf)
        combined(elf,name,boot_image)
        return elf
    if args.app=='coremark':
        sources_c=[ROOT/p for p in coremark.SOURCES]
        app=ROOT/'sw/app/coremark'
        elf=OUT/'firmware.elf'
        coremark.build(elf,0,cc=args.cc)   # ITERATIONS=0: CoreMark sizes the run to >= 10 s
        combined(elf,'firmware',boot_image)
    else:
        elf=build('firmware',[])
    print(f'Firmware: {app.relative_to(ROOT)}; output: {OUT}',flush=True)
    sources=[ROOT/p for p in (ROOT/'rtl/soc.f').read_text().splitlines() if p and not p.startswith('+')]
    sources.append(ROOT/('boards/mes50hp/mes50hp_top_matrix.v' if args.board=='mes50hp' else 'boards/ego1/ego1_top.v'))
    hardware_id=hwid(args.board)
    if args.board=='mes50hp':
        # PDS 参数覆盖依赖工具版本, 生成同名顶层并固化 HW_ID。
        top=OUT/'mes50hp_top_matrix.v'
        top.write_text(sources[-1].read_text(encoding='utf8').replace('parameter [31:0] HW_ID = 0,',
                       f"parameter [31:0] HW_ID = 32'h{hardware_id:08x},"),encoding='utf8')
        sources[-1]=top
        tcl=['cd {'+OUT.as_posix()+'}',
             'set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484']
        tcl += ['add_design {'+p.as_posix()+'}' for p in sources]
        tcl += ['add_constraint {'+(ROOT/'boards/mes50hp/matrix.fdc').as_posix()+'}',
                'add_constraint {'+(ROOT/'boards/mes50hp/pins.fdc').as_posix()+'}',
                'compile -top_module mes50hp_top_matrix -include_path {{'+ROOT.as_posix()+'} {'+(ROOT/'rtl/core').as_posix()+'}}',
                'synthesize -ads -selected_syn_tool_opt 2', 'dev_map', 'pnr', 'report_timing', 'gen_bit_stream']
    else:
        tcl=['cd {'+OUT.as_posix()+'}']
        tcl += ['read_verilog {'+p.as_posix()+'}' for p in
                sources]
        tcl += ['read_xdc {'+(ROOT/'boards/ego1/ego1.xdc').as_posix()+'}',
                'read_xdc {'+(ROOT/'boards/ego1/pins.xdc').as_posix()+'}',
                f"synth_design -top ego1_top -part xc7a35tcsg324-1 -generic HW_ID=32'h{hardware_id:08x} -include_dirs {{"+
                ROOT.as_posix()+' '+(ROOT/'rtl/core').as_posix()+'}',
                'opt_design', 'place_design', 'route_design',
                'report_timing_summary -file timing_summary.rpt',
                'report_utilization -file utilization.rpt',
                'set wns [get_property SLACK [get_timing_paths -delay_type max]]',
                'if {$wns < 0} {error "Timing failed: WNS = $wns ns"}',
                'write_bitstream -force ego1_top.bit']
    (OUT/'build.tcl').write_text('\n'.join(tcl)+'\n',encoding='utf8')
    if args.simulate:
        # 引导窗口缩短 200 倍, 仍长于一个串口字符; UART 保持真实波特率。
        sim_boot=build_boot('boot-sim',['-DSIM_CYCLE_DIV=200'])
        sim_elf=build('sim',['-DSIM_CYCLE_DIV=1000'])
        combined(sim_elf,'sim',sim_boot)
        if not args.lcd:
            for name,define in [('boot-default',[]),('boot-app',['-DNEW_APP'])]:
                app_elf=OUT/(name+'.elf')
                run(coremark.compiler(args.cc),*cflags,*inc,*define,'-T',ROOT/'sw/link.ld',
                    ROOT/'sw/startup.S',ROOT/'tests/board/boot_app.c','-o',app_elf)
                if name=='boot-default': combined(app_elf,'boot-test',sim_boot)
                else:
                    run('llvm-objcopy','-O','binary',app_elf,OUT/'boot-app.bin')
                    # 覆盖协议的末字补零, 不要求 app 的代码长度恰好不对齐。
                    data=(OUT/'boot-app.bin').read_bytes()+b'\x12\x34\x56'
                    (OUT/'boot-app.bin').write_bytes(data)
                    (OUT/'boot-app.hex').write_text(''.join(f'{b:02x}\n' for b in data))
                    (OUT/'boot-app.vh').write_text(f"localparam APP_LENGTH = {len(data)};\n"
                        +f"localparam [31:0] APP_CRC = 32'h{zlib.crc32(data):08x};\n")
        for tb in (['board_lcd_tb'] if args.lcd else ['board_tb','uart_reset_tb','boot_tb']):
            tb_sources=[*[p for p in sources if p.name not in ['ego1_top.v', 'mes50hp_top_matrix.v']],
                        ROOT/'boards/mes50hp/mes50hp_top_matrix.v',ROOT/'tests/board'/(tb+'.sv')]
            if args.lcd:
                tb_sources.append(ROOT/'tests/soc/st7789_model.sv')
            params=["-GTOHOST_ADDR=32'h10000000"] if args.lcd else []   # sw/link.ld .tohost
            if shutil.which('verilator'):
                objdir=OUT/'obj'
                run('verilator','--binary','--timing','-Wno-fatal','--top-module',tb,'-DHARVARD',*params,
                    '+incdir+'+OUT.as_posix(),'+incdir+'+ROOT.as_posix(),'+incdir+'+(ROOT/'rtl/core').as_posix(),*tb_sources,
                    '--Mdir',objdir.as_posix(),'-o',tb+'_sim')
                run(str(objdir/(tb+'_sim')))
            else:
                run('iverilog','-g2012','-s',tb,'-DHARVARD',
                    *(['-P',f"{tb}.TOHOST_ADDR=32'h10000000"] if args.lcd else []),
                    '-I',OUT,'-I',ROOT,'-I',ROOT/'rtl/core','-o',OUT/'board.vvp',*tb_sources)
                run('vvp',OUT/'board.vvp')
    if args.pds:
        pds_build(sources+[ROOT/'rtl/core/defines.v',ROOT/'boards/mes50hp/matrix.fdc',
                           ROOT/'boards/mes50hp/pins.fdc',ROOT/'boards/mes50hp/pins_top.vh',
                           *sources_c,*sorted((ROOT/'sw/boot').glob('*')),OUT/'boot.elf',
                           ROOT/'boards/mes50hp/mes50hp_top_matrix.v',
                           ROOT/'sw/link.ld',elf,OUT/'firmware.hex'])
    if args.vivado:
        vivado_build(sources+[ROOT/'rtl/core/defines.v',ROOT/'boards/ego1/ego1_top.v',
                              ROOT/'boards/ego1/ego1.xdc',ROOT/'boards/ego1/pins.xdc',
                              ROOT/'boards/ego1/pins_top.vh',*sources_c,*sorted((ROOT/'sw/boot').glob('*')),
                              OUT/'boot.elf',ROOT/'sw/link.ld',
                              elf,OUT/'firmware.hex',OUT/'build.tcl'])

def vivado_build(files):
    """Run Vivado in OUT; Tcl checks WNS before writing the bitstream."""
    vivado=shlex.split(os.environ.get('VIVADO',
        'distrobox enter vivado -- '
        '/tools/Xilinx/2025.2/Vivado/bin/vivado'))
    bitstream=OUT/'ego1_top.bit'
    bitstream.unlink(missing_ok=True)
    with (OUT/'vivado-build.log').open('w',encoding='utf8') as log:
        result=subprocess.run([*vivado,'-mode','batch','-source','build.tcl'],
                              cwd=OUT,stdout=log,stderr=subprocess.STDOUT,
                              env={**os.environ,'DBX_CONTAINER_MANAGER':'docker'})
    if result.returncode:
        raise RuntimeError(f'Vivado failed; inspect {OUT}/vivado-build.log')
    log=(OUT/'vivado-build.log').read_text(encoding='utf8',errors='replace')
    if "$readmem data file 'firmware.hex' is read successfully" not in log:
        raise RuntimeError('Vivado did not load firmware initialization')
    if not bitstream.exists():
        raise RuntimeError('Vivado did not generate the bitstream')
    files=[*files,bitstream,OUT/'timing_summary.rpt',OUT/'utilization.rpt']
    manifest={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    (OUT/'build-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf8')
    print('PASS Vivado: bitstream generated, WNS >= 0; see timing_summary.rpt and utilization.rpt.',flush=True)

def pds_build(files):
    """Run PDS in OUT, check initialization/bitstream/timing, write build-manifest.json."""
    pds=os.environ.get('PDS_SHELL',r'C:\pango\PDS_2022.2-SP1-Lite\bin\pds_shell.exe')
    with (OUT/'pds-build.log').open('w',encoding='utf8') as log:
        result=subprocess.run([pds,'-file','build.tcl'],cwd=OUT,stdout=log,stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f'PDS failed; inspect {OUT}/pds-build.log')
    log=(OUT/'pds-build.log').read_text(encoding='utf8',errors='replace')
    if 'Cannot open specified data file' in log:
        raise RuntimeError('PDS did not load firmware initialization')
    timing=OUT/'report_timing/mes50hp_top_matrix.rtr'
    bitstream=OUT/'generate_bitstream/mes50hp_top_matrix.sbit'
    if 'Executing : gen_bit_stream successfully.' not in log or not bitstream.exists():
        raise RuntimeError('PDS did not confirm bitstream generation')
    if not timing.exists() or 'All Constraints Met.' not in timing.read_text(errors='replace'):
        raise RuntimeError('Timing failed; do not use this bitstream as a validated build')
    files=[*files,bitstream,timing]
    manifest={str(p.relative_to(ROOT)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    (OUT/'build-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf8')
    print('PASS PDS: initialized firmware, bitstream generated, all timing constraints met.',flush=True)

if __name__=='__main__':
    main()
