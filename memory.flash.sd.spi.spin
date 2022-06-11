{
    --------------------------------------------
    Filename: memory.flash.sd.spi.spin
    Author: Jesse Burt
    Description: Driver for SPI-connected SDHC/SDXC cards
        20MHz write, 10MHz read
    Copyright (c) 2021
    Started Aug 1, 2021
    Updated Sep 18, 2021
    See end of file for terms of use.
    --------------------------------------------
}

CON

    SECT_SZ      = 512                       ' bytes per sector

' SD card commands
    CMD_BASE        = $40
    CMD0            = CMD_BASE+0                ' GO_IDLE_STATE
    CMD1            = CMD_BASE+1                ' SEND_OP_COND (MMC)

    CMD8            = CMD_BASE+8                ' SEND_IF_COND
        VHS         = 16
        CHKPATT     = 8
        VHS_BITS    = %1111
        CHKPATT_BITS= %1111_1111
        _3V3        = %0001
        _LV         = %0010

    CMD9            = CMD_BASE+9                ' SEND_CSD
    CMD10           = CMD_BASE+10               ' SEND_CID
    CMD12           = CMD_BASE+12               ' STOP_TRANSMISSION
    CMD13           = CMD_BASE+13               ' SEND_STATUS
    CMD16           = CMD_BASE+16               ' SET_BLOCKLEN
    CMD17           = CMD_BASE+17               ' READ_SINGLE_BLOCK
    CMD18           = CMD_BASE+18               ' READ_MULTIPLE_BLOCK
    CMD23           = CMD_BASE+23               ' SET_BLOCK_COUNT (MMC)
    CMD24           = CMD_BASE+24               ' WRITE_BLOCK
    CMD25           = CMD_BASE+25               ' WRITE_MULTIPLE_BLOCK
    CMD41           = CMD_BASE+41               ' xxx
    CMD55           = CMD_BASE+55               ' APP_CMD

    CMD58           = CMD_BASE+58               ' READ_OCR
        BUSY        = 1 << 31
        CCS         = 1 << 30                   '
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

' Application-specific commands
'   (defined as equivalent to general commands - handled differently
'   in AppSpecCMD() )
    ACMD13          = CMD13                     ' SD_STATUS (SDC)
    ACMD23          = CMD23                     ' SET_WR_BLK_ERASE_COUNT (SDC)
    ACMD41          = CMD41                     ' SEND_OP_COND (SDC)

    START_BLK       = $FE                       ' Start token

' R1 bits
    PARAM_ERR       = (1 << 6)                  ' parameter error
    ADDR_ERR        = (1 << 5)                  ' address error
    ERASEQ_ERR      = (1 << 4)                  ' erase sequence error
    CRC_ERR         = (1 << 3)                  ' com CRC error
    ILL_CMD         = (1 << 2)                  ' illegal command
    ERARST          = (1 << 1)                  ' erase reset
    IDLING          = 1                         ' in idle state

    { token values }
    SD_TOKEN_OOR    = %0000_1000                ' out of range
    SD_TOKEN_CECC   = %0000_0100                ' ECC failed
    SD_TOKEN_CC     = %0000_0010                ' CC error
    SD_TOKEN_ERROR  = %0000_0001                ' Error

    WRBUSY          = $00                       ' SD is busy writing block

OBJ

    spi     : "com.spi.nocog"
    time    : "time"
    crc     : "math.crc"

CON

    ENORESP             = $E000_0000
    EVOLTRANGE          = $E000_0001
    ENOHIGHCAP          = $E000_0002

VAR

    long _CS
    long _is_hc

PUB Null{}
' This is not a top-level object

PUB Init(CS_PIN, SCK_PIN, MOSI_PIN, MISO_PIN): status
' Initialize SD card
'   Returns:
'       1..8: (cog number + 1) of SPI engine
'       0: no free cogs available
'       negative numbers: error
    outa[CS_PIN] := 1                           ' deselect SD card
    dira[CS_PIN] := 1
    _CS := CS_PIN

    ' perform initialization at slow bus speed (mandatory)
    spi.init(SCK_PIN, MOSI_PIN, MISO_PIN, 0)
    if (sd_init() =< 0)
        return ENORESP
    status := spi.init(SCK_PIN, MOSI_PIN, MISO_PIN, 0)

