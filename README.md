# sdmem-spin
------------

This is a P8X32A/Propeller, ~~P2X8C4M64P/Propeller 2~~ driver object for SDHC/SDXC memory cards

**IMPORTANT**: This software is meant to be used with the [spin-standard-library](https://github.com/avsa242/spin-standard-library) (P8X32A) ~~or [p2-spin-standard-library](https://github.com/avsa242/p2-spin-standard-library) (P2X8C4M64P)~~. Please install the applicable library first before attempting to use this code, otherwise you will be missing several files required to build the project.

## Salient Features

* SPI connection at ~25kHz
* Supports SDHC, SDXC cards
* Supports 3.3v or Low-voltage range cards
* Read/write 512-byte blocks

## Requirements

P1/SPIN1:
* spin-standard-library
* 1 extra core/cog for the PASM SPI engine

~~P2/SPIN2:~~
* ~~p2-spin-standard-library~~

## Compiler Compatibility

| Processor | Language | Compiler               | Backend     | Status                |
|-----------|----------|------------------------|-------------|-----------------------|
| P1        | SPIN1    | FlexSpin (5.9.10-beta) | Bytecode    | OK                    |
| P1        | SPIN1    | FlexSpin (5.9.10-beta) | Native code | OK                    |
| P1        | SPIN1    | OpenSpin (1.00.81)     | Bytecode    | Untested (deprecated) |
| P2        | SPIN2    | FlexSpin (5.9.10-beta) | NuCode      | Untested              |
| P2        | SPIN2    | FlexSpin (5.9.10-beta) | Native code | Not yet implemented   |
| P1        | SPIN1    | Brad's Spin Tool (any) | Bytecode    | Unsupported           |
| P1, P2    | SPIN1, 2 | Propeller Tool (any)   | Bytecode    | Unsupported           |
| P1, P2    | SPIN1, 2 | PNut (any)             | Bytecode    | Unsupported           |

## Limitations

* Very early in development - may malfunction, or outright fail to build
* Currently developed with slow bytecode SPI engine, until reliability is established
