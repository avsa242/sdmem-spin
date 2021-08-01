# sdmem-spin
------------

This is a P8X32A/Propeller, ~~P2X8C4M64P/Propeller 2~~ driver object for SDHC/SDXC memory cards

**IMPORTANT**: This software is meant to be used with the [spin-standard-library](https://github.com/avsa242/spin-standard-library) (P8X32A) ~~or [p2-spin-standard-library](https://github.com/avsa242/p2-spin-standard-library) (P2X8C4M64P)~~. Please install the applicable library first before attempting to use this code, otherwise you will be missing several files required to build the project.

## Salient Features

* SPI connection at 20MHz (W), 10MHz (R)
* Supports SDHC, SDXC cards
* Supports 3.3v or Low-voltage range cards

## Requirements

P1/SPIN1:
* spin-standard-library
* 1 extra core/cog for the PASM SPI engine

~~P2/SPIN2:~~
* ~~p2-spin-standard-library~~

## Compiler Compatibility

* P1/SPIN1: OpenSpin (tested with 1.00.81), FlexSpin (tested with 6.0.0-beta)
* ~~P2/SPIN2: FlexSpin (tested with 6.0.0-beta)~~ _(not yet implemented)_
* ~~BST~~ (incompatible - no preprocessor)
* ~~Propeller Tool~~ (incompatible - no preprocessor)
* ~~PNut~~ (incompatible - no preprocessor)

## Limitations

* Very early in development - may malfunction, or outright fail to build
* Only one try is given to SD card start/initialization code, and with no timeout. The first initialization attempt on powerup usually fails.
* Read-only/no write support yet

## TODO

- [ ] Write support
- [ ] Port to P2/SPIN2