PUB SD_Init() | resp[2], cmdAttempts

    longfill(@resp, 0, 2)
    cmdAttempts := 0

    SD_powerUpSeq()

    repeat while (resp.byte[0] := SD_goIdleState() <> $01)
        cmdAttempts++
        if (cmdAttempts > 10)
            return ENORESP
    longfill(@resp, 0, 2)

    SD_sendIfCond(@resp)
    if (resp.byte[0] <> $01)
        return ENORESP
    if (resp.byte[4] <> $AA)
        return ENORESP
    longfill(@resp, 0, 2)

    cmdAttempts := 0
    repeat
        if (cmdAttempts > 100)
            return ENORESP
        resp.byte[0] := SD_sendApp()

        if (resp.byte[0] < 2)
            resp.byte[0] := SD_sendOpCond()

        time.msleep(10)

        cmdAttempts++
    while (resp.byte[0] <> $00) 'SD_READY?

    SD_readOCR(@resp)
    ifnot (resp.byte[1] & $80)
        return ENORESP

    return 1

PUB SD_command(cmd, arg, crc)

    spi.wr_byte(cmd)    '$40 already OR'd in with CMD constants
    spi.wr_byte(arg.byte[3])
    spi.wr_byte(arg.byte[2])
    spi.wr_byte(arg.byte[1])
    spi.wr_byte(arg.byte[0])

    spi.wr_byte(crc|$01)

PUB SD_goIdleState: res1

    spi.wr_byte($ff)
    outa[_CS] := 0
    spi.wr_byte($ff)

    SD_command(CMD0, 0, $94)

    res1 := SD_readRes1()

    spi.wr_byte($ff)
    outa[_CS] := 1
    spi.wr_byte($ff)

    return res1

PUB SD_powerUpSeq | i

    outa[_CS] := 1

    time.msleep(1)

    repeat i from 0 to 9
        spi.wr_byte($ff)

    outa[_CS] := 1
    spi.wr_byte($ff)

con

    PARAM_ERROR     = %0100_0000
    ADDR_ERROR      = %0010_0000
    ERASE_SEQ_ERROR = %0001_0000
    CRC_ERROR       = %0000_1000
    ILLEGAL_CMD     = %0000_0100
    ERASE_RESET     = %0000_0010
    IN_IDLE         = %0000_0001

PUB SD_printR1(resp)

    if (resp & %1000_0000)
        'ser.strln(@"Error")
    if (resp == 0)
        'ser.strln(@"Card ready")
    if (resp & PARAM_ERROR)
        'ser.strln(@"Parameter Error")
    if (resp & ADDR_ERROR)
        'ser.strln(@"Address Error")
    if (resp & ERASE_SEQ_ERROR)
        'ser.strln(@"Erase Sequence Error")
    if (resp & CRC_ERROR)
        'ser.strln(@"CRC Error")
    if (resp & ILLEGAL_CMD)
        'ser.strln(@"Illegal Command")
    if (resp & ERASE_RESET)
        'ser.strln(@"Erase Reset Error")
    if (resp & IN_IDLE)
        'ser.strln(@"In Idle State")

CON

    VDD_2728 = %10000000
    VDD_2829 = %00000001
    VDD_2930 = %00000010
    VDD_3031 = %00000100
    VDD_3132 = %00001000
    VDD_3233 = %00010000
    VDD_3334 = %00100000
    VDD_3435 = %01000000
    VDD_3536 = %10000000

