' SPI mode
' INIT OK
' READ CODE INOP w/4W SPI ENGINE (doesn't tristate MOSI?)
' READ CODE WORKS w/TINY SPI ENGINE
' READ CODE WORKS w/MODIFIED 20MHz/10MHz SPI engine (no CS builtin)
'   CMD 18 (52 00 00 00 01 ff), r, r, r: 0x00, r: ff, r: ff, r:fe, r: 00, r: 00 ...
'#define DEBUG
CON

    _clkmode        = xtal1+pll16x
    _xinfreq        = 5_000_000

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


' --
    CS              = 3
    SCK             = 1
    MOSI            = 2
    MISO            = 0
' --

OBJ

    spi : "com.spi.fast-nocs"
    slowspi: "tiny.com.spi"
    time: "time"
    crc : "math.crc"

CON

    ENORESPOND          = $E000_0000
    EVOLTRANGE          = $E000_0001

VAR

    long _CS
    long _is_hc
    byte _blkbuff[512]

PUB Init(CS_PIN, SCK_PIN, MOSI_PIN, MISO_PIN): status | r
' Initialize SD card
    outa[CS_PIN] := 1
    dira[CS_PIN] := 1
    _CS := CS_PIN

    ' perform initialization at slow bus speed (mandatory)
    slowspi.init(SCK_PIN, MOSI_PIN, MISO_PIN, 0)
    time.msleep(1)

    dummyclocks{}
    if setidle{} <> 1
        return ENORESPOND

    ifnot sendintcondcmd(1, $AA)
        return EVOLTRANGE

    initialize{}
    _is_hc := ishighcapacity

    crccheckenabled(false)

    ' shut down slow SPI engine and initialize fast SPI engine
    slowspi.deinit{}
    if (status := spi.init(SCK_PIN, MOSI_PIN, MISO_PIN, 0))

PUB CRCCheckEnabled(state): status | cmd_pkt
' Enable CRC checking in SPI commands
    cmd_pkt := ||(state <> 0)
    repeat
        status := slowcmd(CMD59, @cmd_pkt)
    until status <> $FF                         ' wait for resp. from card

PUB DummyClocks
' Cycle clock to prepare SD card to receive commands
    outa[_CS] := 1                                     ' make sure card isn't selected
    repeat 10
        slowspi.wr_byte($FF)                    ' init: send 80 clocks

PUB Initialize{}: status | cmd_pkt, tries
' Initialize SD card
    cmd_pkt.byte[0] := 1 << 6                   ' HCS bit: req SDHC/XC support
    cmd_pkt.byte[1] := 0
    cmd_pkt.byte[2] := 0
    cmd_pkt.byte[3] := 0

    tries := 0
    repeat
        tries++
        status := appspeccmd(ACMD41, @cmd_pkt)
    until status == 0

PUB IsHighCapacity{}: flag | cmd_pkt
' Flag indicating card is a high-capacity type (i.e., SDHC or SDXC)
    cmd_pkt := 0

    if slowcmd(CMD58, @cmd_pkt) <> 0            ' query card's OCR register
        repeat

    outa[_CS] := 0
    flag := slowspi.rdlong_msbf{}               ' read the response
    outa[_CS] := 1
    return (flag & CCS) <> 0                    ' CCS bit (30)

PUB RdBlock(ptr_buff, block_nr) | cmd_pkt, bsy
' Read block of data from SD card
    cmd_pkt.byte[0] := block_nr.byte[3]
    cmd_pkt.byte[1] := block_nr.byte[2]
    cmd_pkt.byte[2] := block_nr.byte[1]
    cmd_pkt.byte[3] := block_nr.byte[0]

    fastcmd(CMD18, @cmd_pkt)                    ' set to block read mode

    outa[_CS] := 0
    repeat                                      ' wait for card to be ready
        bsy := spi.rd_byte & 1
    while bsy

    spi.rdblock_lsbf(ptr_buff, 512)            ' read block_nr - 512 bytes
    outa[_CS] := 1

    cmd_pkt := 0
    fastcmd(CMD12, @cmd_pkt)                    ' turn off block read

PUB SendIntCondCmd(vrange, chk_patt): resp | cmd_pkt
' Send interface condition command
'   vrange: requested voltage range (_3V3 or _LV)
'   chk_patt: check pattern to write - is echoed by card in response when
'       requested voltage range is accepted
    case vrange
        _3V3:
        _LV:
        other:
            return
    cmd_pkt.byte[0] := 0
    cmd_pkt.byte[1] := 0
    cmd_pkt.byte[2] := vrange & VHS_BITS        ' voltage range of card
    cmd_pkt.byte[3] := chk_patt & $FF           ' check pattern

    slowcmd(CMD8, @cmd_pkt)

    outa[_CS] := 0
    resp := slowspi.rdlong_msbf{}               ' read response
    outa[_CS] := 1

    ' check to see that the card responded with the same voltage range and
    '   bit pattern as requested. If it does, the requested voltage range
    '   is supported. Otherwise, it isn't.
    resp := (resp == (cmd_pkt.byte[2] << 8 | cmd_pkt.byte[3]))

PUB SetIdle{}: status | cmd_pkt
' Set card to idle state

    ' send CMD0 - no params, only dummy/"stuff" bits
    cmd_pkt := 0
    status := slowcmd(CMD0, @cmd_pkt)

PRI AppSpecCMD(cmd, ptr_buff): resp | cmd_pkt
' Application-specific command
    cmd_pkt := 0
    slowcmd(CMD55, @cmd_pkt)
    resp := slowcmd(cmd, ptr_buff)

PRI FastCMD(cmd, ptr_buff): resp | cmd_pkt[2], i, tries
' Send SD card command using fast SPI engine
    tries := 9
    outa[_CS] := 0
    spi.wrlong_msbf($FF_FF_FF_FF)               ' send idle clocks to card
    cmd_pkt.byte[0] := cmd                      ' build packet
    bytemove(@cmd_pkt.byte[1], ptr_buff, 4)
    cmd_pkt.byte[5] := $FF                      ' dummy CRC byte
    spi.wrblock_lsbf(@cmd_pkt, 6)               ' send CMD, params, CRC

    repeat
        resp := spi.rd_byte                     ' read response from card
    while (resp & $80) and (tries--)            ' retry until ready,
    outa[_CS] := 1                                     '   up to 'tries' times

PUB SlowCMD(cmd, ptr_buff): resp | cmd_pkt[2], i, tries
' Send SD card command using slow SPI engine
'   (used only during initialization)
    tries := 9
    outa[_CS] := 0
    slowspi.rdlong_msbf{}                       ' send idle clocks to card
    cmd_pkt.byte[0] := cmd                      ' build packet
    bytemove(@cmd_pkt.byte[1], ptr_buff, 4)
    cmd_pkt.byte[5] := crc.sdcrc7(@cmd_pkt, 5)
    slowspi.wrblock_lsbf(@cmd_pkt, 6)           ' send CMD, params, CRC

    repeat              
        resp := slowspi.rd_byte                 ' read response from card
    while (resp & $80) and (tries--)            ' retry until ready,
    outa[_CS] := 1                                     '   up to 'tries' times

