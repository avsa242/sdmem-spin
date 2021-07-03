CON

    _clkmode        = xtal1+pll16x
    _xinfreq        = 5_000_000

' --
    CS              = 3
    SCK             = 1
    MOSI            = 2
    MISO            = 0
' --

OBJ

    ser : "com.serial.terminal.ansi"
    time: "time"
    sd  : "memory.flash.sd.spi"
    fat : "filesystem.block.fat"

VAR

    byte _blkbuff[512]

PUB Main | r

    ser.start(115_200)
    time.msleep(30)
    ser.clear
    ser.strln(string("serial terminal started"))

    sd.startx(CS, SCK, MOSI, MISO)
    fat.init(@_blkbuff)

    ser.strln(string("reading block..."))
    sd.rdblock(@_blkbuff, $0000)
    ser.printf1(string("\n\np1 start: %d\n"), fat.partition1st)

    sd.rdblock(@_blkbuff, fat.partition1st)
    ser.hexdump(@_blkbuff, fat.partition1st, 4, fat#BYTESPERSECT, 16)
    ser.printf1(string("Volume name: %s\n"), fat.volumename{})
    ser.printf1(string("Sectors per cluster: %d\n"), fat.sectorspercluster{})
    ser.printf1(string("Bytes per logical sector: %d\n"), fat.logicalsectorbytes{})


{
    repeat r from 0 to 11
'        ser.char(byte[fat.volumename][r])
        ser.hex(byte[fat.volumename][r], 2)
        ser.char(" ")
}
    repeat