PUB SD_printR3(resp) | POWER_UP_STATUS, CCS_VAL

    SD_printR1(byte[resp][0])

    if (byte[resp][0] > 1)
        return

    'ser.str(@"Card Power Up Status: ")
    POWER_UP_STATUS := byte[resp][1] & $40
    if (POWER_UP_STATUS)
        'ser.strln(@"READY")
        'ser.str(@"CCS Status: ")
        CCS_VAL := byte[resp][1] & $40
        if (CCS_VAL)
            'ser.strln(@"1\n\r")
        else
            'ser.strln(@"0\n\r")
    else
        'ser.strln(@"BUSY")

    'ser.str(@"VDD Window: ")
    if (byte[resp][3] & VDD_2728)
        'ser.str(@"2.7-2.8, ")
    if (byte[resp][2] & VDD_2829)
        'ser.str(@"2.8-2.9, ")
    if (byte[resp][2] & VDD_2930)
        'ser.str(@"2.9-3.0, ")
    if (byte[resp][2] & VDD_3031)
        'ser.str(@"3.0-3.1, ")
    if (byte[resp][2] & VDD_3132)
        'ser.str(@"3.1-3.2, ")
    if (byte[resp][2] & VDD_3233)
        'ser.str(@"3.2-3.3, ")
    if (byte[resp][2] & VDD_3334)
        'ser.str(@"3.3-3.4, ")
    if (byte[resp][2] & VDD_3435)
        'ser.str(@"3.4-3.5, ")
    if (byte[resp][2] & VDD_3536)
        'ser.str(@"3.5-3.6")
    'ser.newline

CON

    VOLTAGE_ACC_27_33   = %0000_0001
    VOLTAGE_ACC_LOW     = %0000_0010
    VOLTAGE_ACC_RES1    = %0000_0100
    VOLTAGE_ACC_RES2    = %0000_1000

PUB SD_printR7(resp) | CMD_VER, VOL_ACC, i

    SD_printR1(byte[resp][0])

    if (byte[resp][0] > 1)  'error
        return

    CMD_VER := byte[resp][1]
    'ser.printf1(@"Command version: %x\n\r", (CMD_VER >> 4) & $f0)

    VOL_ACC := byte[resp][3]
    'ser.str(@"Voltage accepted: ")
    if (VOL_ACC == VOLTAGE_ACC_27_33)
        'ser.strln(@"2.7-3.6V")
    elseif (VOL_ACC == VOLTAGE_ACC_LOW)
        'ser.strln(@"LOW VOLTAGE")
    elseif (VOL_ACC == VOLTAGE_ACC_RES1)
        'ser.strln(@"RESERVED")
    elseif (VOL_ACC == VOLTAGE_ACC_RES2)
        'ser.strln(@"RESERVED")
    else
        'ser.strln(@"NOT DEFINED")

    'ser.printf1(@"Echo: %x\n\r", byte[resp][4])

PUB SD_readOCR(resp)

    spi.wr_byte($ff)
    outa[_CS] := 0
    spi.wr_byte($ff)

    SD_command(CMD58, 0, 0)

    SD_readRes3(resp)

    spi.wr_byte($ff)
    outa[_CS] := 1
    spi.wr_byte($ff)

PUB SD_readRes1: res1 | i

    i := res1 := 0
    repeat
        res1 := spi.rd_byte
        i++
        if (i > 8)
            quit
'        'ser.printf1(@"SD_readRes1(): res1 == %x\n\r", res1)
    while (res1 => $0f)

PUB SD_readRes3(res3)

    byte[res3][0] := SD_readRes1()

    if (byte[res3][0] > 1)   ' error
        return

    byte[res3][1] := spi.rd_byte()
    byte[res3][2] := spi.rd_byte()
    byte[res3][3] := spi.rd_byte()
    byte[res3][4] := spi.rd_byte()

PUB SD_readRes7(res7)

    byte[res7][0] := SD_readRes1()

    if (byte[res7][0] > 1)   ' error
        return

    byte[res7][1] := spi.rd_byte()
    byte[res7][2] := spi.rd_byte()
    byte[res7][3] := spi.rd_byte()
    byte[res7][4] := spi.rd_byte()

