"""板级配置与引脚生成。"""

import csv
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def read_board(name):
    return tomllib.loads((ROOT / 'boards' / name / 'board.toml').read_text())


def boards():
    return {p.parent.name: read_board(p.parent.name) for p in sorted((ROOT / 'boards').glob('*/board.toml'))}


def gen_pins(board):
    vivado = read_board(board)['tool'] == 'vivado'
    path = ROOT / 'boards' / board
    pins = list(csv.DictReader((path / 'pins.csv').open()))
    note = '由 ama gen pins 生成, 不要手改'
    vh = [f'// {note}', f'`define IO_N {len(pins)}']
    for name in ['UART_TX', 'UART_RX']:
        n = next(i for i, pin in enumerate(pins) if pin['name'] == name)
        vh.append(f'`define {name}_PIN {n}')
    vh += [f'`define PIN_{pin["name"]} {i}' for i, pin in enumerate(pins)]
    for direction in ['inout', 'out', 'in_n']:
        mask = sum(1 << i for i, pin in enumerate(pins) if pin['dir'] == direction)
        vh.append(f"`define IO_{direction.upper()}_MASK 128'h{mask:032x}")
    (path / 'pins_top.vh').write_text('\n'.join(vh) + '\n')
    header = [f'/* {note} */']
    header += [f'#define PIN_{pin["name"]} {i}' for i, pin in enumerate(pins)]
    (ROOT / 'sw/bsp' / f'{board}_pins.h').write_text('\n'.join(header) + '\n')
    lines = [f'# {note}']
    for i, pin in enumerate(pins):
        port = f'io[{i}]'
        output = pin['dir'] in ['inout', 'out']
        if vivado:
            lines += [
                f'set_property PACKAGE_PIN {pin["pad"]} [get_ports {{{port}}}]',
                f'set_property IOSTANDARD LVCMOS33 [get_ports {{{port}}}]',
            ]
            if output:
                lines += [
                    f'set_property SLEW SLOW [get_ports {{{port}}}]',
                    f'set_property DRIVE 4 [get_ports {{{port}}}]',
                ]
        else:
            direction = {'inout': 'INOUT', 'out': 'OUTPUT', 'in': 'INPUT', 'in_n': 'INPUT'}[pin['dir']]
            attrs = [
                ('DIRECTION', direction),
                ('LOC', pin['pad']),
                ('VCCIO', '3.3'),
                ('STANDARD', 'LVCMOS33'),
                ('NONE', 'TRUE'),
            ]
            if output:
                attrs += [('DRIVE', '8'), ('SLEW', 'SLOW')]
            lines += [f'define_attribute {{p:{port}}} {{PAP_IO_{key}}} {{{value}}}' for key, value in attrs]
    (path / ('pins.xdc' if vivado else 'pins.fdc')).write_text('\n'.join(lines) + '\n')
