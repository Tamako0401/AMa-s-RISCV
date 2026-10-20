.section .text.init
.globl _start
_start:
li s11, 2
li t0, 0x00000000
li t1, 0xaaaaaaaa
add t0, t0, t1
li t2, 0xaaaaaaaa
bne t0, t2, fail
li s11, 3
li t0, 0x00000001
li t1, 0x00000020
add t0, t0, t1
li t2, 0x00000021
bne t0, t2, fail
li s11, 4
li t0, 0xffffffff
li t1, 0x0000001f
add t0, t0, t1
li t2, 0x0000001e
bne t0, t2, fail
li s11, 5
li t0, 0x80000000
li t1, 0x7fffffff
add t0, t0, t1
li t2, 0xffffffff
bne t0, t2, fail
li s11, 6
li t0, 0x7fffffff
li t1, 0x80000000
add t0, t0, t1
li t2, 0xffffffff
bne t0, t2, fail
li s11, 7
li t0, 0x0000001f
li t1, 0xffffffff
add t0, t0, t1
li t2, 0x0000001e
bne t0, t2, fail
li s11, 8
li t0, 0x00000020
li t1, 0x00000001
add t0, t0, t1
li t2, 0x00000021
bne t0, t2, fail
li s11, 9
li t0, 0xaaaaaaaa
li t1, 0x00000000
add t0, t0, t1
li t2, 0xaaaaaaaa
bne t0, t2, fail
li s11, 10
li t0, 0xe7f6ae87
li t1, 0x3d27fa99
add t0, t0, t1
li t2, 0x251ea920
bne t0, t2, fail
li s11, 11
li t0, 0x7c8c13e6
li t1, 0x502cd728
add t0, t0, t1
li t2, 0xccb8eb0e
bne t0, t2, fail
li s11, 12
li t0, 0xfe03e2cd
li t1, 0x1ed68825
add t0, t0, t1
li t2, 0x1cda6af2
bne t0, t2, fail
li s11, 13
li t0, 0x124080f4
li t1, 0x13d82785
add t0, t0, t1
li t2, 0x2618a879
bne t0, t2, fail
li s11, 14
li t0, 0x7ebfc7ed
li t1, 0x678bcae7
add t0, t0, t1
li t2, 0xe64b92d4
bne t0, t2, fail
li s11, 15
li t0, 0xf705e82c
li t1, 0x5c818392
add t0, t0, t1
li t2, 0x53876bbe
bne t0, t2, fail
li s11, 16
li t0, 0xae7e52b0
li t1, 0x1b58e332
add t0, t0, t1
li t2, 0xc9d735e2
bne t0, t2, fail
li s11, 17
li t0, 0x4f9c8590
li t1, 0x121f5ae3
add t0, t0, t1
li t2, 0x61bbe073
bne t0, t2, fail
li s11, 18
li t0, 0x2f5ec026
li t1, 0xc956e90d
add t0, t0, t1
li t2, 0xf8b5a933
bne t0, t2, fail
li s11, 19
li t0, 0xaa11c62e
li t1, 0x77315398
add t0, t0, t1
li t2, 0x214319c6
bne t0, t2, fail
li s11, 20
li t0, 0x4ae10033
li t1, 0x4109a157
add t0, t0, t1
li t2, 0x8beaa18a
bne t0, t2, fail
li s11, 21
li t0, 0x01cea1e7
li t1, 0x22201a08
add t0, t0, t1
li t2, 0x23eebbef
bne t0, t2, fail
li s11, 22
li t0, 0x59eae3bd
li t1, 0xd3c98afb
add t0, t0, t1
li t2, 0x2db46eb8
bne t0, t2, fail
li s11, 23
li t0, 0x89d7792f
li t1, 0xc23f9285
add t0, t0, t1
li t2, 0x4c170bb4
bne t0, t2, fail
li s11, 24
li t0, 0xe3867646
li t1, 0xf5ba6b04
add t0, t0, t1
li t2, 0xd940e14a
bne t0, t2, fail
li s11, 25
li t0, 0xa095f4aa
li t1, 0x9d795e71
add t0, t0, t1
li t2, 0x3e0f531b
bne t0, t2, fail
li s11, 26
li t0, 0x323f28f4
li t1, 0xa30405df
add t0, t0, t1
li t2, 0xd5432ed3
bne t0, t2, fail
li s11, 27
li t0, 0x03203ca5
li t1, 0xe03874aa
add t0, t0, t1
li t2, 0xe358b14f
bne t0, t2, fail
li s11, 28
li t0, 0x81269ee2
li t1, 0x2478ce2b
add t0, t0, t1
li t2, 0xa59f6d0d
bne t0, t2, fail
li s11, 29
li t0, 0x854eefcb
li t1, 0xe68460c3
add t0, t0, t1
li t2, 0x6bd3508e
bne t0, t2, fail
li s11, 30
li t0, 0xedf73733
li t1, 0x11efc6ef
add t0, t0, t1
li t2, 0xffe6fe22
bne t0, t2, fail
li s11, 31
li t0, 0x4849befc
li t1, 0x345e32e3
add t0, t0, t1
li t2, 0x7ca7f1df
bne t0, t2, fail
li s11, 32
li t0, 0x9ef7ced6
li t1, 0xc594c591
add t0, t0, t1
li t2, 0x648c9467
bne t0, t2, fail
li s11, 33
li t0, 0x6d7e25e6
li t1, 0x1cceed64
add t0, t0, t1
li t2, 0x8a4d134a
bne t0, t2, fail
li s11, 34
li t0, 0x00000000
li t1, 0xaaaaaaaa
sub t0, t0, t1
li t2, 0x55555556
bne t0, t2, fail
li s11, 35
li t0, 0x00000001
li t1, 0x00000020
sub t0, t0, t1
li t2, 0xffffffe1
bne t0, t2, fail
li s11, 36
li t0, 0xffffffff
li t1, 0x0000001f
sub t0, t0, t1
li t2, 0xffffffe0
bne t0, t2, fail
li s11, 37
li t0, 0x80000000
li t1, 0x7fffffff
sub t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 38
li t0, 0x7fffffff
li t1, 0x80000000
sub t0, t0, t1
li t2, 0xffffffff
bne t0, t2, fail
li s11, 39
li t0, 0x0000001f
li t1, 0xffffffff
sub t0, t0, t1
li t2, 0x00000020
bne t0, t2, fail
li s11, 40
li t0, 0x00000020
li t1, 0x00000001
sub t0, t0, t1
li t2, 0x0000001f
bne t0, t2, fail
li s11, 41
li t0, 0xaaaaaaaa
li t1, 0x00000000
sub t0, t0, t1
li t2, 0xaaaaaaaa
bne t0, t2, fail
li s11, 42
li t0, 0x6c853efe
li t1, 0x1e2fdc12
sub t0, t0, t1
li t2, 0x4e5562ec
bne t0, t2, fail
li s11, 43
li t0, 0x0e0bdf64
li t1, 0xe36a3bd6
sub t0, t0, t1
li t2, 0x2aa1a38e
bne t0, t2, fail
li s11, 44
li t0, 0x9cb52730
li t1, 0x091a5d19
sub t0, t0, t1
li t2, 0x939aca17
bne t0, t2, fail
li s11, 45
li t0, 0xb2328a1c
li t1, 0xb0bf1be0
sub t0, t0, t1
li t2, 0x01736e3c
bne t0, t2, fail
li s11, 46
li t0, 0x679c2971
li t1, 0x0987fa54
sub t0, t0, t1
li t2, 0x5e142f1d
bne t0, t2, fail
li s11, 47
li t0, 0x20b3ca2d
li t1, 0xe602d2dd
sub t0, t0, t1
li t2, 0x3ab0f750
bne t0, t2, fail
li s11, 48
li t0, 0xfe23f134
li t1, 0x424fd8ea
sub t0, t0, t1
li t2, 0xbbd4184a
bne t0, t2, fail
li s11, 49
li t0, 0x9b1582cb
li t1, 0x51073c09
sub t0, t0, t1
li t2, 0x4a0e46c2
bne t0, t2, fail
li s11, 50
li t0, 0x07514971
li t1, 0x2efd8948
sub t0, t0, t1
li t2, 0xd853c029
bne t0, t2, fail
li s11, 51
li t0, 0xfd497568
li t1, 0x7e4743f5
sub t0, t0, t1
li t2, 0x7f023173
bne t0, t2, fail
li s11, 52
li t0, 0x23507b06
li t1, 0x9626b8b5
sub t0, t0, t1
li t2, 0x8d29c251
bne t0, t2, fail
li s11, 53
li t0, 0x21a42789
li t1, 0x2147ec13
sub t0, t0, t1
li t2, 0x005c3b76
bne t0, t2, fail
li s11, 54
li t0, 0x1b05e763
li t1, 0x37193188
sub t0, t0, t1
li t2, 0xe3ecb5db
bne t0, t2, fail
li s11, 55
li t0, 0x08648211
li t1, 0x0b75b0e6
sub t0, t0, t1
li t2, 0xfceed12b
bne t0, t2, fail
li s11, 56
li t0, 0x28da08ff
li t1, 0x9c98553a
sub t0, t0, t1
li t2, 0x8c41b3c5
bne t0, t2, fail
li s11, 57
li t0, 0x86ffa6f2
li t1, 0x11ec7e79
sub t0, t0, t1
li t2, 0x75132879
bne t0, t2, fail
li s11, 58
li t0, 0x0c0133b0
li t1, 0x99936145
sub t0, t0, t1
li t2, 0x726dd26b
bne t0, t2, fail
li s11, 59
li t0, 0xe1667c70
li t1, 0x73f408b0
sub t0, t0, t1
li t2, 0x6d7273c0
bne t0, t2, fail
li s11, 60
li t0, 0x15cb40da
li t1, 0x722824eb
sub t0, t0, t1
li t2, 0xa3a31bef
bne t0, t2, fail
li s11, 61
li t0, 0xa1e3c723
li t1, 0xc167f24a
sub t0, t0, t1
li t2, 0xe07bd4d9
bne t0, t2, fail
li s11, 62
li t0, 0x08906c0b
li t1, 0xa65a3bb4
sub t0, t0, t1
li t2, 0x62363057
bne t0, t2, fail
li s11, 63
li t0, 0x4ec4455d
li t1, 0x12572652
sub t0, t0, t1
li t2, 0x3c6d1f0b
bne t0, t2, fail
li s11, 64
li t0, 0x31de0468
li t1, 0xf1f0cf4f
sub t0, t0, t1
li t2, 0x3fed3519
bne t0, t2, fail
li s11, 65
li t0, 0xd1f1592f
li t1, 0x7674b61d
sub t0, t0, t1
li t2, 0x5b7ca312
bne t0, t2, fail
li s11, 66
li t0, 0x00000000
li t1, 0xaaaaaaaa
sll t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 67
li t0, 0x00000001
li t1, 0x00000020
sll t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 68
li t0, 0xffffffff
li t1, 0x0000001f
sll t0, t0, t1
li t2, 0x80000000
bne t0, t2, fail
li s11, 69
li t0, 0x80000000
li t1, 0x7fffffff
sll t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 70
li t0, 0x7fffffff
li t1, 0x80000000
sll t0, t0, t1
li t2, 0x7fffffff
bne t0, t2, fail
li s11, 71
li t0, 0x0000001f
li t1, 0xffffffff
sll t0, t0, t1
li t2, 0x80000000
bne t0, t2, fail
li s11, 72
li t0, 0x00000020
li t1, 0x00000001
sll t0, t0, t1
li t2, 0x00000040
bne t0, t2, fail
li s11, 73
li t0, 0xaaaaaaaa
li t1, 0x00000000
sll t0, t0, t1
li t2, 0xaaaaaaaa
bne t0, t2, fail
li s11, 74
li t0, 0x91b87b38
li t1, 0x88038e84
sll t0, t0, t1
li t2, 0x1b87b380
bne t0, t2, fail
li s11, 75
li t0, 0xe9fc8472
li t1, 0x1c86b543
sll t0, t0, t1
li t2, 0x4fe42390
bne t0, t2, fail
li s11, 76
li t0, 0x05f3f097
li t1, 0x837ca57f
sll t0, t0, t1
li t2, 0x80000000
bne t0, t2, fail
li s11, 77
li t0, 0xc44d8119
li t1, 0x33719817
sll t0, t0, t1
li t2, 0x8c800000
bne t0, t2, fail
li s11, 78
li t0, 0xf7ef4ffa
li t1, 0x3c80aae7
sll t0, t0, t1
li t2, 0xf7a7fd00
bne t0, t2, fail
li s11, 79
li t0, 0x7b0e2d00
li t1, 0xa1ff5636
sll t0, t0, t1
li t2, 0x40000000
bne t0, t2, fail
li s11, 80
li t0, 0x7ae30ac4
li t1, 0xecd3a25d
sll t0, t0, t1
li t2, 0x80000000
bne t0, t2, fail
li s11, 81
li t0, 0x45823580
li t1, 0xd814cb27
sll t0, t0, t1
li t2, 0xc11ac000
bne t0, t2, fail
li s11, 82
li t0, 0xb479b49c
li t1, 0x371ab7c5
sll t0, t0, t1
li t2, 0x8f369380
bne t0, t2, fail
li s11, 83
li t0, 0xb6f7237c
li t1, 0x2e767c1a
sll t0, t0, t1
li t2, 0xf0000000
bne t0, t2, fail
li s11, 84
li t0, 0x5984c3e1
li t1, 0x94fca7e7
sll t0, t0, t1
li t2, 0xc261f080
bne t0, t2, fail
li s11, 85
li t0, 0xe612ce6a
li t1, 0xc6b7c10c
sll t0, t0, t1
li t2, 0x2ce6a000
bne t0, t2, fail
li s11, 86
li t0, 0xfd3b9448
li t1, 0xb51e05ec
sll t0, t0, t1
li t2, 0xb9448000
bne t0, t2, fail
li s11, 87
li t0, 0x26a8488f
li t1, 0xf46baa8d
sll t0, t0, t1
li t2, 0x0911e000
bne t0, t2, fail
li s11, 88
li t0, 0x1430b2c2
li t1, 0xcf65cba0
sll t0, t0, t1
li t2, 0x1430b2c2
bne t0, t2, fail
li s11, 89
li t0, 0x1c1f6987
li t1, 0x5571740a
sll t0, t0, t1
li t2, 0x7da61c00
bne t0, t2, fail
li s11, 90
li t0, 0x736e1873
li t1, 0x63b5efb3
sll t0, t0, t1
li t2, 0xc3980000
bne t0, t2, fail
li s11, 91
li t0, 0x52a986dd
li t1, 0xc35043d3
sll t0, t0, t1
li t2, 0x36e80000
bne t0, t2, fail
li s11, 92
li t0, 0x9d8f3fa1
li t1, 0x74752a41
sll t0, t0, t1
li t2, 0x3b1e7f42
bne t0, t2, fail
li s11, 93
li t0, 0x12a150b3
li t1, 0x7e100785
sll t0, t0, t1
li t2, 0x542a1660
bne t0, t2, fail
li s11, 94
li t0, 0xcb13cb85
li t1, 0xe4496dc3
sll t0, t0, t1
li t2, 0x589e5c28
bne t0, t2, fail
li s11, 95
li t0, 0xd0453b7c
li t1, 0xfeaaebbe
sll t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 96
li t0, 0x033c4598
li t1, 0xe9e5186e
sll t0, t0, t1
li t2, 0x11660000
bne t0, t2, fail
li s11, 97
li t0, 0x1d643434
li t1, 0xb5c9b3e9
sll t0, t0, t1
li t2, 0xc8686800
bne t0, t2, fail
li s11, 98
li t0, 0x00000000
li t1, 0xaaaaaaaa
srl t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 99
li t0, 0x00000001
li t1, 0x00000020
srl t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 100
li t0, 0xffffffff
li t1, 0x0000001f
srl t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 101
li t0, 0x80000000
li t1, 0x7fffffff
srl t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 102
li t0, 0x7fffffff
li t1, 0x80000000
srl t0, t0, t1
li t2, 0x7fffffff
bne t0, t2, fail
li s11, 103
li t0, 0x0000001f
li t1, 0xffffffff
srl t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 104
li t0, 0x00000020
li t1, 0x00000001
srl t0, t0, t1
li t2, 0x00000010
bne t0, t2, fail
li s11, 105
li t0, 0xaaaaaaaa
li t1, 0x00000000
srl t0, t0, t1
li t2, 0xaaaaaaaa
bne t0, t2, fail
li s11, 106
li t0, 0xb5ae4d9e
li t1, 0xa3dfdcab
srl t0, t0, t1
li t2, 0x0016b5c9
bne t0, t2, fail
li s11, 107
li t0, 0x6c3752a3
li t1, 0xbd4b6693
srl t0, t0, t1
li t2, 0x00000d86
bne t0, t2, fail
li s11, 108
li t0, 0xc31abe99
li t1, 0xf061d78e
srl t0, t0, t1
li t2, 0x00030c6a
bne t0, t2, fail
li s11, 109
li t0, 0x7ff0eac8
li t1, 0x6d342998
srl t0, t0, t1
li t2, 0x0000007f
bne t0, t2, fail
li s11, 110
li t0, 0x51745fe4
li t1, 0x61c854be
srl t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 111
li t0, 0x639b81ae
li t1, 0xdf3dbfba
srl t0, t0, t1
li t2, 0x00000018
bne t0, t2, fail
li s11, 112
li t0, 0xb0755c5a
li t1, 0x8c42b922
srl t0, t0, t1
li t2, 0x2c1d5716
bne t0, t2, fail
li s11, 113
li t0, 0xd845cf81
li t1, 0xeb534eba
srl t0, t0, t1
li t2, 0x00000036
bne t0, t2, fail
li s11, 114
li t0, 0xb7f7b33c
li t1, 0x95a46d67
srl t0, t0, t1
li t2, 0x016fef66
bne t0, t2, fail
li s11, 115
li t0, 0xe14968c7
li t1, 0x3bb56418
srl t0, t0, t1
li t2, 0x000000e1
bne t0, t2, fail
li s11, 116
li t0, 0xf78414ef
li t1, 0x680e0d9a
srl t0, t0, t1
li t2, 0x0000003d
bne t0, t2, fail
li s11, 117
li t0, 0x89070ce0
li t1, 0x2fd2d055
srl t0, t0, t1
li t2, 0x00000448
bne t0, t2, fail
li s11, 118
li t0, 0xc29ed83f
li t1, 0xdd470e32
srl t0, t0, t1
li t2, 0x000030a7
bne t0, t2, fail
li s11, 119
li t0, 0x19046288
li t1, 0x76142ad7
srl t0, t0, t1
li t2, 0x00000032
bne t0, t2, fail
li s11, 120
li t0, 0xb9708b8d
li t1, 0x5d6e6062
srl t0, t0, t1
li t2, 0x2e5c22e3
bne t0, t2, fail
li s11, 121
li t0, 0x73e6311b
li t1, 0x21b41a5a
srl t0, t0, t1
li t2, 0x0000001c
bne t0, t2, fail
li s11, 122
li t0, 0x104985ba
li t1, 0x5c43f9e1
srl t0, t0, t1
li t2, 0x0824c2dd
bne t0, t2, fail
li s11, 123
li t0, 0x9a97f591
li t1, 0xa1a699fe
srl t0, t0, t1
li t2, 0x00000002
bne t0, t2, fail
li s11, 124
li t0, 0x90419b5e
li t1, 0xdb70479a
srl t0, t0, t1
li t2, 0x00000024
bne t0, t2, fail
li s11, 125
li t0, 0xe1ee140e
li t1, 0x086e9c3f
srl t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 126
li t0, 0x49f1e0dc
li t1, 0x63071d39
srl t0, t0, t1
li t2, 0x00000024
bne t0, t2, fail
li s11, 127
li t0, 0x0836bdf0
li t1, 0x669e067c
srl t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 128
li t0, 0xd42cb3f7
li t1, 0x814c1fa6
srl t0, t0, t1
li t2, 0x0350b2cf
bne t0, t2, fail
li s11, 129
li t0, 0x8ed3bdce
li t1, 0xc5bba1d1
srl t0, t0, t1
li t2, 0x00004769
bne t0, t2, fail
li s11, 130
li t0, 0x00000000
li t1, 0xaaaaaaaa
sra t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 131
li t0, 0x00000001
li t1, 0x00000020
sra t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 132
li t0, 0xffffffff
li t1, 0x0000001f
sra t0, t0, t1
li t2, 0xffffffff
bne t0, t2, fail
li s11, 133
li t0, 0x80000000
li t1, 0x7fffffff
sra t0, t0, t1
li t2, 0xffffffff
bne t0, t2, fail
li s11, 134
li t0, 0x7fffffff
li t1, 0x80000000
sra t0, t0, t1
li t2, 0x7fffffff
bne t0, t2, fail
li s11, 135
li t0, 0x0000001f
li t1, 0xffffffff
sra t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 136
li t0, 0x00000020
li t1, 0x00000001
sra t0, t0, t1
li t2, 0x00000010
bne t0, t2, fail
li s11, 137
li t0, 0xaaaaaaaa
li t1, 0x00000000
sra t0, t0, t1
li t2, 0xaaaaaaaa
bne t0, t2, fail
li s11, 138
li t0, 0x67817a39
li t1, 0xa487e45a
sra t0, t0, t1
li t2, 0x00000019
bne t0, t2, fail
li s11, 139
li t0, 0xb4c0bdec
li t1, 0x7051826f
sra t0, t0, t1
li t2, 0xffff6981
bne t0, t2, fail
li s11, 140
li t0, 0xb48c5017
li t1, 0x74d4174d
sra t0, t0, t1
li t2, 0xfffda462
bne t0, t2, fail
li s11, 141
li t0, 0x89c1d171
li t1, 0xfea7f654
sra t0, t0, t1
li t2, 0xfffff89c
bne t0, t2, fail
li s11, 142
li t0, 0x5c1fe27a
li t1, 0x481cc7c0
sra t0, t0, t1
li t2, 0x5c1fe27a
bne t0, t2, fail
li s11, 143
li t0, 0x67b898ab
li t1, 0xd98aacdd
sra t0, t0, t1
li t2, 0x00000003
bne t0, t2, fail
li s11, 144
li t0, 0x3655d070
li t1, 0x7aa03946
sra t0, t0, t1
li t2, 0x00d95741
bne t0, t2, fail
li s11, 145
li t0, 0x3735bc2c
li t1, 0xc214c275
sra t0, t0, t1
li t2, 0x000001b9
bne t0, t2, fail
li s11, 146
li t0, 0xac686ec7
li t1, 0x7119307e
sra t0, t0, t1
li t2, 0xfffffffe
bne t0, t2, fail
li s11, 147
li t0, 0x023d32da
li t1, 0x6b2fac75
sra t0, t0, t1
li t2, 0x00000011
bne t0, t2, fail
li s11, 148
li t0, 0x40ab12b9
li t1, 0x23324318
sra t0, t0, t1
li t2, 0x00000040
bne t0, t2, fail
li s11, 149
li t0, 0x8a1c65ae
li t1, 0x4223407a
sra t0, t0, t1
li t2, 0xffffffe2
bne t0, t2, fail
li s11, 150
li t0, 0x4c12899d
li t1, 0x02464fcc
sra t0, t0, t1
li t2, 0x0004c128
bne t0, t2, fail
li s11, 151
li t0, 0x7b269c38
li t1, 0x9b2b7d9e
sra t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 152
li t0, 0xeea80f78
li t1, 0x9c5544c1
sra t0, t0, t1
li t2, 0xf75407bc
bne t0, t2, fail
li s11, 153
li t0, 0xec7f182a
li t1, 0xae237fca
sra t0, t0, t1
li t2, 0xfffb1fc6
bne t0, t2, fail
li s11, 154
li t0, 0x3e6b5d93
li t1, 0xaffb2762
sra t0, t0, t1
li t2, 0x0f9ad764
bne t0, t2, fail
li s11, 155
li t0, 0x81ef0c07
li t1, 0x27caf6ec
sra t0, t0, t1
li t2, 0xfff81ef0
bne t0, t2, fail
li s11, 156
li t0, 0x9092075f
li t1, 0xe2c49ee7
sra t0, t0, t1
li t2, 0xff21240e
bne t0, t2, fail
li s11, 157
li t0, 0xa2cd1ddc
li t1, 0x6dc6f49a
sra t0, t0, t1
li t2, 0xffffffe8
bne t0, t2, fail
li s11, 158
li t0, 0x56e00a97
li t1, 0xef1d3b10
sra t0, t0, t1
li t2, 0x000056e0
bne t0, t2, fail
li s11, 159
li t0, 0xe99d25ff
li t1, 0xc99d9768
sra t0, t0, t1
li t2, 0xffe99d25
bne t0, t2, fail
li s11, 160
li t0, 0x8c9652d0
li t1, 0x291ea1d5
sra t0, t0, t1
li t2, 0xfffffc64
bne t0, t2, fail
li s11, 161
li t0, 0x25874401
li t1, 0xa5afa3f8
sra t0, t0, t1
li t2, 0x00000025
bne t0, t2, fail
li s11, 162
li t0, 0x00000000
li t1, 0xaaaaaaaa
slt t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 163
li t0, 0x00000001
li t1, 0x00000020
slt t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 164
li t0, 0xffffffff
li t1, 0x0000001f
slt t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 165
li t0, 0x80000000
li t1, 0x7fffffff
slt t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 166
li t0, 0x7fffffff
li t1, 0x80000000
slt t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 167
li t0, 0x0000001f
li t1, 0xffffffff
slt t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 168
li t0, 0x00000020
li t1, 0x00000001
slt t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 169
li t0, 0xaaaaaaaa
li t1, 0x00000000
slt t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 170
li t0, 0xd2c5434a
li t1, 0x82960df5
slt t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 171
li t0, 0xa85ce3bb
li t1, 0xcaed1004
slt t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 172
li t0, 0x5c06fd32
li t1, 0xa71153e2
slt t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 173
li t0, 0x0e6539b0
li t1, 0xec6ae167
slt t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 174
li t0, 0x3dd6a5e6
li t1, 0xdbdad3a5
slt t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 175
li t0, 0x1c95a4e8
li t1, 0x2121faec
slt t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 176
li t0, 0xd794b960
li t1, 0xae1e10c2
slt t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 177
li t0, 0x0bc24904
li t1, 0x0ef29cff
slt t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 178
li t0, 0x361d8f2c
li t1, 0x2b081b96
slt t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 179
li t0, 0x3e8d2968
li t1, 0x9d469e44
slt t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 180
li t0, 0xc0b8c363
li t1, 0xfa1c9ffb
slt t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 181
li t0, 0x5eab6548
li t1, 0x8ec82b9a
slt t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 182
li t0, 0x62efb1af
li t1, 0x772d8acf
slt t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 183
li t0, 0x28868b83
li t1, 0x804a26ea
slt t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 184
li t0, 0x1c7bcb6b
li t1, 0x4415a977
slt t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 185
li t0, 0x7bf40167
li t1, 0xabd53f65
slt t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 186
li t0, 0xd52dec13
li t1, 0x918ccfd1
slt t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 187
li t0, 0x21db9d72
li t1, 0xeac810ba
slt t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 188
li t0, 0xa715ae79
li t1, 0x8e245845
slt t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 189
li t0, 0x3e35a411
li t1, 0xff9cc953
slt t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 190
li t0, 0x9b37e457
li t1, 0x3fcb8535
slt t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 191
li t0, 0xcc4ac1b7
li t1, 0xd5c4a602
slt t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 192
li t0, 0x6c2d8c0e
li t1, 0x661980d4
slt t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 193
li t0, 0x0e794f19
li t1, 0x19ccc671
slt t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 194
li t0, 0x00000000
li t1, 0xaaaaaaaa
sltu t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 195
li t0, 0x00000001
li t1, 0x00000020
sltu t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 196
li t0, 0xffffffff
li t1, 0x0000001f
sltu t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 197
li t0, 0x80000000
li t1, 0x7fffffff
sltu t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 198
li t0, 0x7fffffff
li t1, 0x80000000
sltu t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 199
li t0, 0x0000001f
li t1, 0xffffffff
sltu t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 200
li t0, 0x00000020
li t1, 0x00000001
sltu t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 201
li t0, 0xaaaaaaaa
li t1, 0x00000000
sltu t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 202
li t0, 0x14235392
li t1, 0x76b91000
sltu t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 203
li t0, 0xa5e488fa
li t1, 0xec22fed8
sltu t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 204
li t0, 0xd4f34097
li t1, 0xa60d9f8c
sltu t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 205
li t0, 0x912628ce
li t1, 0x6cae5cd2
sltu t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 206
li t0, 0xf55568eb
li t1, 0x3ce7d1c1
sltu t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 207
li t0, 0x4f7097a2
li t1, 0x331807ae
sltu t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 208
li t0, 0x625b6d3b
li t1, 0x1c5acbae
sltu t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 209
li t0, 0xe0948442
li t1, 0x6d3ef18e
sltu t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 210
li t0, 0x67169a53
li t1, 0x485844d2
sltu t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 211
li t0, 0x8c1fd204
li t1, 0x85443c24
sltu t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 212
li t0, 0x7a126c9b
li t1, 0x1e4a2617
sltu t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 213
li t0, 0x360edb4f
li t1, 0x9440d091
sltu t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 214
li t0, 0xb1a0f04b
li t1, 0x07acc91c
sltu t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 215
li t0, 0x77b49376
li t1, 0x142e4412
sltu t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 216
li t0, 0xbbaa0d1f
li t1, 0xb6e02704
sltu t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 217
li t0, 0x0067afc4
li t1, 0x01785902
sltu t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 218
li t0, 0x219d39dc
li t1, 0xe669aee5
sltu t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 219
li t0, 0xd9d8f71a
li t1, 0x26c93b65
sltu t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 220
li t0, 0x85b98c43
li t1, 0x417a3a3f
sltu t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 221
li t0, 0x190632fe
li t1, 0x4662a2e0
sltu t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 222
li t0, 0x598cabc1
li t1, 0xe880c25d
sltu t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 223
li t0, 0x25a033c9
li t1, 0xb63d47bf
sltu t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 224
li t0, 0x5b7c77af
li t1, 0xf863a6f0
sltu t0, t0, t1
li t2, 0x00000001
bne t0, t2, fail
li s11, 225
li t0, 0xea981289
li t1, 0xc9809519
sltu t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 226
li t0, 0x00000000
li t1, 0xaaaaaaaa
xor t0, t0, t1
li t2, 0xaaaaaaaa
bne t0, t2, fail
li s11, 227
li t0, 0x00000001
li t1, 0x00000020
xor t0, t0, t1
li t2, 0x00000021
bne t0, t2, fail
li s11, 228
li t0, 0xffffffff
li t1, 0x0000001f
xor t0, t0, t1
li t2, 0xffffffe0
bne t0, t2, fail
li s11, 229
li t0, 0x80000000
li t1, 0x7fffffff
xor t0, t0, t1
li t2, 0xffffffff
bne t0, t2, fail
li s11, 230
li t0, 0x7fffffff
li t1, 0x80000000
xor t0, t0, t1
li t2, 0xffffffff
bne t0, t2, fail
li s11, 231
li t0, 0x0000001f
li t1, 0xffffffff
xor t0, t0, t1
li t2, 0xffffffe0
bne t0, t2, fail
li s11, 232
li t0, 0x00000020
li t1, 0x00000001
xor t0, t0, t1
li t2, 0x00000021
bne t0, t2, fail
li s11, 233
li t0, 0xaaaaaaaa
li t1, 0x00000000
xor t0, t0, t1
li t2, 0xaaaaaaaa
bne t0, t2, fail
li s11, 234
li t0, 0x92b38032
li t1, 0xe26e84e0
xor t0, t0, t1
li t2, 0x70dd04d2
bne t0, t2, fail
li s11, 235
li t0, 0xaa9467c6
li t1, 0x731b5365
xor t0, t0, t1
li t2, 0xd98f34a3
bne t0, t2, fail
li s11, 236
li t0, 0x89d359f3
li t1, 0x722192c4
xor t0, t0, t1
li t2, 0xfbf2cb37
bne t0, t2, fail
li s11, 237
li t0, 0xe6cfe9b4
li t1, 0x9cc432c2
xor t0, t0, t1
li t2, 0x7a0bdb76
bne t0, t2, fail
li s11, 238
li t0, 0x96dca71f
li t1, 0x40c4dd66
xor t0, t0, t1
li t2, 0xd6187a79
bne t0, t2, fail
li s11, 239
li t0, 0x29174812
li t1, 0xbc492fc6
xor t0, t0, t1
li t2, 0x955e67d4
bne t0, t2, fail
li s11, 240
li t0, 0x84f6e051
li t1, 0x5cd2a892
xor t0, t0, t1
li t2, 0xd82448c3
bne t0, t2, fail
li s11, 241
li t0, 0xe1acf029
li t1, 0xc48b06f8
xor t0, t0, t1
li t2, 0x2527f6d1
bne t0, t2, fail
li s11, 242
li t0, 0x988d61db
li t1, 0x99d2ee58
xor t0, t0, t1
li t2, 0x015f8f83
bne t0, t2, fail
li s11, 243
li t0, 0xfd938a88
li t1, 0xe9419844
xor t0, t0, t1
li t2, 0x14d212cc
bne t0, t2, fail
li s11, 244
li t0, 0x99745865
li t1, 0xee9ef78e
xor t0, t0, t1
li t2, 0x77eaafeb
bne t0, t2, fail
li s11, 245
li t0, 0x4ed92166
li t1, 0x1be65219
xor t0, t0, t1
li t2, 0x553f737f
bne t0, t2, fail
li s11, 246
li t0, 0x6ecaa424
li t1, 0xdab2a01b
xor t0, t0, t1
li t2, 0xb478043f
bne t0, t2, fail
li s11, 247
li t0, 0x72822162
li t1, 0x9cb4ce17
xor t0, t0, t1
li t2, 0xee36ef75
bne t0, t2, fail
li s11, 248
li t0, 0xcfb84bad
li t1, 0x67366067
xor t0, t0, t1
li t2, 0xa88e2bca
bne t0, t2, fail
li s11, 249
li t0, 0xba8d67c2
li t1, 0xfe85dea5
xor t0, t0, t1
li t2, 0x4408b967
bne t0, t2, fail
li s11, 250
li t0, 0xfa5cb308
li t1, 0x525bc8f8
xor t0, t0, t1
li t2, 0xa8077bf0
bne t0, t2, fail
li s11, 251
li t0, 0x004ef0de
li t1, 0x0768afdd
xor t0, t0, t1
li t2, 0x07265f03
bne t0, t2, fail
li s11, 252
li t0, 0xe1af4b56
li t1, 0x3538d357
xor t0, t0, t1
li t2, 0xd4979801
bne t0, t2, fail
li s11, 253
li t0, 0x73420489
li t1, 0xf0e5c86e
xor t0, t0, t1
li t2, 0x83a7cce7
bne t0, t2, fail
li s11, 254
li t0, 0xb084823e
li t1, 0xc7fd8ad6
xor t0, t0, t1
li t2, 0x777908e8
bne t0, t2, fail
li s11, 255
li t0, 0xd55b9467
li t1, 0x8722c1a2
xor t0, t0, t1
li t2, 0x527955c5
bne t0, t2, fail
li s11, 256
li t0, 0x14b83c09
li t1, 0xe43e1f84
xor t0, t0, t1
li t2, 0xf086238d
bne t0, t2, fail
li s11, 257
li t0, 0xc2ba5359
li t1, 0xfabb2af7
xor t0, t0, t1
li t2, 0x380179ae
bne t0, t2, fail
li s11, 258
li t0, 0x00000000
li t1, 0xaaaaaaaa
or t0, t0, t1
li t2, 0xaaaaaaaa
bne t0, t2, fail
li s11, 259
li t0, 0x00000001
li t1, 0x00000020
or t0, t0, t1
li t2, 0x00000021
bne t0, t2, fail
li s11, 260
li t0, 0xffffffff
li t1, 0x0000001f
or t0, t0, t1
li t2, 0xffffffff
bne t0, t2, fail
li s11, 261
li t0, 0x80000000
li t1, 0x7fffffff
or t0, t0, t1
li t2, 0xffffffff
bne t0, t2, fail
li s11, 262
li t0, 0x7fffffff
li t1, 0x80000000
or t0, t0, t1
li t2, 0xffffffff
bne t0, t2, fail
li s11, 263
li t0, 0x0000001f
li t1, 0xffffffff
or t0, t0, t1
li t2, 0xffffffff
bne t0, t2, fail
li s11, 264
li t0, 0x00000020
li t1, 0x00000001
or t0, t0, t1
li t2, 0x00000021
bne t0, t2, fail
li s11, 265
li t0, 0xaaaaaaaa
li t1, 0x00000000
or t0, t0, t1
li t2, 0xaaaaaaaa
bne t0, t2, fail
li s11, 266
li t0, 0x4c8d1f80
li t1, 0x3aaabbd4
or t0, t0, t1
li t2, 0x7eafbfd4
bne t0, t2, fail
li s11, 267
li t0, 0x82969a63
li t1, 0x0d9b2c66
or t0, t0, t1
li t2, 0x8f9fbe67
bne t0, t2, fail
li s11, 268
li t0, 0x9b717240
li t1, 0x14d9f957
or t0, t0, t1
li t2, 0x9ff9fb57
bne t0, t2, fail
li s11, 269
li t0, 0x31528be4
li t1, 0x3aed4e94
or t0, t0, t1
li t2, 0x3bffcff4
bne t0, t2, fail
li s11, 270
li t0, 0x7e71b9c2
li t1, 0xa51f9e18
or t0, t0, t1
li t2, 0xff7fbfda
bne t0, t2, fail
li s11, 271
li t0, 0x2b0b1229
li t1, 0x115f21ca
or t0, t0, t1
li t2, 0x3b5f33eb
bne t0, t2, fail
li s11, 272
li t0, 0x8f3648a0
li t1, 0x7ec9f563
or t0, t0, t1
li t2, 0xfffffde3
bne t0, t2, fail
li s11, 273
li t0, 0x672e607b
li t1, 0xc103b703
or t0, t0, t1
li t2, 0xe72ff77b
bne t0, t2, fail
li s11, 274
li t0, 0x1d0ccbee
li t1, 0xa9ea2df4
or t0, t0, t1
li t2, 0xbdeeeffe
bne t0, t2, fail
li s11, 275
li t0, 0x4cd85174
li t1, 0x49e440da
or t0, t0, t1
li t2, 0x4dfc51fe
bne t0, t2, fail
li s11, 276
li t0, 0x5691b45d
li t1, 0x4a7bb077
or t0, t0, t1
li t2, 0x5efbb47f
bne t0, t2, fail
li s11, 277
li t0, 0x046ef545
li t1, 0x410afcdf
or t0, t0, t1
li t2, 0x456efddf
bne t0, t2, fail
li s11, 278
li t0, 0x8e2cab62
li t1, 0xe0bf04e5
or t0, t0, t1
li t2, 0xeebfafe7
bne t0, t2, fail
li s11, 279
li t0, 0x491c035e
li t1, 0xff27821c
or t0, t0, t1
li t2, 0xff3f835e
bne t0, t2, fail
li s11, 280
li t0, 0x0e7dd57c
li t1, 0x4aff9227
or t0, t0, t1
li t2, 0x4effd77f
bne t0, t2, fail
li s11, 281
li t0, 0x04a1bfde
li t1, 0xc9052c21
or t0, t0, t1
li t2, 0xcda5bfff
bne t0, t2, fail
li s11, 282
li t0, 0x63c739c9
li t1, 0x7cf459dd
or t0, t0, t1
li t2, 0x7ff779dd
bne t0, t2, fail
li s11, 283
li t0, 0xe1925e3f
li t1, 0x0ade7277
or t0, t0, t1
li t2, 0xebde7e7f
bne t0, t2, fail
li s11, 284
li t0, 0x8ca6b835
li t1, 0x0cc14f2c
or t0, t0, t1
li t2, 0x8ce7ff3d
bne t0, t2, fail
li s11, 285
li t0, 0x27f90f6e
li t1, 0x806d39f8
or t0, t0, t1
li t2, 0xa7fd3ffe
bne t0, t2, fail
li s11, 286
li t0, 0x6912fc71
li t1, 0xdbc2e714
or t0, t0, t1
li t2, 0xfbd2ff75
bne t0, t2, fail
li s11, 287
li t0, 0xa6c7a8ab
li t1, 0xbb686724
or t0, t0, t1
li t2, 0xbfefefaf
bne t0, t2, fail
li s11, 288
li t0, 0x3ce6646c
li t1, 0x4aa64a87
or t0, t0, t1
li t2, 0x7ee66eef
bne t0, t2, fail
li s11, 289
li t0, 0x267f425d
li t1, 0x87f4884b
or t0, t0, t1
li t2, 0xa7ffca5f
bne t0, t2, fail
li s11, 290
li t0, 0x00000000
li t1, 0xaaaaaaaa
and t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 291
li t0, 0x00000001
li t1, 0x00000020
and t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 292
li t0, 0xffffffff
li t1, 0x0000001f
and t0, t0, t1
li t2, 0x0000001f
bne t0, t2, fail
li s11, 293
li t0, 0x80000000
li t1, 0x7fffffff
and t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 294
li t0, 0x7fffffff
li t1, 0x80000000
and t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 295
li t0, 0x0000001f
li t1, 0xffffffff
and t0, t0, t1
li t2, 0x0000001f
bne t0, t2, fail
li s11, 296
li t0, 0x00000020
li t1, 0x00000001
and t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 297
li t0, 0xaaaaaaaa
li t1, 0x00000000
and t0, t0, t1
li t2, 0x00000000
bne t0, t2, fail
li s11, 298
li t0, 0xd088f70a
li t1, 0x76ed3d19
and t0, t0, t1
li t2, 0x50883508
bne t0, t2, fail
li s11, 299
li t0, 0x2714bd45
li t1, 0x07ba102e
and t0, t0, t1
li t2, 0x07101004
bne t0, t2, fail
li s11, 300
li t0, 0xb7f53567
li t1, 0xd0444e2f
and t0, t0, t1
li t2, 0x90440427
bne t0, t2, fail
li s11, 301
li t0, 0xe6edc3a1
li t1, 0xc40fa394
and t0, t0, t1
li t2, 0xc40d8380
bne t0, t2, fail
li s11, 302
li t0, 0xe0030f8f
li t1, 0x9efa0666
and t0, t0, t1
li t2, 0x80020606
bne t0, t2, fail
li s11, 303
li t0, 0x6640df38
li t1, 0xeb29c226
and t0, t0, t1
li t2, 0x6200c220
bne t0, t2, fail
li s11, 304
li t0, 0xa8a33a3e
li t1, 0xe96f2f94
and t0, t0, t1
li t2, 0xa8232a14
bne t0, t2, fail
li s11, 305
li t0, 0x30075ef6
li t1, 0xd48150f1
and t0, t0, t1
li t2, 0x100150f0
bne t0, t2, fail
li s11, 306
li t0, 0xffd313a3
li t1, 0x84ca061b
and t0, t0, t1
li t2, 0x84c20203
bne t0, t2, fail
li s11, 307
li t0, 0x88132ab6
li t1, 0xe8e46b8a
and t0, t0, t1
li t2, 0x88002a82
bne t0, t2, fail
li s11, 308
li t0, 0x2e8d4a54
li t1, 0xf43c1925
and t0, t0, t1
li t2, 0x240c0804
bne t0, t2, fail
li s11, 309
li t0, 0xebb102b7
li t1, 0x10145bfe
and t0, t0, t1
li t2, 0x001002b6
bne t0, t2, fail
li s11, 310
li t0, 0xa44ef6ff
li t1, 0x3f3ee4e9
and t0, t0, t1
li t2, 0x240ee4e9
bne t0, t2, fail
li s11, 311
li t0, 0x6709f35d
li t1, 0x2cd5ef06
and t0, t0, t1
li t2, 0x2401e304
bne t0, t2, fail
li s11, 312
li t0, 0x994923e2
li t1, 0xed76cbe1
and t0, t0, t1
li t2, 0x894003e0
bne t0, t2, fail
li s11, 313
li t0, 0x52c85840
li t1, 0x2ebe8eb6
and t0, t0, t1
li t2, 0x02880800
bne t0, t2, fail
li s11, 314
li t0, 0x7d3d1929
li t1, 0xd29258c0
and t0, t0, t1
li t2, 0x50101800
bne t0, t2, fail
li s11, 315
li t0, 0x4ea7fb66
li t1, 0x4209b288
and t0, t0, t1
li t2, 0x4201b200
bne t0, t2, fail
li s11, 316
li t0, 0xe1a0005b
li t1, 0xd344a616
and t0, t0, t1
li t2, 0xc1000012
bne t0, t2, fail
li s11, 317
li t0, 0x9315fde4
li t1, 0x5491bd36
and t0, t0, t1
li t2, 0x1011bd24
bne t0, t2, fail
li s11, 318
li t0, 0x82fe4daf
li t1, 0x5a00e353
and t0, t0, t1
li t2, 0x02004103
bne t0, t2, fail
li s11, 319
li t0, 0x1f8caf1e
li t1, 0xd4472e96
and t0, t0, t1
li t2, 0x14042e16
bne t0, t2, fail
li s11, 320
li t0, 0x7e9a608a
li t1, 0x9b2f9d11
and t0, t0, t1
li t2, 0x1a0a0000
bne t0, t2, fail
li s11, 321
li t0, 0x73128f3f
li t1, 0x44f89379
and t0, t0, t1
li t2, 0x40108339
bne t0, t2, fail
li s11, 322
li t0, 0x9c0f12b3
addi t0, t0, -613
li t2, 0x9c0f104e
bne t0, t2, fail
li s11, 323
li t0, 0xb351f764
addi t0, t0, 914
li t2, 0xb351faf6
bne t0, t2, fail
li s11, 324
li t0, 0xdf49cd3e
addi t0, t0, 310
li t2, 0xdf49ce74
bne t0, t2, fail
li s11, 325
li t0, 0xb15fdf7a
addi t0, t0, -458
li t2, 0xb15fddb0
bne t0, t2, fail
li s11, 326
li t0, 0xaaffaccb
addi t0, t0, 675
li t2, 0xaaffaf6e
bne t0, t2, fail
li s11, 327
li t0, 0xdabe240e
addi t0, t0, 1070
li t2, 0xdabe283c
bne t0, t2, fail
li s11, 328
li t0, 0x30c190aa
addi t0, t0, -433
li t2, 0x30c18ef9
bne t0, t2, fail
li s11, 329
li t0, 0x90390286
addi t0, t0, -844
li t2, 0x9038ff3a
bne t0, t2, fail
li s11, 330
li t0, 0x467a4eb7
addi t0, t0, -1144
li t2, 0x467a4a3f
bne t0, t2, fail
li s11, 331
li t0, 0x9b8a08ad
addi t0, t0, -2024
li t2, 0x9b8a00c5
bne t0, t2, fail
li s11, 332
li t0, 0x36240aff
addi t0, t0, 215
li t2, 0x36240bd6
bne t0, t2, fail
li s11, 333
li t0, 0x3fb529b1
addi t0, t0, -501
li t2, 0x3fb527bc
bne t0, t2, fail
li s11, 334
li t0, 0x96794a1e
addi t0, t0, 49
li t2, 0x96794a4f
bne t0, t2, fail
li s11, 335
li t0, 0xedc02011
addi t0, t0, -1561
li t2, 0xedc019f8
bne t0, t2, fail
li s11, 336
li t0, 0xf876ab30
addi t0, t0, 1071
li t2, 0xf876af5f
bne t0, t2, fail
li s11, 337
li t0, 0x92e3be8c
addi t0, t0, -151
li t2, 0x92e3bdf5
bne t0, t2, fail
li s11, 338
li t0, 0x265c6ac9
slti t0, t0, -612
li t2, 0x00000000
bne t0, t2, fail
li s11, 339
li t0, 0x8e789f87
slti t0, t0, 528
li t2, 0x00000001
bne t0, t2, fail
li s11, 340
li t0, 0xae9c3980
slti t0, t0, 470
li t2, 0x00000001
bne t0, t2, fail
li s11, 341
li t0, 0x3199edfd
slti t0, t0, -1727
li t2, 0x00000000
bne t0, t2, fail
li s11, 342
li t0, 0xe7c7c1d7
slti t0, t0, -809
li t2, 0x00000001
bne t0, t2, fail
li s11, 343
li t0, 0x5c00b1be
slti t0, t0, 591
li t2, 0x00000000
bne t0, t2, fail
li s11, 344
li t0, 0xaeb2338c
slti t0, t0, -1044
li t2, 0x00000001
bne t0, t2, fail
li s11, 345
li t0, 0xd24a4cf3
slti t0, t0, 1641
li t2, 0x00000001
bne t0, t2, fail
li s11, 346
li t0, 0xccdc8ac3
slti t0, t0, -124
li t2, 0x00000001
bne t0, t2, fail
li s11, 347
li t0, 0xccb6acbd
slti t0, t0, 1355
li t2, 0x00000001
bne t0, t2, fail
li s11, 348
li t0, 0x074435cb
slti t0, t0, -189
li t2, 0x00000000
bne t0, t2, fail
li s11, 349
li t0, 0x04128154
slti t0, t0, 645
li t2, 0x00000000
bne t0, t2, fail
li s11, 350
li t0, 0xb6355e0d
slti t0, t0, -830
li t2, 0x00000001
bne t0, t2, fail
li s11, 351
li t0, 0xae8678a2
slti t0, t0, 72
li t2, 0x00000001
bne t0, t2, fail
li s11, 352
li t0, 0x48e889e4
slti t0, t0, -1458
li t2, 0x00000000
bne t0, t2, fail
li s11, 353
li t0, 0x2e43003a
slti t0, t0, 1690
li t2, 0x00000000
bne t0, t2, fail
li s11, 354
li t0, 0x10db7f8c
sltiu t0, t0, -1853
li t2, 0x00000001
bne t0, t2, fail
li s11, 355
li t0, 0x1135dbf5
sltiu t0, t0, -1889
li t2, 0x00000001
bne t0, t2, fail
li s11, 356
li t0, 0x5509e4a8
sltiu t0, t0, 1573
li t2, 0x00000000
bne t0, t2, fail
li s11, 357
li t0, 0x525784aa
sltiu t0, t0, -263
li t2, 0x00000001
bne t0, t2, fail
li s11, 358
li t0, 0xf0eec7a7
sltiu t0, t0, -1845
li t2, 0x00000001
bne t0, t2, fail
li s11, 359
li t0, 0x56d38a12
sltiu t0, t0, -333
li t2, 0x00000001
bne t0, t2, fail
li s11, 360
li t0, 0x6fcf49c1
sltiu t0, t0, 626
li t2, 0x00000000
bne t0, t2, fail
li s11, 361
li t0, 0xde1a4fd5
sltiu t0, t0, 1174
li t2, 0x00000000
bne t0, t2, fail
li s11, 362
li t0, 0x2c1906e7
sltiu t0, t0, 1584
li t2, 0x00000000
bne t0, t2, fail
li s11, 363
li t0, 0xed855dcf
sltiu t0, t0, 733
li t2, 0x00000000
bne t0, t2, fail
li s11, 364
li t0, 0x939d8285
sltiu t0, t0, 187
li t2, 0x00000000
bne t0, t2, fail
li s11, 365
li t0, 0xceb3506a
sltiu t0, t0, -1208
li t2, 0x00000001
bne t0, t2, fail
li s11, 366
li t0, 0x781a0c5e
sltiu t0, t0, 705
li t2, 0x00000000
bne t0, t2, fail
li s11, 367
li t0, 0x730d179a
sltiu t0, t0, 22
li t2, 0x00000000
bne t0, t2, fail
li s11, 368
li t0, 0xd39d4964
sltiu t0, t0, -1220
li t2, 0x00000001
bne t0, t2, fail
li s11, 369
li t0, 0xc422e66a
sltiu t0, t0, 209
li t2, 0x00000000
bne t0, t2, fail
li s11, 370
li t0, 0x500cb99f
xori t0, t0, -1509
li t2, 0xaff34384
bne t0, t2, fail
li s11, 371
li t0, 0x8e244cd1
xori t0, t0, 842
li t2, 0x8e244f9b
bne t0, t2, fail
li s11, 372
li t0, 0xb6462bbd
xori t0, t0, -765
li t2, 0x49b9d6be
bne t0, t2, fail
li s11, 373
li t0, 0x1844a562
xori t0, t0, 1116
li t2, 0x1844a13e
bne t0, t2, fail
li s11, 374
li t0, 0x1ca65462
xori t0, t0, -984
li t2, 0xe359a84a
bne t0, t2, fail
li s11, 375
li t0, 0xb25c134d
xori t0, t0, 1648
li t2, 0xb25c153d
bne t0, t2, fail
li s11, 376
li t0, 0x97f56215
xori t0, t0, 112
li t2, 0x97f56265
bne t0, t2, fail
li s11, 377
li t0, 0x884f2ae4
xori t0, t0, -1118
li t2, 0x77b0d146
bne t0, t2, fail
li s11, 378
li t0, 0x1938b4e5
xori t0, t0, -1468
li t2, 0xe6c74ea1
bne t0, t2, fail
li s11, 379
li t0, 0x234ce788
xori t0, t0, 1020
li t2, 0x234ce474
bne t0, t2, fail
li s11, 380
li t0, 0xd71d4cc4
xori t0, t0, 1896
li t2, 0xd71d4bac
bne t0, t2, fail
li s11, 381
li t0, 0x4cd23d57
xori t0, t0, -275
li t2, 0xb32dc3ba
bne t0, t2, fail
li s11, 382
li t0, 0xae1d4ef1
xori t0, t0, -1560
li t2, 0x51e2b719
bne t0, t2, fail
li s11, 383
li t0, 0xe10071a0
xori t0, t0, -1098
li t2, 0x1eff8a16
bne t0, t2, fail
li s11, 384
li t0, 0x0af4dcd5
xori t0, t0, -408
li t2, 0xf50b22bd
bne t0, t2, fail
li s11, 385
li t0, 0x42f43ec5
xori t0, t0, 1606
li t2, 0x42f43883
bne t0, t2, fail
li s11, 386
li t0, 0x18cd890e
ori t0, t0, -127
li t2, 0xffffff8f
bne t0, t2, fail
li s11, 387
li t0, 0x80000524
ori t0, t0, -320
li t2, 0xffffffe4
bne t0, t2, fail
li s11, 388
li t0, 0x05aab281
ori t0, t0, -1110
li t2, 0xfffffbab
bne t0, t2, fail
li s11, 389
li t0, 0x5b367b83
ori t0, t0, 2030
li t2, 0x5b367fef
bne t0, t2, fail
li s11, 390
li t0, 0x38c18b34
ori t0, t0, 2001
li t2, 0x38c18ff5
bne t0, t2, fail
li s11, 391
li t0, 0xf10996f1
ori t0, t0, 10
li t2, 0xf10996fb
bne t0, t2, fail
li s11, 392
li t0, 0xbca1865d
ori t0, t0, -24
li t2, 0xfffffffd
bne t0, t2, fail
li s11, 393
li t0, 0x8dd28bd6
ori t0, t0, -1669
li t2, 0xfffffbff
bne t0, t2, fail
li s11, 394
li t0, 0x6e32fee3
ori t0, t0, 800
li t2, 0x6e32ffe3
bne t0, t2, fail
li s11, 395
li t0, 0x98f16d33
ori t0, t0, -1897
li t2, 0xfffffdb7
bne t0, t2, fail
li s11, 396
li t0, 0xac47ac2e
ori t0, t0, -77
li t2, 0xffffffbf
bne t0, t2, fail
li s11, 397
li t0, 0x8b5f7f18
ori t0, t0, -824
li t2, 0xffffffd8
bne t0, t2, fail
li s11, 398
li t0, 0x90e3023e
ori t0, t0, 1022
li t2, 0x90e303fe
bne t0, t2, fail
li s11, 399
li t0, 0x052198e7
ori t0, t0, -134
li t2, 0xffffffff
bne t0, t2, fail
li s11, 400
li t0, 0xffc4e83f
ori t0, t0, 450
li t2, 0xffc4e9ff
bne t0, t2, fail
li s11, 401
li t0, 0x07e6f2be
ori t0, t0, 811
li t2, 0x07e6f3bf
bne t0, t2, fail
li s11, 402
li t0, 0x038ff7e7
andi t0, t0, 408
li t2, 0x00000180
bne t0, t2, fail
li s11, 403
li t0, 0xb9d51d8d
andi t0, t0, -136
li t2, 0xb9d51d08
bne t0, t2, fail
li s11, 404
li t0, 0xe12a0553
andi t0, t0, -1166
li t2, 0xe12a0152
bne t0, t2, fail
li s11, 405
li t0, 0xdc0e8d5c
andi t0, t0, 1609
li t2, 0x00000448
bne t0, t2, fail
li s11, 406
li t0, 0xd7e55297
andi t0, t0, -152
li t2, 0xd7e55200
bne t0, t2, fail
li s11, 407
li t0, 0xdca4a5f6
andi t0, t0, 77
li t2, 0x00000044
bne t0, t2, fail
li s11, 408
li t0, 0x40c8cd53
andi t0, t0, 277
li t2, 0x00000111
bne t0, t2, fail
li s11, 409
li t0, 0xd23846c5
andi t0, t0, 639
li t2, 0x00000245
bne t0, t2, fail
li s11, 410
li t0, 0x3aab2f5a
andi t0, t0, 1789
li t2, 0x00000658
bne t0, t2, fail
li s11, 411
li t0, 0x79d74d45
andi t0, t0, -169
li t2, 0x79d74d45
bne t0, t2, fail
li s11, 412
li t0, 0x5a97bbf4
andi t0, t0, 1842
li t2, 0x00000330
bne t0, t2, fail
li s11, 413
li t0, 0x9914aedf
andi t0, t0, -1408
li t2, 0x9914aa80
bne t0, t2, fail
li s11, 414
li t0, 0x27e83688
andi t0, t0, 1475
li t2, 0x00000480
bne t0, t2, fail
li s11, 415
li t0, 0x153a5651
andi t0, t0, 616
li t2, 0x00000240
bne t0, t2, fail
li s11, 416
li t0, 0xa4f22b0b
andi t0, t0, 1334
li t2, 0x00000102
bne t0, t2, fail
li s11, 417
li t0, 0x57047108
andi t0, t0, -1155
li t2, 0x57047108
bne t0, t2, fail
li s11, 418
li t0, 0xca679a43
slli t0, t0, 29
li t2, 0x60000000
bne t0, t2, fail
li s11, 419
li t0, 0x06a7529c
slli t0, t0, 6
li t2, 0xa9d4a700
bne t0, t2, fail
li s11, 420
li t0, 0x084ffacb
slli t0, t0, 3
li t2, 0x427fd658
bne t0, t2, fail
li s11, 421
li t0, 0x13b7f2c8
slli t0, t0, 16
li t2, 0xf2c80000
bne t0, t2, fail
li s11, 422
li t0, 0x74eedea4
slli t0, t0, 11
li t2, 0x76f52000
bne t0, t2, fail
li s11, 423
li t0, 0x7f082ea4
slli t0, t0, 28
li t2, 0x40000000
bne t0, t2, fail
li s11, 424
li t0, 0x71f56836
slli t0, t0, 27
li t2, 0xb0000000
bne t0, t2, fail
li s11, 425
li t0, 0x97afd468
slli t0, t0, 7
li t2, 0xd7ea3400
bne t0, t2, fail
li s11, 426
li t0, 0x170505db
slli t0, t0, 7
li t2, 0x8282ed80
bne t0, t2, fail
li s11, 427
li t0, 0x5c1cef14
slli t0, t0, 23
li t2, 0x8a000000
bne t0, t2, fail
li s11, 428
li t0, 0xa681891d
slli t0, t0, 29
li t2, 0xa0000000
bne t0, t2, fail
li s11, 429
li t0, 0x4469c4ee
slli t0, t0, 22
li t2, 0x3b800000
bne t0, t2, fail
li s11, 430
li t0, 0x1803b727
slli t0, t0, 19
li t2, 0xb9380000
bne t0, t2, fail
li s11, 431
li t0, 0xc6a8744a
slli t0, t0, 31
li t2, 0x00000000
bne t0, t2, fail
li s11, 432
li t0, 0x0377a3a3
slli t0, t0, 19
li t2, 0x1d180000
bne t0, t2, fail
li s11, 433
li t0, 0xaa25f5a9
slli t0, t0, 26
li t2, 0xa4000000
bne t0, t2, fail
li s11, 434
li t0, 0x6b7e4b40
srli t0, t0, 18
li t2, 0x00001adf
bne t0, t2, fail
li s11, 435
li t0, 0xe7b04bd5
srli t0, t0, 26
li t2, 0x00000039
bne t0, t2, fail
li s11, 436
li t0, 0x446cd1fc
srli t0, t0, 13
li t2, 0x00022366
bne t0, t2, fail
li s11, 437
li t0, 0x984f1282
srli t0, t0, 21
li t2, 0x000004c2
bne t0, t2, fail
li s11, 438
li t0, 0xb640ac1f
srli t0, t0, 8
li t2, 0x00b640ac
bne t0, t2, fail
li s11, 439
li t0, 0x4ee68e46
srli t0, t0, 18
li t2, 0x000013b9
bne t0, t2, fail
li s11, 440
li t0, 0xfb644e56
srli t0, t0, 29
li t2, 0x00000007
bne t0, t2, fail
li s11, 441
li t0, 0xdec2aaf1
srli t0, t0, 25
li t2, 0x0000006f
bne t0, t2, fail
li s11, 442
li t0, 0x87457c96
srli t0, t0, 27
li t2, 0x00000010
bne t0, t2, fail
li s11, 443
li t0, 0x6eff7290
srli t0, t0, 3
li t2, 0x0ddfee52
bne t0, t2, fail
li s11, 444
li t0, 0xa29b8118
srli t0, t0, 18
li t2, 0x000028a6
bne t0, t2, fail
li s11, 445
li t0, 0x6b011e60
srli t0, t0, 29
li t2, 0x00000003
bne t0, t2, fail
li s11, 446
li t0, 0x3a54fea9
srli t0, t0, 31
li t2, 0x00000000
bne t0, t2, fail
li s11, 447
li t0, 0xd7eeda78
srli t0, t0, 6
li t2, 0x035fbb69
bne t0, t2, fail
li s11, 448
li t0, 0x02f06334
srli t0, t0, 23
li t2, 0x00000005
bne t0, t2, fail
li s11, 449
li t0, 0x5193809c
srli t0, t0, 27
li t2, 0x0000000a
bne t0, t2, fail
li s11, 450
li t0, 0x87926cc3
srai t0, t0, 23
li t2, 0xffffff0f
bne t0, t2, fail
li s11, 451
li t0, 0xdf3c75de
srai t0, t0, 19
li t2, 0xfffffbe7
bne t0, t2, fail
li s11, 452
li t0, 0x75a4c97f
srai t0, t0, 31
li t2, 0x00000000
bne t0, t2, fail
li s11, 453
li t0, 0x567e8f47
srai t0, t0, 30
li t2, 0x00000001
bne t0, t2, fail
li s11, 454
li t0, 0x9147d0a5
srai t0, t0, 0
li t2, 0x9147d0a5
bne t0, t2, fail
li s11, 455
li t0, 0x4d9e1556
srai t0, t0, 12
li t2, 0x0004d9e1
bne t0, t2, fail
li s11, 456
li t0, 0xebaf3b12
srai t0, t0, 17
li t2, 0xfffff5d7
bne t0, t2, fail
li s11, 457
li t0, 0x892a2e25
srai t0, t0, 15
li t2, 0xffff1254
bne t0, t2, fail
li s11, 458
li t0, 0xe9437f85
srai t0, t0, 29
li t2, 0xffffffff
bne t0, t2, fail
li s11, 459
li t0, 0x30c0ea4e
srai t0, t0, 24
li t2, 0x00000030
bne t0, t2, fail
li s11, 460
li t0, 0xb8d74f3f
srai t0, t0, 8
li t2, 0xffb8d74f
bne t0, t2, fail
li s11, 461
li t0, 0xe02075e8
srai t0, t0, 21
li t2, 0xffffff01
bne t0, t2, fail
li s11, 462
li t0, 0x2b39476e
srai t0, t0, 21
li t2, 0x00000159
bne t0, t2, fail
li s11, 463
li t0, 0xb63b9dc9
srai t0, t0, 9
li t2, 0xffdb1dce
bne t0, t2, fail
li s11, 464
li t0, 0x46d391cf
srai t0, t0, 30
li t2, 0x00000001
bne t0, t2, fail
li s11, 465
li t0, 0x01e533fc
srai t0, t0, 1
li t2, 0x00f299fe
bne t0, t2, fail
li s11, 466
li t0, 0x00000000
li t1, 0x00000000
beq t0, t1, 1f
j fail
1:
li s11, 467
li t0, 0x00000000
li t1, 0x00000001
beq t0, t1, fail
li s11, 468
li t0, 0x00000001
li t1, 0x00000000
beq t0, t1, fail
li s11, 469
li t0, 0xffffffff
li t1, 0x00000001
beq t0, t1, fail
li s11, 470
li t0, 0x80000000
li t1, 0x7fffffff
beq t0, t1, fail
li s11, 471
li t0, 0x00000000
li t1, 0x00000000
bne t0, t1, fail
li s11, 472
li t0, 0x00000000
li t1, 0x00000001
bne t0, t1, 1f
j fail
1:
li s11, 473
li t0, 0x00000001
li t1, 0x00000000
bne t0, t1, 1f
j fail
1:
li s11, 474
li t0, 0xffffffff
li t1, 0x00000001
bne t0, t1, 1f
j fail
1:
li s11, 475
li t0, 0x80000000
li t1, 0x7fffffff
bne t0, t1, 1f
j fail
1:
li s11, 476
li t0, 0x00000000
li t1, 0x00000000
blt t0, t1, fail
li s11, 477
li t0, 0x00000000
li t1, 0x00000001
blt t0, t1, 1f
j fail
1:
li s11, 478
li t0, 0x00000001
li t1, 0x00000000
blt t0, t1, fail
li s11, 479
li t0, 0xffffffff
li t1, 0x00000001
blt t0, t1, 1f
j fail
1:
li s11, 480
li t0, 0x80000000
li t1, 0x7fffffff
blt t0, t1, 1f
j fail
1:
li s11, 481
li t0, 0x00000000
li t1, 0x00000000
bge t0, t1, 1f
j fail
1:
li s11, 482
li t0, 0x00000000
li t1, 0x00000001
bge t0, t1, fail
li s11, 483
li t0, 0x00000001
li t1, 0x00000000
bge t0, t1, 1f
j fail
1:
li s11, 484
li t0, 0xffffffff
li t1, 0x00000001
bge t0, t1, fail
li s11, 485
li t0, 0x80000000
li t1, 0x7fffffff
bge t0, t1, fail
li s11, 486
li t0, 0x00000000
li t1, 0x00000000
bltu t0, t1, fail
li s11, 487
li t0, 0x00000000
li t1, 0x00000001
bltu t0, t1, 1f
j fail
1:
li s11, 488
li t0, 0x00000001
li t1, 0x00000000
bltu t0, t1, fail
li s11, 489
li t0, 0xffffffff
li t1, 0x00000001
bltu t0, t1, fail
li s11, 490
li t0, 0x80000000
li t1, 0x7fffffff
bltu t0, t1, fail
li s11, 491
li t0, 0x00000000
li t1, 0x00000000
bgeu t0, t1, 1f
j fail
1:
li s11, 492
li t0, 0x00000000
li t1, 0x00000001
bgeu t0, t1, fail
li s11, 493
li t0, 0x00000001
li t1, 0x00000000
bgeu t0, t1, 1f
j fail
1:
li s11, 494
li t0, 0xffffffff
li t1, 0x00000001
bgeu t0, t1, 1f
j fail
1:
li s11, 495
li t0, 0x80000000
li t1, 0x7fffffff
bgeu t0, t1, 1f
j fail
1:
li a0, 1
j finish
fail: mv a0, s11
finish: li t0, 0x10000000
sw a0, 0(t0)
1: j 1b