PUB SD_readSingleBlock(addr, buf, token): res1 | read, readAttempts, i

    'ser.strln(@"SD_readSingleBlock()")
    res1 := read := readAttempts := 0
    byte[token] := $ff

    spi.wr_byte($ff)
    outa[_CS] := 0
    spi.wr_byte($ff)

    'ser.strln(@"sending CMD17")
    SD_command(CMD17, addr, $00)

    res1 := SD_readRes1()
    'ser.printf1(@"res1 is %x\n\r", res1)
    if (res1 <> $ff)
        readAttempts := 0
        repeat while (++readAttempts <> 20)
'            'ser.printf1(@"readattempts = %d\n\r", readAttempts)
            if ((read := spi.rd_byte) <> $ff)
                quit
            time.msleep(10)
        if (read == $fe)    ' start token
            'ser.strln(@"got start token")
            repeat i from 0 to 511
                byte[buf][i] := spi.rd_byte
            spi.rd_byte
            spi.rd_byte ' throw away CRC
        byte[token] := read

    spi.wr_byte($ff)
    outa[_CS] := 1
    spi.wr_byte($ff)

    return res1


PUB SD_sendApp(): res1

    spi.wr_byte($ff)
    outa[_CS] := 0
    spi.wr_byte($ff)

    SD_command(CMD55, 0, 0)

    res1 := SD_readRes1()

    spi.wr_byte($ff)
    outa[_CS] := 1
    spi.wr_byte($ff)

    return res1

PUB SD_sendIfCond(resp)

    spi.wr_byte($ff)
    outa[_CS] := 0
    spi.wr_byte($ff)

    SD_command(CMD8, $00_00_01_aa, $86)

    SD_readRes7(resp)

    spi.wr_byte($ff)
    outa[_CS] := 1
    spi.wr_byte($ff)

PUB SD_sendOpCond(): res1

    spi.wr_byte($ff)
    outa[_CS] := 0
    spi.wr_byte($ff)

    SD_command(ACMD41, $40_00_00_00, 0)

    res1 := SD_readRes1()

    spi.wr_byte($ff)
    outa[_CS] := 1
    spi.wr_byte($ff)

    return res1

PUB SD_writeSingleBlock(addr, buf, token): resp | readAttempts, read, i

'    'ser.printf3(@"SD_writeSingleBlock(): addr = %x, buf = %x, token = %x", addr, buf, token)
    readAttempts := read := i := 0
    byte[token] := $ff

    spi.wr_byte($ff)
    outa[_CS] := 0
    spi.wr_byte($ff)

    SD_command(CMD24, addr, 0)

    resp.byte[0] := SD_readRes1()

    if (resp.byte[0] == 0)  'READY?
        spi.wr_byte(START_BLK)

        repeat i from 0 to 511
            spi.wr_byte(byte[buf][i])

        readAttempts := 0
        repeat while (++readAttempts <> 25)
            read := spi.rd_byte
            if (read <> $ff)
                byte[token] := $ff
                quit
            time.msleep(10)

        if (read & $1f) == $05  ' block was accepted by the card
            byte[token] := $05

            readAttempts := 0
            repeat
                read := spi.rd_byte
                if (++readAttempts == 25)
                    byte[token] := $00
                    quit
                time.msleep(10)
            while (read == WRBUSY)

    spi.wr_byte($ff)
    outa[_CS] := 1
    spi.wr_byte($ff)

    return resp.byte[0]

PUB RdBlock(ptr_buff, block_nr): resp | token

    token := 0
    resp := SD_readSingleBlock(block_nr, ptr_buff, @token)
    if (token == $fe)
        return 512

PUB WrBlock(ptr_buff, block_nr): resp | token

    token := 0
    resp := SD_writeSingleBlock(block_nr, ptr_buff, @token)
    'ser.printf1(@"WrBlock(): token = %x\n\r", token)
    if (token == $05)
        return 512

DAT
{
    --------------------------------------------------------------------------------------------------------
    TERMS OF USE: MIT License

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
    associated documentation files (the "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the
    following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial
    portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
    LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
    WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    --------------------------------------------------------------------------------------------------------
}

