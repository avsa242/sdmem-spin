{
    --------------------------------------------
    Filename: memory.sd-spi.spin
    Author: Jesse Burt
    Description: Driver for SPI-connected SDHC/SDXC cards
        20MHz write, 10MHz read
    Copyright (c) 2022
    Started Aug 1, 2021
    Updated Aug 24, 2022
    See end of file for terms of use.
    --------------------------------------------
}

CON

    SECT_SZ         = 512                       ' bytes per sector

' SD card commands
    CMD_BASE        = $40
    CMD0            = CMD_BASE+0                ' GO_IDLE_STATE
    CMD8            = CMD_BASE+8                ' SEND_IF_COND
        VHS         = 16
        CHKPATT     = 8
        VHS_BITS    = %1111
        CHKPATT_BITS= %1111_1111
        _3V3        = %0001
        _LV         = %0010

    CMD12           = CMD_BASE+12               ' STOP_TRANSMISSION
    CMD17           = CMD_BASE+17               ' READ_SINGLE_BLOCK
    CMD18           = CMD_BASE+18               ' READ_MULTIPLE_BLOCK
    CMD24           = CMD_BASE+24               ' WRITE_BLOCK
    CMD25           = CMD_BASE+25               ' WRITE_MULTIPLE_BLOCK
    CMD55           = CMD_BASE+55               ' APP_CMD

    CMD58           = CMD_BASE+58               ' READ_OCR
        BUSY        = 1 << 31
        CCS         = 1 << 30
        UHS2CS      = 1 << 29
        S18A        = 1 << 24
        V3_5TO3_6   = 1 << 23
        V3_4TO3_5   = 1 << 22
        V3_3TO3_4   = 1 << 21
        V3_2TO3_3   = 1 << 20
        V3_1TO3_2   = 1 << 19
        V3_0TO3_1   = 1 << 18
        V2_9TO3_0   = 1 << 17
        V2_8TO2_9   = 1 << 16
        V2_7TO2_8   = 1 << 15

    CMD59           = CMD_BASE+59               ' CRC_ON_OFF
        CRCEN       = 0

    { application-specific commands }
    ACMD41          = CMD_BASE+41               ' SEND_OP_COND (SDC)

    { R1 response bits }
    PARAM_ERR       = (1 << 6)                  ' parameter error
    ADDR_ERR        = (1 << 5)                  ' address error
    ERASEQ_ERR      = (1 << 4)                  ' erase sequence error
    CRC_ERR         = (1 << 3)                  ' com CRC error
    ILL_CMD         = (1 << 2)                  ' illegal command
    ERARST          = (1 << 1)                  ' erase reset
    IDLING          = 1                         ' in idle state

    { token values }
    START_BLK       = $FE                       ' Start token
    TOKEN_OOR       = %0000_1000                ' out of range
    TOKEN_CECC      = %0000_0100                ' ECC failed
    TOKEN_CC        = %0000_0010                ' CC error
    TOKEN_ERROR     = %0000_0001                ' Error

    WRBUSY          = $00                       ' SD is busy writing block
    BLK_ACCEPTED    = $05
    READ_OK         = SECT_SZ
    WRITE_OK        = SECT_SZ

OBJ

    spi     : "com.spi.nocog"
    time    : "time"

CON

    ENORESP             = -2
    EVOLTRANGE          = -3
    ENOHIGHCAP          = -4
    ERDIO               = -5
    EWRIO               = -6

VAR

    long _CS

PUB null{}
' This is not a top-level object

PUB init(CS_PIN, SCK_PIN, MOSI_PIN, MISO_PIN): status
' Initialize block I/O
'   Returns:
'       1..8: (cog number + 1) of SPI engine
'       0: no free cogs available
'       negative numbers: error
    outa[CS_PIN] := 1                           ' deselect SD card
    dira[CS_PIN] := 1
    _CS := CS_PIN

    { perform initialization at slow bus speed (mandatory) }
    spi.init(SCK_PIN, MOSI_PIN, MISO_PIN, 0)
    if (card_init{} =< 0)
        return ENORESP
    status := spi.init(SCK_PIN, MOSI_PIN, MISO_PIN, 0)

PUB rd_block(ptr_buff, blkaddr): res1 | tries, read
' Read a block/sector from the card
'   ptr_buff: address of buffer to copy data to
'   blkaddr: block/sector address to read from
    tries := read := 0

    outa[_CS] := 0

    { the first tries at sending the read block command doesn't always succeed,
        so try sending it up to 10 times, waiting 10ms in between tries }
    repeat 10
        command(CMD17, blkaddr, $00)

        res1 := read_res1{}
        if (res1 <> $ff)                        ' acknowledged
            quit
        time.msleep(10)

    if (res1 <> $ff)
        tries := 0
        repeat while (++tries < 20)
            if ((read := spi.rd_byte{}) <> $ff)
                quit
            time.msleep(10)
        if (read == START_BLK)                  ' start token received
            spi.rdblock_lsbf(ptr_buff, SECT_SZ)
            spi.rd_byte{}
            spi.rd_byte{}                       ' throw away CRC

    spi.wr_byte($ff)
    outa[_CS] := 1

    if (read == START_BLK)
        return READ_OK
    else
        return ERDIO                            ' read error

CON READY = 0
PUB wr_block(ptr_buff, blkaddr): resp | tries, read
' Write data to a block/sector on the card
'   ptr_buff: pointer to buffer containing data to write
'   blkaddr: block/sector address to write to
    tries := read := 0
    resp := $ff

    outa[_CS] := 0
    command(CMD24, blkaddr, 0)

    resp.byte[0] := read_res1{}

    if (resp.byte[0] == READY)
        spi.wr_byte(START_BLK)
        spi.wrblock_lsbf(ptr_buff, SECT_SZ)
        tries := 0
        repeat while (++tries <> 25)
            read := spi.rd_byte{}
            if (read <> $ff)
                resp := $ff
                quit
            time.msleep(10)

        if ((read & $1f) == BLK_ACCEPTED)  ' block was accepted by the card
            resp := BLK_ACCEPTED

            tries := 0
            repeat
                read := spi.rd_byte{}
                if (++tries == 25)
                    resp := $00
                    quit
                time.msleep(10)
            while (read == WRBUSY)

    spi.wr_byte($ff)
    outa[_CS] := 1

    if (resp == BLK_ACCEPTED)
        return WRITE_OK
    else
        return EWRIO                            ' write error

PRI app_spec_cmd{}: res1
' Signal to card that the next command will be an application-specific command
'   Returns: response register R1
    outa[_CS] := 0
    command(CMD55, 0, 0)

    res1 := read_res1{}

    spi.wr_byte($ff)
    outa[_CS] := 1

    return res1

PRI card_init{}: status | resp[2], tries
' Initialize the card
    longfill(@resp, 0, 3)

    power_up_seq{}

    { try (up to 10 times) setting the card to idle state }
    repeat while (resp.byte[0] := set_idle{} <> $01)
        tries++
        if (tries > 10)
            return ENORESP
    longfill(@resp, 0, 2)

    send_if_cond(@resp)
    if (resp.byte[0] <> $01)
        return ENORESP
    if (resp.byte[4] <> $AA)
        return ENORESP
    longfill(@resp, 0, 2)

    tries := 0
    repeat
        if (tries > 100)
            return ENORESP
        resp.byte[0] := app_spec_cmd{}

        if (resp.byte[0] < 2)
            resp.byte[0] := send_op_cond{}

        time.msleep(10)

        tries++
    while (resp.byte[0] <> $00)                 ' ready?

    read_ocr(@resp)
    ifnot (resp.byte[1] & $80)
        return ENORESP

    return 1

PRI command(cmd, arg, crc)
' Send a command to the card
'   cmd: command
'   arg: arguments/parameters (4 bytes, MSByte-first)
'   crc: 7-bit CRC
'   Returns: none
    spi.wr_byte($ff)                            ' dummy clocks
    spi.wr_byte(cmd)
    spi.wrlong_msbf(arg)
    spi.wr_byte(crc | $01)

PRI power_up_seq{} | i
' Power up/wake up cards connected to the bus
    { ensure card is _NOT_ selected }
    outa[_CS] := 1

    time.msleep(1)

    { send 80 clocks to the bus to wake up connected card(s) }
    repeat i from 0 to 9
        spi.wr_byte($ff)

    spi.wr_byte($ff)

PRI read_ocr(ptr_resp)
' Read operating conditions register
'   ptr_resp: pointer to buffer to copy response to
'   Returns: none
    outa[_CS] := 0
    command(CMD58, 0, 0)

    read_res3(ptr_resp)

    spi.wr_byte($ff)
    outa[_CS] := 1

PRI read_res1{}: res1 | tries
' Read response register (R1)
'   Returns: response R1
    tries := res1 := 0
    repeat
        res1 := spi.rd_byte{}
        tries++
        if (tries > 8)                          ' give up after 8 tries
            quit
    while (res1 => $0f)

PRI read_res3(ptr_resp)
' Read response register (R3)
'   ptr_resp: pointer to buffer to copy response to
'   Returns: none
    byte[ptr_resp][0] := read_res1{}

    if (byte[ptr_resp][0] > 1)                  ' error
        return

    byte[ptr_resp][1] := spi.rd_byte{}
    byte[ptr_resp][2] := spi.rd_byte{}
    byte[ptr_resp][3] := spi.rd_byte{}
    byte[ptr_resp][4] := spi.rd_byte{}

PRI read_res7(ptr_buff)
' Read response register (R7)
'   ptr_buff: pointer to buffer to copy response to
'   Returns: none
    byte[ptr_buff][0] := read_res1{}

    if (byte[ptr_buff][0] > 1)                  ' error
        return

    byte[ptr_buff][1] := spi.rd_byte{}
    byte[ptr_buff][2] := spi.rd_byte{}
    byte[ptr_buff][3] := spi.rd_byte{}
    byte[ptr_buff][4] := spi.rd_byte{}

PRI send_if_cond(ptr_buff)
' Send interface conditions to card
'   ptr_buff: pointer to buffer to copy response to
'   Returns: none
    outa[_CS] := 0
    command(CMD8, $00_00_01_aa, $86)

    read_res7(ptr_buff)

    spi.wr_byte($ff)
    outa[_CS] := 1

PRI send_op_cond{}: res1
' Send operating conditions command to card
'   Returns: response register R1
    outa[_CS] := 0
    command(ACMD41, $40_00_00_00, 0)

    res1 := read_res1{}

    spi.wr_byte($ff)
    outa[_CS] := 1

    return res1

PRI set_idle{}: res1
' Command card to idle state
'   Returns: result register (R1)
    outa[_CS] := 0
    command(CMD0, 0, $94)

    res1 := read_res1{}

    spi.wr_byte($ff)
    outa[_CS] := 1

    return res1

DAT
{
Copyright 2022 Jesse Burt

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT
OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
}

